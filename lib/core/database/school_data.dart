import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/grades/domain/grades.dart';
import '../../features/timetable/domain/timetable.dart';
import '../auth/neuq_login_protocol.dart';
import '../auth/school_auth.dart';
import '../network/neuq_web_client.dart';
import '../time/campus_clock.dart';
import '../time/neuq_periods.dart';
import 'app_database.dart';
import 'neuq_school_data_source.dart';
import 'school_data_source.dart';

export 'school_data_source.dart';

enum SchoolDataSet { timetable, grades }

final schoolWebClientProvider = Provider<NeuqWebClient?>((ref) {
  final supported = ref.watch(schoolAuthRepositoryProvider).available;
  final subject = ref.watch(
    schoolSessionProvider.select((value) => value.asData?.value?.subject),
  );
  if (!supported || subject == null || !isStoredSchoolSubject(subject)) {
    return null;
  }
  final browser = NeuqWebClient(subject);
  ref.onDispose(browser.dispose);
  return browser;
});

final schoolDataSourceProvider = Provider<SchoolDataSource?>((ref) {
  final browser = ref.watch(schoolWebClientProvider);
  return browser == null ? null : NeuqSchoolDataSource(browser);
});

bool isSchoolRecord(String id) => id.startsWith('school:');

class SchoolCache<T> {
  const SchoolCache(this.data, this.syncedAt);
  final T data;
  final DateTime syncedAt;
}

final schoolTimetableCacheProvider =
    StreamProvider.autoDispose<SchoolCache<Timetable>?>((ref) {
      if (ref.watch(schoolDataSourceProvider) == null) {
        return Stream.value(null);
      }
      return SchoolDataRepository(ref.watch(databaseProvider)).watchTimetable();
    });

final schoolGradesCacheProvider =
    StreamProvider.autoDispose<SchoolCache<SchoolGradeBook>?>((ref) {
      if (ref.watch(schoolDataSourceProvider) == null) {
        return Stream.value(null);
      }
      return SchoolDataRepository(ref.watch(databaseProvider)).watchGrades();
    });

final schoolRefreshProvider = FutureProvider.autoDispose
    .family<void, SchoolDataSet>((ref, section) async {
      final source = ref.watch(schoolDataSourceProvider);
      final session = ref.watch(schoolSessionProvider).asData?.value;
      if (source == null || session == null) return;
      final repository = ref.watch(schoolDataRepositoryProvider);
      await repository.refresh(section, source);
    }, retry: (_, _) => null);

final schoolDataRepositoryProvider = Provider.autoDispose(
  (ref) => SchoolDataRepository(ref.watch(databaseProvider)),
);

class SchoolDataRepository {
  SchoolDataRepository(this._db);
  final AppDatabase _db;
  final _inFlight = <SchoolDataSet, Future<void>>{};

  Future<void> refresh(SchoolDataSet section, SchoolDataSource source) =>
      _inFlight.putIfAbsent(
        section,
        () => _refresh(section, source).whenComplete(() {
          _inFlight.remove(section);
        }),
      );

