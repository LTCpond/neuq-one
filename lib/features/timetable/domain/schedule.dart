import 'dart:convert';

import '../../../core/time/campus_clock.dart';
import '../../exams/domain/exam.dart';
import 'course_colors.dart';
import 'timetable.dart';

class ScheduleInterval {
  const ScheduleInterval(this.start, this.end);

  final DateTime start;
  final DateTime end;

  factory ScheduleInterval.day(DateTime date) =>
      ScheduleInterval(campusInstant(date, 0), campusInstant(date, 1440));

  bool get isValid => start.isBefore(end);

  bool overlaps(ScheduleInterval other) =>
      isValid &&
      other.isValid &&
      start.isBefore(other.end) &&
      other.start.isBefore(end);

  ScheduleInterval? intersection(ScheduleInterval other) => overlaps(other)
      ? ScheduleInterval(
          start.isAfter(other.start) ? start : other.start,
          end.isBefore(other.end) ? end : other.end,
        )
      : null;
}

enum ScheduleEventType { course, exam }

class ScheduleEvent {
  ScheduleEvent.course(Course value, Semester term, DateTime date)
    : course = value,
      semester = term,
      exam = null,
      time = ScheduleInterval(
        campusInstant(date, value.startMinute),
        campusInstant(date, value.endMinute),
      );

  ScheduleEvent.exam(Exam value)
    : exam = value,
      course = null,
      semester = null,
      time = ScheduleInterval(value.at.toUtc(), value.endsAt.toUtc());

  final Course? course;
  final Semester? semester;
  final Exam? exam;
  final ScheduleInterval time;

  ScheduleEventType get type =>
      exam == null ? ScheduleEventType.course : ScheduleEventType.exam;
  String get id => exam == null
      ? 'course:${course!.id}:${time.start.millisecondsSinceEpoch}'
      : 'exam:${exam!.id}';
  String get name => exam?.name ?? course!.name;
  String get room => exam?.room ?? course!.room;
  String get teacher => course?.teacher ?? '';
  int? get colorIndex => course?.colorIndex;
  DateTime get date => campusDateAt(time.start);
  String get timeLabel => exam?.campusTimeRange ?? course!.time;

  List<Object> get _identity => [
    type.name,
    if (exam != null)
      exam!.id
    else ...[
      semester!.id,
      courseSubjectKey(course!),
      teacher.replaceAll(RegExp(r'\s+'), ''),
    ],
    time.start.millisecondsSinceEpoch,
    time.end.millisecondsSinceEpoch,
  ];
}

int compareScheduleEvents(ScheduleEvent a, ScheduleEvent b) {
  final start = a.time.start.compareTo(b.time.start);
  if (start != 0) return start;
  final type = b.type.index.compareTo(a.type.index);
  return type == 0 ? a.id.compareTo(b.id) : type;
}

class CourseSchedule {
  CourseSchedule(Timetable? timetable) {
    if (timetable == null) return;
    final terms = {for (final term in timetable.semesters) term.id: term};
    for (final course in timetable.courses) {
      final term = terms[course.semesterId];
      if (term == null || course.weekday < 1 || course.weekday > 7) continue;
      for (final week in course.weeks.toSet()) {
        if (!term.includes(week, course.weekday)) continue;
        final date = term.dateFor(week, course.weekday);
        final event = ScheduleEvent.course(course, term, date);
        if (event.time.isValid) (_days[date] ??= []).add(event);
      }
    }
    _dates.addAll(_days.keys);
    _dates.sort();
    for (final events in _days.values) {
      events.sort(compareScheduleEvents);
    }
  }

  final _days = <DateTime, List<ScheduleEvent>>{};
  final _dates = <DateTime>[];

  Iterable<ScheduleEvent> on(DateTime date, {String? semesterId}) =>
      (_days[calendarDate(date)] ?? const <ScheduleEvent>[]).where(
        (event) => semesterId == null || event.semester!.id == semesterId,
      );

