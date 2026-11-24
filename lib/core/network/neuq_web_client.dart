import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../auth/neuq_login_protocol.dart';

enum SchoolWebFailure implements Exception {
  expired,
  differentAccount,
  unavailable,
  denied,
}

enum NeuqPage {
  timetable('/eams/courseTableForStd.action', ajax: true),
  calendar('/eams/dataQuery.action', ajax: true),
  schedule('/eams/courseTableForStd!courseTable.action', ajax: true),
  grades('/eams/teach/grade/course/person!historyCourseGrade.action'),
  rooms('/eams/classroom/apply/free.action'),
  roomResult('/eams/classroom/apply/free!search.action', ajax: true);

  const NeuqPage(this.path, {this.ajax = false});
  final String path;
  final bool ajax;

  Uri requestUri([Map<String, String> query = const {}]) {
    final parameters = {
      if (ajax && this != roomResult) 'sf_request_type': 'ajax',
      ...query,
    };
    return Uri.https(
      schoolAcademicHost,
      path,
      parameters.isEmpty ? null : parameters,
    );
  }

  bool get followsAcademicRedirects => this == roomResult;
}

/// Runs read-only requests within the app's first-party WebView cookie store.
/// Each batch starts by verifying the signed-in account against its local DB.
class NeuqWebClient {
  NeuqWebClient(this.subject);

  static const _channel = 'NeuqReadReply';
  static const _timeout = Duration(seconds: 18);
  final String subject;
  final _replies = <String, Completer<Map<String, dynamic>>>{};
  WebViewController? _controller;
  Completer<SchoolWebFailure?>? _home;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  bool _reconnecting = false;
  int _generation = 0;

  Future<T?> reconnect<T>(Future<T?> Function() open) async {
    if (_disposed || _reconnecting) return null;
    _reconnecting = true;
    _generation++;
    try {
      return await open();
    } finally {
      _reconnecting = false;
    }
  }

  Future<T> read<T>(Future<T> Function() operation) {
    final request = _tail.then((_) async {
      if (_disposed) throw SchoolWebFailure.unavailable;
      if (_reconnecting) throw SchoolWebFailure.expired;
      final generation = _generation;
      await _verifyHome();
      _checkGeneration(generation);
      final result = await operation();
      _checkGeneration(generation);
      return result;
    });
    _tail = request.then<void>((_) {}, onError: (Object _) {});
    return request;
  }

  void _checkGeneration(int generation) {
    if (_disposed) throw SchoolWebFailure.unavailable;
    if (_generation != generation) throw SchoolWebFailure.expired;
  }

  Future<void> _verifyHome() async {
    final controller = await _openDocument(schoolWebEntry);
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        if (_disposed) throw SchoolWebFailure.unavailable;
        final url = Uri.tryParse(await controller.currentUrl() ?? '');
        if (url == null || !isAcademicDocument(url)) {
          throw SchoolWebFailure.expired;
        }
        final evidence = await controller.runJavaScriptReturningResult(
          schoolIdentityProbe,
        );
        final verified = schoolSubjectFromEvidence(url, evidence);
        if (verified != null) {
          if (verified != subject) throw SchoolWebFailure.differentAccount;
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      throw SchoolWebFailure.expired;
    } on SchoolWebFailure {
      rethrow;
    } catch (_) {
      throw SchoolWebFailure.unavailable;
    }
  }

  Future<WebViewController> _openDocument(Uri address) async {
    final home = _home = Completer<SchoolWebFailure?>();
    try {
      if (_disposed) throw SchoolWebFailure.unavailable;
      final controller = _controller ??= await _createController();
      if (_disposed) throw SchoolWebFailure.unavailable;
      await controller.loadRequest(address);
      final failure = await home.future.timeout(_timeout);
      if (failure != null) throw failure;
      return controller;
    } on SchoolWebFailure {
      rethrow;
    } catch (_) {
      throw SchoolWebFailure.unavailable;
    } finally {
      _home = null;
    }
  }

