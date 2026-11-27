import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:drift/native.dart';
import 'package:neuq_one/app/app.dart';
import 'package:neuq_one/app/router.dart';
import 'package:neuq_one/app/login_page.dart';
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/diagnostics/diagnostics.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/profile/data/app_updates.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/profile/presentation/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.neuqone.neuq_one/app_version');
  const installed = '0.9.1';
  const latest = '0.10.0';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getVersion');
      return installed;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  AppUpdatesRepository repository(Object? release) {
    final client = MockClient((request) async {
      expect(request.url, publicAssetsRoot.resolve('/assets/app/latest.json'));
      expect(request.headers['cache-control'], 'no-cache');
      return _manifest(release);
    });
    addTearDown(client.close);
    return AppUpdatesRepository(
      PublicDataClient(client, assetsBackupOrigin: publicAssetsRoot),
    );
  }

  test('compares stable release versions numerically', () async {
    expect(
      await repository(_release(latest)).checkForUpdate(),
      isA<AppUpdateAvailable>()
          .having(
            (result) => result.currentVersion,
            'currentVersion',
            installed,
          )
          .having((result) => result.latestVersion, 'latestVersion', latest)
          .having((result) => result.url, 'url', _releaseUrl(latest)),
    );
    for (final version in [installed, '0.8.9']) {
      expect(
        await repository(_release(version)).checkForUpdate(),
        isA<AppUpToDate>(),
      );
    }
  });

  testWidgets(
    'Android Debug shows DEV and checks published versions only on demand',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => '$installed-dev',
      );
      final prefs = _UpdatePreferences();
      prefs.values['appUpdates.state.v1'] = jsonEncode({
        'channel': 'beta',
        'lastSuccess': DateTime.now().millisecondsSinceEpoch,
        'available': _release(latest),
      });
      var requests = 0;
      final scope = await _mountApp(
        tester,
        MockClient((_) async {
          requests++;
          return _manifest(_release(latest));
        }),
        prefs,
        useActualBuildMode: true,
      );
      expect(scope.read(androidDebugBuildProvider), isTrue);
      expect(requests, 0);
      expect(scope.read(appUpdateCoordinatorProvider).available, isNull);
      scope.read(routerProvider).go('/profile');
      await tester.pumpAndSettle();

      final about = find.text('关于 NEUQ One');
      await tester.ensureVisible(about);
      await tester.pumpAndSettle();
      expect(find.text('DEV'), findsOneWidget);
      expect(find.text('当前版本 v$installed-dev'), findsOneWidget);
      await tester.tap(about);
      await tester.pumpAndSettle();
      expect(find.text('关于 NEUQ One · DEV'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('发布渠道最新版本 v$latest。开发版需重新构建。'), findsOneWidget);
      expect(find.text('前往下载'), findsNothing);
      expect(find.text('v$latest 可用'), findsNothing);
      expect(scope.read(appUpdateCoordinatorProvider).available, isNull);
    },
  );

  test('automatic checks persist success and back off errors; manual bypasses both', () async {
    final prefs = _UpdatePreferences();
    var now = DateTime.utc(2026, 11, 26);
    var requests = 0;
    var networkAvailable = false;
    final client = MockClient((_) async {
      requests++;
      return networkAvailable ? _manifest(null) : http.Response('', 503);
    });
    addTearDown(client.close);
    AppUpdateCoordinator launch() => AppUpdateCoordinator(
      AppUpdatesRepository(PublicDataClient(client)),
      prefs,
      clock: () => now,
    );
    await expectLater(
      launch().check(automatic: true),
      throwsA(isA<Exception>()),
    );
    now = now.add(const Duration(minutes: 59));
    expect(await launch().check(automatic: true), isNull);
    expect(requests, 2);
    now = now.add(const Duration(minutes: 1));
    await expectLater(
      launch().check(automatic: true),
      throwsA(isA<Exception>()),
    );
    now = now.add(const Duration(minutes: 119));
    expect(await launch().check(automatic: true), isNull);
    expect(requests, 4);
    now = now.add(const Duration(minutes: 1));
    networkAvailable = true;
    expect(await launch().check(automatic: true), isA<NoPublishedAppRelease>());
    now = now.add(const Duration(hours: 23, minutes: 59));
    expect(await launch().check(automatic: true), isNull);
    expect(
      await launch().check(automatic: false),
      isA<NoPublishedAppRelease>(),
    );
    expect(requests, 6);
    now = now.add(const Duration(hours: 24));
    expect(await launch().check(automatic: true), isA<NoPublishedAppRelease>());
    expect(requests, 7);
  });

  test(
    'rewinding the clock reanchors the stored interval across restarts',
    () async {
      final prefs = _UpdatePreferences();
      var now = DateTime.utc(2026, 11, 26);
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return _manifest(null);
      });
      addTearDown(client.close);
      AppUpdateCoordinator launch() => AppUpdateCoordinator(
        AppUpdatesRepository(PublicDataClient(client)),
        prefs,
        clock: () => now,
      );
      await launch().checkAtStartup();
      now = now.subtract(const Duration(days: 5));
      expect(await launch().checkAtStartup(), isNull);
      now = now.add(const Duration(hours: 24));
      expect(await launch().checkAtStartup(), isA<NoPublishedAppRelease>());
      expect(requests, 2);
    },
  );

  test('manual and automatic share one request and a manual action owns presentation', () async {
    final prefs = _UpdatePreferences();
    final finish = Completer<http.Response>();
    var requests = 0;
    final client = MockClient((_) {
      requests++;
      return finish.future;
    });
    addTearDown(client.close);
    final coordinator = AppUpdateCoordinator(
      AppUpdatesRepository(PublicDataClient(client)),
      prefs,
    );
    final startup = coordinator.checkAtStartup();
    expect(coordinator.checkAtStartup(), same(startup));
    final manual = coordinator.check(automatic: false);
    expect(coordinator.beginPresentation(), isTrue);
    expect(coordinator.beginPresentation(), isFalse);
    finish.complete(_manifest(_release(latest)));
    expect(await startup, same(await manual));
    expect(requests, 1);
    await coordinator.presentAutomatically(
      canShow: () => true,
      show: (_, _) async {
        fail('a second presentation must not start');
      },
    );
    await coordinator.noteManualPresentation(latest);
    coordinator.endPresentation();
    expect(prefs.values['appUpdates.lastPromptedVersion'], latest);
    expect(
      await coordinator.check(automatic: false),
      isA<AppUpdateAvailable>(),
    );
    expect(requests, 2);
  });

  test('restores offers, preserves them on failure and clears on withdrawal or upgrade', () async {
    final prefs = _UpdatePreferences();
    var response = _manifest(_release(latest, changelog: ['更新摘要']));
    final client = MockClient((_) async => response);
    addTearDown(client.close);
    final repository = AppUpdatesRepository(
      PublicDataClient(client, cooldown: Duration.zero),
    );
    AppUpdateCoordinator launch() => AppUpdateCoordinator(repository, prefs);
    await launch().checkAtStartup();
    final offline = launch();
    await offline.restore();
    expect(offline.available?.changelog, ['更新摘要']);
    response = http.Response('', 503);
    await expectLater(
      offline.check(automatic: false),
      throwsA(isA<Exception>()),
    );
    expect(offline.available?.latestVersion, latest);
    response = _manifest(null);
    expect(await offline.check(automatic: false), isA<NoPublishedAppRelease>());
    expect(offline.available, isNull);
    final withdrawn = launch();
    await withdrawn.restore();
    expect(withdrawn.available, isNull);
    response = _manifest(_release(latest));
    await launch().check(automatic: false);
    messenger.setMockMethodCallHandler(channel, (_) async => latest);
    final upgraded = launch();
    await upgraded.restore();
    expect(upgraded.available, isNull);
    expect(
      prefs.values['appUpdates.state.v1'],
      isNot(contains(_releaseUrl(latest))),
    );
  });

  test('restores the existing ignored version and handles storage failure without popups', () async {
    var failPromptWrite = false;
    final prefs = _UpdatePreferences(
      onPromptWrite: () {
        if (failPromptWrite) throw StateError('storage failed');
      },
    );
    prefs.values['appUpdates.ignoredVersion'] = latest;
    final client = MockClient((_) async => _manifest(_release(latest)));
    addTearDown(client.close);
    AppUpdateCoordinator launch() => AppUpdateCoordinator(
      AppUpdatesRepository(PublicDataClient(client)),
      prefs,
    );
    final migrated = launch();
    await migrated.checkAtStartup();
    Future<void> unexpected(AppUpdateAvailable _, VoidCallback _) async =>
        fail('unexpected popup');
    await migrated.presentAutomatically(canShow: () => true, show: unexpected);
    prefs.values.remove('appUpdates.ignoredVersion');
    failPromptWrite = true;
    for (var i = 0; i < 2; i++) {
      final restarted = launch();
      await restarted.checkAtStartup();
      expect(restarted.available?.latestVersion, latest);
      await restarted.presentAutomatically(
        canShow: () => true,
        show: unexpected,
      );
    }
  });

  test(
    'an unsafe route during durable preparation leaves the version eligible',
    () async {
      var safe = true;
      var interrupt = true;
      final prefs = _UpdatePreferences(
        onPromptWrite: () {
          if (interrupt) safe = false;
        },
      );
      final client = MockClient((_) async => _manifest(_release(latest)));
      addTearDown(client.close);
      final coordinator = AppUpdateCoordinator(
        AppUpdatesRepository(PublicDataClient(client)),
        prefs,
      );
      await coordinator.checkAtStartup();
      await coordinator.presentAutomatically(
        canShow: () => safe,
        show: (_, _) async {
          fail('presentation must recheck the route after writing');
        },
      );
      expect(prefs.values['appUpdates.lastPromptedVersion'], isNull);
      interrupt = false;
      safe = true;
      await coordinator.presentAutomatically(
        canShow: () => safe,
        show: (_, shown) async => shown(),
      );
      expect(prefs.values['appUpdates.lastPromptedVersion'], latest);
    },
  );

  testWidgets(
    'startup defers the offer during login and shows it after authentication',
    (tester) async {
      final pending = Completer<http.Response>();
      final client = MockClient((_) => pending.future);
      final prefs = _UpdatePreferences();
      final auth = _UpdateAuth(session: null);
      final scope = await _mountApp(tester, client, prefs, auth: auth);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('正在恢复登录状态'), findsNothing);
      pending.complete(_manifest(_release(latest)));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.values['appUpdates.lastPromptedVersion'], isNull);
      await scope
          .read(schoolSessionProvider.notifier)
          .signIn(
            const NeuqCredentials('fixture', 'fixture'),
            rememberPassword: false,
          );
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);
      await tester.tap(find.text('稍后更新'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.values['appUpdates.lastPromptedVersion'], latest);
    },
  );

  for (final dismiss in ['later', 'download', 'back', 'barrier']) {
    testWidgets(
      'automatic popup after $dismiss remains suppressed across restart',
      (tester) async {
        final prefs = _UpdatePreferences();
        var now = DateTime.utc(2026, 11, 26);
        var version = latest;
        var requests = 0;
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final downloads = <MethodCall>[];
        const browser = MethodChannel('plugins.flutter.io/url_launcher');
        messenger.setMockMethodCallHandler(browser, (call) async {
          downloads.add(call);
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(browser, null));
        Future<ProviderContainer> launch() => _mountApp(
          tester,
          MockClient((_) async {
            requests++;
            return _manifest(_release(version, changelog: ['修复测试功能']));
          }),
          prefs,
          clock: () => now,
          database: db,
        );
        final first = await launch();
        expect(find.text('发现新版本'), findsOneWidget);
        expect(find.text('修复测试功能'), findsOneWidget);
        switch (dismiss) {
          case 'later':
            await tester.tap(find.text('稍后更新'));
          case 'download':
            await tester.tap(find.text('前往下载'));
          case 'back':
            await tester.binding.handlePopRoute();
          case 'barrier':
            await tester.tapAt(const Offset(8, 8));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        if (dismiss == 'download') {
          expect(
            downloads.single.arguments,
            containsPair('url', _releaseUrl(latest)),
          );
        }
        first.read(routerProvider).go('/profile');
        await tester.pumpAndSettle();
        expect(find.text('v$latest 可用'), findsOneWidget);
        expect(requests, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        now = now.add(const Duration(hours: 25));
        final second = await launch();
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests, 2);
        second.read(routerProvider).go('/profile');
        await tester.pumpAndSettle();
        expect(find.text('v$latest 可用'), findsOneWidget);
        if (dismiss == 'later') {
          await tester.ensureVisible(find.text('检查更新'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('检查更新'));
          await tester.pumpAndSettle();
          expect(find.text('发现新版本'), findsOneWidget);
          expect(find.text('修复测试功能'), findsOneWidget);
          await tester.tap(find.text('稍后更新'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          version = '0.11.0';
          now = now.add(const Duration(hours: 25));
          await launch();
          expect(find.text('发现新版本'), findsOneWidget);
          expect(find.text('最新版本：v0.11.0'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'automatic prompt waits for foreground and an open branch dialog',
    (tester) async {
      final pending = Completer<http.Response>();
      final prefs = _UpdatePreferences();
      final scope = await _mountApp(
        tester,
        MockClient((_) => pending.future),
        prefs,
      );
      scope.read(routerProvider).go('/profile');
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ProfilePage)),
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: const Text('正在办理'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('结束办理'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(_manifest(_release(latest)));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);
      expect(prefs.values['appUpdates.lastPromptedVersion'], isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);
      await tester.tap(find.text('结束办理'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);
    },
  );

  test('a manifest without a published release has its own result', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await repository(null).checkForUpdate(),
      isA<NoPublishedAppRelease>(),
    );
  });

  test('rejects an update link outside the official release', () async {
    await expectLater(
      repository({'version': '1.0.0', 'url': 'https://example.test/update.apk'})
          .checkForUpdate(),
      _manifestFailure(DiagnosticCode.invalidData),
    );
  });

  test(
    'validates the mirror manifest after rejecting a primary download link',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.host);
        if (request.url.host == publicAssetsRoot.host) {
          return _manifest({
            'version': '1.0.0',
            'url': 'https://example.test/update.apk',
          });
        }
        return _manifest(_release(latest));
      });
      addTearDown(client.close);
      final result = await AppUpdatesRepository(PublicDataClient(client))
          .checkForUpdate();
      expect(
        result,
        isA<AppUpdateAvailable>().having(
          (update) => update.url,
          'url',
          _releaseUrl(latest),
        ),
      );
      expect(requests, [publicAssetsRoot.host, publicAssetsBackupRoot.host]);
    },
  );

  test('stable sees only stable, beta chooses the highest version and accepts old manifests', () async {
    Future<AppUpdateResult> check(
      Object? stable,
      Object? beta,
      AppUpdateChannel channel,
    ) async {
      final client = MockClient(
        (_) async => _manifest(stable, prerelease: beta),
      );
      addTearDown(client.close);
      return AppUpdatesRepository(
        PublicDataClient(client),
        channel: channel,
      ).checkForUpdate();
    }

    const beta = AppUpdateChannel.beta;
    const stable = AppUpdateChannel.stable;
    final preview = _release('1.0.0', prerelease: true);
    expect(await check(null, preview, stable), isA<NoPublishedAppRelease>());
    final betaResult =
        await check(_release(latest), preview, beta) as AppUpdateAvailable;
    expect(betaResult.latestVersion, '1.0.0');
    expect(betaResult.prerelease, isTrue);
    final stableResult =
        await check(_release(latest), preview, stable) as AppUpdateAvailable;
    expect(stableResult.latestVersion, latest);
    expect(stableResult.prerelease, isFalse);
    final tied =
        await check(_release('1.0.0'), preview, beta) as AppUpdateAvailable;
    expect(tied.prerelease, isFalse);
    expect(
      await check(null, _release('0.8.0', prerelease: true), beta),
      isA<AppUpToDate>(),
    );
    for (final invalid in ['1.01.0', '1.0.0-rc.1', '1.0.0\n']) {
      await expectLater(
        check(_release(invalid), preview, beta),
        _manifestFailure(DiagnosticCode.invalidData),
      );
    }
    await expectLater(
      check(preview, null, stable),
      _manifestFailure(DiagnosticCode.invalidData),
    );
    await expectLater(
      check(null, _release(latest), beta),
      _manifestFailure(DiagnosticCode.invalidData),
    );
    final older =
        await check(_release(latest), null, stable) as AppUpdateAvailable;
    expect(older.changelog, isEmpty);
  });

  test(
    'bounds response size, count and Unicode length of optional changelog',
    () async {
      final emoji = List.filled(180, '📚').join();
      final result =
          await repository(
                _release(
                  latest,
                  changelog: [
                    emoji,
                    500,
                    '  ',
                    '<script>示例</script>',
                    '三',
                    '四',
                    '五',
                    '六',
                  ],
                ),
              ).checkForUpdate()
              as AppUpdateAvailable;
      expect(result.changelog, hasLength(5));
      expect(result.changelog.first.runes, hasLength(160));
      expect(result.changelog[1], '<script>示例</script>');
      final over = List.filled(17000, 'x').join();
      await expectLater(
        repository(_release(latest, changelog: [over])).checkForUpdate(),
        _manifestFailure(DiagnosticCode.responseTooLarge),
      );
    },
  );

  testWidgets(
    'beta summary scrolls and stays usable with larger text on a small dark screen',
    (tester) async {
      final lines = List.generate(
        5,
        (i) => '改进 $i ${List.filled(140, '课').join()}',
      );
      await _mountProfile(
        tester,
        Brightness.dark,
        MockClient(
          (_) async => _manifest(
            null,
            prerelease: _release(latest, prerelease: true, changelog: lines),
          ),
        ),
        size: const Size(320, 500),
        textScale: 1.6,
      );
      final update = find.text('检查更新');
      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      await tester.tap(update);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('NEUQ One v$latest 公测版'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('本次更新')),
        findsOneWidget,
      );
      final change = find.text(lines.last);
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      expect(change, findsOneWidget);
      expect(find.text('前往下载').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('稍后更新'));
      await tester.pumpAndSettle();
      expect(find.text('v$latest 可用'), findsOneWidget);
    },
  );

  testWidgets(
    'profile checks directly, prevents duplicate checks and opens the release',
    (tester) async {
      final pending = Completer<http.Response>();
      var requests = 0;
      const browserChannel = MethodChannel('plugins.flutter.io/url_launcher');
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(browserChannel, (call) async {
        launches.add(call);
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(browserChannel, null),
      );

      await _mountProfile(
        tester,
        Brightness.dark,
        MockClient((_) {
          requests++;
          return pending.future;
        }),
      );
      final update = find.text('检查更新');
      final tile = find.ancestor(of: update, matching: find.byType(ListTile));
      final about = find.text('关于 NEUQ One');
      final entries = [find.text('隐私说明'), update, about, find.text('GitHub')];
      await tester.ensureVisible(entries.last);
      await tester.pumpAndSettle();
      for (var i = 1; i < entries.length; i++) {
        expect(
          tester.getTopLeft(entries[i]).dy,
          greaterThan(tester.getTopLeft(entries[i - 1]).dy),
        );
      }
      expect(
        find.descendant(of: tile, matching: find.text('当前版本 v$installed')),
        findsOneWidget,
      );

      await tester.tap(about);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('NEUQ One 是面向东北大学秦皇岛分校学生的'),
        ),
        findsOneWidget,
      );
      final close = find.descendant(of: dialog, matching: find.text('关闭'));
      expect(close, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byType(TextButton)),
        findsNWidgets(3),
      );
      await tester.tap(find.text('问题反馈'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('参与贡献'));
      await tester.pumpAndSettle();
      expect(launches.map((call) => (call.arguments as Map)['url']), [
        'https://github.com/LTCpond/neuq-one/issues',
        'https://github.com/LTCpond/neuq-one/pulls',
      ]);
      launches.clear();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(requests, 0);

      await tester.tap(update);
      await tester.tap(update);
      await tester.pump();
      final progress = find.descendant(
        of: tile,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(progress, findsOneWidget);
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      expect(requests, 1);

      pending.complete(_manifest(_release(latest)));
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('最新版本：v$latest')),
        findsOneWidget,
      );
      expect(find.text('当前版本：v$installed'), findsOneWidget);
      expect(find.text('本次更新'), findsNothing);
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(launches.single.method, 'launch');
      expect(
        launches.single.arguments,
        containsPair('url', _releaseUrl(latest)),
      );
      expect(launches.single.arguments, containsPair('useWebView', false));
      expect(launches.single.arguments, containsPair('useSafariVC', false));
    },
  );

  testWidgets(
    'profile reports unavailable releases, failures and an up-to-date app',
    (tester) async {
      final outcomes = [
        (_manifest(null), '暂无可用更新'),
        (http.Response('', 503), '检查更新失败，请稍后重试'),
        (_manifest(_release(installed)), '当前已是最新版本'),
      ];
      final responses = outcomes.iterator;
      await _mountProfile(
        tester,
        Brightness.light,
        MockClient((request) async {
          if (request.url.host == publicAssetsBackupRoot.host) {
            return http.Response('', 503);
          }
          expect(responses.moveNext(), isTrue);
          return responses.current.$1;
        }),
      );

      final update = find.text('检查更新');
      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      for (final (_, message) in outcomes) {
        await tester.tap(update);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
    },
  );
}

String _releaseUrl(String version) =>
    'https://github.com/LTCpond/neuq-one/releases/tag/v$version';

Matcher _manifestFailure(DiagnosticCode code) => throwsA(
  isA<PublicDataException>().having((error) => error.code, 'code', code),
);

Map<String, Object> _release(
  String version, {
  bool? prerelease,
  List<Object>? changelog,
}) => {
  'version': version,
  'url': _releaseUrl(version),
  'prerelease': ?prerelease,
  'changelog': ?changelog,
};

http.Response _manifest(Object? release, {Object? prerelease}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'release': release,
          'prerelease': ?prerelease,
        }),
      ),
      200,
    );

