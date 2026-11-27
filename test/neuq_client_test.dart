import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialApp, Scaffold, TextFormField;
import 'package:neuq_one/app/school_reconnect_button.dart';
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
  late DateTime now;
  late List<SchoolSessionStatus> sessionStatuses;

  Future<String> readGrades() =>
      client.read(_subject, (session) => session.request(NeuqPage.grades));

  Future<bool> recover([
    SchoolRecoveryTrigger trigger = SchoolRecoveryTrigger.foreground,
  ]) => client.recoverSession(_subject, trigger: trigger);

  setUp(() {
    remembered = null;
    now = DateTime.utc(2026, 11, 27);
    sessionStatuses = [];
    school = _School();
    client = NeuqClient(
      readRemembered: (subject) async =>
          subject == _subject ? remembered : null,
      forgetRemembered: (_) async => remembered = null,
      createClient: () => MockClient(school.handle),
      onSessionStatus: sessionStatuses.add,
      clock: () => now,
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
      SchoolSessionHealth.connected,
    ]);
  });

  test(
    'manual recovery verifies a working session without a second login',
    () async {
      await client.signIn(_account, onVerified: (_) async {});
      final checks = school.landingRequests;
      expect(await recover(SchoolRecoveryTrigger.manual), isTrue);
      expect(school.landingRequests, checks + 1);
      expect(school.loginAttempts, 1);
      expect(sessionStatuses.last.health, SchoolSessionHealth.connected);
    },
  );

  test(
    'network recovery backs off and a manual retry can reconnect early',
    () async {
      remembered = _account;
      school.intercept = (_) async =>
          throw http.ClientException('offline fixture');
      await expectLater(recover(), throwsA(SchoolRequestFailure.unavailable));
      expect(sessionStatuses.last.health, SchoolSessionHealth.offline);
      final checks = school.landingRequests;
      await expectLater(recover(), throwsA(SchoolRequestFailure.unavailable));
      expect(school.landingRequests, checks);

      await expectLater(
        recover(SchoolRecoveryTrigger.manual),
        throwsA(SchoolRequestFailure.unavailable),
      );
      expect(school.landingRequests, checks + 1);
      await expectLater(
        recover(SchoolRecoveryTrigger.manual),
        throwsA(SchoolRequestFailure.unavailable),
      );
      expect(school.landingRequests, checks + 1);

      school.intercept = null;
      now = now.add(const Duration(seconds: 10));
      expect(await recover(), isTrue);
      expect(school.loginAttempts, 1);
      expect(sessionStatuses.last.health, SchoolSessionHealth.connected);
      expect(await recover(), isFalse);

      now = now.add(const Duration(seconds: 5));
      school.intercept = (_) async =>
          throw http.ClientException('offline fixture');
      await expectLater(recover(), throwsA(SchoolRequestFailure.unavailable));
      school.intercept = null;
      expect(await recover(SchoolRecoveryTrigger.manual), isTrue);
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'transport, server and data errors never renew a verified session',
    () async {
      remembered = _account;
      await client.signIn(_account, onVerified: (_) async {});
      final checks = school.landingRequests;
      school.intercept = (_) async => http.Response('', 503);
      await expectLater(
        readGrades(),
        throwsA(SchoolRequestFailure.unavailable),
      );
      expect(sessionStatuses.last.health, SchoolSessionHealth.offline);
      school.intercept = null;
      expect(await readGrades(), 'grade data');
      await expectLater(
        client.read<void>(_subject, (_) async => throw const FormatException()),
        throwsFormatException,
      );
      expect(sessionStatuses.last.health, SchoolSessionHealth.connected);
      expect(school.landingRequests, checks);
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'manual and foreground recovery coalesce with concurrent academic reads',
    () async {
      remembered = _account;
      final started = Completer<void>();
      final resume = Completer<void>();
      school.intercept = (request) async {
        if (request.method == 'POST' &&
            request.url.host == schoolIdentityHost) {
          started.complete();
          await resume.future;
        }
        return null;
      };
      final foreground = recover();
      await started.future;
      final manual = recover(SchoolRecoveryTrigger.manual);
      final reads = [readGrades(), readGrades(), readGrades()];
      expect(identical(foreground, manual), isTrue);
      resume.complete();
      expect(await foreground, isTrue);
      expect(await Future.wait(reads), [
        'grade data',
        'grade data',
        'grade data',
      ]);
      expect(school.loginAttempts, 1);

      school.intercept = null;
      school.expire();
      expect(await Future.wait([readGrades(), readGrades(), readGrades()]), [
        'grade data',
        'grade data',
        'grade data',
      ]);
      expect(school.loginAttempts, 2);
    },
  );

  test('a valid landing page can leave a business endpoint expired', () async {
    remembered = _account;
    await client.signIn(_account, onVerified: (_) async {});
    school.intercept = (request) async {
      if (request.url.path == NeuqPage.grades.path &&
          request.headers['cookie'] == 'ACADEMIC=session-1') {
        return http.Response('', 401);
      }
      return null;
    };
    expect(await readGrades(), 'grade data');
    expect(school.gradeRequests, 2);
    expect(school.loginAttempts, 2);

    school.intercept = (request) async =>
        request.url.path == NeuqPage.grades.path
        ? http.Response('', 401)
        : null;
    await expectLater(
      readGrades(),
      throwsA(SchoolRequestFailure.sessionRejected),
    );
    expect(school.gradeRequests, 4);
    expect(school.loginAttempts, 3);
    expect(sessionStatuses.last.health, SchoolSessionHealth.expired);
    await expectLater(
      readGrades(),
      throwsA(SchoolRequestFailure.sessionRejected),
    );
    expect(school.gradeRequests, 4);
    expect(school.loginAttempts, 3);
  });

  test('a fresh academic cookie from CAS can recover without a password', () async {
    await client.signIn(_account, onVerified: (_) async {});
    school.intercept = (request) async {
      if (request.url.path == NeuqPage.grades.path &&
          request.headers['cookie'] == 'ACADEMIC=session-1') {
        return http.Response('', 401);
      }
      if (request.url == schoolWebEntry &&
          request.headers['cookie'] == 'ACADEMIC=session-1') {
        return http.Response(
          '<title>教务系统</title><a href="/eams/logout.action">退出</a><a href="/eams/account.action">示例同学(${_account.username})</a>',
          200,
          headers: {
            'content-type': 'text/html; charset=UTF-8',
            'set-cookie': 'ACADEMIC=session-refreshed; Path=/eams; Secure',
          },
        );
      }
      if (request.url.path == NeuqPage.grades.path &&
          request.headers['cookie'] == 'ACADEMIC=session-refreshed') {
        return http.Response('grade data', 200);
      }
      return null;
    };
    expect(await readGrades(), 'grade data');
    expect(school.gradeRequests, 2);
    expect(school.loginAttempts, 1);
  });

  test(
    'invalid remembered credentials are deleted and stop automatic attempts',
    () async {
      remembered = _account;
      school.invalidPassword = true;
      await expectLater(
        recover(),
        throwsA(SchoolRequestFailure.invalidCredentials),
      );
      expect(remembered, isNull);
      expect(sessionStatuses.last.health, SchoolSessionHealth.expired);
      now = now.add(const Duration(minutes: 10));
      await expectLater(
        recover(SchoolRecoveryTrigger.manual),
        throwsA(SchoolRequestFailure.invalidCredentials),
      );
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'school throttling holds across manual recovery and manual sign-in',
    () async {
      remembered = _account;
      school.intercept = (_) async =>
          http.Response('', 429, headers: {'retry-after': '600'});
      await expectLater(recover(), throwsA(SchoolRequestFailure.denied));
      school.intercept = null;
      now = now.add(const Duration(minutes: 5));
      await expectLater(
        recover(SchoolRecoveryTrigger.manual),
        throwsA(SchoolRequestFailure.denied),
      );
      await expectLater(
        client.signIn(_account, onVerified: (_) async {}),
        throwsA(SchoolRequestFailure.denied),
      );
      expect(school.landingRequests, 1);
      now = now.add(const Duration(minutes: 5));
      expect(await recover(), isTrue);
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'school access denial stops automatic recovery after the cooldown',
    () async {
      remembered = _account;
      school.intercept = (_) async => http.Response('', 403);
      await expectLater(recover(), throwsA(SchoolRequestFailure.denied));
      school.intercept = null;
      await expectLater(
        recover(SchoolRecoveryTrigger.manual),
        throwsA(SchoolRequestFailure.denied),
      );
      now = now.add(const Duration(minutes: 5));
      await expectLater(recover(), throwsA(SchoolRequestFailure.denied));
      expect(school.landingRequests, 1);
      expect(await recover(SchoolRecoveryTrigger.manual), isTrue);
      expect(school.loginAttempts, 1);
    },
  );

  test(
    'a queued foreground check skips recovery once the app is hidden',
    () async {
      await client.signIn(_account, onVerified: (_) async {});
      final started = Completer<void>();
      final finish = Completer<void>();
      final read = client.read(_subject, (_) async {
        started.complete();
        await finish.future;
      });
      await started.future;
      var foreground = true;
      final checks = school.landingRequests;
      final recovery = client.recoverSession(
        _subject,
        trigger: SchoolRecoveryTrigger.foreground,
        isForeground: () => foreground,
      );
      foreground = false;
      finish.complete();
      await read;
      expect(await recovery, isFalse);
      expect(school.landingRequests, checks);
    },
  );

  test('logout cancels a renewal already posting to CAS', () async {
    remembered = _account;
    final posted = Completer<void>();
    final resume = Completer<void>();
    school.intercept = (request) async {
      if (request.method == 'POST') {
        posted.complete();
        await resume.future;
      }
      return null;
    };
    final recovery = recover();
    await posted.future;
    final failure = expectLater(
      recovery,
      throwsA(SchoolRequestFailure.cancelled),
    );
    final disconnected = client.disconnect(() async => remembered = null);
    resume.complete();
    await failure;
    await disconnected;
    await expectLater(readGrades(), throwsA(SchoolRequestFailure.expired));
    expect(school.landingRequests, 1);
    expect(sessionStatuses.last, (
      subject: null,
      health: SchoolSessionHealth.unknown,
    ));
  });

  test(
    'forgetting credentials cancels renewal before submitting a password',
    () async {
      remembered = _account;
      final openingForm = Completer<void>();
      final resume = Completer<void>();
      school.intercept = (request) async {
        if (request.url == _cas) {
          openingForm.complete();
          await resume.future;
        }
        return null;
      };
      final recovery = recover();
      await openingForm.future;
      final failure = expectLater(
        recovery,
        throwsA(SchoolRequestFailure.cancelled),
      );
      final forgotten = client.forgetPassword(_subject);
      resume.complete();
      await failure;
      await forgotten;
      await expectLater(recover(), throwsA(SchoolRequestFailure.expired));
      expect(school.loginAttempts, 0);
      expect(remembered, isNull);
    },
  );

  Future<void> mountReconnect(
    WidgetTester tester, {
    required bool savePassword,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({
      'neuqSchoolLogin': jsonEncode({
        'subject': _subject,
        if (savePassword) 'username': _account.username,
        if (savePassword) 'password': _account.password,
      }),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neuqHttpClientFactoryProvider.overrideWithValue(
            () => MockClient.streaming((request, _) async {
              final result = await school.handle(request as http.Request);
              final body = StreamController<List<int>>(onCancel: () async {});
              body.add(result.bodyBytes);
              unawaited(body.close());
              return http.StreamedResponse(
                body.stream,
                result.statusCode,
                headers: result.headers,
              );
            }),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SchoolReconnectButton())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapReconnect(WidgetTester tester) async {
    await tester.tap(find.byType(SchoolReconnectButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'manual reconnect uses the saved password without showing a form',
    (tester) async {
      await mountReconnect(tester, savePassword: true);
      final button = find.text('重新连接教务');
      await tapReconnect(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(school.loginAttempts, 1);
      final scope = ProviderScope.containerOf(tester.element(button));
      expect(
        scope.read(schoolSessionStatusProvider).health,
        SchoolSessionHealth.connected,
      );
    },
  );

  for (final savePassword in [false, true]) {
    testWidgets(
      'manual reconnect shows the login form when password is ${savePassword ? 'wrong' : 'missing'}',
      (tester) async {
        await mountReconnect(tester, savePassword: savePassword);
        school.invalidPassword = savePassword;
        await tapReconnect(tester);
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(school.loginAttempts, savePassword ? 1 : 0);
        if (savePassword) {
          expect(
            find.text(SchoolRequestFailure.invalidCredentials.message),
            findsOneWidget,
          );
        } else {
          await tester.enterText(
            find.byType(TextFormField).first,
            _account.username,
          );
          await tester.enterText(
            find.byType(TextFormField).last,
            _account.password,
          );
          await tester.tap(find.text('统一身份认证登录'));
          await tester.pumpAndSettle();
          expect(find.byType(TextFormField), findsNothing);
          expect(school.loginAttempts, 1);
        }
      },
    );
  }

  testWidgets(
    'manual reconnect gives network feedback or the official login action',
    (tester) async {
      await mountReconnect(tester, savePassword: true);
      school.intercept = (_) async =>
          throw http.ClientException('offline fixture');
      await tapReconnect(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.text(SchoolRequestFailure.unavailable.message),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      school.intercept = null;
      school.challenge = true;
      await tapReconnect(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('打开官方教务'), findsOneWidget);
      expect(school.loginAttempts, 0);
    },
  );

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
    final failure = expectLater(read, throwsA(SchoolRequestFailure.cancelled));
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
  int landingRequests = 0;
  int gradeRequests = 0;
  int cardTickets = 0;
  Uri? cardReturn;
  bool challenge = false;
  bool invalidPassword = false;
  Future<http.Response?> Function(http.Request)? intercept;
  String returnedCode = _account.username;
  String formAction = '/authserver/login';
  String? _session;

  void expire() => _session = null;

  Future<http.Response> handle(http.Request request) async {
    expect(request.followRedirects, isFalse);
    final uri = request.url;
    if (uri == schoolWebEntry) landingRequests++;
    if (uri.path == NeuqPage.grades.path) gradeRequests++;
    final override = await intercept?.call(request);
    if (override != null) return override;
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
      if (invalidPassword) return reply('密码错误');
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
