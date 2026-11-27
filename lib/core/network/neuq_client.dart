import 'dart:async';
import 'dart:convert';
import 'dart:io' show Cookie, HttpDate, HttpException;
import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../auth/neuq_login_protocol.dart';
import '../diagnostics/diagnostics.dart';

enum SchoolSessionHealth { unknown, restoring, connected, expired, offline }

enum SchoolRecoveryTrigger {
  foreground(DiagnosticStage.foregroundRecovery),
  manual(DiagnosticStage.manualRecovery),
  academicRead(DiagnosticStage.academicRecovery),
  campusCard(DiagnosticStage.campusCardRecovery);

  const SchoolRecoveryTrigger(this.stage);
  final DiagnosticStage stage;
}

typedef SchoolSessionStatus = ({String? subject, SchoolSessionHealth health});

DiagnosticCode schoolFailureCode(Object error) => switch (error) {
  SchoolRequestFailure.expired ||
  SchoolRequestFailure.sessionRejected => DiagnosticCode.sessionExpired,
  SchoolRequestFailure.cancelled => DiagnosticCode.recoveryCancelled,
  SchoolRequestFailure.unavailable => DiagnosticCode.unavailable,
  SchoolRequestFailure.denied ||
  SchoolRequestFailure.differentAccount ||
  SchoolRequestFailure.invalidCredentials ||
  SchoolRequestFailure.verificationRequired => DiagnosticCode.rejected,
  SchoolRequestFailure.unsupportedLogin => DiagnosticCode.invalidData,
  FormatException() || TypeError() => DiagnosticCode.invalidData,
  _ => DiagnosticCode.unexpected,
};

enum SchoolRequestFailure implements Exception {
  expired('教务登录已过期，请重新连接。'),
  sessionRejected('教务会话暂时无法恢复，请稍后重试。'),
  differentAccount('请使用当前工作台对应的学校账号。'),
  invalidCredentials('学校未接受这组账号和密码，请核对后重试。'),
  verificationRequired('学校要求额外验证，可在系统浏览器打开官方教务。'),
  unsupportedLogin('学校的登录流程暂不受支持，请在系统浏览器访问教务。'),
  unavailable('暂时无法连接学校系统，请检查网络后重试。'),
  denied('学校暂未开放此访问，请稍后重试。'),
  cancelled('教务连接操作已取消。');

  const SchoolRequestFailure(this.message);
  final String message;

  bool get requiresCredentials =>
      this == expired || this == invalidCredentials || this == differentAccount;

  bool get requiresOfficialLogin =>
      this == verificationRequired || this == unsupportedLogin;
}

class NeuqCredentials {
  const NeuqCredentials(this.username, this.password);

  final String username;
  final String password;
}

enum NeuqPage {
  timetable('/eams/courseTableForStd.action', ajax: true),
  calendar('/eams/dataQuery.action', ajax: true),
  schedule('/eams/courseTableForStd!courseTable.action', ajax: true),
  grades('/eams/teach/grade/course/person!historyCourseGrade.action');

  const NeuqPage(this.path, {this.ajax = false});
  final String path;
  final bool ajax;

  Uri requestUri([Map<String, String> query = const {}]) {
    final parameters = {if (ajax) 'sf_request_type': 'ajax', ...query};
    return Uri.https(
      schoolAcademicHost,
      path,
      parameters.isEmpty ? null : parameters,
    );
  }
}

class NeuqClient {
  NeuqClient({
    required this.readRemembered,
    required this.forgetRemembered,
    this.onSessionStatus,
    http.Client Function()? createClient,
    DateTime Function()? clock,
  }) : _createClient = createClient ?? http.Client.new,
       _now = clock ?? DateTime.now;

  final Future<NeuqCredentials?> Function(String subject) readRemembered;
  final Future<void> Function(String subject) forgetRemembered;
  final void Function(SchoolSessionStatus)? onSessionStatus;
  final http.Client Function() _createClient;
  final DateTime Function() _now;
  static const _accessCooldown = Duration(minutes: 5);
  static const _foregroundCheckInterval = Duration(seconds: 5);
  Future<void> _tail = Future.value();
  NeuqSession? _session;
  String? _subject;
  SchoolSessionStatus _status = (
    subject: null,
    health: SchoolSessionHealth.unknown,
  );
  ({String subject, int generation, Future<bool> result})? _recovery;
  DateTime? _retryAfter;
  DateTime? _lastForegroundCheck;
  DateTime? _accessBlockedUntil;
  SchoolRequestFailure? _renewalFailure;
  bool _schoolAccessDenied = false;
  int _temporaryFailures = 0;
  bool _manualRetryUsed = false;
  int _generation = 0;
  int _confirmation = 0;
  bool _disposed = false;
  bool _signedOut = false;

