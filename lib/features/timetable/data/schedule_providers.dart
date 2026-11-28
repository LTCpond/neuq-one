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

final scheduleCourseCheckProvider = Provider.autoDispose<String>((ref) {
  final hasSchoolCache = ref.watch(
    schoolTimetableCacheProvider.select((state) => state.value != null),
  );
  final localError = ref.watch(
    timetableProvider.select((state) => state.hasError),
  );
  if (!hasSchoolCache || localError) return '课表尚未完整读取，暂时无法完整检测课程冲突。';
  return '冲突检测依据本地课表缓存，教务课程安排请以学校为准。';
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
