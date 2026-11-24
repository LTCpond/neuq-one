import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/storage/settings.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/time/campus_clock.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';

final reminderServiceProvider = Provider((ref) => CourseReminderService());

final reminderSyncProvider = FutureProvider<void>((ref) async {
  final lead = ref.watch(
    settingsProvider.select((state) => state.value?.reminderMinutes),
  );
  if (lead == null) return;
  final service = ref.watch(reminderServiceProvider);
  if (lead == 0 || ref.watch(schoolSessionProvider).asData?.value == null) {
    await service.sync(const Timetable([], []), 0);
    return;
  }
  final timetable = ref.watch(visibleTimetableProvider).value;
  if (timetable != null) await service.sync(timetable, lead);
});

class CourseReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _queue = Future.value();
  List<_Reminder>? _scheduled;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _initialize() =>
      _initialization ??= _setup().onError<Object>((error, stack) {
        _initialization = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _setup() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_course'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  Future<void> sync(Timetable timetable, int lead) {
    if (!supported) return Future.value();
    final operation = _queue.then((_) => _sync(timetable, lead));
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _sync(Timetable timetable, int lead) async {
    final reminders = lead == 0 ? <_Reminder>[] : _upcoming(timetable, lead);
    if (listEquals(_scheduled, reminders)) return;
    await _initialize();
    await _plugin.cancelAllPendingNotifications();
    _scheduled = null;
    for (final (index, item) in reminders.indexed) {
      if (!item.at.isAfter(DateTime.now().toUtc())) continue;
      await _plugin.zonedSchedule(
        id: 1000 + index,
        scheduledDate: tz.TZDateTime.from(
          item.at,
          tz.getLocation('Asia/Shanghai'),
        ),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'courses',
            '课程提醒',
            channelDescription: '本地课表的上课提醒',
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: '即将上课 · ${item.name}',
        body: item.details,
      );
    }
    _scheduled = reminders;
  }

  List<_Reminder> _upcoming(Timetable timetable, int lead) {
    final now = DateTime.now().toUtc();
    final reminders = <_Reminder>[];
    for (final term in timetable.semesters) {
      for (final course in timetable.forSemester(term.id)) {
        for (final week in course.weeks) {
          if (!course.occurs(term, week, course.weekday)) continue;
          final at = term
              .dateFor(week, course.weekday)
              .add(Duration(minutes: course.startMinute - lead))
              .subtract(campusOffset);
          if (!at.isAfter(now)) continue;
          reminders.add((
            at: at,
            name: course.name,
            details: [
              course.time,
              course.room,
            ].where((text) => text.isNotEmpty).join(' · '),
          ));
        }
      }
    }
    reminders.sort((a, b) => a.at.compareTo(b.at));
    return reminders.take(60).toList();
  }
}

typedef _Reminder = ({DateTime at, String name, String details});