  Future<String> signIn(
    NeuqCredentials credentials, {
    String? expectedSubject,
    required Future<void> Function(String) onVerified,
  }) {
    _generation++;
    return _queue((generation) async {
      if (expectedSubject != null) _checkSubject(expectedSubject);
      try {
        _checkAccess();
        if (expectedSubject != null) {
          _publish(expectedSubject, SchoolSessionHealth.restoring, generation);
        }
        final subject = await _signIn(
          credentials,
          expectedSubject,
          generation,
          onVerified,
        );
        _checkGeneration(generation);
        _signedOut = false;
        _schoolAccessDenied = false;
        _resetRetry();
        _confirm(subject, generation);
        return subject;
      } catch (error) {
        _recordFailure(DiagnosticStage.signIn, error);
        final subject = expectedSubject ?? _subject;
        if (subject != null) _publishFailure(subject, error, generation);
        rethrow;
      }
    });
  }

  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) {
    final pending = _recovery;
    if (pending != null &&
        pending.generation == _generation &&
        pending.subject == subject) {
      _recordRecovery(trigger, DiagnosticCode.recoveryJoined);
      return pending.result;
    }
    final generation = _generation;
    final confirmation = _confirmation;
    final result =
        _queue((generation) async {
          if (isForeground?.call() == false) return false;
          _checkSubject(subject);
          if (_confirmation != confirmation &&
              _status.health == SchoolSessionHealth.connected) {
            _recordRecovery(trigger, DiagnosticCode.recoveryJoined);
            return true;
          }
          if (trigger == SchoolRecoveryTrigger.foreground) {
            final lastCheck = _lastForegroundCheck;
            if (lastCheck != null) {
              final elapsed = _now().difference(lastCheck);
              if (!elapsed.isNegative && elapsed < _foregroundCheckInterval) {
                _recordRecovery(trigger, DiagnosticCode.checkInterval);
                return false;
              }
            }
          }
          await _recover(subject, generation, trigger);
          _checkGeneration(generation);
          if (trigger == SchoolRecoveryTrigger.foreground) {
            _lastForegroundCheck = _now();
          }
          _schoolAccessDenied = false;
          _resetRetry();
          _confirm(subject, generation);
          return true;
        }).whenComplete(() {
          if (_recovery?.generation == generation &&
              _recovery?.subject == subject) {
            _recovery = null;
          }
        });
    _recovery = (subject: subject, generation: generation, result: result);
    return result;
  }

  Future<T> read<T>(
    String subject,
    Future<T> Function(NeuqSession) operation,
  ) => _queue((generation) async {
    _checkSubject(subject);
    try {
      _checkAccess();
      final result = await _readAcademic(subject, operation, generation);
      _checkGeneration(generation);
      if (_retryAfter != null) _resetRetry();
      _confirm(subject, generation);
      return result;
    } catch (error) {
      _recordFailure(DiagnosticStage.request, error);
      if (generation == _generation &&
          error == SchoolRequestFailure.verificationRequired &&
          _renewalFailure != error) {
        _deferRecovery(error);
      }
      _publishFailure(subject, error, generation);
      rethrow;
    }
  });

  Future<T> _readAcademic<T>(
    String subject,
    Future<T> Function(NeuqSession) operation,
    int generation,
  ) async {
    final current = _session;
    if (current != null) {
      try {
        return await operation(current);
      } on SchoolRequestFailure catch (error) {
        if (error != SchoolRequestFailure.expired) rethrow;
        _checkGeneration(generation);
      }
    }
    final recovered = await _recover(
      subject,
      generation,
      SchoolRecoveryTrigger.academicRead,
      rejectedByRequest: true,
    );
    try {
      return await operation(recovered);
    } on SchoolRequestFailure catch (error) {
      if (error != SchoolRequestFailure.expired) rethrow;
      _checkGeneration(generation);
      _clearSession();
      _deferRecovery(SchoolRequestFailure.sessionRejected);
      throw SchoolRequestFailure.sessionRejected;
    } on FormatException {
      _checkGeneration(generation);
      _confirm(subject, generation);
      rethrow;
    }
  }

  Future<Uri> campusCardSignIn(String subject, Uri login) =>
      _queue((generation) async {
        _checkSubject(subject);
        _checkAccess();
        final service = campusCardCasService(login);
        if (service == null) throw SchoolRequestFailure.unsupportedLogin;
        final current = _session;
        if (current != null) {
          try {
            return await current._campusCardReturn(login, service);
          } on SchoolRequestFailure catch (error) {
            if (error != SchoolRequestFailure.expired) rethrow;
            _checkGeneration(generation);
          }
        }
        final renewed = await _recover(
          subject,
          generation,
          SchoolRecoveryTrigger.campusCard,
          rejectedByRequest: true,
        );
        _checkGeneration(generation);
        _resetRetry();
        _confirm(subject, generation);
        return renewed._campusCardReturn(login, service);
      });

  Future<NeuqSession> _recover(
    String subject,
    int generation,
    SchoolRecoveryTrigger trigger, {
    bool rejectedByRequest = false,
  }) async {
    _checkRecoveryAllowed(trigger);
    _recordRecovery(trigger, DiagnosticCode.recoveryStarted);
    _publish(subject, SchoolSessionHealth.restoring, generation);
    try {
      final current = _session;
      NeuqSession? verified;
      if (current != null) {
        final cookies =
            rejectedByRequest && trigger == SchoolRecoveryTrigger.academicRead
            ? current._academicCookies
            : null;
        if (await _verify(current, subject, generation)) {
          verified = current;
          // A valid landing page can still leave a read endpoint logged out.
          // Prefer a renewed login before spending that read's single retry.
          if (!rejectedByRequest ||
              cookies != null &&
                  !_sameCookies(cookies, current._academicCookies)) {
            _recordRecovery(trigger, DiagnosticCode.completed);
            return current;
          }
        }
      }
      final session = await _renew(subject, generation) ?? verified;
      if (session == null) throw SchoolRequestFailure.expired;
      _recordRecovery(trigger, DiagnosticCode.completed);
      return session;
    } catch (error) {
      _recordFailure(trigger.stage, error);
      _checkGeneration(generation);
      _deferRecovery(error);
      _publishFailure(subject, error, generation);
      if (error == SchoolRequestFailure.invalidCredentials ||
          error == SchoolRequestFailure.differentAccount) {
        try {
          await forgetRemembered(subject);
        } catch (storageError) {
          _recordFailure(DiagnosticStage.clear, storageError);
        }
      }
      _checkGeneration(generation);
      rethrow;
    }
  }

  Future<bool> _verify(
    NeuqSession current,
    String subject,
    int generation,
  ) async {
    try {
      final verified = await current.verify(
        checkActive: () => _checkGeneration(generation),
      );
      _checkGeneration(generation);
      if (verified == subject) return true;
      _clearSession();
      throw SchoolRequestFailure.differentAccount;
    } on SchoolRequestFailure catch (error) {
      if (error != SchoolRequestFailure.expired) rethrow;
      _checkGeneration(generation);
      _clearSession();
      return false;
    }
  }

  Future<NeuqSession?> _renew(String subject, int generation) async {
    final credentials = await readRemembered(subject);
    _checkGeneration(generation);
    if (credentials == null) return null;
    try {
      await _signIn(credentials, subject, generation, (_) async {});
      _checkGeneration(generation);
      return _session!;
    } catch (error) {
      _recordFailure(DiagnosticStage.renew, error);
      if (error == SchoolRequestFailure.expired) {
        throw SchoolRequestFailure.sessionRejected;
      }
      rethrow;
    }
  }

  void _checkSubject(String subject) {
    if (_signedOut) throw SchoolRequestFailure.expired;
    if (_subject != null && _subject != subject) {
      throw SchoolRequestFailure.differentAccount;
    }
    _subject = subject;
  }

  bool get _accessBlocked => _accessBlockedUntil?.isAfter(_now()) == true;

  void _checkAccess() {
    if (_accessBlocked) throw SchoolRequestFailure.denied;
  }

  void _protectAccess(int status, String? retryAfter) {
    if (status == 403) _schoolAccessDenied = true;
    final now = _now();
    var until = now.add(_accessCooldown);
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      final DateTime requested;
      try {
        requested = seconds == null
            ? HttpDate.parse(retryAfter)
            : now.add(Duration(seconds: seconds.clamp(0, 31536000)));
        if (requested.isAfter(until)) until = requested;
      } on FormatException {
        // Use the default cooldown for a malformed Retry-After.
      } on HttpException {
        // Use the default cooldown for a malformed Retry-After.
      }
    }
    if (_accessBlockedUntil?.isAfter(until) != true) {
      _accessBlockedUntil = until;
    }
  }

  void _checkRecoveryAllowed(SchoolRecoveryTrigger trigger) {
    try {
      _checkAccess();
      if (_schoolAccessDenied && trigger != SchoolRecoveryTrigger.manual) {
        throw SchoolRequestFailure.denied;
      }
      final failure = _renewalFailure;
      if (failure == null) return;
      final retryAfter = _retryAfter;
      if (retryAfter == null) throw failure;
      if (!_now().isBefore(retryAfter)) return;
      if (trigger != SchoolRecoveryTrigger.manual ||
          failure != SchoolRequestFailure.unavailable ||
          _manualRetryUsed) {
        throw failure;
      }
      _manualRetryUsed = true;
    } catch (_) {
      _recordRecovery(trigger, DiagnosticCode.retryBackoff);
      rethrow;
    }
  }

  void _deferRecovery(Object error) {
    switch (error) {
      case SchoolRequestFailure.denied:
        break;
      case SchoolRequestFailure.expired ||
          SchoolRequestFailure.differentAccount ||
          SchoolRequestFailure.invalidCredentials ||
          SchoolRequestFailure.verificationRequired ||
          SchoolRequestFailure.unsupportedLogin:
        _renewalFailure = error as SchoolRequestFailure;
        _retryAfter = null;
      default:
        final seconds = min(60, 5 << min(_temporaryFailures, 4));
        _temporaryFailures++;
        _retryAfter = _now().add(Duration(seconds: seconds));
        _renewalFailure = error == SchoolRequestFailure.sessionRejected
            ? SchoolRequestFailure.sessionRejected
            : SchoolRequestFailure.unavailable;
    }
  }

  void _resetRetry() {
    _retryAfter = null;
    _renewalFailure = null;
    _temporaryFailures = 0;
    _manualRetryUsed = false;
  }

  void _confirm(String subject, int generation) {
    _confirmation++;
    _publish(subject, SchoolSessionHealth.connected, generation);
  }

  void _publish(String? subject, SchoolSessionHealth health, int generation) {
    if (!_disposed && generation == _generation) {
      final next = (subject: subject, health: health);
      if (_status == next) return;
      _status = next;
      onSessionStatus?.call(next);
    }
  }

  void _publishFailure(String subject, Object error, int generation) =>
      _publish(subject, switch (error) {
        SchoolRequestFailure.expired ||
        SchoolRequestFailure.sessionRejected ||
        SchoolRequestFailure.invalidCredentials ||
        SchoolRequestFailure.verificationRequired ||
        SchoolRequestFailure.unsupportedLogin ||
        SchoolRequestFailure.differentAccount => SchoolSessionHealth.expired,
        SchoolRequestFailure.denied when _session != null && !_accessBlocked =>
          SchoolSessionHealth.connected,
        FormatException() || TypeError() =>
          _status.health == SchoolSessionHealth.restoring
              ? SchoolSessionHealth.unknown
              : _status.health,
        SchoolRequestFailure.cancelled => _status.health,
        _ => SchoolSessionHealth.offline,
      }, generation);

  void _recordRecovery(SchoolRecoveryTrigger trigger, DiagnosticCode code) =>
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        trigger.stage,
        level: DiagnosticSeverity.debug,
        code: code,
      );

  void _recordFailure(DiagnosticStage stage, Object error) =>
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        stage,
        code: schoolFailureCode(error),
        error: error,
      );

  Future<String> _signIn(
    NeuqCredentials credentials,
    String? expectedSubject,
    int generation,
    Future<void> Function(String) onVerified,
  ) async {
    final claimedSubject = schoolSubjectForStudentCode(credentials.username);
    if (claimedSubject == null || credentials.password.isEmpty) {
      throw SchoolRequestFailure.invalidCredentials;
    }
    if (expectedSubject != null && claimedSubject != expectedSubject) {
      throw SchoolRequestFailure.differentAccount;
    }
    final candidate = NeuqSession._(_createClient(), _protectAccess);
    try {
      final subject = await candidate._authenticate(credentials, () {
        _checkGeneration(generation);
        _checkAccess();
      });
      _checkGeneration(generation);
      if (subject != claimedSubject) {
        throw SchoolRequestFailure.differentAccount;
      }
      await onVerified(subject);
      _checkGeneration(generation);
      _clearSession();
      _session = candidate;
      _subject = subject;
      return subject;
    } finally {
      if (!identical(_session, candidate)) candidate._close();
    }
  }

  Future<T> _queue<T>(
    Future<T> Function(int generation) operation, {
    bool cancelOnChange = true,
  }) {
    final generation = _generation;
    final result = _tail.then((_) async {
      if (cancelOnChange) _checkGeneration(generation);
      try {
        return await operation(generation);
      } finally {
        if (cancelOnChange) _checkGeneration(generation);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation) {
      throw SchoolRequestFailure.cancelled;
    }
  }

  void _clearSession() {
    _session?._close();
    _session = null;
  }

  Future<void> disconnect(Future<void> Function() erase) {
    _generation++;
    _signedOut = true;
    _subject = null;
    _lastForegroundCheck = null;
    _resetRetry();
    _clearSession();
    _publish(null, SchoolSessionHealth.unknown, _generation);
    return _queue((_) => erase(), cancelOnChange: false);
  }

  Future<void> forgetPassword(String subject) {
    if (_subject == null || _subject == subject) {
      _generation++;
      if (_status.health == SchoolSessionHealth.restoring) {
        _publish(subject, SchoolSessionHealth.unknown, _generation);
      }
    }
    // Later logins must wait for a requested storage mutation to complete.
    return _queue((_) => forgetRemembered(subject), cancelOnChange: false);
  }

  void dispose() {
    _disposed = true;
    _clearSession();
  }
}

class NeuqSession {
  NeuqSession._(this._http, this._protectAccess);

  static const _timeout = Duration(seconds: 15);
  static const _maxBytes = 2 * 1024 * 1024;
  static const _redirects = {301, 302, 303, 307, 308};
  final http.Client _http;
  final void Function(int status, String? retryAfter) _protectAccess;
  final _cookies = <(String, String, String), (Cookie, DateTime?)>{};

  Map<(String, String, String), String> get _academicCookies => {
    for (final entry in _cookies.entries)
      if (entry.key.$1 == schoolAcademicHost) entry.key: entry.value.$1.value,
  };

  Future<String> _authenticate(
    NeuqCredentials credentials,
    void Function() checkActive,
  ) async {
    final entry = await _navigate(schoolWebEntry, checkActive: checkActive);
    if (!isAcademicCasLogin(entry.uri)) {
      throw SchoolRequestFailure.unsupportedLogin;
    }
    final page = html.parse(entry.body);
    _checkChallenge(page);
    final forms = page.querySelectorAll('form#casLoginForm');
    if (forms.length != 1) throw SchoolRequestFailure.unsupportedLogin;
    final form = forms.single;
    final target = _resolveFrom(entry.uri, form.attributes['action']);
    if (target == null || form.attributes['method']?.toLowerCase() != 'post') {
      throw SchoolRequestFailure.unsupportedLogin;
    }
    if (!isAcademicCasLogin(target) ||
        schoolNavigation(target) != SchoolNavigation.allow ||
        target.origin != entry.uri.origin ||
        target.queryParameters.containsKey('service') &&
            target.queryParameters['service'] !=
                entry.uri.queryParameters['service']) {
      throw SchoolRequestFailure.unsupportedLogin;
    }
    String? field(String name) =>
        form.querySelector('input[name="$name"]')?.attributes['value'];
    final salt = utf8.encode(
      form.querySelector('#pwdDefaultEncryptSalt')?.attributes['value'] ?? '',
    );
    final lt = field('lt');
    final execution = field('execution');
    if (salt.length != 16 ||
        lt == null ||
        lt.isEmpty ||
        execution == null ||
        execution.isEmpty ||
        form.querySelector('[name="username"]') == null ||
        form.querySelector('[name="password"]') == null) {
      throw SchoolRequestFailure.unsupportedLogin;
    }
    checkActive();
    final result = await _navigate(
      target,
      form: {
        'username': credentials.username,
        'password': _encodePassword(credentials.password, salt),
        'lt': lt,
        'execution': execution,
        '_eventId': field('_eventId') ?? 'submit',
        'dllt': field('dllt') ?? 'userNamePasswordLogin',
        'rmShown': field('rmShown') ?? '1',
      },
      referer: entry.uri,
      checkActive: checkActive,
    );
    checkActive();
    if (isAcademicCasLogin(result.uri)) {
      final returned = html.parse(result.body);
      _checkChallenge(returned);
      if (RegExp(
        r'密码(?:不正确|错误)|账号或密码|用户名或密码|无效的凭据|invalid credentials',
        caseSensitive: false,
      ).hasMatch(returned.body?.text ?? '')) {
        throw SchoolRequestFailure.invalidCredentials;
      }
      throw SchoolRequestFailure.verificationRequired;
    }
    return _verifiedSubject(result, checkActive);
  }

  Future<String> verify({required void Function() checkActive}) async =>
      _verifiedSubject(
        await _navigate(schoolWebEntry, checkActive: checkActive),
        checkActive,
      );

  Future<Uri> _campusCardReturn(Uri login, Uri service) async {
    final response = await _send(login, campusCardSignIn: true);
    if (_redirects.contains(response.statusCode)) {
      await response.stream.listen(null).cancel();
      final callback = _resolveFrom(login, response.headers['location']);
      if (callback != null && isCampusCardCasReturn(service, callback)) {
        // The campus card WebView must redeem this service ticket itself.
        return callback;
      }
      throw SchoolRequestFailure.verificationRequired;
    }
    final page = html.parse(await _body(response));
    _checkChallenge(page);
    if (page.querySelector('form#casLoginForm, input[type="password"]') !=
        null) {
      throw SchoolRequestFailure.expired;
    }
    throw SchoolRequestFailure.verificationRequired;
  }

  Future<String> _verifiedSubject(
    ({Uri uri, String body}) result,
    void Function() checkActive,
  ) async {
    if (isAcademicCasLogin(result.uri)) {
      _checkChallenge(html.parse(result.body));
      throw SchoolRequestFailure.expired;
    }
    final doc = html.parse(result.body);
    if (doc.querySelector('input[type="password"]') != null) {
      _checkChallenge(doc);
      throw SchoolRequestFailure.expired;
    }
    final subject = schoolSubjectFromDocument(result.uri, doc);
    if (subject != null) return subject;
    final frames = doc
        .querySelectorAll('frame[src], iframe[src]')
        .where(schoolElementVisible)
        .map((frame) => _resolveFrom(result.uri, frame.attributes['src']))
        .whereType<Uri>()
        .toSet();
    final subjects = <String>{};
    for (final frame in frames.where(isAcademicDocument).take(4)) {
      final page = await _navigate(frame, checkActive: checkActive);
      final account = schoolSubjectFromDocument(
        page.uri,
        html.parse(page.body),
      );
      if (account != null) subjects.add(account);
    }
    if (subjects.length == 1) return subjects.single;
    throw const FormatException('无法确认教务页面中的学校身份');
  }

  Future<String> request(
    NeuqPage page, {
    Map<String, String> query = const {},
    Map<String, String>? form,
  }) async {
    final uri = page.requestUri(query);
    final response = await _send(
      uri,
      form: form,
      ajax: page.ajax,
      referer: schoolWebEntry,
    );
    if (_redirects.contains(response.statusCode)) {
      await response.stream.listen(null).cancel();
      final target = _resolveFrom(uri, response.headers['location']);
      if (target != null &&
          (isAcademicCasLogin(target) || _isAcademicLogin(target))) {
        throw SchoolRequestFailure.expired;
      }
      if (target != null &&
          target.host == schoolIdentityHost &&
          schoolNavigation(target) == SchoolNavigation.allow) {
        throw SchoolRequestFailure.verificationRequired;
      }
      throw SchoolRequestFailure.unavailable;
    }
    final body = await _body(response);
    if (RegExp(
      r'''type\s*=\s*["']?password\b''',
      caseSensitive: false,
    ).hasMatch(body)) {
      _checkChallenge(html.parse(body));
      throw SchoolRequestFailure.expired;
    }
    return body;
  }

  Future<({Uri uri, String body})> _navigate(
    Uri start, {
    Map<String, String>? form,
    Uri? referer,
    required void Function() checkActive,
  }) async {
    var uri = start;
    for (var count = 0; count < 8; count++) {
      checkActive();
      final target = academicSessionAddress(uri);
      if (target == null) {
        if (_isAcademicLogin(uri)) throw SchoolRequestFailure.expired;
        if (uri.host == schoolIdentityHost &&
            schoolNavigation(uri) == SchoolNavigation.allow) {
          throw SchoolRequestFailure.verificationRequired;
        }
        throw SchoolRequestFailure.unsupportedLogin;
      }
      final response = await _send(
        target,
        form: form,
        referer: referer,
        protectAuthentication: true,
      );
      if (form != null && response.statusCode == 401) {
        await response.stream.listen(null).cancel();
        throw SchoolRequestFailure.invalidCredentials;
      }
      if (!_redirects.contains(response.statusCode)) {
        return (uri: target, body: await _body(response));
      }
      await response.stream.listen(null).cancel();
      final next = _resolveFrom(target, response.headers['location']);
      if (next == null ||
          (form != null && const {307, 308}.contains(response.statusCode))) {
        throw SchoolRequestFailure.unsupportedLogin;
      }
      uri = next;
      referer = null;
      form = null;
    }
    throw SchoolRequestFailure.unavailable;
  }

  Future<http.StreamedResponse> _send(
    Uri uri, {
    Map<String, String>? form,
    Uri? referer,
    bool ajax = false,
    bool campusCardSignIn = false,
    bool protectAuthentication = false,
  }) async {
    final allowed = campusCardSignIn
        ? form == null && campusCardCasService(uri) != null
        : schoolNavigation(uri) == SchoolNavigation.allow;
    if (!allowed) {
      throw SchoolRequestFailure.unsupportedLogin;
    }
    final request = http.Request(form == null ? 'GET' : 'POST', uri)
      ..followRedirects = false;
    request.headers['Accept'] = 'text/html, application/json';
    if (ajax) request.headers['X-Requested-With'] = 'XMLHttpRequest';
    if (referer != null) request.headers['Referer'] = referer.toString();
    if (form != null) {
      request.headers['Origin'] = uri.origin;
      request.bodyFields = form;
    }
    final now = DateTime.now();
    _cookies.removeWhere(
      (_, value) => value.$2 != null && !value.$2!.isAfter(now),
    );
    final matching =
        _cookies.entries
            .where(
              (entry) =>
                  entry.key.$1 == uri.host &&
                  _matchesPath(uri.path, entry.key.$2),
            )
            .toList()
          ..sort((a, b) => b.key.$2.length.compareTo(a.key.$2.length));
    if (matching.isNotEmpty) {
      request.headers['Cookie'] = matching
          .map((entry) => '${entry.value.$1.name}=${entry.value.$1.value}')
          .join('; ');
    }
    try {
      final response = await _http.send(request).timeout(_timeout);
      if (response.statusCode == 429 ||
          response.statusCode == 403 && protectAuthentication) {
        _protectAccess(response.statusCode, response.headers['retry-after']);
        diagnostics.record(
          DiagnosticModule.schoolAuth,
          DiagnosticStage.request,
          code: response.statusCode == 429
              ? DiagnosticCode.rateLimited
              : DiagnosticCode.rejected,
          httpStatus: response.statusCode,
        );
      }
      for (final header
          in response.headersSplitValues['set-cookie'] ?? const []) {
        _rememberCookie(uri, header, now);
      }
      return response;
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        DiagnosticStage.request,
        error: error,
      );
      throw SchoolRequestFailure.unavailable;
    }
  }

  void _rememberCookie(Uri uri, String header, DateTime now) {
    try {
      final cookie = Cookie.fromSetCookieValue(header);
      final domain = cookie.domain?.toLowerCase().replaceFirst(
        RegExp(r'^\.'),
        '',
      );
      if (domain != null && domain != uri.host && domain != 'neuq.edu.cn') {
        return;
      }
      // Keep cookies scoped to the first-party host that issued them.
      final path = cookie.path;
      final prefix = path != null && path.startsWith('/')
          ? path
          : uri.path.substring(0, max(1, uri.path.lastIndexOf('/')));
      final key = (uri.host, prefix, cookie.name);
      final maxAge = cookie.maxAge;
      final expiry = maxAge == null
          ? cookie.expires
          : now.add(Duration(seconds: maxAge.clamp(0, 31536000)));
      if (expiry != null && !expiry.isAfter(now)) {
        _cookies.remove(key);
      } else if (_cookies.containsKey(key) || _cookies.length < 64) {
        _cookies[key] = (cookie, expiry);
      }
    } on FormatException {
      // Ignore invalid cookies without widening their scope.
    }
  }

  Future<String> _body(http.StreamedResponse response) async {
    final status = response.statusCode;
    if (status != 200) {
      await response.stream.listen(null).cancel();
      if (status == 401) throw SchoolRequestFailure.expired;
      if (status == 403 || status == 429) throw SchoolRequestFailure.denied;
      if (status >= 500) {
        diagnostics.record(
          DiagnosticModule.schoolAuth,
          DiagnosticStage.request,
          code: DiagnosticCode.serverError,
          httpStatus: status,
        );
      }
      throw SchoolRequestFailure.unavailable;
    }
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (bytes.length + chunk.length > _maxBytes) {
          throw SchoolRequestFailure.unavailable;
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes());
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        error is FormatException
            ? DiagnosticStage.decode
            : DiagnosticStage.request,
        error: error,
      );
      if (error is FormatException) rethrow;
      throw SchoolRequestFailure.unavailable;
    }
  }

  void _close() {
    _cookies.clear();
    _http.close();
  }
}

