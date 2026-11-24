import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/exams.dart';

final examRepositoryProvider = Provider<ExamRepository>(
  (ref) => LocalExamRepository(ref.watch(databaseProvider)),
);
final examsProvider = StreamProvider<List<Exam>>(
  (ref) => ref.watch(examRepositoryProvider).watch(),
);

class LocalExamRepository implements ExamRepository {
  LocalExamRepository(this.db);
  final AppDatabase db;

  static Exam fromRow(ExamRow row) =>
      Exam(id: row.id, name: row.name, at: row.at.toUtc(), room: row.room);

  @override
  Stream<List<Exam>> watch() =>
      (db.select(db.examRows)..orderBy([(r) => OrderingTerm.asc(r.at)]))
          .watch()
          .map((rows) => rows.map(fromRow).toList());

  @override
  Future<void> save(Exam exam) async {
    if (exam.id.trim().isEmpty ||
        exam.name.trim().isEmpty ||
        exam.campusTime.year < 2000 ||
        exam.campusTime.year > 2100) {
      throw const FormatException('请输入有效的考试名称和时间');
    }
    await db
        .into(db.examRows)
        .insertOnConflictUpdate(
          ExamRow(
            id: exam.id,
            name: exam.name.trim(),
            at: exam.at.toUtc(),
            room: exam.room.trim(),
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.examRows)..where((row) => row.id.equals(id))).go();
}
