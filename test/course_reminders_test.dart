import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NotificationPlatform platform;
  late CourseReminderService service;
  final now = DateTime.utc(2099, 11, 23, 0);
  final semester = Semester(id: 'term', name: '学期', start: now, weeks: 4);
  Timetable schedule(List<String> ids, {String room = '101'}) => Timetable(
    [semester],
    [
      for (final (index, id) in ids.indexed)
        Course(
          id: id,
          semesterId: 'term',
          name: id,
          teacher: '',
          room: room,
          weekday: DateTime.monday,
          startMinute: 8 * 60 + 40 + index * 5,
          endMinute: 9 * 60 + index * 5,
          weeks: const [1],
          colorIndex: 0,
        ),
    ],
  );
  Future<ReminderStatus> sync(
    List<String> ids, {
    String? subject = 'current',
    int lead = 10,
    bool allowInexact = false,
    String room = '101',
  }) => service.sync(
    subject: subject,
    timetable: schedule(ids, room: room),
    lead: lead,
    allowInexact: allowInexact,
  );

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = _NotificationPlatform();
    messenger.setMockMethodCallHandler(channel, platform.call);
    service = CourseReminderService(clock: () => now);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'permission denial, consent to inexact, upgrade to exact and revocation',
    () async {
      platform.allowed = false;
      platform.exact = false;
      expect((await sync(['A'])).condition, ReminderCondition.permissionDenied);
      expect(platform.calls, isNot(contains('requestNotificationsPermission')));
      expect(await service.requestPermission(), isFalse);
      platform.grantOnRequest = true;
      expect(await service.requestPermission(), isTrue);
      expect(
        (await sync(['A'])).condition,
        ReminderCondition.exactPermissionNeeded,
      );
      expect(platform.pending, isEmpty);
      final inexact = await sync(['A'], allowInexact: true);
      expect(inexact.condition, ReminderCondition.inexact);
      expect(inexact.firstDay, DateTime.utc(2099, 11, 23));
      expect(
        (platform.scheduled.single['platformSpecifics'] as Map)['scheduleMode'],
        'inexactAllowWhileIdle',
      );
      expect(platform.scheduled.single['timeZoneName'], 'Asia/Shanghai');
      expect(
        platform.scheduled.single['scheduledDateTime'],
        '2099-11-23T08:30:00',
      );
      final id = platform.pending.keys.single;
      expect(await service.requestExactPermission(), isTrue);
      expect((await sync(['A'])).condition, ReminderCondition.active);
      expect(
        (platform.scheduled.last['platformSpecifics'] as Map)['scheduleMode'],
        'exactAllowWhileIdle',
      );
      expect(platform.pending.keys.single, id);
      platform.allowed = false;
      expect((await sync(['A'])).condition, ReminderCondition.permissionDenied);
      expect(platform.pending, isEmpty);
    },
  );

  test(
    'failed addition or edit preserves other alarms and retries incrementally',
    () async {
      platform.failTitle = '即将上课 · B';
      platform.pending[444] = {
        'id': 444,
        'title': '其他通知',
        'body': '',
        'payload': 'other',
      };
      platform.pending[1001] = {
        'id': 1001,
        'title': '即将上课 · 旧版',
        'body': '',
        'payload': '',
      };
      expect(
        (await sync(['A', 'B'])).condition,
        ReminderCondition.partialFailure,
      );
      expect(platform.cancelled, contains(1001));
      expect(platform.pending, contains(444));
      final idA = platform.pending.values.singleWhere(
        (p) => p['title'] == '即将上课 · A',
      )['id'];
      platform.failTitle = null;
      expect((await sync(['A', 'B'])).count, 2);
      expect(
        platform.scheduled.where((p) => p['title'] == '即将上课 · A'),
        hasLength(1),
      );
      final count = platform.scheduled.length;
      await sync(['A', 'B']);
      expect(platform.scheduled, hasLength(count));
      platform.failTitle = '即将上课 · A';
      expect(
        (await sync(['A', 'B'], room: '202')).condition,
        ReminderCondition.partialFailure,
      );
      expect(platform.pending[idA]?['body'], contains('101'));
      platform.failTitle = null;
      await sync(['A', 'B'], room: '202');
      expect(platform.pending[idA]?['body'], contains('202'));
      final lost = platform.pending.values.singleWhere(
        (p) => p['title'] == '即将上课 · B',
      )['id'];
      platform.pending.remove(lost);
      expect((await sync(['A', 'B'], room: '202')).count, 2);
      expect(platform.pending, contains(lost));
    },
  );

  test(
    'logout and switches cancel only course alarms; test uses its own ID',
    () async {
      platform.pending[1003] = {'id': 1003, 'title': '其他业务', 'body': ''};
      await sync(['A']);
      expect(await service.sendTest(), ReminderTestResult.submitted);
      expect(platform.shown.single['id'], CourseReminderService.testId);
      expect(platform.shown.single['title'], 'NEUQ One · 测试通知');
      final shownDetails = platform.shown.single['platformSpecifics'] as Map;
      final scheduleDetails =
          platform.scheduled.single['platformSpecifics'] as Map;
      expect(shownDetails['channelId'], scheduleDetails['channelId']);
      expect(shownDetails['icon'], scheduleDetails['icon']);
      await sync(['A'], subject: 'different');
      expect(
        platform.pending.values.where((p) => p['title'] == '即将上课 · A'),
        hasLength(1),
      );
      await sync(const [], subject: null);
      expect(platform.pending.keys, [1003]);
      expect(platform.cancelled, isNot(contains(CourseReminderService.testId)));
      expect(platform.calls, isNot(contains('cancelAllPendingNotifications')));
      expect(await service.sendTest(), ReminderTestResult.submitted);
    },
  );

  test(
    'Android rolling window supports more than 60 pending requests',
    () async {
      final many = Timetable(
        [semester],
        [
          for (var i = 0; i < 24; i++)
            Course(
              id: '$i',
              semesterId: 'term',
              name: '$i',
              teacher: '',
              room: '',
              weekday: DateTime.monday,
              startMinute: 8 * 60 + 40 + i,
              endMinute: 9 * 60 + i,
              weeks: const [1, 2, 3, 4],
              colorIndex: 0,
            ),
        ],
      );
      final result = await service.sync(
        subject: 'current',
        timetable: many,
        lead: 10,
        allowInexact: false,
      );
      expect(result.count, 96);
      expect(result.lastDay, now.add(const Duration(days: 21)));
      expect(platform.pending.length, 96);
    },
  );

  test(
    'iOS initializes without requesting and reserves space for other notices',
    () async {
      IOSFlutterLocalNotificationsPlugin.registerWith();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.ios = true;
      platform.allowed = false;
      expect((await sync(['A'])).condition, ReminderCondition.permissionDenied);
      expect(platform.calls, isNot(contains('requestPermissions')));
      platform.grantOnRequest = true;
      expect(await service.sendTest(), ReminderTestResult.submitted);
      platform.pending[140] = {'id': 140, 'title': '其他', 'payload': 'other'};
      expect((await sync([for (var i = 0; i < 60; i++) '$i'])).count, 55);
      expect(platform.pending, hasLength(56));
      expect(platform.pending, contains(140));
    },
  );
}

