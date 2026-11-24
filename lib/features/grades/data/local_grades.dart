import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/school_data.dart';
import '../domain/grades.dart';

final gradesRepositoryProvider = Provider<GradesRepository>(
  (ref) => LocalGradesRepository(ref.watch(databaseProvider)),
);
final gradesProvider = StreamProvider<List<Grade>>(
  (ref) => ref.watch(gradesRepositoryProvider).watch(),
);

class LocalGradesRepository implements GradesRepository {
  LocalGradesRepository(this.db);
  final AppDatabase db;

  static Grade fromRow(GradeRow row) => Grade(
    id: row.id,
    semesterId: row.semesterId,
    name: row.name,
    credit: row.credit,
    score: row.score,
    kind: GradeKind.values.byName(row.kind),
    demo: row.demo,
    format: ScoreFormat.values.byName(row.format),
  );

  @override
  Stream<List<Grade>> watch() =>
      (db.select(db.gradeRows)..orderBy([(r) => OrderingTerm.asc(r.name)]))
          .watch()
          .map((rows) => rows.map(fromRow).toList());

  @override
  Future<void> save(Grade grade) async {
    if (grade.id.trim().isEmpty ||
        isSchoolRecord(grade.id) ||
        isSchoolRecord(grade.semesterId) ||
        grade.name.trim().isEmpty ||
        !grade.credit.isFinite ||
        grade.credit <= 0 ||
        grade.credit > 50 ||
        !grade.validScore) {
      throw const FormatException('请输入课程名称、有效成绩和学分');
    }
    await db
        .into(db.gradeRows)
        .insertOnConflictUpdate(
          GradeRow(
            id: grade.id,
            semesterId: grade.semesterId,
            name: grade.name.trim(),
            credit: grade.credit,
            score: grade.score,
            kind: grade.kind.name,
            demo: grade.demo,
            format: grade.format.name,
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.gradeRows)..where((r) => r.id.equals(id))).go();
}

class MockGradesRepository implements GradesRepository {
  MockGradesRepository(this.semesterId);

  final String semesterId;

  @override
  Stream<List<Grade>> watch() => Stream.value([
    Grade(
      id: 'demo-math',
      semesterId: semesterId,
      name: '高等数学',
      credit: 4,
      score: 88,
      kind: GradeKind.required,
      demo: true,
    ),
    Grade(
      id: 'demo-draw',
      semesterId: semesterId,
      name: '视觉设计导论',
      credit: 2,
      score: 93,
      kind: GradeKind.elective,
      demo: true,
    ),
    Grade(
      id: 'demo-lang',
      semesterId: semesterId,
      name: '大学英语',
      credit: 3,
      score: 81,
      kind: GradeKind.required,
      demo: true,
    ),
  ]);

  @override
  Future<void> save(Grade grade) async => throw UnsupportedError('演示成绩只读');

  @override
  Future<void> delete(String id) async => throw UnsupportedError('演示成绩只读');
}