Future<ProviderContainer> _mountApp(
  WidgetTester tester,
  MockClient client,
  _UpdatePreferences prefs, {
  _UpdateAuth? auth,
  DateTime Function()? clock,
  AppDatabase? database,
  bool useActualBuildMode = false,
}) async {
  addTearDown(client.close);
  final db = database ?? AppDatabase(NativeDatabase.memory());
  if (database == null) addTearDown(db.close);
  final scope = ProviderContainer.test(
    overrides: [
      if (!useActualBuildMode)
        androidDebugBuildProvider.overrideWithValue(false),
      settingsProvider.overrideWith(_TestSettings.new),
      preferencesProvider.overrideWithValue(prefs),
      schoolAuthRepositoryProvider.overrideWithValue(auth ?? _UpdateAuth()),
      schoolDataSourceProvider.overrideWithValue(null),
      databaseProvider.overrideWithValue(db),
      reminderSyncProvider.overrideWith(
        (ref) async => const ReminderStatus(ReminderCondition.off),
      ),
      publicDataClientProvider.overrideWithValue(PublicDataClient(client)),
      if (clock != null)
        appUpdateCoordinatorProvider.overrideWith(
          (ref) => AppUpdateCoordinator(
            ref.read(appUpdatesProvider),
            prefs,
            clock: clock,
          ),
        ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: scope, child: const NeuqOneApp()),
  );
  await tester.pumpAndSettle();
  return scope;
}

class _UpdateAuth implements SchoolAuthRepository {
  _UpdateAuth({this.session = _verified});
  static const _verified = SchoolSession(subject: 'fixture-update-account');
  final SchoolSession? session;
  @override
  bool get available => true;
  @override
  bool get canRememberPassword => false;
  @override
  Future<SchoolSession?> restoreSession() async => session;
  @override
  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) async => false;
  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async => _verified;
  @override
  Future<bool> hasRememberedPassword(String subject) async => false;
  @override
  Future<void> forgetPassword(String subject) async {}
  @override
  Future<void> disconnect() async {}
}

Future<void> _mountProfile(
  WidgetTester tester,
  Brightness brightness,
  MockClient client, {
  Size size = const Size(390, 700),
  double textScale = 1,
}) async {
  addTearDown(client.close);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        androidDebugBuildProvider.overrideWithValue(false),
        settingsProvider.overrideWith(_TestSettings.new),
        preferencesProvider.overrideWithValue(_UpdatePreferences()),
        schoolConnectionProvider.overrideWith(
          (ref) async => SchoolConnection.disconnected,
        ),
        rememberedSchoolPasswordProvider.overrideWith((ref) async => false),
        reminderSyncProvider.overrideWith(
          (ref) async => const ReminderStatus(ReminderCondition.off),
        ),
        publicDataClientProvider.overrideWithValue(
          PublicDataClient(client, cooldown: Duration.zero),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ProfilePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _UpdatePreferences implements SharedPreferencesAsync {
  _UpdatePreferences({this.onPromptWrite});

  final values = <String, Object>{};
  final VoidCallback? onPromptWrite;
  @override
  Future<int?> getInt(String key) async => values[key] as int?;
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<void> setInt(String key, int value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (key == 'appUpdates.lastPromptedVersion') {
      onPromptWrite?.call();
    }
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
