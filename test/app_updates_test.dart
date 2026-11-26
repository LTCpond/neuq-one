import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/profile/data/app_updates.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/profile/presentation/profile_page.dart';

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
    return AppUpdatesRepository(PublicDataClient(client));
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
      throwsFormatException,
    );
  });

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
        findsOneWidget,
      );
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
        find.descendant(
          of: dialog,
          matching: find.text('当前版本 v$installed\n最新版本 v$latest'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('前往 GitHub 下载'));
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
        MockClient((_) async {
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

Map<String, String> _release(String version) => {
  'version': version,
  'url': _releaseUrl(version),
};

http.Response _manifest(Object? release) =>
    http.Response(jsonEncode({'schemaVersion': 1, 'release': release}), 200);

Future<void> _mountProfile(
  WidgetTester tester,
  Brightness brightness,
  MockClient client,
) async {
  addTearDown(client.close);
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_TestSettings.new),
        schoolConnectionProvider.overrideWith(
          (ref) async => SchoolConnection.disconnected,
        ),
        rememberedSchoolPasswordProvider.overrideWith((ref) async => false),
        reminderSyncProvider.overrideWith((ref) async {}),
        publicDataClientProvider.overrideWithValue(PublicDataClient(client)),
      ],
      child: MaterialApp(
        theme: appTheme(brightness),
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
