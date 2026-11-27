import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../../auth/neuq_cas_form.dart';
import '../../auth/neuq_login_protocol.dart';
import '../../diagnostics/diagnostics.dart';
import 'campus_resource.dart';
import 'campus_transport.dart';
import 'webvpn_session_manager.dart';

/// The caller supplies the school-verified portal addresses and a parser for
/// an authenticated identity response. There is no production registration.
class NeuqWebVpnProtocol implements WebVpnProtocol {
  NeuqWebVpnProtocol({
    required this.portalCasEntry,
    required this.casReturn,
    required this.identityPage,
    required this.verifiedSubject,
    http.Client Function()? createClient,
    DateTime Function()? clock,
  }) : _createClient = createClient ?? http.Client.new,
       _now = clock ?? DateTime.now;

  final Uri portalCasEntry;
  final Uri casReturn;
  final Uri identityPage;
  final String? Function(Document) verifiedSubject;
  final http.Client Function() _createClient;
  final DateTime Function() _now;

  static final _portal = Uri.parse(officialWebVpnUrl);
  static const _device = CampusUrlScope(officialWebVpnHost, '/fingerprint');
  static final _casPath = RegExp(
    r'^/authserver/login(?:;jsessionid=[A-Za-z0-9._-]+)?$',
    caseSensitive: false,
  );
  static const _redirects = {301, 302, 303, 307, 308};

  @override
  Future<WebVpnSession> authenticate(WebVpnAuthentication attempt) async {
    _validateConfiguration();
    final cancellation = attempt.cancellation;
    cancellation.check();
    final client = _WebVpnCookieClient(_createClient(), _now);
    final abort = Completer<void>();
    final unbind = cancellation.listen(() {
      abort.complete();
      client.close();
    });
    var accepted = false;
    try {
      final subject = await _authenticate(client, attempt, abort.future);
      cancellation.check();
      if (subject != attempt.subject) throw CampusAccessFailure.accountMismatch;
      accepted = true;
      return WebVpnSession(subject: subject, httpClient: client);
    } catch (error) {
      cancellation.check();
      throw classifyCampusError(error);
    } finally {
      unbind();
      if (!accepted) client.close();
    }
  }