class _NotificationPlatform {
  bool allowed = true;
  bool exact = true;
  bool grantOnRequest = false;
  bool ios = false;
  String? failTitle;
  final calls = <String>[];
  final pending = <int, Map<String, Object?>>{};
  final scheduled = <Map<Object?, Object?>>[];
  final shown = <Map<Object?, Object?>>[];
  final cancelled = <int>[];

  Future<Object?> call(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'initialize':
        return !ios;
      case 'areNotificationsEnabled':
        return allowed;
      case 'checkPermissions':
        return {'isEnabled': allowed, 'isAlertEnabled': allowed};
      case 'requestNotificationsPermission':
      case 'requestPermissions':
        return allowed = grantOnRequest;
      case 'requestExactAlarmsPermission':
        return exact = true;
      case 'canScheduleExactNotifications':
        return exact;
      case 'getNotificationChannels':
        return [];
      case 'pendingNotificationRequests':
        return pending.values.toList();
      case 'zonedSchedule':
        final args = call.arguments as Map;
        scheduled.add(Map.of(args));
        if (args['title'] == failTitle) {
          throw PlatformException(code: 'test_schedule_failure');
        }
        final id = args['id'] as int;
        pending[id] = {
          'id': id,
          'title': args['title'],
          'body': args['body'],
          'payload': args['payload'],
        };
        return null;
      case 'cancel':
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        pending.remove(id);
        return null;
      case 'show':
        shown.add(Map.of(call.arguments as Map));
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}
