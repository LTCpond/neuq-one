import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/features/exams/data/local_exams.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/grades/data/local_grades.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/timetable/data/local_timetable.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

import 'timetable_test.dart' show course;

void main() {
  final term = Semester(
    id: 'term',
    name: '测试学期',
    start: DateTime.utc(2026, 8, 31),
    weeks: 4,
  );
  const grade = Grade(
    id: 'g',
    semesterId: 'term',
    name: '线性代数',
    credit: 3,
    score: 88,
    kind: GradeKind.required,
  );

  test(
    'records persist after a database reopen, including sparse weeks',
    () async {
      final directory = await Directory.systemTemp.createTemp('neuq_one_test_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');

      final initial = AppDatabase(NativeDatabase(file));
      final initialTimetable = LocalTimetableRepository(initial);
      await initialTimetable.saveSemester(term);
      await initialTimetable.saveCourse(course('id', [1, 3]));
      await LocalGradesRepository(initial).save(grade);
      await initial.close();

      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      final timetable = LocalTimetableRepository(reopened);
      final snapshot = await timetable.watch().first;
      final restored = snapshot.semesters.single;
      expect(restored.start, term.start);
      expect(snapshot.on(restored, 1, DateTime.monday), hasLength(1));
      expect(snapshot.on(restored, 2, DateTime.monday), isEmpty);
      expect(snapshot.on(restored, 3, DateTime.monday), hasLength(1));
      expect(
        (await LocalGradesRepository(reopened).watch().first).single.score,
        88,
      );
      await timetable.deleteCourse('id');
      expect((await timetable.watch().first).courses, isEmpty);
    },
  );

  test('concurrent overlapping saves commit only one course', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final timetable = LocalTimetableRepository(db);
    await timetable.saveSemester(term);
    final outcomes = await Future.wait([
      for (final id in ['1', '2'])
        timetable
            .saveCourse(course(id, [1]))
            .then(
              (_) => true,
              onError: (Object error) {
                expect(error, isA<FormatException>());
                return false;
              },
            ),
    ]);
    expect(outcomes.where((success) => success), hasLength(1));
    expect((await timetable.watch().first).courses, hasLength(1));
  });

  test('local exams persist start and end times across a reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'neuq_one_exam_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/exams.sqlite');
    final exam = Exam(
      id: 'e',
      name: '高等数学',
      at: DateTime.utc(2026, 11, 27, 1),
      endsAt: DateTime.utc(2026, 11, 27, 3),
      room: '工学馆 101',
    );

    final initial = AppDatabase(NativeDatabase(file));
    await LocalExamRepository(initial).save(exam);
    await initial.close();

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final repository = LocalExamRepository(reopened);
    final restored = (await repository.watch().first).single;
    expect(restored.name, '高等数学');
    expect(restored.at, exam.at);
    expect(restored.endsAt, exam.endsAt);
    expect(restored.room, '工学馆 101');

    await repository.delete('e');
    expect(await repository.watch().first, isEmpty);
  });

  test('version 2 exams gain a default end time during migration', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE exam_rows (
              id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
              at INTEGER NOT NULL, room TEXT NOT NULL
            );
            INSERT INTO exam_rows VALUES ('old', '旧考试', 1700000000, '考场');
            PRAGMA user_version = 2;
          ''');
        },
      ),
    );
    addTearDown(db.close);
    final exam = (await LocalExamRepository(db).watch().first).single;
    expect(exam.name, '旧考试');
    expect(exam.endsAt.difference(exam.at), const Duration(hours: 1));
  });

  test(
    'local GPA weights numeric attempts by credits for both admission cohorts',
    () {
      const failed = Grade(
        id: 'f',
        semesterId: 'term',
        name: '另一门课',
        credit: 1,
        score: 52,
        kind: GradeKind.elective,
      );
      final result = GradeSummary([grade, failed], GpaScale.current);
      expect(result.average, 70);
      expect(result.credits, 4);
      expect(result.passedCredits, 3);
      expect(result.gpa, closeTo(2.85, .0001));
      expect(
        GradeSummary([grade, failed], GpaScale.legacy).gpa,
        closeTo(2.85, .0001),
      );
      expect(GradeSummary([], GpaScale.current).gpa, isNull);
    },
  );
}
