import 'package:json_annotation/json_annotation.dart';

import '../../../core/time/campus_clock.dart';

part 'timetable.g.dart';

@JsonSerializable()
class Semester {
  const Semester({
    required this.id,
    required this.name,
    required this.start,
    required this.weeks,
  });

  factory Semester.fromJson(Map<String, dynamic> json) =>
      _$SemesterFromJson(json);

  final String id;
  final String name;
  final DateTime start;
  final int weeks;

  Map<String, dynamic> toJson() => _$SemesterToJson(this);

  DateTime dateFor(int week, int weekday) =>
      mondayOf(start).add(Duration(days: (week - 1) * 7 + weekday - 1));

  int? weekFor(DateTime date) {
    final day = calendarDate(date);
    if (day.isBefore(calendarDate(start))) return null;
    final week = day.difference(mondayOf(start)).inDays ~/ 7 + 1;
    return week <= weeks ? week : null;
  }

  bool includes(int week, int weekday) =>
      week >= 1 &&
      week <= weeks &&
      !dateFor(week, weekday).isBefore(calendarDate(start));
}

Semester? currentSemester(List<Semester> semesters, DateTime now) {
  for (final semester in semesters) {
    if (!calendarDate(semester.start).isAfter(calendarDate(now))) {
      return semester;
    }
  }
  return semesters.firstOrNull;
}

enum WeekParity {
  all('每周'),
  odd('单周'),
  even('双周');

  const WeekParity(this.label);
  final String label;
}

List<int> parseWeeks(String text, int maxWeek, WeekParity parity) {
  final weeks = <int>{};
  for (final token in text.trim().split(RegExp(r'[,，、\s]+'))) {
    final match = RegExp(r'^(\d{1,2})(?:[-–－](\d{1,2}))?$').firstMatch(token);
    if (match == null) throw const FormatException('用逗号分隔周次，例如 1-8,10,12');
    final start = int.parse(match[1]!);
    final end = int.parse(match[2] ?? match[1]!);
    if (start < 1 || end > maxWeek || end < start) {
      throw FormatException('周次必须在 1–$maxWeek 周内，且起始周不可大于结束周');
    }
    for (var week = start; week <= end; week++) {
      if (parity == WeekParity.all ||
          (parity == WeekParity.odd ? week.isOdd : week.isEven)) {
        weeks.add(week);
      }
    }
  }
  if (weeks.isEmpty) throw const FormatException('请至少选择一个符合单双周条件的教学周');
  return weeks.toList()..sort();
}

@JsonSerializable()
class Course {
  const Course({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.teacher,
    required this.room,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    required this.colorIndex,
  });

  factory Course.fromJson(Map<String, dynamic> json) => _$CourseFromJson(json);

  final String id;
  final String semesterId;
  final String name;
  final String teacher;
  final String room;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final List<int> weeks;
  final int colorIndex;

  Map<String, dynamic> toJson() => _$CourseToJson(this);
  Course withColor(int color) => color == colorIndex
      ? this
      : Course(
          id: id,
          semesterId: semesterId,
          name: name,
          teacher: teacher,
          room: room,
          weekday: weekday,
          startMinute: startMinute,
          endMinute: endMinute,
          weeks: weeks,
          colorIndex: color,
        );
  String get time => '${clockLabel(startMinute)}–${clockLabel(endMinute)}';

  bool occurs(Semester semester, int week, int day) =>
      weekday == day && weeks.contains(week) && semester.includes(week, day);

  bool conflictsWith(Course other, Semester semester) =>
      id != other.id &&
      semesterId == other.semesterId &&
      weekday == other.weekday &&
      startMinute < other.endMinute &&
      other.startMinute < endMinute &&
      weeks.any(
        (week) =>
            other.weeks.contains(week) && semester.includes(week, weekday),
      );
}

class Timetable {
  const Timetable(this.semesters, this.courses);
  final List<Semester> semesters;
  final List<Course> courses;

  List<Course> forSemester(String id) =>
      courses.where((item) => item.semesterId == id).toList();

  List<Course> on(Semester semester, int week, int weekday) =>
      forSemester(semester.id)
          .where((course) => course.occurs(semester, week, weekday))
          .toList();
}

abstract interface class TimetableRepository {
  Stream<Timetable> watch();
  Future<void> saveSemester(Semester semester);
  Future<void> saveCourse(Course course);
  Future<void> deleteCourse(String id);
}

abstract interface class SchoolTimetableDataSource {
  Future<Timetable> fetchTimetable();
}