  Iterable<ScheduleEvent> overlapping(ScheduleInterval interval) sync* {
    if (!interval.isValid) return;
    final first = campusDateAt(interval.start);
    final last = campusDateAt(interval.end);
    var low = 0;
    var high = _dates.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_dates[middle].isBefore(first)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < _dates.length; index++) {
      final date = _dates[index];
      if (date.isAfter(last)) break;
      yield* _days[date]!.where((event) => event.time.overlaps(interval));
    }
  }
}

class ScheduleConflict {
  const ScheduleConflict(this.exam, this.other);

  final ScheduleEvent exam;
  final ScheduleEvent other;

  ScheduleInterval get overlap => exam.time.intersection(other.time)!;
  String get key => jsonEncode([exam._identity, other._identity]);
}

class ScheduleEvents {
  ScheduleEvents(this.courses, Iterable<Exam> exams)
    : exams = [
        for (final exam in exams)
          if (exam.at.isBefore(exam.endsAt)) ScheduleEvent.exam(exam),
      ]..sort(compareScheduleEvents);

  final CourseSchedule courses;
  final List<ScheduleEvent> exams;

  Iterable<ScheduleEvent> examsOverlapping(ScheduleInterval interval) sync* {
    for (final exam in exams) {
      if (!exam.time.start.isBefore(interval.end)) break;
      if (exam.time.overlaps(interval)) yield exam;
    }
  }

  List<ScheduleEvent> on(
    DateTime date, {
    String? semesterId,
    bool showExams = true,
  }) => [
    ...courses.on(date, semesterId: semesterId),
    if (showExams) ...examsOverlapping(ScheduleInterval.day(date)),
  ]..sort(compareScheduleEvents);

  List<ScheduleEvent> conflictsForDraft(
    ScheduleInterval time, {
    String? excludeExamId,
  }) => [
    ...courses.overlapping(time),
    ...examsOverlapping(time).where((event) => event.exam!.id != excludeExamId),
  ]..sort(compareScheduleEvents);
}

class ScheduleConflicts {
  ScheduleConflicts(ScheduleEvents schedule) {
    final exams = schedule.exams;
    for (final (index, exam) in exams.indexed) {
      for (final course in schedule.courses.overlapping(exam.time)) {
        _add(ScheduleConflict(exam, course));
      }
      for (var next = index + 1; next < exams.length; next++) {
        final other = exams[next];
        if (!other.time.start.isBefore(exam.time.end)) break;
        if (exam.time.overlaps(other.time)) _add(ScheduleConflict(exam, other));
      }
    }
  }

  final _pairs = <ScheduleConflict>[];
  final _byExam = <String, List<ScheduleConflict>>{};
  Iterable<ScheduleConflict> get pairs => _pairs;

  void _add(ScheduleConflict conflict) {
    _pairs.add(conflict);
    (_byExam[conflict.exam.exam!.id] ??= []).add(conflict);
    if (conflict.other.exam case final other?) {
      (_byExam[other.id] ??= []).add(conflict);
    }
  }

  Iterable<ScheduleConflict> forExam(String id, {DateTime? date}) {
    final pairs = _byExam[id] ?? const <ScheduleConflict>[];
    if (date == null) return pairs;
    final day = ScheduleInterval.day(date);
    return pairs.where((pair) => day.overlaps(pair.overlap));
  }

  List<ScheduleEvent> relatedTo(
    Iterable<ScheduleEvent> selected, {
    DateTime? date,
  }) {
    final found = {for (final event in selected) event.id: event};
    final queue = found.values.where((event) => event.exam != null).toList();
    for (var index = 0; index < queue.length; index++) {
      for (final pair in forExam(queue[index].exam!.id, date: date)) {
        for (final event in [pair.exam, pair.other]) {
          if (found.containsKey(event.id)) continue;
          found[event.id] = event;
          if (event.exam != null) queue.add(event);
        }
      }
    }
    return found.values.toList()..sort(compareScheduleEvents);
  }
}
