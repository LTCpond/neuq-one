import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/grades/data/local_grades.dart';
import 'package:neuq_one/features/grades/data/neuq_plan_completion.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/grades/domain/plan_completion.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

import 'fixtures/plan_completion.dart';

void main() {
  test('published periods cover all twelve teaching slots and breaks', () {
    expect(neuqPeriods, hasLength(12));
    expect(neuqPeriods[1], (start: 530, end: 575));
    expect(neuqPeriods[4], (start: 840, end: 885));
    expect(neuqPeriods[10], (start: 1225, end: 1270));
    expect(neuqPeriods.last, (start: 1275, end: 1320));
    expect(
      neuqPeriods.indexed.every(
        (entry) =>
            entry.$1 == 0 || entry.$2.start > neuqPeriods[entry.$1 - 1].end,
      ),
      isTrue,
    );
  });

  test('both NEUQ GPA policies account for attempt entries and exclusions', () {
    final original = _grade('first', 59, 4);
    final retake = _grade('retake', 90, 4);
    final ranked = _grade('ranked', 85, 2, format: ScoreFormat.fiveLevel);
    final passed = _grade('passed', 60, 3, format: ScoreFormat.binary);
    final deferred = _grade('deferred', 0, 1, format: ScoreFormat.deferred);
    final culture = _grade('culture', 100, 2, kind: GradeKind.cultureElective);
    final practice = _grade('practice', 80, 2, kind: GradeKind.extracurricular);
    final micro = _grade('micro', 100, 1, kind: GradeKind.microMajor);
    final attempts = [original, retake, ranked, passed, deferred, culture];

    expect(GpaScale.forAdmission(2025), GpaScale.current);
    expect(GpaScale.forAdmission(2024), GpaScale.legacy);
    expect(GpaScale.current.pointsFor(_grade('pass', 60, 1)), 1);
    expect(GpaScale.current.pointsFor(_grade('round', 87.654, 1)), 3.7654);
    expect(GpaScale.legacy.pointsFor(_grade('round', 87.654, 1)), 3.77);
    expect(GpaScale.current.pointsFor(deferred), isNull);
    expect(GpaScale.current.pointsFor(micro), isNull);
    expect(GpaScale.legacy.pointsFor(practice), isNull);
    expect(GradeSummary(attempts, GpaScale.current).gpa, closeTo(2.3, 0.00001));
    expect(
      GradeSummary(attempts, GpaScale.legacy).gpa,
      closeTo(32 / 13, 0.00001),
    );
  });

  test('version 1 grades remain readable after the migration', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
        CREATE TABLE grade_rows (
          id TEXT NOT NULL PRIMARY KEY, semester_id TEXT NOT NULL,
          name TEXT NOT NULL, credit REAL NOT NULL, score REAL NOT NULL,
          kind TEXT NOT NULL, demo INTEGER NOT NULL
        );
        INSERT INTO grade_rows VALUES ('old', 's', '已有成绩', 3, 87, 'required', 0);
        PRAGMA user_version = 1;
      ''');
        },
      ),
    );
    addTearDown(db.close);
    final grade = (await LocalGradesRepository(db).watch().first).single;
    expect(grade.score, 87);
    expect(grade.format, ScoreFormat.numeric);
    expect(await SchoolDataRepository(db).watchGrades().first, isNull);
  });

  test(
    'school refresh deduplicates concurrent reads and retains valid snapshots',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SchoolDataRepository(db);
      final source = _TestSchoolSource();
      expect(await repo.watchGrades().first, isNull);
      final first = repo.refresh(SchoolDataSet.grades, source);
      final second = repo.refresh(SchoolDataSet.grades, source);
      expect(identical(first, second), isTrue);
      source.reply.complete(
        SchoolGradeBook(
          [source.term],
          [_grade('first', 88, 3)],
          semesterGpa: {'school:term': 3.6721},
          cumulativeGpa: 3.6502,
        ),
      );
      await first;
      final cached = (await repo.watchGrades().first)!;
      expect(cached.data.grades.single.score, 88);
      expect(cached.data.semesterGpa['school:term'], 3.6721);
      expect(cached.data.cumulativeGpa, 3.6502);
      expect(source.requests, 1);
      source.reply = Completer();
      final failed = repo.refresh(SchoolDataSet.grades, source);
      final result = expectLater(failed, throwsFormatException);
      source.reply.complete(SchoolGradeBook([], [_grade('invalid', 90, 4)]));
      await result;
      final retained = (await repo.watchGrades().first)!;
      expect(retained.data.grades.single.score, 88);
      expect(retained.data.cumulativeGpa, 3.6502);
      expect(retained.syncedAt, cached.syncedAt);
      source.reply = Completer();
      final empty = repo.refresh(SchoolDataSet.grades, source);
      source.reply.complete(const SchoolGradeBook([], []));
      await empty;
      expect((await repo.watchGrades().first)!.data.grades, isEmpty);
    },
  );

  test('failed plan refresh keeps the last report and its timestamp', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = SchoolDataRepository(db);
    final source = _TestSchoolSource();
    final report = readNeuqPlanCompletion(
      planCompletionHtml,
      schoolSubjectForStudentCode(planFixtureStudent)!,
    );
    source.planReply.complete(report);
    await repository.refresh(SchoolDataSet.planCompletion, source);
    final first = (await repository.watchPlanCompletion().first)!;

    source.planReply = Completer();
    final failed = expectLater(
      repository.refresh(SchoolDataSet.planCompletion, source),
      throwsA(SchoolRequestFailure.unavailable),
    );
    source.planReply.completeError(SchoolRequestFailure.unavailable);
    await failed;
    final retained = (await repository.watchPlanCompletion().first)!;
    expect(retained.data.toJson(), report.toJson());
    expect(retained.syncedAt, first.syncedAt);
    expect(await repository.watchGrades().first, isNull);
  });
}

Grade _grade(
  String id,
  double score,
  double credit, {
  ScoreFormat format = ScoreFormat.numeric,
  GradeKind kind = GradeKind.required,
}) => Grade(
  id: 'school:$id',
  semesterId: 'school:term',
  name: '测试课程',
  credit: credit,
  score: score,
  kind: kind,
  format: format,
);

class _TestSchoolSource implements SchoolDataSource {
  final term = Semester(
    id: 'school:term',
    name: '测试学期',
    start: DateTime.utc(2026, 9, 7),
    weeks: 18,
  );
  int requests = 0;
  Completer<SchoolGradeBook> reply = Completer();
  Completer<PlanCompletion> planReply = Completer();

  @override
  Future<SchoolGradeBook> fetchGrades() {
    requests++;
    return reply.future;
  }

  @override
  Future<Timetable> fetchTimetable() async => const Timetable([], []);

  @override
  Future<PlanCompletion> fetchPlanCompletion() => planReply.future;
}
