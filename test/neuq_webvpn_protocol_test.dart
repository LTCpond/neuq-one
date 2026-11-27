import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/network/campus_access/campus_resource.dart';
import 'package:neuq_one/core/network/campus_access/neuq_webvpn_protocol.dart';
import 'package:neuq_one/core/network/campus_access/webvpn_session_manager.dart';

const _student = '00000001';
const _password = 'synthetic-password';
const _launcher = '/fixture/launch';
const _return = '/fixture/return';
const _identity = '/fixture/identity';
final _subject = schoolSubjectForStudentCode(_student)!;
final _service = Uri.https(officialWebVpnHost, _return);
final _cas = Uri.https(schoolIdentityHost, '/authserver/login', {
  'service': _service.toString(),
});

void main() {
  test('CAS form is submitted once and only a verified portal subject opens a session', () async {
    final fixture = _Flow();
    final session = await fixture.login();
    addTearDown(session.close);
    expect(fixture.passwordReads, 1);
    expect(fixture.passwordPosts, 1);
    expect(session.subject, _subject);
    expect(session.logout, isNull);
    final response = await session.httpClient.get(
      Uri.https(officialWebVpnHost, '/fixture/read'),
    );
    expect(response.body, contains('vpn_session=fixture'));
    expect(response.body, contains('fixture_domain=fixture'));
    expect(response.body, isNot(contains('cas_host=')));
    expect(response.body, isNot(contains('unrelated=')));

    fixture.now = fixture.now.add(const Duration(seconds: 30));
    final expired = await session.httpClient.get(
      Uri.https(officialWebVpnHost, '/fixture/read'),
    );
    expect(expired.body, isNot(contains('vpn_session=')));
    expect(expired.body, contains('fixture_domain=fixture'));
    final pathMismatch = await session.httpClient.get(
      Uri.https(officialWebVpnHost, '/fixtures/read'),
    );
    expect(pathMismatch.body, isEmpty);
    await expectLater(
      session.httpClient.get(Uri.http(officialWebVpnHost, '/fixture/read')),
      throwsA(CampusAccessFailure.unsafeEndpoint),
    );

    final next = await fixture.login();
    next.close();
    expect(fixture.passwordPosts, 2);
  });

  test(
    'saved password is unnecessary for a school-issued CAS return on its own',
    () async {
      final fixture = _Flow()
        ..casPage = _redirect('$_service?ticket=fixture-ticket');
      final session = await fixture.login();
      session.close();
      expect(fixture.passwordReads, 0);
      expect(fixture.passwordPosts, 0);
    },
  );

  test(
    'device, captcha and extra verification stop without reading the password',
    () async {
      final device = _Flow()..portalPage = _redirect('/fingerprint');
      await expectLater(
        device.login(),
        throwsA(CampusAccessFailure.deviceVerificationRequired),
      );
      expect(device.paths, ['/']);
      expect(device.passwordReads, 0);
      for (final (markup, failure) in [
        (
          '<input name="needCaptcha" value="true">',
          CampusAccessFailure.captchaRequired,
        ),
        ('<input name="otp">', CampusAccessFailure.verificationRequired),
        ('<p>需要验证设备</p>', CampusAccessFailure.deviceVerificationRequired),
      ]) {
        final fixture = _Flow()..casPage = _html('$_form$markup');
        await expectLater(fixture.login(), throwsA(failure));
        expect(fixture.passwordReads, 0);
        expect(fixture.passwordPosts, 0);
      }
    },
  );

  test(
    'an unrecognized, missing or wrong password cannot open a session',
    () async {
      final missing = _Flow()..remembered = null;
      await expectLater(
        missing.login(),
        throwsA(CampusAccessFailure.credentialsRequired),
      );
      expect(missing.passwordReads, 1);
      expect(missing.passwordPosts, 0);

      final invalid = _Flow()
        ..posted = _html('<p>密码错误</p><input name="captcha">');
      await expectLater(
        invalid.login(),
        throwsA(CampusAccessFailure.invalidCredentials),
      );
      expect(invalid.passwordPosts, 1);

      final challenged = _Flow()
        ..posted = _html('<p>密码错误次数过多</p><input name="otp">');
      await expectLater(
        challenged.login(),
        throwsA(CampusAccessFailure.verificationRequired),
      );
      expect(challenged.passwordPosts, 1);

      final rejected = _Flow()..posted = _html('<p>未能登录</p>');
      await expectLater(
        rejected.login(),
        throwsA(CampusAccessFailure.authenticationRejected),
      );
      expect(rejected.passwordPosts, 1);

      final other = _Flow()..confirmedStudent = '00000002';
      await expectLater(
        other.login(),
        throwsA(CampusAccessFailure.accountMismatch),
      );
      final fakeSuccess = _Flow()..confirmedStudent = null;
      await expectLater(
        fakeSuccess.login(),
        throwsA(CampusAccessFailure.authenticationRejected),
      );
    },
  );

  test('foreign hosts, mismatched CAS services and untrusted forms stop before any password read', () async {
    final wrongService = _cas.replace(
      queryParameters: {'service': 'https://outside.example/fixture'},
    );
    for (final (launcher, action) in [
      ('https://outside.example/fixture', '/authserver/login'),
      (wrongService.toString(), '/authserver/login'),
      (_cas.toString(), 'https://outside.example/fixture'),
      (_cas.toString(), wrongService.toString()),
    ]) {
      final fixture = _Flow()
        ..launcherPage = _redirect(launcher)
        ..casPage = _html(_form.replaceFirst('/authserver/login', action));
      await expectLater(
        fixture.login(),
        throwsA(CampusAccessFailure.unsafeEndpoint),
      );
      expect(fixture.passwordReads, 0);
      expect(fixture.passwordPosts, 0);
    }
    final replay = _Flow()
      ..posted = _redirect('$_service?ticket=fixture-ticket', status: 307);
    await expectLater(
      replay.login(),
      throwsA(CampusAccessFailure.authenticationRejected),
    );
    expect(replay.passwordPosts, 1);
    expect(replay.paths, isNot(contains(_return)));
  });

  test('a cancelled credential lookup cannot submit a late password', () async {
    final fixture = _Flow();
    final started = Completer<void>();
    final remembered = Completer<NeuqCredentials?>();
    final cancel = CampusCancellation();
    final result = fixture.login(
      cancellation: cancel,
      read: () {
        started.complete();
        return remembered.future;
      },
    );
    await started.future;
    final stopped = expectLater(result, throwsA(CampusAccessFailure.cancelled));
    cancel.cancel();
    remembered.complete(const NeuqCredentials(_student, _password));
    await stopped;
    expect(fixture.passwordPosts, 0);
  });
}