  Future<WebViewController> _createController() async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      _channel,
      onMessageReceived: _receive,
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final url = Uri.tryParse(request.url);
          final address = url == null ? null : academicReadAddress(url);
          if (address != null && address == url) {
            return NavigationDecision.navigate;
          }
          if (request.isMainFrame && address != null) {
            unawaited(
              controller.loadRequest(address).catchError((Object _) {
                _finishDocument(SchoolWebFailure.unavailable);
              }),
            );
            return NavigationDecision.prevent;
          }
          if (!request.isMainFrame && request.url == 'about:blank') {
            return NavigationDecision.navigate;
          }
          if (request.isMainFrame) {
            _finishDocument(
              url != null && _requiresSchoolLogin(url)
                  ? SchoolWebFailure.expired
                  : SchoolWebFailure.unavailable,
            );
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: (url) {
          final document = Uri.tryParse(url);
          if (document != null && isAcademicDocument(document)) {
            _finishDocument(null);
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != false) {
            _finishDocument(SchoolWebFailure.unavailable);
          }
        },
      ),
    );
    return controller;
  }

  void _finishDocument(SchoolWebFailure? failure) {
    final home = _home;
    if (home != null && !home.isCompleted) home.complete(failure);
  }

  Future<void> prepareClassroomQuery() async {
    try {
      await _openDocument(NeuqPage.rooms.requestUri());
    } on SchoolWebFailure catch (error) {
      if (error != SchoolWebFailure.expired) rethrow;
      await _rejectSignIn(NeuqPage.roomResult);
    }
  }

  Future<Map<String, String>> classroomBuildingIds(List<String> names) async {
    final controller = _controller;
    if (controller == null) return const {};
    try {
      final result = await controller.runJavaScriptReturningResult(
        '($_classroomOptions)(${jsonEncode(names)})',
      );
      if (result is! String) return const {};
      final decoded = jsonDecode(result);
      final options = decoded is String ? jsonDecode(decoded) : decoded;
      if (options is! Map) return const {};
      final number = RegExp(r'^\d{1,10}$');
      return {
        for (final name in names)
          if (options[name] case final String id when number.hasMatch(id))
            name: id,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Never> _rejectSignIn(NeuqPage page) async {
    if (page.followsAcademicRedirects) {
      await _verifyHome();
      throw SchoolWebFailure.denied;
    }
    throw SchoolWebFailure.expired;
  }

  Future<String> request(
    NeuqPage page, {
    Map<String, String> query = const {},
    Map<String, String>? form,
  }) async {
    final controller = _controller;
    if (_disposed || controller == null) throw SchoolWebFailure.unavailable;
    if (_reconnecting) throw SchoolWebFailure.expired;
    final uri = page.requestUri(query);
    final id = const Uuid().v4();
    final reply = _replies[id] = Completer<Map<String, dynamic>>();
    final payload = jsonEncode({
      'url': uri.toString(),
      'id': id,
      'form': form,
      'ajax': page.ajax,
      'followAcademicRedirects': page.followsAcademicRedirects,
    });
    try {
      await controller.runJavaScript('($_readScript)($payload)');
      final result = await reply.future.timeout(_timeout);
      final status = result['status'];
      if (status == 401 || result['redirected'] == true) {
        await _rejectSignIn(page);
      }
      if (status == 403) throw SchoolWebFailure.denied;
      if (page.followsAcademicRedirects && status == null) {
        await _verifyHome();
      }
      final body = result['body'];
      if (status != 200 || body is! String) throw SchoolWebFailure.unavailable;
      final finalUrl = result['url'];
      final document = finalUrl is String ? Uri.tryParse(finalUrl) : null;
      if (document == null || !isAcademicDocument(document)) {
        if (document == null || !_requiresSchoolLogin(document)) {
          throw SchoolWebFailure.unavailable;
        }
        await _rejectSignIn(page);
      }
      if (RegExp(
        r'''type\s*=\s*["']?password\b''',
        caseSensitive: false,
      ).hasMatch(body)) {
        await _rejectSignIn(page);
      }
      return body;
    } on SchoolWebFailure {
      rethrow;
    } catch (_) {
      throw SchoolWebFailure.unavailable;
    } finally {
      _replies.remove(id);
    }
  }

  void _receive(JavaScriptMessage message) {
    if (_disposed || message.message.length > 6 * 1024 * 1024) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map<String, dynamic> ||
          data['origin'] != 'https://$schoolAcademicHost') {
        return;
      }
      final reply = _replies[data['id']];
      if (reply != null && !reply.isCompleted) reply.complete(data);
    } on FormatException {
      return;
    }
  }

  void dispose() {
    _disposed = true;
    final home = _home;
    if (home != null && !home.isCompleted) {
      home.complete(SchoolWebFailure.unavailable);
    }
    for (final reply in _replies.values) {
      if (!reply.isCompleted) reply.complete(const {});
    }
    _controller = null;
  }
}

bool _requiresSchoolLogin(Uri document) =>
    schoolNavigation(document) != SchoolNavigation.block &&
    (document.host == schoolIdentityHost ||
        document.path.toLowerCase().contains('login'));

const _classroomOptions = r'''
names => {
  if (location.origin !== "https://jwxt.neuq.edu.cn" ||
      !location.pathname.startsWith("/eams/classroom/apply/free")) return "{}";
  const control = document.querySelector('select[name="classroom.building.id"]');
  if (!control) return "{}";
  const result = {};
  for (const name of names) {
    const ids = new Set([...control.options]
      .filter(option => !option.disabled && /^\d+$/.test(option.value) &&
        option.label.replace(/\s+/g, "").includes(name))
      .map(option => option.value));
    if (ids.size === 1) result[name] = [...ids][0];
  }
  return JSON.stringify(result);
}
''';

const _readScript = r'''
async ({id, url, form, ajax, followAcademicRedirects}) => {
  const origin = "https://jwxt.neuq.edu.cn";
  if (location.origin !== origin || new URL(url).origin !== origin) return;
  const send = value => NeuqReadReply.postMessage(JSON.stringify({id, origin, ...value}));
  const timer = new AbortController();
  const deadline = setTimeout(() => timer.abort(), 12000);
  try {
    const response = await fetch(url, {
      method: form === null ? "GET" : "POST",
      body: form === null ? undefined : new URLSearchParams(form),
      headers: ajax ? {"X-Requested-With": "XMLHttpRequest"} : undefined,
      credentials: "same-origin",
      mode: "same-origin",
      redirect: followAcademicRedirects ? "follow" : "manual",
      cache: "no-store",
      signal: timer.signal,
    });
    const body = response.ok ? await response.text() : undefined;
    send({status: response.status, url: response.url, redirected: response.type === "opaqueredirect",
      body: body && body.length > 2000000 ? undefined : body});
  } catch (_) {
    send({});
  } finally {
    clearTimeout(deadline);
  }
}
''';
