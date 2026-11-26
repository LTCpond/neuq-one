import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'classroom_cache.g.dart';

@DataClassName('ClassroomCacheEntry')
class ClassroomCacheEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get checkedAt => dateTime()();
  TextColumn get resource => text().nullable()();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  TextColumn get cacheControl => text().nullable()();
  DateTimeColumn get freshUntil => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Public data belongs to the installation and can be read before sign-in.
@DriftDatabase(tables: [ClassroomCacheEntries])
class ClassroomCache extends _$ClassroomCache {
  ClassroomCache([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'neuq_one_public_classrooms'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          classroomCacheEntries,
          classroomCacheEntries.resource,
        );
      }
    },
  );

  Future<ClassroomCacheEntry?> readWeek() => (select(
    classroomCacheEntries,
  )..where((row) => row.id.equals(1))).getSingleOrNull();

  Future<void> writeWeek(ClassroomCacheEntry entry) async {
    await into(classroomCacheEntries).insertOnConflictUpdate(entry);
  }

  Future<int> cacheBytes() async {
    final row = await readWeek();
    if (row == null) return 0;
    return [
      row.payload,
      row.resource,
      row.etag,
      row.lastModified,
      row.cacheControl,
    ].whereType<String>().fold<int>(
      0,
      (sum, value) => sum + utf8.encode(value).length,
    );
  }

  Future<void> removeWeek() async {
    await (delete(
      classroomCacheEntries,
    )..where((row) => row.id.equals(1))).go();
  }
}

final classroomCacheProvider = Provider<ClassroomCache>((ref) {
  final cache = ClassroomCache();
  ref.onDispose(cache.close);
  return cache;
});