bool _sameCookies(Map<Object, String> previous, Map<Object, String> next) =>
    previous.length == next.length &&
    previous.entries.every((entry) => next[entry.key] == entry.value);

Uri? _resolveFrom(Uri base, String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final reference = Uri.tryParse(raw);
  return reference == null ? null : base.resolveUri(reference);
}

bool _matchesPath(String path, String prefix) =>
    path == prefix ||
    (prefix.endsWith('/')
        ? path.startsWith(prefix)
        : path.startsWith('$prefix/'));

bool _isAcademicLogin(Uri uri) =>
    uri.host == schoolAcademicHost &&
    schoolNavigation(uri) == SchoolNavigation.allow &&
    uri.path.toLowerCase().contains('login');

void _checkChallenge(Document page) {
  if (page.querySelector(
            'input[name="needCaptcha"][value="true"], input[name="needCaptcha"][value="1"]',
          ) !=
          null ||
      page
          .querySelectorAll(
            'input[name="captcha"], input[name="captchaResponse"], input[name="captchaCode"], input[name="otp"], input[name="smsCode"], input[autocomplete="one-time-code"], #captchaImg, [data-sitekey]',
          )
          .where((element) => element.attributes['type'] != 'hidden')
          .any(schoolElementVisible)) {
    throw SchoolRequestFailure.verificationRequired;
  }
  final visibleText = page
      .querySelectorAll('body, body *')
      .where(
        (node) =>
            !const {'script', 'style'}.contains(node.localName) &&
            schoolElementVisible(node),
      )
      .expand((node) => node.nodes.whereType<Text>())
      .map((node) => node.data)
      .join(' ');
  if (RegExp(r'请输入验证码|验证码错误|请完成验证|请拖动滑块|设备校验|双重登录认证|多因素认证')
      .hasMatch(visibleText)) {
    throw SchoolRequestFailure.verificationRequired;
  }
}

String _encodePassword(String password, List<int> salt) {
  // This is the CAS form's wire format. HTTPS protects the complete form.
  const alphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
  final random = Random.secure();
  int randomCharacter(int _) =>
      alphabet.codeUnitAt(random.nextInt(alphabet.length));
  final iv = Uint8List.fromList(List.generate(16, randomCharacter));
  final prefix = List.generate(64, randomCharacter);
  final bytes = Uint8List.fromList([...prefix, ...utf8.encode(password)]);
  try {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(Uint8List.fromList(salt)), iv),
              null,
            ),
          );
    return base64.encode(cipher.process(bytes));
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