  Future<void> _refresh(SchoolDataSet section, SchoolDataSource source) async {
    final Map<String, Object?> data;
    switch (section) {
      case SchoolDataSet.timetable:
        final result = await source.fetchTimetable();
        final terms = _terms(result.semesters);
        _checkIds(result.courses.map((course) => course.id));
        for (final course in result.courses) {
          final term = terms[course.semesterId];
          if (term == null ||
              course.name.trim().isEmpty ||
              course.weekday < 1 ||
              course.weekday > 7 ||
              course.colorIndex < 0 ||
              periodAtStart(course.startMinute) == null ||
              periodAtEnd(course.endMinute) == null ||
              course.startMinute >= course.endMinute ||
              course.weeks.isEmpty ||
              course.weeks.toSet().length != course.weeks.length ||
              course.weeks.any((week) => week < 1 || week > term.weeks) ||
              !course.weeks.any(
                (week) => term.includes(week, course.weekday),
              )) {
            throw const FormatException('教务课表包含无效的课程安排');
          }
        }
        data = {
          'semesters': result.semesters.map((term) => term.toJson()).toList(),
          'courses': result.courses.map((course) => course.toJson()).toList(),
        };
      case SchoolDataSet.grades:
        final result = await source.fetchGrades();
        final terms = _terms(result.semesters);
        if (result.semesterGpa.entries.any(
              (entry) =>
                  !terms.containsKey(entry.key) || !_validGpa(entry.value),
            ) ||
            (result.cumulativeGpa != null &&
                !_validGpa(result.cumulativeGpa!))) {
          throw const FormatException('教务系统返回了无效的绩点');
        }
        _checkIds(result.grades.map((grade) => grade.id));
        for (final grade in result.grades) {
          if (!terms.containsKey(grade.semesterId) ||
              grade.name.trim().isEmpty ||
              grade.demo ||
              !grade.validScore ||
              !grade.credit.isFinite ||
              grade.credit < 0 ||
              grade.credit > 50) {
            throw const FormatException('教务成绩包含无效的考核记录');
          }
        }
        data = {
          'semesters': result.semesters.map((term) => term.toJson()).toList(),
          'grades': result.grades.map((grade) => grade.toJson()).toList(),
          'semesterGpa': result.semesterGpa,
          'cumulativeGpa': result.cumulativeGpa,
        };
    }
    await _db
        .into(_db.schoolCacheRows)
        .insertOnConflictUpdate(
          SchoolCacheRow(
            id: section.name,
            payload: jsonEncode(data),
            syncedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Stream<SchoolCache<Timetable>?> watchTimetable() =>
      _row(SchoolDataSet.timetable).map((row) {
        if (row == null) return null;
        final data = jsonDecode(row.payload) as Map<String, dynamic>;
        final classes = _list(data, 'courses', Course.fromJson)
          ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
        return SchoolCache(
          Timetable(_list(data, 'semesters', Semester.fromJson), classes),
          row.syncedAt.toUtc(),
        );
      });

  Stream<SchoolCache<SchoolGradeBook>?> watchGrades() =>
      _row(SchoolDataSet.grades).map((row) {
        if (row == null) return null;
        final data = jsonDecode(row.payload) as Map<String, dynamic>;
        return SchoolCache(
          SchoolGradeBook(
            _list(data, 'semesters', Semester.fromJson),
            _list(data, 'grades', Grade.fromJson),
            semesterGpa:
                (data['semesterGpa'] as Map<String, dynamic>?)?.map(
                  (key, value) => MapEntry(key, (value as num).toDouble()),
                ) ??
                const {},
            cumulativeGpa: (data['cumulativeGpa'] as num?)?.toDouble(),
          ),
          row.syncedAt.toUtc(),
        );
      });

  static bool _validGpa(double value) =>
      value.isFinite && value >= 0 && value <= 5;

  Stream<SchoolCacheRow?> _row(SchoolDataSet section) => (_db.select(
    _db.schoolCacheRows,
  )..where((row) => row.id.equals(section.name))).watchSingleOrNull();

  static List<T> _list<T>(
    Map<String, dynamic> data,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) => (data[key] as List)
      .map((item) => fromJson(item as Map<String, dynamic>))
      .toList();

  static Map<String, Semester> _terms(List<Semester> semesters) {
    _checkIds(semesters.map((term) => term.id));
    if (semesters.any(
      (term) =>
          term.name.trim().isEmpty ||
          term.weeks < 1 ||
          term.weeks > 30 ||
          term.start != calendarDate(term.start) ||
          term.start.year < 2000 ||
          term.start.year > 2100,
    )) {
      throw const FormatException('教务系统返回了无效学期');
    }
    return {for (final term in semesters) term.id: term};
  }

  // A source must emit stable school-prefixed IDs for terms and records. Grade
  // IDs represent attempts, so retakes are retained as separate records.
  static void _checkIds(Iterable<String> ids) {
    if (ids.any((id) => !isSchoolRecord(id) || id.length == 'school:'.length) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('教务系统返回了重复或无效的记录编号');
    }
  }
}
