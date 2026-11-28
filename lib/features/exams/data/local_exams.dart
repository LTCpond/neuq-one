import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/database/app_database.dart';
import '../domain/exam.dart';

export '../../../core/time/campus_clock.dart' show campusInstant;

final examRepositoryProvider = Provider<ExamRepository>(
  (ref) => LocalExamRepository(ref.watch(databaseProvider)),
);
final examStreamProvider = StreamProvider.autoDispose
    .family<List<Exam>, String>((ref, subject) {
      if (ref.watch(
            schoolSessionProvider.select(
              (state) => state.asData?.value?.subject,
            ),
          ) !=
          subject) {
        return const Stream.empty();
      }
      return ref.watch(examRepositoryProvider).watch();
    });

final examsProvider = Provider.autoDispose<AsyncValue<List<Exam>>>((ref) {
  final subject = ref.watch(
    schoolSessionProvider.select((state) => state.asData?.value?.subject),
  );
  return subject == null
      ? const AsyncLoading()
      : ref.watch(examStreamProvider(subject));
});

class LocalExamRepository implements ExamRepository {
  LocalExamRepository(this.db);

  final AppDatabase db;

  static Exam fromRow(ExamRow row) => Exam(
    id: row.id,
    name: row.name,
    at: row.at.toUtc(),
    endsAt: row.endsAt.toUtc(),
    room: row.room,
  );

  @override
  Stream<List<Exam>> watch() =>
      (db.select(db.examRows)..orderBy([(r) => OrderingTerm.asc(r.at)]))
          .watch()
          .map((rows) => rows.map(fromRow).toList());

  @override
  Future<void> save(Exam exam) async {
    final start = exam.campusStart;
    final end = exam.campusEnd;
    if (exam.id.trim().isEmpty ||
        exam.name.trim().isEmpty ||
        start.year < 2000 ||
        start.year > 2100 ||
        end.year < 2000 ||
        end.year > 2100) {
      throw const FormatException('请填写有效的考试科目、日期和起止时间');
    }
    if (examTimeValidation(exam.at, exam.endsAt) case final error?) {
      throw FormatException(error);
    }
    await db
        .into(db.examRows)
        .insertOnConflictUpdate(
          ExamRow(
            id: exam.id,
            name: exam.name.trim(),
            at: exam.at.toUtc(),
            endsAt: exam.endsAt.toUtc(),
            room: exam.room.trim(),
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.examRows)..where((row) => row.id.equals(id))).go();
}
