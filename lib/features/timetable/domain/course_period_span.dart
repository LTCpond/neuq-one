import '../../../core/time/neuq_periods.dart';
import 'timetable.dart';

/// Zero-based start and exclusive end in the school's twelve-period grid.
({int start, int end}) coursePeriodSpan(Course course) {
  final start =
      (periodAtStart(course.startMinute) ??
              neuqPeriods
                      .where((period) => course.startMinute >= period.end)
                      .length +
                  1)
          .clamp(1, neuqPeriods.length) -
      1;
  final end =
      periodAtEnd(course.endMinute) ??
      neuqPeriods.where((period) => course.endMinute > period.start).length;
  return (start: start, end: end.clamp(start + 1, neuqPeriods.length));
}