  Future<String> _authenticate(
    _WebVpnCookieClient client,
    WebVpnAuthentication attempt,
    Future<void> abort,
  ) async {
    var uri = _portal;
    var sawCas = false;
    var returned = false;
    var openedLauncher = false;
    var submitted = false;
    Map<String, String>? fields;
    Uri? referer;

    for (var step = 0; step < 10; step++) {
      attempt.cancellation.check();
      if (_device.allows(uri)) {
        throw CampusAccessFailure.deviceVerificationRequired;
      }
      final isCas = _isCas(uri);
      if (isCas) {
        if (!_validCas(uri, requireService: !sawCas)) {
          throw CampusAccessFailure.unsafeEndpoint;
        }
        if (returned) throw CampusAccessFailure.authenticationRejected;
        sawCas = true;
      } else if (sawCas && !returned && _isCasReturn(uri)) {
        returned = true;
      } else if (uri != _portal &&
          uri != portalCasEntry &&
          !(returned && uri == identityPage)) {
        if (_isIdentityOrigin(uri) && uri.path.startsWith('/authserver/')) {
          throw CampusAccessFailure.verificationRequired;
        }
        throw CampusAccessFailure.unsafeEndpoint;
      }
      if (uri == portalCasEntry) openedLauncher = true;

      final request = http.AbortableRequest(
        fields == null ? 'GET' : 'POST',
        uri,
        abortTrigger: abort,
      )..followRedirects = false;
      request.headers['Accept'] = 'text/html';
      final sendingPassword = fields != null;
      if (sendingPassword) {
        request.headers['Origin'] = uri.origin;
        request.headers['Referer'] = referer.toString();
        request.bodyFields = fields;
        fields = null;
      }
      final response = await client.send(request);
      final status = response.statusCode;
      diagnostics.record(
        DiagnosticModule.webVpn,
        DiagnosticStage.request,
        level: DiagnosticSeverity.debug,
        httpStatus: status,
        route: CampusAccessRoute.webVpn,
      );
      if (_redirects.contains(status)) {
        await response.stream.listen(null).cancel();
        final next = _resolve(uri, response.headers['location']);
        if (next == null) throw CampusAccessFailure.unsafeEndpoint;
        if (sendingPassword && (status == 307 || status == 308)) {
          throw CampusAccessFailure.authenticationRejected;
        }
        uri = next;
        continue;
      }
      if (status == 429 || status >= 500) {
        await response.stream.listen(null).cancel();
        throw status == 429
            ? CampusAccessFailure.rateLimited
            : CampusAccessFailure.server;
      }

      final page = await _html(response, attempt.cancellation);
      if (isCas && submitted && schoolCasPasswordRejected(page)) {
        throw CampusAccessFailure.invalidCredentials;
      }
      switch (schoolCasChallenge(page)) {
        case SchoolCasChallenge.captcha:
          throw CampusAccessFailure.captchaRequired;
        case SchoolCasChallenge.device:
          throw CampusAccessFailure.deviceVerificationRequired;
        case SchoolCasChallenge.additional:
          throw CampusAccessFailure.verificationRequired;
        case null:
          break;
      }
      if (status == 401 || status == 403) {
        throw CampusAccessFailure.unauthorized;
      }
      if (status != 200) throw CampusAccessFailure.invalidResponse;

      if (isCas) {
        if (submitted) throw CampusAccessFailure.authenticationRejected;
        final form = SchoolCasPasswordForm.parse(page);
        if (form == null) throw CampusAccessFailure.verificationRequired;
        final target = _resolve(uri, form.action);
        if (target == null || !_validCas(target, requireService: false)) {
          throw CampusAccessFailure.unsafeEndpoint;
        }
        final credentials = await attempt.readRemembered();
        if (credentials == null) throw CampusAccessFailure.credentialsRequired;
        if (schoolSubjectForStudentCode(credentials.username) !=
            attempt.subject) {
          throw CampusAccessFailure.accountMismatch;
        }
        attempt.cancellation.check();
        fields = form.fields(credentials.username, credentials.password);
        referer = uri;
        uri = target;
        submitted = true;
      } else if (returned) {
        if (uri != identityPage) {
          uri = identityPage;
          continue;
        }
        if (page.querySelector('form#casLoginForm, input[type="password"]') !=
            null) {
          throw CampusAccessFailure.authenticationRejected;
        }
        final subject = verifiedSubject(page);
        if (subject == null) throw CampusAccessFailure.authenticationRejected;
        return subject;
      } else if (!openedLauncher &&
          page
              .querySelectorAll('a[href]')
              .where(schoolElementVisible)
              .any(
                (link) =>
                    _resolve(uri, link.attributes['href']) == portalCasEntry,
              )) {
        uri = portalCasEntry;
      } else {
        throw CampusAccessFailure.verificationRequired;
      }
    }
    throw CampusAccessFailure.invalidResponse;
  }

  void _validateConfiguration() {
    for (final entry in [portalCasEntry, casReturn, identityPage]) {
      if (!const CampusUrlScope(
            officialWebVpnHost,
            '/',
            subtree: true,
          ).allows(entry) ||
          _device.allows(entry) ||
          entry.queryParametersAll.containsKey('ticket')) {
        throw CampusAccessFailure.unsafeEndpoint;
      }
    }
    if (portalCasEntry == _portal ||
        casReturn == portalCasEntry ||
        casReturn == identityPage) {
      throw CampusAccessFailure.unsafeEndpoint;
    }
  }

  bool _isCas(Uri uri) => _isIdentityOrigin(uri) && _casPath.hasMatch(uri.path);

  bool _isIdentityOrigin(Uri uri) => const CampusUrlScope(
    schoolIdentityHost,
    '/authserver',
    subtree: true,
  ).allows(uri);

  bool _validCas(Uri uri, {required bool requireService}) {
    if (!_isCas(uri)) return false;
    final query = uri.queryParametersAll;
    final service = query['service'];
    if (query.containsKey('ticket')) return false;
    if (service == null) return !requireService;
    return service.length == 1 && Uri.tryParse(service.single) == casReturn;
  }

  bool _isCasReturn(Uri uri) {
    if (!CampusUrlScope(officialWebVpnHost, casReturn.path).allows(uri)) {
      return false;
    }
    final query = uri.queryParametersAll;
    final ticket = query['ticket'];
    final expected = casReturn.queryParametersAll;
    return ticket != null &&
        ticket.length == 1 &&
        RegExp(r'^[!-~]{1,512}$').hasMatch(ticket.single) &&
        query.length == expected.length + 1 &&
        expected.entries.every((entry) {
          final values = query[entry.key];
          return values != null &&
              values.length == entry.value.length &&
              values.indexed.every(
                (value) => entry.value[value.$1] == value.$2,
              );
        });
  }

