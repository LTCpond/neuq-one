import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/school_auth.dart';

part 'app_database.g.dart';

@DataClassName('SemesterRow')
class SemesterRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get start => dateTime()();
  IntColumn get weeks => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CourseRow')
class CourseRows extends Table {
  TextColumn get id => text()();
  TextColumn get semesterId => text().references(SemesterRows, #id)();
  TextColumn get name => text()();
  TextColumn get teacher => text()();
  TextColumn get room => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  TextColumn get weeks => text()();
  IntColumn get colorIndex => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GradeRow')
class GradeRows extends Table {
  TextColumn get id => text()();
  TextColumn get semesterId => text().references(SemesterRows, #id)();
  TextColumn get name => text()();
  RealColumn get credit => real()();
  RealColumn get score => real()();
  TextColumn get kind => text()();
  BoolColumn get demo => boolean()();
  TextColumn get format => text().withDefault(const Constant('numeric'))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExamRow')
class ExamRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get room => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SchoolCacheRow')
class SchoolCacheRows extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [SemesterRows, CourseRows, GradeRows, ExamRows, SchoolCacheRows],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor, String name = 'neuq_one'])
    : super(executor ?? driftDatabase(name: name));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await transaction(() async {
          await migrator.addColumn(gradeRows, gradeRows.format);
          await migrator.createTable(schoolCacheRows);
        });
      }
    },
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final subject = ref.watch(
    schoolSessionProvider.select((value) => value.asData?.value?.subject),
  );
  if (subject == null || subject.trim().isEmpty) throw StateError('缺少学校会话');
  final account = const Uuid().v5(Namespace.url.value, 'neuq-one:$subject');
  final database = AppDatabase(null, 'neuq_one_$account');
  ref.onDispose(database.close);
  return database;
});
