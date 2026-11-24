import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/school_data.dart';
import '../../../core/time/campus_clock.dart';
import '../domain/timetable.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => LocalTimetableRepository(ref.watch(databaseProvider)),
);
final timetableProvider = StreamProvider<Timetable>(
  (ref) => ref.watch(timetableRepositoryProvider).watch(),
);

final visibleTimetableProvider = Provider<AsyncValue<Timetable>>((ref) {
  final local = ref.watch(timetableProvider);
  final school = ref.watch(schoolTimetableCacheProvider).value?.data;
  if (school == null) return local;
  return local.whenData(
    (data) => Timetable(
      [...school.semesters, ...data.semesters]
        ..sort((a, b) => b.start.compareTo(a.start)),
      [...school.courses, ...data.courses],
    ),
  );
});

class LocalTimetableRepository implements TimetableRepository {
  LocalTimetableRepository(this.db);

  final AppDatabase db;

  static Semester semesterFromRow(SemesterRow row) => Semester(
    id: row.id,
    name: row.name,
    start: row.start.toUtc(),
    weeks: row.weeks,
  );

  static Course courseFromRow(CourseRow row) => Course(
    id: row.id,
    semesterId: row.semesterId,
    name: row.name,
    teacher: row.teacher,
    room: row.room,
    weekday: row.weekday,
    startMinute: row.startMinute,
    endMinute: row.endMinute,
    weeks: row.weeks.split(',').map(int.parse).toList(),
    colorIndex: row.colorIndex,
  );

  @override
  Stream<Timetable> watch() {
    final semesters = db.semesterRows;
    final courses = db.courseRows;
    final query =
        db.select(semesters).join([
          leftOuterJoin(courses, courses.semesterId.equalsExp(semesters.id)),
        ])..orderBy([
          OrderingTerm.desc(semesters.start),
          OrderingTerm.asc(semesters.name),
          OrderingTerm.asc(courses.weekday),
          OrderingTerm.asc(courses.startMinute),
        ]);
    return query.watch().map((rows) {
      final terms = <String, Semester>{};
      final classes = <Course>[];
      for (final row in rows) {
        final term = row.readTable(semesters);
        terms.putIfAbsent(term.id, () => semesterFromRow(term));
        final course = row.readTableOrNull(courses);
        if (course != null) classes.add(courseFromRow(course));
      }
      return Timetable(terms.values.toList(), classes);
    });
  }

  @override
  Future<void> saveSemester(Semester semester) => db.transaction(() async {
    if (semester.name.trim().isEmpty ||
        semester.weeks < 1 ||
        semester.weeks > 30 ||
        semester.start.year < 2000 ||
        semester.start.year > 2100 ||
        semester.id.trim().isEmpty ||
        isSchoolRecord(semester.id) ||
        semester.start != calendarDate(semester.start)) {
      throw const FormatException('请输入有效的学期名称、开学日期和教学周数（1–30）');
    }
    final courses = await _courses(semester.id);
    for (final course in courses) {
      if (course.weeks.any((week) => week > semester.weeks) ||
          !course.weeks.any(
            (week) => semester.includes(week, course.weekday),
          )) {
        throw FormatException('学期修改会使「${course.name}」的周次失效，请先调整课程');
      }
      if (courses.any((other) => course.conflictsWith(other, semester))) {
        throw const FormatException('学期修改会造成课程时间冲突，请先调整课程');
      }
    }
    await db
        .into(db.semesterRows)
        .insertOnConflictUpdate(
          SemesterRow(
            id: semester.id,
            name: semester.name.trim(),
            start: semester.start,
            weeks: semester.weeks,
          ),
        );
  });

  @override
  Future<void> saveCourse(Course course) => db.transaction(() async {
    final row = await (db.select(
      db.semesterRows,
    )..where((r) => r.id.equals(course.semesterId))).getSingleOrNull();
    if (row == null) throw const FormatException('找不到课程所属学期');
    final semester = semesterFromRow(row);
    if (course.id.trim().isEmpty ||
        isSchoolRecord(course.id) ||
        isSchoolRecord(course.semesterId) ||
        course.name.trim().isEmpty ||
        course.weekday < 1 ||
        course.weekday > 7 ||
        course.startMinute < 0 ||
        course.endMinute > 1439 ||
        course.endMinute <= course.startMinute ||
        course.colorIndex < 0 ||
        course.weeks.isEmpty ||
        course.weeks.any((week) => week < 1 || week > semester.weeks) ||
        !course.weeks.any((week) => semester.includes(week, course.weekday))) {
      throw const FormatException('请检查课程名称、时间和教学周');
    }
    final conflicts = (await _courses(course.semesterId))
        .where((other) => course.conflictsWith(other, semester));
    if (conflicts.isNotEmpty) {
      throw FormatException('与「${conflicts.first.name}」时间重叠');
    }
    final normalizedWeeks = course.weeks.toSet().toList()..sort();
    await db
        .into(db.courseRows)
        .insertOnConflictUpdate(
          CourseRow(
            id: course.id,
            semesterId: course.semesterId,
            name: course.name.trim(),
            teacher: course.teacher.trim(),
            room: course.room.trim(),
            weekday: course.weekday,
            startMinute: course.startMinute,
            endMinute: course.endMinute,
            weeks: normalizedWeeks.join(','),
            colorIndex: course.colorIndex,
          ),
        );
  });

  Future<List<Course>> _courses(String id) async => (await (db.select(
    db.courseRows,
  )..where((r) => r.semesterId.equals(id))).get()).map(courseFromRow).toList();

  @override
  Future<void> deleteCourse(String id) =>
      (db.delete(db.courseRows)..where((r) => r.id.equals(id))).go();
}