  static Uri? _resolve(Uri base, String? location) {
    if (location == null ||
        location.trim().isEmpty ||
        location.contains(r'\')) {
      return null;
    }
    final reference = Uri.tryParse(location);
    return reference == null ? null : base.resolveUri(reference);
  }

  Future<Document> _html(
    http.StreamedResponse response,
    CampusCancellation cancellation,
  ) async {
    if (response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase() !=
        'text/html') {
      await response.stream.listen(null).cancel();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw CampusAccessFailure.unauthorized;
      }
      throw CampusAccessFailure.invalidResponse;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      cancellation.check();
      if (bytes.length + chunk.length > CampusAccessLimits.responseBytes) {
        throw CampusAccessFailure.invalidResponse;
      }
      bytes.add(chunk);
    }
    return html.parse(utf8.decode(bytes.takeBytes()));
  }
}

class _WebVpnCookieClient extends http.BaseClient {
  _WebVpnCookieClient(this._inner, this._now);

  final http.Client _inner;
  final DateTime Function() _now;
  final _cookies =
      <
        (String, String, String),
        ({Cookie cookie, bool hostOnly, DateTime? expires})
      >{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw CampusAccessFailure.cancelled;
    final uri = request.url;
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.authority.contains('@') ||
        !const {officialWebVpnHost, schoolIdentityHost}.contains(uri.host)) {
      throw CampusAccessFailure.unsafeEndpoint;
    }
    request.followRedirects = false;
    final now = _now();
    _cookies.removeWhere((_, cookie) => cookie.expires?.isAfter(now) == false);
    final matching = _cookies.entries.where((entry) {
      final (domain, path, _) = entry.key;
      return (entry.value.hostOnly
              ? uri.host == domain
              : _matchesDomain(uri.host, domain)) &&
          (uri.path == path ||
              uri.path.startsWith(path.endsWith('/') ? path : '$path/')) &&
          (!entry.value.cookie.secure || uri.scheme == 'https');
    }).toList()..sort((a, b) => b.key.$2.length.compareTo(a.key.$2.length));
    if (matching.isNotEmpty) {
      request.headers['Cookie'] = matching
          .map((entry) {
            final cookie = entry.value.cookie;
            return '${cookie.name}=${cookie.value}';
          })
          .join('; ');
    }
    final response = await _inner.send(request);
    if (!_closed) {
      for (final header
          in response.headersSplitValues['set-cookie'] ?? const <String>[]) {
        _remember(uri, header, _now());
      }
    }
    return response;
  }

  void _remember(Uri uri, String header, DateTime now) {
    try {
      final cookie = Cookie.fromSetCookieValue(header);
      final declaredDomain = cookie.domain?.toLowerCase().replaceFirst(
        RegExp(r'^\.'),
        '',
      );
      final domain = declaredDomain ?? uri.host;
      if (!_matchesDomain(domain, 'neuq.edu.cn') ||
          !_matchesDomain(uri.host, domain)) {
        return;
      }
      if (cookie.name.startsWith('__Host-') &&
              (declaredDomain != null ||
                  cookie.path != '/' ||
                  !cookie.secure) ||
          cookie.name.startsWith('__Secure-') && !cookie.secure) {
        return;
      }
      final lastSlash = uri.path.lastIndexOf('/');
      final path = cookie.path?.startsWith('/') == true
          ? cookie.path!
          : lastSlash <= 0
          ? '/'
          : uri.path.substring(0, lastSlash);
      final maxAge = cookie.maxAge;
      final expiry = maxAge == null
          ? cookie.expires
          : now.add(Duration(seconds: maxAge.clamp(0, 31536000)));
      final key = (domain, path, cookie.name);
      if (expiry?.isAfter(now) == false) {
        _cookies.remove(key);
      } else if (_cookies.length < 64 || _cookies.containsKey(key)) {
        _cookies[key] = (
          cookie: cookie,
          hostOnly: declaredDomain == null,
          expires: expiry,
        );
      }
    } on FormatException {
      // Ignore malformed Set-Cookie headers.
    }
  }

  static bool _matchesDomain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _cookies.clear();
    _inner.close();
  }
}