const _form = '''
<form id="casLoginForm" method="post" action="/authserver/login">
  <input name="username"><input name="password" type="password">
  <input name="lt" value="fixture"><input name="execution" value="fixture">
  <input id="pwdDefaultEncryptSalt" value="0123456789abcdef">
</form>
''';

http.Response _html(String body, {Map<String, String> headers = const {}}) =>
    http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=utf-8', ...headers},
    );

http.Response _redirect(String to, {int status = 302}) =>
    http.Response('', status, headers: {'location': to});

class _Flow {
  DateTime now = DateTime.utc(2026, 1, 1);
  int passwordReads = 0;
  int passwordPosts = 0;
  final paths = <String>[];
  NeuqCredentials? remembered = const NeuqCredentials(_student, _password);
  String? confirmedStudent = _student;
  http.Response portalPage = _html('<a href="$_launcher">统一身份认证</a>');
  http.Response launcherPage = _redirect(_cas.toString());
  http.Response casPage = _html(
    _form,
    headers: {'set-cookie': 'cas_host=fixture; Path=/authserver; Secure'},
  );
  http.Response posted = _redirect(
    '$_service?ticket=fixture-ticket',
    status: 303,
  );

  Future<WebVpnSession> login({
    CampusCancellation? cancellation,
    Future<NeuqCredentials?> Function()? read,
  }) =>
      NeuqWebVpnProtocol(
        portalCasEntry: Uri.https(officialWebVpnHost, _launcher),
        casReturn: _service,
        identityPage: Uri.https(officialWebVpnHost, _identity),
        verifiedSubject: (page) {
          // This is a synthetic portal marker, never a school response rule.
          final code = page.querySelector('[data-fixture-subject]')?.text;
          return code == null ? null : schoolSubjectForStudentCode(code);
        },
        createClient: () => MockClient(_handle),
        clock: () => now,
      ).authenticate(
        WebVpnAuthentication(_subject, cancellation ?? CampusCancellation(), (
          _,
        ) async {
          passwordReads++;
          return read == null ? remembered : await read();
        }),
      );

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    final cookies = request.headers['cookie'] ?? '';
    expect(request.followRedirects, isFalse);
    paths.add(uri.path);
    if (request.method == 'POST') {
      passwordPosts++;
      expect(uri.host, schoolIdentityHost);
      expect(uri.path, '/authserver/login');
      expect(request.bodyFields['username'], _student);
      expect(request.bodyFields['password'], isNot(_password));
      expect(request.bodyFields['lt'], 'fixture');
      if (casPage.headers.containsKey('set-cookie')) {
        expect(cookies, contains('cas_host=fixture'));
      }
      return posted;
    }
    switch (uri.path) {
      case '/':
        expect(cookies, isEmpty);
        return portalPage;
      case _launcher:
        return launcherPage;
      case '/authserver/login':
        expect(cookies, isEmpty);
        return casPage;
      case _return:
        expect(uri.queryParameters['ticket'], 'fixture-ticket');
        return http.Response(
          '',
          302,
          headers: {
            'location': _identity,
            'set-cookie':
                'vpn_session=fixture; Path=/fixture; Max-Age=30; Secure, '
                'fixture_domain=fixture; Domain=.neuq.edu.cn; Path=/fixture; Secure, '
                'unrelated=fixture; Domain=outside.example; Path=/; Secure',
          },
        );
      case _identity:
        expect(cookies, contains('vpn_session=fixture'));
        return _html(
          confirmedStudent == null
              ? '<p>门户</p>'
              : '<p data-fixture-subject>$confirmedStudent</p>',
        );
      default:
        return _html(cookies);
    }
  }
}
