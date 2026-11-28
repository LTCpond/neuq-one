import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/grades/domain/grades.dart';
import '../../features/grades/domain/plan_completion.dart';
import '../../features/timetable/domain/timetable.dart';
import '../../features/timetable/domain/course_colors.dart';
import '../auth/neuq_login_protocol.dart';
import '../auth/school_auth.dart';
import '../diagnostics/diagnostics.dart';
import '../network/neuq_client.dart' show schoolFailureCode;
import '../time/campus_clock.dart';
import '../time/neuq_periods.dart';
import 'app_database.dart';
import 'neuq_school_data_source.dart';
import 'school_data_source.dart';

export 'school_data_source.dart';

enum SchoolDataSet { timetable, grades, planCompletion }

final schoolDataSourceProvider = Provider<SchoolDataSource?>((ref) {
  final supported = ref.watch(schoolAuthRepositoryProvider).available;
  final subject = ref.watch(
    schoolSessionProvider.select((value) => value.asData?.value?.subject),
  );
  if (!supported || subject == null || !isStoredSchoolSubject(subject)) {
    return null;
  }
  return NeuqSchoolDataSource(ref.watch(neuqClientProvider), subject);
});

bool isSchoolRecord(String id) => id.startsWith('school:');

class SchoolCache<T> {
  const SchoolCache(this.data, this.syncedAt, {this.revision});
  final T data;
  final DateTime syncedAt;
  final String? revision;
}

final schoolTimetableCacheStreamProvider = StreamProvider.autoDispose
    .family<SchoolCache<Timetable>?, String>((ref, subject) {
      if (ref.watch(
            schoolSessionProvider.select(
              (state) => state.asData?.value?.subject,
            ),
          ) !=
          subject) {
        return const Stream.empty();
      }
      return SchoolDataRepository(ref.watch(databaseProvider)).watchTimetable();
    });

final schoolTimetableCacheProvider =
    Provider.autoDispose<AsyncValue<SchoolCache<Timetable>?>>((ref) {
      final subject = ref.watch(
        schoolSessionProvider.select((state) => state.asData?.value?.subject),
      );
      if (subject == null || !isStoredSchoolSubject(subject)) {
        return const AsyncData(null);
      }
      return ref.watch(schoolTimetableCacheStreamProvider(subject));
    });

final schoolGradesCacheProvider =
    StreamProvider.autoDispose<SchoolCache<SchoolGradeBook>?>((ref) {
      if (ref.watch(schoolDataSourceProvider) == null) {
        return Stream.value(null);
      }
      return SchoolDataRepository(ref.watch(databaseProvider)).watchGrades();
    });

final schoolPlanCompletionCacheProvider =
    StreamProvider.autoDispose<SchoolCache<PlanCompletion>?>((ref) {
      if (ref.watch(schoolDataSourceProvider) == null) {
        return Stream.value(null);
      }
      return ref.watch(schoolDataRepositoryProvider).watchPlanCompletion();
    });

final schoolRefreshProvider = FutureProvider.autoDispose
    .family<void, SchoolDataSet>((ref, section) async {
      final source = ref.watch(schoolDataSourceProvider);
      if (source == null) return;
      final repository = ref.watch(schoolDataRepositoryProvider);
      await repository.refresh(section, source);
    }, retry: (_, _) => null);

final refreshSchoolDataProvider = Provider<void Function()>(
  (ref) => () {
    for (final section in SchoolDataSet.values) {
      ref.invalidate(schoolRefreshProvider(section));
    }
  },
);

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
        () => _refresh(section, source)
            .onError<Object>((error, stack) {
              diagnostics.record(
                DiagnosticModule.academics,
                DiagnosticStage.sync,
                code: error is SchoolRequestFailure
                    ? schoolFailureCode(error)
                    : null,
                error: error,
              );
              Error.throwWithStackTrace(error, stack);
            })
            .whenComplete(() {
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
        await _db.transaction(() async {
          final previous = await (_db.select(
            _db.schoolCacheRows,
          )..where((row) => row.id.equals(section.name))).getSingleOrNull();
          final existing = previous == null
              ? null
              : _readPreviousColors(previous.payload);
          await _save(section, {
            'semesters': result.semesters.map((term) => term.toJson()).toList(),
            'courses': result.courses.map((course) => course.toJson()).toList(),
            'colors': assignCourseColors(result, existing ?? const {}),
            'revision': const Uuid().v4(),
          });
        });
        return;
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
      case SchoolDataSet.planCompletion:
        data = (await source.fetchPlanCompletion()).toJson();
    }
    await _save(section, data);
  }

  Future<void> _save(SchoolDataSet section, Map<String, Object?> data) async {
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

  Stream<SchoolCache<Timetable>?> watchTimetable() {
    Timetable? previous;
    String? previousKey;
    return _row(SchoolDataSet.timetable).map((row) {
      if (row == null) {
        previous = null;
        previousKey = null;
        return null;
      }
      final data = jsonDecode(row.payload) as Map<String, dynamic>;
      final timetable = _readTimetable(data);
      final colored = withCourseColors(
        timetable,
        _readColors(data) ?? assignCourseColors(timetable),
      );
      final key = jsonEncode([
        colored.semesters.map((term) => term.toJson()).toList(),
        colored.courses.map((course) => course.toJson()).toList(),
      ]);
      if (previousKey != key) {
        previousKey = key;
        previous = colored;
      }
      return SchoolCache(
        previous!,
        row.syncedAt.toUtc(),
        revision: data['revision'] as String?,
      );
    });
  }

  static Timetable _readTimetable(Map<String, dynamic> data) => Timetable(
    _list(data, 'semesters', Semester.fromJson),
    _list(data, 'courses', Course.fromJson)..sort((a, b) {
      final byTime = a.startMinute.compareTo(b.startMinute);
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    }),
  );

  static Map<String, Map<String, int>>? _readColors(Map<String, dynamic> data) {
    final colors = data['colors'];
    if (colors is! Map<String, dynamic>) return null;
    return {
      for (final term in colors.entries)
        if (term.value is Map<String, dynamic>)
          term.key: {
            for (final color in (term.value as Map<String, dynamic>).entries)
              if (color.value is int) color.key: color.value as int,
          },
    };
  }

  static Map<String, Map<String, int>>? _readPreviousColors(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return _readColors(data) ?? assignCourseColors(_readTimetable(data));
    } on Object {
      // A valid refresh replaces an unreadable cache.
      return null;
    }
  }

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

  Stream<SchoolCache<PlanCompletion>?> watchPlanCompletion() =>
      _row(SchoolDataSet.planCompletion).map((row) {
        if (row == null) return null;
        return SchoolCache(
          PlanCompletion.fromJson(
            jsonDecode(row.payload) as Map<String, dynamic>,
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
