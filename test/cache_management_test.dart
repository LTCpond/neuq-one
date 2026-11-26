import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/core/diagnostics/diagnostics.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/storage/cache_files.dart';
import 'package:neuq_one/core/storage/picker_cache.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/features/profile/data/cache_management.dart';
import 'package:neuq_one/features/services/data/campus_map.dart';
import 'package:neuq_one/features/services/data/classroom_cache.dart';
import 'package:neuq_one/features/services/data/school_policies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'temporary file clear preserves an active picker and draft attachments',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final picker = PickerCache();
      final retain = picker.retain();
      try {
        await expectLater(
          picker.clearCache(),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        retain();
      }
      final active = Completer<void>();
      final selection = picker.run(() => active.future);
      await expectLater(
        picker.clearCache(),
        throwsA(isA<FileSystemException>()),
      );
      active.complete();
      await selection;
    },
  );

  test(
    'diagnostics are bounded and omit messages, URLs and exception details',
    () {
      final log = Diagnostics();
      const private = 'synthetic-user-password-cookie';
      for (var i = 0; i < 160; i++) {
        log.record(
          DiagnosticModule.publicData,
          DiagnosticStage.request,
          error: http.ClientException(
            private,
            Uri.parse('https://example.invalid/?q=$private'),
          ),
        );
      }
      expect(log.entries, hasLength(Diagnostics.capacity));
      expect(log.entries.last.code, DiagnosticCode.network);
      log.record(
        DiagnosticModule.reminders,
        DiagnosticStage.initialize,
        error: PlatformException(
          code: 'invalid_icon',
          message: private,
          details: {'token': private},
        ),
      );
      expect(log.entries.last.code, DiagnosticCode.missingResource);
      expect(log.entries.last.exceptionType, 'PlatformException');
      expect(log.entries.toString(), isNot(contains(private)));
      expect(log.entries.toString(), isNot(contains('example.invalid')));
      log.clear();
      expect(log.entries, isEmpty);
    },
  );

  test(
    'clear waits for a disk write already started and rejects old downloads',
    () async {
      final guard = CacheWrites();
      final token = guard.version;
      final finish = Completer<void>();
      var cached = false;
      final writer = guard.write(token, () async {
        await finish.future;
        cached = true;
      });
      final clearing = guard.clear(() async {
        expect(cached, isTrue);
        cached = false;
      });
      expect(guard.version, isNull);
      finish.complete();
      await writer;
      await clearing;
      await guard.write(token, () async {
        cached = true;
      });
      expect(cached, isFalse);
    },
  );

  test('single and all cache clear preserve the account DB, secure store and preferences', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final directory = await Directory.systemTemp.createTemp(
      'neuq-cache-manager-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = http.Client();
    addTearDown(client.close);
    final dataClient = PublicDataClient(client);
    final publicDb = ClassroomCache(NativeDatabase.memory());
    addTearDown(publicDb.close);
    final accountFile = File.fromUri(
      directory.uri.resolve('private-account.sqlite'),
    );
    final accountDb = AppDatabase(NativeDatabase(accountFile));
    addTearDown(accountDb.close);
    await accountDb.customStatement(
      "CREATE TABLE fixture_user_data (value TEXT)",
    );
    await accountDb.customStatement(
      "INSERT INTO fixture_user_data VALUES ('saved schedule')",
    );
    final export = File.fromUri(directory.uri.resolve('saved-external.ics'));
    await export.writeAsString('saved export');
    const secure = FlutterSecureStorage();
    FlutterSecureStorage.setMockInitialValues({
      'neuqSchoolLogin': 'fixture identity and encrypted password',
      'campusMail:fixture': 'fixture mail credentials',
    });
    final secureBefore = await secure.readAll();
    final prefs = _CachePreferences({
      'employmentFeed': '{"events":[],"syncedAt":"2026-11-26T00:00:00Z"}',
      'theme': 'dark',
      'reminderMinutes': 15,
      'appUpdates.lastPromptedVersion': '0.2.0',
      'appUpdates.state.v1': '{"channel":"beta"}',
    });
    final map = File.fromUri(
      directory.uri.resolve('neuq_one_campus_map.cache'),
    );
    await map.writeAsBytes([1, 2, 3]);
    final pdf = File.fromUri(directory.uri.resolve('school-policies/test.pdf'));
    await pdf.parent.create();
    await pdf.writeAsBytes([1, 2, 3, 4]);
    await publicDb.writeWeek(
      ClassroomCacheEntry(
        id: 1,
        payload: '{}',
        etag: 'old',
        lastModified: null,
        cacheControl: null,
        checkedAt: DateTime.utc(2026),
        freshUntil: null,
      ),
    );
    final scope = ProviderContainer.test(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        classroomCacheProvider.overrideWithValue(publicDb),
        campusMapRepositoryProvider.overrideWithValue(
          CampusMapRepository(dataClient, () async => directory),
        ),
        schoolPolicyRepositoryProvider.overrideWithValue(
          SchoolPolicyRepository(dataClient, () async => directory),
        ),
      ],
    );
    final manager = scope.read(cacheManagerProvider);
    final before = await manager.sizes();
    expect(before[CacheCategory.campusMap], 3);
    expect(before[CacheCategory.policies], 4);
    expect(before[CacheCategory.classrooms], 5);
    expect(before[CacheCategory.employment], greaterThan(0));
    expect(await manager.clear(CacheCategory.policies), isEmpty);
    expect(await pdf.exists(), isFalse);
    expect(await map.exists(), isTrue);
    expect(await manager.clear(), isEmpty);
    expect((await manager.sizes()).values, everyElement(0));
    expect(await secure.readAll(), secureBefore);
    expect(prefs.values, {
      'theme': 'dark',
      'reminderMinutes': 15,
      'appUpdates.lastPromptedVersion': '0.2.0',
      'appUpdates.state.v1': '{"channel":"beta"}',
    });
    expect(await export.readAsString(), 'saved export');
    expect(
      (await accountDb
              .customSelect('SELECT value FROM fixture_user_data')
              .getSingle())
          .read<String>('value'),
      'saved schedule',
    );
  });

  test('a failed category does not prevent other cache clears', () async {
    var cleared = false;
    final manager = CacheManager({
      CacheCategory.campusMap: (
        size: () async => 2,
        clear: () async {
          throw const FileSystemException('fixture lock');
        },
      ),
      CacheCategory.classrooms: (
        size: () async => 1,
        clear: () async {
          cleared = true;
        },
      ),
    });
    expect(await manager.clear(), {CacheCategory.campusMap});
    expect(cleared, isTrue);
  });
}

class _CachePreferences implements SharedPreferencesAsync {
  _CachePreferences(this.values);
  final Map<String, Object> values;
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
