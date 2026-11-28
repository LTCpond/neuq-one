import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/features/exams/data/exam_conflict_reminders.dart';
import 'package:neuq_one/features/exams/data/local_exams.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/timetable/data/schedule_providers.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = 'neuq-eams:aaaaaaaa-aaaa-5aaa-aaaa-aaaaaaaaaaaa';
const _bob = 'neuq-eams:bbbbbbbb-bbbb-5bbb-bbbb-bbbbbbbbbbbb';
final _date = mondayOf(DateTime.utc(2099, 1, 10));
final _term = Semester(id: 'school:test', name: '测试学期', start: _date, weeks: 4);

void main() {
  test('Drift 同步、手动考试与通知在应用级响应，读取失败和换账号时保留各自状态', () async {
    final previousDriftWarning =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousDriftWarning,
    );
    final databases = {
      _alice: AppDatabase(NativeDatabase.memory()),
      _bob: AppDatabase(NativeDatabase.memory()),
    };
    addTearDown(() async {
      for (final database in databases.values) {
        await database.close();
      }
    });
    final prefs = _Prefs();
    final notifications = _Notifications();
    final containers = <ProviderContainer>[];
    ProviderContainer start() {
      final container = ProviderContainer(
        overrides: [
          schoolSessionProvider.overrideWith(_Session.new),
          databaseProvider.overrideWith((ref) {
            final subject = ref
                .watch(schoolSessionProvider)
                .asData!
                .value!
                .subject;
            return databases[subject]!;
          }),
          preferencesProvider.overrideWithValue(prefs),
          reminderServiceProvider.overrideWithValue(notifications),
        ],
      );
      container.listen(examConflictReminderSyncProvider, (_, _) {});
      containers.add(container);
      return container;
    }

    addTearDown(() {
      for (final container in containers) {
        container.dispose();
      }
    });
    var container = start();
    await container.read(schoolSessionProvider.future);
    final repository = SchoolDataRepository(databases[_alice]!);
    final exams = LocalExamRepository(databases[_alice]!);
    Exam examAt(int start, int end) => Exam(
      id: 'manual',
      name: '样例考试',
      at: campusInstant(_date, start),
      endsAt: campusInstant(_date, end),
    );

    Future<void> refresh(bool overlaps) async {
      await repository.refresh(
        SchoolDataSet.timetable,
        _Source(
          Timetable(
            [_term],
            [
              Course(
                id: overlaps ? 'school:shifted' : 'school:original',
                semesterId: _term.id,
                name: '样例课程',
                teacher: '任课教师',
                room: '教室',
                weekday: DateTime.monday,
                startMinute: overlaps ? 530 : 605,
                endMinute: overlaps ? 575 : 650,
                weeks: const [1],
                colorIndex: 0,
              ),
            ],
          ),
        ),
      );
      final revision = (await repository.watchTimetable().first)!.revision;
      await _when(
        () => prefs.ledgers.any((ledger) => ledger.revision == revision),
      );
    }

    await _when(() => prefs.ledgers.length == 1);
    expect(container.read(scheduleCourseCheckProvider).complete, isFalse);
    expect(
      container.read(scheduleCourseCheckProvider).message,
      contains('暂时无法完整检测'),
    );
    await refresh(false);
    await exams.save(examAt(540, 555));
    await _when(() => prefs.ledgers.single.exams.length == 1);
    expect(container.read(scheduleConflictsProvider).pairs, isEmpty);
    expect(notifications.attempts, 0);

    await refresh(true);
    await _when(() => notifications.attempts >= 1);
    expect(notifications.sent, isEmpty);
    expect(prefs.ledgers.single.pending, hasLength(1));
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    expect(container.read(scheduleCourseCheckProvider).complete, isTrue);
    expect(container.read(scheduleCourseCheckProvider).message, isNull);
    await expectLater(
      repository.refresh(SchoolDataSet.timetable, const _Source(null)),
      throwsFormatException,
    );
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    final database = databases[_alice]!;
    final lastGood = await database
        .select(database.schoolCacheRows)
        .getSingle();
    await database
        .into(database.schoolCacheRows)
        .insertOnConflictUpdate(lastGood.copyWith(payload: '{'));
    await _when(() => container.read(schoolTimetableCacheProvider).hasError);
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    expect(prefs.ledgers.single.pending, hasLength(1));
    await database
        .into(database.schoolCacheRows)
        .insertOnConflictUpdate(lastGood);
    await _when(() => !container.read(schoolTimetableCacheProvider).hasError);

    notifications.allowed = true;
    container.invalidate(examConflictWakeProvider);
    await _when(
      () =>
          notifications.sent.length == 1 &&
          prefs.ledgers.single.pending.isEmpty,
    );
    final link = examConflictNotificationLocation(
      notifications.sent.single,
      _alice,
      1,
    );
    expect(link?.path, '/grades');
    expect(link?.queryParameters, containsPair('exam', 'manual'));
    expect(
      link?.queryParameters,
      containsPair('date', _date.toIso8601String().split('T').first),
    );
    expect(
      examConflictNotificationLocation(notifications.sent.single, _bob, 1),
      isNull,
    );
    await refresh(true);
    expect(notifications.sent, hasLength(1));

    container.dispose();
    containers.remove(container);
    container = start();
    await container.read(schoolSessionProvider.future);
    await _when(
      () => container.read(scheduleConflictsProvider).pairs.length == 1,
    );
    expect(notifications.sent, hasLength(1));
    await refresh(false);
    expect(container.read(scheduleConflictsProvider).pairs, isEmpty);
    await refresh(true);
    await _when(
      () =>
          notifications.sent.length == 2 &&
          prefs.ledgers.single.pending.isEmpty,
    );

    await exams.save(examAt(610, 625));
    await _when(() => prefs.ledgers.single.active.isEmpty);
    expect(container.read(scheduleConflictsProvider).pairs, isEmpty);
    await exams.save(examAt(540, 555));
    await _when(() => prefs.ledgers.single.active.length == 1);
    expect(notifications.sent, hasLength(2));
    await container
        .read(settingsProvider.notifier)
        .setShowExamsInTimetable(false);
    await _when(
      () =>
          container.read(settingsProvider).value?.showExamsInTimetable == false,
    );
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    expect(notifications.sent, hasLength(2));
    await exams.delete('manual');
    await _when(() => prefs.ledgers.single.exams.isEmpty);
    expect(container.read(scheduleConflictsProvider).pairs, isEmpty);

    await container
        .read(settingsProvider.notifier)
        .setExamConflictReminders(false);
    await refresh(false);
    await exams.save(examAt(540, 555));
    await _when(() => prefs.ledgers.single.exams.length == 1);
    await refresh(true);
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    expect(notifications.sent, hasLength(2));

    (container.read(schoolSessionProvider.notifier) as _Session).switchTo(_bob);
    await _when(() => prefs.ledgers.length == 2);
    expect(container.read(scheduleEventsProvider).exams, isEmpty);
    expect(container.read(scheduleConflictsProvider).pairs, isEmpty);
    expect(
      prefs.ledgers.where((ledger) => ledger.active.isNotEmpty),
      hasLength(1),
    );
    expect(notifications.dismissals, 1);

    await container
        .read(settingsProvider.notifier)
        .setExamConflictReminders(true);
    final historicalDate = mondayOf(DateTime.utc(2001, 4, 10));
    final historicalTerm = Semester(
      id: 'school:historical',
      name: '历史学期',
      start: historicalDate,
      weeks: 4,
    );
    final bob = databases[_bob]!;
    await LocalExamRepository(bob).save(
      Exam(
        id: 'finished',
        name: '历史考试',
        at: campusInstant(historicalDate, 490),
        endsAt: campusInstant(historicalDate, 520),
      ),
    );
    await _when(
      () => prefs.ledgers.every((ledger) => ledger.exams.length == 1),
    );
    await SchoolDataRepository(bob).refresh(
      SchoolDataSet.timetable,
      _Source(
        Timetable(
          [historicalTerm],
          [
            Course(
              id: 'school:historical-class',
              semesterId: historicalTerm.id,
              name: '历史课程',
              teacher: '',
              room: '',
              weekday: DateTime.monday,
              startMinute: 480,
              endMinute: 525,
              weeks: const [1],
              colorIndex: 0,
            ),
          ],
        ),
      ),
    );
    final historicalRevision = (await SchoolDataRepository(
      bob,
    ).watchTimetable().first)!.revision;
    await _when(
      () =>
          prefs.ledgers.any((ledger) => ledger.revision == historicalRevision),
    );
    expect(container.read(scheduleConflictsProvider).pairs, hasLength(1));
    expect(notifications.sent, hasLength(2));
  });
}

