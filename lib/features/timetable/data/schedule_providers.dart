import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/school_data.dart';
import '../../../core/time/campus_clock.dart';
import '../../exams/data/local_exams.dart';
import '../domain/schedule.dart';
import '../presentation/timetable_date.dart';
import 'local_timetable.dart';

final _courseScheduleProvider = Provider.autoDispose<CourseSchedule>((ref) {
  return CourseSchedule(
    ref.watch(visibleTimetableProvider.select((state) => state.value)),
  );
});

final scheduleEventsProvider = Provider.autoDispose<ScheduleEvents>((ref) {
  return ScheduleEvents(
    ref.watch(_courseScheduleProvider),
    ref.watch(examsProvider.select((state) => state.value)) ?? const [],
  );
});

final scheduleConflictsProvider = Provider.autoDispose<ScheduleConflicts>(
  (ref) => ScheduleConflicts(ref.watch(scheduleEventsProvider)),
);

enum ScheduleCourseCheck { complete, incomplete }

class ScheduleCourseCheckStatus {
  const ScheduleCourseCheckStatus(this.condition);

  final ScheduleCourseCheck condition;

  bool get complete => condition == ScheduleCourseCheck.complete;

  /// The extra explanation is only needed when conflict detection could miss
  /// courses. A complete local cache adds no footer to the exam editor.
  String? get message => switch (condition) {
    ScheduleCourseCheck.complete => null,
    ScheduleCourseCheck.incomplete => '课表尚未完整读取，暂时无法完整检测课程冲突。',
  };
}

final scheduleCourseCheckProvider =
    Provider.autoDispose<ScheduleCourseCheckStatus>((ref) {
      final hasSchoolCache = ref.watch(
        schoolTimetableCacheProvider.select((state) => state.value != null),
      );
      final localError = ref.watch(
        timetableProvider.select((state) => state.hasError),
      );
      return ScheduleCourseCheckStatus(
        hasSchoolCache && !localError
            ? ScheduleCourseCheck.complete
            : ScheduleCourseCheck.incomplete,
      );
    });

/// Campus wall-clock time, refreshed only at midnight, exam ends and resume.
final scheduleClockProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(timetableClockProvider)();
  var next = calendarDate(now).add(const Duration(days: 1));
  for (final exam
      in ref.watch(examsProvider.select((state) => state.value)) ?? const []) {
    final end = exam.campusEnd;
    if (end.isAfter(now) && end.isBefore(next)) next = end;
  }
  final timer = Timer(next.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return now;
});
