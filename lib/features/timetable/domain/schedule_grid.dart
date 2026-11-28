import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import 'course_period_span.dart';
import 'schedule.dart';

typedef GridSpan = ({double start, double end});

class ExamGroup {
  const ExamGroup(this.events, this.time);

  final List<ScheduleEvent> events;
  final ScheduleInterval time;
}

/// Connected components of overlapping exams, clipped to one campus date.
List<ExamGroup> groupExamsOn(DateTime date, Iterable<ScheduleEvent> exams) {
  final day = ScheduleInterval.day(date);
  final groups = <ExamGroup>[];
  for (final event in exams) {
    final time = event.time.intersection(day);
    if (time == null) continue;
    if (groups.isEmpty || !time.start.isBefore(groups.last.time.end)) {
      groups.add(ExamGroup([event], time));
    } else {
      final previous = groups.last;
      previous.events.add(event);
      if (time.end.isAfter(previous.time.end)) {
        groups[groups.length - 1] = ExamGroup(
          previous.events,
          ScheduleInterval(previous.time.start, time.end),
        );
      }
    }
  }
  return groups;
}

double _minuteOn(DateTime date, DateTime instant) =>
    instant.difference(campusInstant(date, 0)).inMicroseconds /
    Duration.microsecondsPerMinute;

double _gridPosition(double minute) {
  for (final (index, period) in neuqPeriods.indexed) {
    if (minute <= period.start) return index.toDouble();
    if (minute < period.end) {
      return index + (minute - period.start) / (period.end - period.start);
    }
  }
  return neuqPeriods.length.toDouble();
}

GridSpan examGridSpan(DateTime date, ScheduleInterval time) => (
  start: _gridPosition(_minuteOn(date, time.start)),
  end: _gridPosition(_minuteOn(date, time.end)),
);

bool examNeedsSupplement(DateTime date, ExamGroup group) {
  final span = examGridSpan(date, group.time);
  if (span.end - span.start < .75) return true;
  final from = _minuteOn(date, group.time.start);
  final to = _minuteOn(date, group.time.end);
  return !neuqPeriods.any(
        (period) => from >= period.start && from < period.end,
      ) ||
      !neuqPeriods.any((period) => to > period.start && to <= period.end) ||
      group.events.any((event) {
        final span = examGridSpan(date, event.time);
        return span.end <= span.start;
      });
}

List<GridSpan> visibleCourseSpans(
  DateTime date,
  ScheduleEvent course,
  List<ExamGroup> exams,
) {
  if (exams.isEmpty) {
    final span = coursePeriodSpan(course.course!);
    return [(start: span.start.toDouble(), end: span.end.toDouble())];
  }
  if (!exams.any((exam) => exam.time.overlaps(course.time))) {
    final span = examGridSpan(date, course.time);
    if (span.start < span.end) return [span];
    // Historical courses outside the school periods retain their old slot.
    final legacy = coursePeriodSpan(course.course!);
    final projected = (
      start: legacy.start.toDouble(),
      end: legacy.end.toDouble(),
    );
    return exams.any((exam) {
          final span = examGridSpan(date, exam.time);
          return span.start < projected.end && projected.start < span.end;
        })
        ? []
        : [projected];
  }
  final spans = <GridSpan>[];
  var start = course.time.start;
  for (final exam in exams) {
    final overlap = exam.time.intersection(course.time);
    if (overlap == null) continue;
    final span = examGridSpan(date, ScheduleInterval(start, overlap.start));
    if (span.start < span.end) spans.add(span);
    start = overlap.end;
  }
  final remaining = examGridSpan(
    date,
    ScheduleInterval(start, course.time.end),
  );
  if (remaining.start < remaining.end) spans.add(remaining);
  return spans;
}