Future<void> _when(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('未等到预期的异步状态');
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
}

class _Session extends SchoolSessionController {
  @override
  Future<SchoolSession?> build() async => const SchoolSession(subject: _alice);

  void switchTo(String subject) =>
      state = AsyncData(SchoolSession(subject: subject));
}

class _Notifications extends CourseReminderService {
  bool allowed = false;
  int attempts = 0;
  int dismissals = 0;
  final sent = <String>[];

  @override
  bool get supported => true;

  @override
  Future<bool> showExamConflict({
    required String body,
    required String payload,
    required bool Function() isCurrent,
  }) async {
    attempts++;
    if (!allowed || !isCurrent()) return false;
    sent.add(payload);
    return true;
  }

  @override
  Future<void> dismissExamConflict() async => dismissals++;
}

class _Prefs implements SharedPreferencesAsync {
  final _values = <String, Object>{};

  Iterable<ExamConflictLedger> get ledgers => _values.entries
      .where((entry) => entry.key.startsWith('schedule.examConflicts.'))
      .map((entry) => ExamConflictLedger.decode(entry.value as String)!);

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source implements SchoolDataSource {
  const _Source(this.data);
  final Timetable? data;

  @override
  Future<Timetable> fetchTimetable() async =>
      data ?? (throw const FormatException());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
