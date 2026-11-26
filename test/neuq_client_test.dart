import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/network/neuq_client.dart'
    show NeuqClient, NeuqPage, SchoolSessionHealth, SchoolSessionStatus;
import 'package:pointycastle/export.dart';

const _account = NeuqCredentials('00001234', 'synthetic-password');
final _subject = schoolSubjectForStudentCode(_account.username)!;
final _cas = Uri.https(schoolIdentityHost, '/authserver/login', {
  'service': schoolWebEntry.toString(),
});
final _cardCas = Uri.https(schoolIdentityHost, '/authserver/login', {
  'service': campusCardEntry.toString(),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _School school;
  late NeuqClient client;
  NeuqCredentials? remembered;
  late List<SchoolSessionStatus> sessionStatuses;

  setUp(() {
    remembered = null;
    sessionStatuses = [];
    school = _School();
    client = NeuqClient(
      readRemembered: (subject) async =>
          subject == _subject ? remembered : null,
      forgetRemembered: (_) async => remembered = null,
      createClient: () => MockClient(school.handle),
      onSessionStatus: sessionStatuses.add,
    );
  });

  tearDown(() => client.dispose());

  test(
    'verified login shares only academic cookies with grade requests',
    () async {
      expect(await client.signIn(_account, onVerified: (_) async {}), _subject);
      expect(
        await client.read(
          _subject,
          (session) => session.request(NeuqPage.grades),
        ),
        'grade data',
      );
      expect(school.loginAttempts, 1);
    },
  );

  test('expired session renews once using the remembered account', () async {
    await client.signIn(
      _account,
      onVerified: (_) async => remembered = _account,
    );
    school.expire();
    expect(
      await client.read(
        _subject,
        (session) => session.request(NeuqPage.grades),
      ),
      'grade data',
    );
    expect(school.loginAttempts, 2);
    expect(sessionStatuses.map((status) => status.health), [
      SchoolSessionHealth.connected,
      SchoolSessionHealth.restoring,
      SchoolSessionHealth.restoring,
      SchoolSessionHealth.connected,
    ]);
  });

  test('disconnect suppresses an academic result already in flight', () async {
    await client.signIn(_account, onVerified: (_) async {});
    final started = Completer<void>();
    final finish = Completer<String>();
    final read = client.read(_subject, (_) {
      started.complete();
      return finish.future;
    });
    await started.future;
    final disconnect = client.disconnect(() async {});
    final failure = expectLater(read, throwsA(SchoolRequestFailure.expired));
    finish.complete('synthetic test result');
    await failure;
    await disconnect;
    expect(sessionStatuses.last, (
      subject: null,
      health: SchoolSessionHealth.unknown,
    ));
    expect(sessionStatuses, hasLength(2));
  });

  test(
    'campus card gets its own unredeemed ticket from the existing CAS login',
    () async {
      await client.signIn(_account, onVerified: (_) async {});
      final first = await client.campusCardSignIn(_subject, _cardCas);
      final second = await client.campusCardSignIn(_subject, _cardCas);
      expect(
        first,
        campusCardEntry.replace(queryParameters: {'ticket': 'ST-card-1'}),
      );
      expect(
        second,
        campusCardEntry.replace(queryParameters: {'ticket': 'ST-card-2'}),
      );
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'campus card can renew a remembered login when CAS has expired',
    () async {
      await client.signIn(
        _account,
        onVerified: (_) async => remembered = _account,
      );
      school.expire();
      expect(
        await client.campusCardSignIn(_subject, _cardCas),
        campusCardEntry.replace(queryParameters: {'ticket': 'ST-card-1'}),
      );
      expect(school.loginAttempts, 2);
    },
  );

  test('campus card requires its exact CAS service and stops for interactive login', () async {
    await client.signIn(_account, onVerified: (_) async {});
    await expectLater(
      client.campusCardSignIn(_subject, _cas),
      throwsA(SchoolRequestFailure.unsupportedLogin),
    );
    school.cardReturn = schoolWebEntry.replace(
      queryParameters: {'ticket': 'ST-other'},
    );
    await expectLater(
      client.campusCardSignIn(_subject, _cardCas),
      throwsA(SchoolRequestFailure.verificationRequired),
    );
    school.expire();
    await expectLater(
      client.campusCardSignIn(_subject, _cardCas),
      throwsA(SchoolRequestFailure.expired),
    );
    expect(school.loginAttempts, 1);
  });

  test(
    'challenge and unverified form actions stop before posting credentials',
    () async {
      school.challenge = true;
      await expectLater(
        client.signIn(_account, onVerified: (_) async {}),
        throwsA(SchoolRequestFailure.verificationRequired),
      );
      school.challenge = false;
      school.formAction = 'https://outside.example/authserver/login';
      await expectLater(
        client.signIn(_account, onVerified: (_) async {}),
        throwsA(SchoolRequestFailure.unsupportedLogin),
      );
      expect(school.loginAttempts, 0);
    },
  );

  test(
    'an account mismatch is never recorded and logout clears active access',
    () async {
      school.returnedCode = '00005678';
      await expectLater(
        client.signIn(
          _account,
          onVerified: (_) async => fail('Unexpected saved account'),
        ),
        throwsA(SchoolRequestFailure.differentAccount),
      );
      school.returnedCode = _account.username;
      await client.signIn(
        _account,
        onVerified: (_) async => remembered = _account,
      );
      await client.disconnect(() async => remembered = null);
      await expectLater(
        client.read(_subject, (session) => session.request(NeuqPage.grades)),
        throwsA(SchoolRequestFailure.expired),
      );
      expect(remembered, isNull);
      expect(school.loginAttempts, 2);
    },
  );

  test(
    'Android keeps an offline identity and renews only with opt-in storage',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      FlutterSecureStorage.setMockInitialValues({
        'verifiedNeuqStudent': _subject,
      });
      final scope = ProviderContainer.test(
        overrides: [
          neuqHttpClientFactoryProvider.overrideWithValue(
            () => MockClient(school.handle),
          ),
        ],
      );
      final repository = scope.read(schoolAuthRepositoryProvider);
      expect((await repository.restoreSession())?.subject, _subject);
      expect(
        await scope.read(schoolConnectionProvider.future),
        SchoolConnection.unknown,
      );
      expect(await repository.hasRememberedPassword(_subject), isFalse);
      await repository.signIn(_account, rememberPassword: true);
      expect(await repository.hasRememberedPassword(_subject), isTrue);

      final afterRestart = ProviderContainer.test(
        overrides: [
          neuqHttpClientFactoryProvider.overrideWithValue(
            () => MockClient(school.handle),
          ),
        ],
      );
      final newRepository = afterRestart.read(schoolAuthRepositoryProvider);
      expect((await newRepository.restoreSession())?.subject, _subject);
      expect(
        await afterRestart.read(schoolConnectionProvider.future),
        SchoolConnection.unknown,
      );
      final newClient = afterRestart.read(neuqClientProvider);
      expect(
        await newClient.read(
          _subject,
          (session) => session.request(NeuqPage.grades),
        ),
        'grade data',
      );
      expect(school.loginAttempts, 2);
      expect(
        await afterRestart.read(schoolConnectionProvider.future),
        SchoolConnection.connected,
      );
      await expectLater(
        newClient.read<void>(_subject, (_) async {
          throw SchoolRequestFailure.unavailable;
        }),
        throwsA(SchoolRequestFailure.unavailable),
      );
      expect(
        await afterRestart.read(schoolConnectionProvider.future),
        SchoolConnection.offline,
      );
      expect(
        (await afterRestart.read(schoolSessionProvider.future))?.subject,
        _subject,
      );

      await newRepository.forgetPassword(_subject);
      expect(await newRepository.hasRememberedPassword(_subject), isFalse);
      final stored = await const FlutterSecureStorage().read(
        key: 'neuqSchoolLogin',
      );
      expect(jsonDecode(stored!), {'subject': _subject});
      expect((await newRepository.restoreSession())?.subject, _subject);
      school.expire();
      await expectLater(
        newClient.read(_subject, (session) => session.request(NeuqPage.grades)),
        throwsA(SchoolRequestFailure.expired),
      );
      expect(school.loginAttempts, 2);
      expect(
        await afterRestart.read(schoolConnectionProvider.future),
        SchoolConnection.expired,
      );
      expect(
        (await afterRestart.read(schoolSessionProvider.future))?.subject,
        _subject,
      );
    },
  );
}

class _School {
  int loginAttempts = 0;
  int cardTickets = 0;
  Uri? cardReturn;
  bool challenge = false;
  String returnedCode = _account.username;
  String formAction = '/authserver/login';
  String? _session;

  void expire() => _session = null;

  Future<http.Response> handle(http.Request request) async {
    expect(request.followRedirects, isFalse);
    final uri = request.url;
    expect(uri.scheme, 'https');
    final cookie = request.headers['cookie'] ?? '';
    final hasSession =
        _session != null && cookie.contains('ACADEMIC=$_session');
    http.Response reply(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'text/html; charset=UTF-8'},
    );

    if (uri.host == schoolIdentityHost) {
      expect(uri.path, '/authserver/login');
      expect(cookie, isNot(contains('ACADEMIC')));
      if (uri == _cardCas) {
        expect(request.method, 'GET');
        expect(request.body, isEmpty);
        expect(cookie, 'CAS=authenticated');
        if (_session == null) return reply('<input type="password">');
        final callback =
            cardReturn ??
            campusCardEntry.replace(
              queryParameters: {'ticket': 'ST-card-${++cardTickets}'},
            );
        return http.Response(
          '',
          302,
          headers: {'location': callback.toString()},
        );
      }
      if (request.method == 'GET') {
        return http.Response(
          '''
          <form id="casLoginForm" method="post" action="$formAction">
          <input name="username"><input type="password" name="password">
          <input name="lt" value="fixture"><input name="execution" value="fixture">
          <input id="pwdDefaultEncryptSalt" value="0123456789abcdef">
          ${challenge ? '<input name="captcha">' : '<div hidden>请输入验证码</div>'}
          </form>
          ''',
          200,
          headers: {
            'content-type': 'text/html; charset=UTF-8',
            'set-cookie': 'CAS=flow; Path=/authserver; Secure; HttpOnly',
          },
        );
      }
      expect(request.method, 'POST');
      expect(cookie, 'CAS=flow');
      expect(request.bodyFields['username'], _account.username);
      final encrypted = request.bodyFields['password']!;
      expect(encrypted, isNot(contains(_account.password)));
      final cipher =
          PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
              false,
              PaddedBlockCipherParameters(
                ParametersWithIV(
                  KeyParameter(
                    Uint8List.fromList(ascii.encode('0123456789abcdef')),
                  ),
                  Uint8List(16),
                ),
                null,
              ),
            );
      final decrypted = cipher.process(base64Decode(encrypted));
      expect(utf8.decode(decrypted.skip(64).toList()), _account.password);
      loginAttempts++;
      return http.Response(
        '',
        302,
        headers: {
          'location':
              '${schoolWebEntry.toString().replaceFirst('https:', 'http:')}?ticket=fixture',
          'set-cookie': 'CAS=authenticated; Path=/authserver; Secure; HttpOnly',
        },
      );
    }

    expect(uri.host, schoolAcademicHost);
    expect(cookie, isNot(contains('CAS=')));
    if (uri.path == schoolWebEntry.path) {
      if (uri.queryParameters['ticket'] == 'fixture') {
        _session = 'session-$loginAttempts';
        return http.Response(
          '',
          303,
          headers: {
            'location': schoolWebEntry.toString(),
            'set-cookie': 'ACADEMIC=$_session; Path=/eams; Secure; HttpOnly',
          },
        );
      }
      if (!hasSession) {
        return http.Response('', 302, headers: {'location': _cas.toString()});
      }
      return reply(
        '<title>教务系统</title><a href="/eams/logout.action">退出</a><a href="/eams/account.action">示例同学($returnedCode)</a>',
      );
    }
    expect(uri.path, NeuqPage.grades.path);
    if (!hasSession) {
      return http.Response('', 302, headers: {'location': _cas.toString()});
    }
    return reply('grade data');
  }
}
