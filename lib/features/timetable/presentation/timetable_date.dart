import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/campus_clock.dart';

final timetableClockProvider = Provider<DateTime Function()>(
  (ref) => campusNow,
);

final timetableDateProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(timetableClockProvider)();
  final today = calendarDate(now);
  final midnight = today.add(const Duration(days: 1));
  final timer = Timer(midnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return today;
});
