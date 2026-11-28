import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';

final reminderServiceProvider = Provider((ref) => CourseReminderService());

final reminderSyncProvider = FutureProvider<ReminderStatus>((ref) async {
  final settings = ref.watch(settingsProvider).value;
  final identity = ref.watch(schoolSessionProvider);
  if (settings == null || identity.isLoading) {
    return const ReminderStatus(ReminderCondition.settingUp);
  }
  final service = ref.watch(reminderServiceProvider);
  final subject = identity.asData?.value?.subject;
  final lead = settings.reminderMinutes;
  final timetable = subject == null || lead == 0
      ? null
      : ref.watch(visibleTimetableProvider);
  final schoolCache = timetable == null
      ? null
      : ref.watch(schoolTimetableCacheProvider);
  final local = timetable == null ? null : ref.watch(timetableProvider);
  final waitingForSchoolCache =
      (schoolCache?.isLoading ?? false) ||
      (schoolCache?.hasError ?? false) ||
      (local?.isLoading ?? false) ||
      (local?.hasError ?? false);
  return service.sync(
    subject: subject,
    timetable: waitingForSchoolCache ? null : timetable?.asData?.value,
    timetableFailed:
        (schoolCache?.hasError ?? false) ||
        (timetable?.hasError ?? false) ||
        (local?.hasError ?? false),
    lead: lead,
    allowInexact: settings.allowInexactReminders,
  );
}, retry: (_, _) => null);

enum ReminderCondition {
  off,
  settingUp,
  active,
  permissionDenied,
  exactPermissionNeeded,
  inexact,
  partialFailure,
  failed,
  noUpcoming,
  unsupported,
}

class ReminderStatus {
  const ReminderStatus(
    this.condition, {
    this.count = 0,
    this.firstDay,
    this.lastDay,
    this.inexact = false,
  });

  final ReminderCondition condition;
  final int count;
  final DateTime? firstDay;
  final DateTime? lastDay;
  final bool inexact;

  String get label => switch (condition) {
    ReminderCondition.off => '未开启',
    ReminderCondition.settingUp => '正在设置',
    ReminderCondition.active => '正常运行',
    ReminderCondition.permissionDenied => '通知权限未授权',
    ReminderCondition.exactPermissionNeeded => '请选择定时方式',
    ReminderCondition.inexact => '非精确定时，可能延迟',
    ReminderCondition.partialFailure => '部分排程失败，可重试',
    ReminderCondition.failed => '排程失败，可重试',
    ReminderCondition.noUpcoming => '当前排程范围内暂无课程提醒',
    ReminderCondition.unsupported => '当前设备不支持课程提醒',
  };
}

enum ReminderTestResult { submitted, permissionDenied, unsupported }

class CourseReminderService {
  CourseReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? clock,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _clock = clock ?? DateTime.now;

  static const testId = 999;
  static const _titlePrefix = '即将上课 · ';
  static const _payloadPrefix = 'neuq-course-v1/';
  static const _channelId = 'courses';
  static const _examChannelId = 'exam-conflicts';
  static const _examConflictId = 998;
  static const examConflictPayloadPrefix = 'neuq-exam-conflict-v1/';
  static const _settingsChannel = MethodChannel(
    'org.neuqone.neuq_one/notification_settings',
  );
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '课程提醒',
      channelDescription: '本地课表的上课提醒',
      icon: 'ic_stat_course',
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _clock;
  Future<void>? _initialization;
  Future<void>? _launchCheck;
  String? _pendingExamTap;
  VoidCallback? onExamConflictTap;
  Future<void> _queue = Future.value();
  int _revision = 0;

  // Android exposes the plugin's persisted schedule. Reassert exact alarms
  // once per process because revocation can remove them before Android restarts us.
  final _assertedAndroidRequests = <int, String>{};

  bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get supported =>
      !kIsWeb && (isAndroid || defaultTargetPlatform == TargetPlatform.iOS);

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  Future<void> _initialize() => _initialization ??= _setup().onError<Object>((
    error,
    stack,
  ) {
    _initialization = null;
    _log(DiagnosticStage.initialize, error, level: DiagnosticSeverity.error);
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _setup() async {
    tz_data.initializeTimeZones();
    final ready = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_course'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || !payload.startsWith(examConflictPayloadPrefix)) {
          return;
        }
        _pendingExamTap = payload;
        onExamConflictTap?.call();
      },
    );
    // On iOS the plugin returns false when setup requests no authorizations.
    if (ready == null || (isAndroid && !ready)) {
      throw PlatformException(code: 'notification_initialization_failed');
    }
    diagnostics.record(
      DiagnosticModule.reminders,
      DiagnosticStage.initialize,
      level: DiagnosticSeverity.debug,
    );
  }

  Future<bool> notificationsAllowed() => _notificationsAllowed(_channelId);

  Future<bool> _notificationsAllowed(String channelId) async {
    if (!supported) return false;
    await _initialize();
    if (isAndroid) {
      if (await _android?.areNotificationsEnabled() != true) return false;
      final channels = await _android?.getNotificationChannels();
      return !(channels?.any(
            (channel) =>
                channel.id == channelId &&
                channel.importance == Importance.none,
          ) ??
          false);
    }
    final permission = await _ios?.checkPermissions();
    return permission?.isEnabled == true ||
        permission?.isProvisionalEnabled == true;
  }

  Future<void> _checkNotificationLaunch() async {
    await _initialize();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.startsWith(examConflictPayloadPrefix)) {
      _pendingExamTap ??= payload;
    }
  }

  Future<String?> takeExamConflictTap() async {
    if (!supported) return null;
    await (_launchCheck ??= _checkNotificationLaunch().onError<Object>((
      error,
      stack,
    ) {
      _launchCheck = null;
      Error.throwWithStackTrace(error, stack);
    }));
    final payload = _pendingExamTap;
    _pendingExamTap = null;
    return payload;
  }

  Future<bool> showExamConflict({
    required String body,
    required String payload,
    required bool Function() isCurrent,
  }) async {
    if (!await _notificationsAllowed(_examChannelId) || !isCurrent()) {
      return false;
    }
    await _plugin.show(
      id: _examConflictId,
      title: '考试时间冲突提醒',
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _examChannelId,
          '考试冲突提醒',
          channelDescription: '教务课表更新后发现的新考试时间冲突',
          icon: 'ic_stat_course',
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    return true;
  }

  Future<void> dismissExamConflict() async {
    if (!supported) return;
    await _initialize();
    await _plugin.cancel(id: _examConflictId);
  }

  Future<bool> requestPermission() async {
    try {
      if (await notificationsAllowed()) return true;
      if (!supported) return false;
      if (isAndroid) {
        await _android?.requestNotificationsPermission();
      } else {
        await _ios?.requestPermissions(alert: true, sound: true);
      }
      final allowed = await notificationsAllowed();
      if (!allowed) _denied();
      return allowed;
    } catch (error) {
      _log(DiagnosticStage.permission, error);
      rethrow;
    }
  }

  Future<bool> requestExactPermission() async {
    if (!supported || !isAndroid) return false;
    try {
      await _initialize();
      final granted = await _android?.requestExactAlarmsPermission() ?? false;
      if (!granted) _denied();
      return granted;
    } catch (error) {
      _log(DiagnosticStage.permission, error);
      rethrow;
    }
  }

  Future<bool> openNotificationSettings() async =>
      supported && await _settingsChannel.invokeMethod<bool>('open') == true;

  Future<ReminderTestResult> sendTest() async {
    if (!supported) return ReminderTestResult.unsupported;
    if (!await requestPermission()) return ReminderTestResult.permissionDenied;
    try {
      await _plugin.show(
        id: testId,
        title: 'NEUQ One · 测试通知',
        body: '这是一条课程提醒测试通知。',
        notificationDetails: _details,
      );
      return ReminderTestResult.submitted;
    } catch (error) {
      _log(DiagnosticStage.show, error);
      rethrow;
    }
  }

  Future<ReminderStatus> sync({
    required String? subject,
    required Timetable? timetable,
    required int lead,
    required bool allowInexact,
    bool timetableFailed = false,
  }) {
    if (!supported) {
      return Future.value(const ReminderStatus(ReminderCondition.unsupported));
    }
    final revision = ++_revision;
    final operation = _queue.then((_) async {
      try {
        return await _sync(
          revision,
          subject,
          timetable,
          lead,
          allowInexact,
          timetableFailed,
        );
      } catch (error) {
        _log(DiagnosticStage.sync, error, level: DiagnosticSeverity.error);
        return const ReminderStatus(ReminderCondition.failed);
      }
    });
    _queue = operation.then((_) {});
    return operation;
  }

  Future<ReminderStatus> _sync(
    int revision,
    String? subject,
    Timetable? timetable,
    int lead,
    bool allowInexact,
    bool timetableFailed,
  ) async {
    const settingUp = ReminderStatus(ReminderCondition.settingUp);
    if (revision != _revision) return settingUp;
    await _initialize();
    final pending = await _plugin.pendingNotificationRequests();
    if (revision != _revision) return settingUp;
    final enabled = lead > 0 && subject != null;
    final owner = enabled ? _digest([subject]) : null;
    var condition = enabled ? ReminderCondition.active : ReminderCondition.off;
    var inexact = false;
    if (enabled) {
      if (!await notificationsAllowed()) {
        condition = ReminderCondition.permissionDenied;
        _denied();
      } else if (isAndroid &&
          await _android?.canScheduleExactNotifications() != true) {
        condition = allowInexact
            ? ReminderCondition.inexact
            : ReminderCondition.exactPermissionNeeded;
        inexact = allowInexact;
      }
    }
    final canSchedule =
        condition == ReminderCondition.active ||
        condition == ReminderCondition.inexact;
    final now = _clock().toUtc();
    final candidates = canSchedule && timetable != null
        ? _upcoming(timetable, lead, now)
        : null;
    final requests = {for (final request in pending) request.id: request};
    final reserved = requests.keys.toSet()..add(testId);
    final owned = <String, PendingNotificationRequest>{};
    var failures = 0;
    var foreign = 0;
    for (final request in pending) {
      if (revision != _revision) return settingUp;
      final record = _record(request.payload);
      final legacy =
          record == null &&
          _isLegacy(request.id, request.title, request.payload);
      if (record == null && !legacy) {
        foreign++;
        continue;
      }
      final key = record?.key;
      if (canSchedule &&
          record != null &&
          record.owner == owner &&
          (candidates == null || candidates.containsKey(key)) &&
          !owned.containsKey(key)) {
        owned[key!] = request;
      } else if (await _cancel(request.id)) {
        requests.remove(request.id);
      } else {
        failures++;
        foreign++; // Still occupies a platform slot.
      }
    }

    if (revision != _revision) return settingUp;
    if (!canSchedule) {
      _assertedAndroidRequests.clear();
      return ReminderStatus(
        failures > 0 ? ReminderCondition.failed : condition,
      );
    }
    if (candidates == null) {
      return ReminderStatus(
        timetableFailed || failures > 0
            ? (owned.isEmpty
                  ? ReminderCondition.failed
                  : ReminderCondition.partialFailure)
            : ReminderCondition.settingUp,
        count: owned.length,
        inexact: inexact,
      );
    }

    // Leave headroom for other uses of AlarmManager and the iOS notification queue.
    final limit = ((isAndroid ? 400 : 64) - foreign - (isAndroid ? 20 : 8))
        .clamp(0, isAndroid ? 380 : 56);
    final selected = candidates.entries.take(limit).toList();
    final selectedKeys = selected.map((entry) => entry.key).toSet();
    // Keep the nearest requests if the available system budget shrinks.
    for (final entry in owned.entries.toList().reversed) {
      if (selectedKeys.contains(entry.key)) continue;
      if (revision != _revision) return settingUp;
      if (await _cancel(entry.value.id)) {
        requests.remove(entry.value.id);
        owned.remove(entry.key);
      } else {
        failures++;
      }
    }

    var changed = requests.length != pending.length;
    final expected = <String, String>{};
    final mode = isAndroid ? (inexact ? 'inexact' : 'exact') : 'ios';
    for (final MapEntry(key: key, value: item) in selected) {
      if (revision != _revision) return settingUp;
      if (!item.at.isAfter(_clock().toUtc())) continue;
      final current = owned[key];
      final id = current?.id ?? _allocateId(_digest([owner, key]), reserved);
      final fingerprint = _digest([item.title, item.body]);
      final payload =
          '$_payloadPrefix$owner/$key/$mode/${item.at.millisecondsSinceEpoch}/$fingerprint';
      expected[key] = payload;
      if (current?.payload == payload &&
          current?.title == item.title &&
          current?.body == item.body &&
          (!isAndroid || inexact || _assertedAndroidRequests[id] == payload)) {
        continue;
      }
      if (current == null && requests.length >= foreign + limit) {
        failures++;
        continue;
      }
      try {
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(
            item.at,
            tz.getLocation('Asia/Shanghai'),
          ),
          notificationDetails: _details,
          androidScheduleMode: inexact
              ? AndroidScheduleMode.inexactAllowWhileIdle
              : AndroidScheduleMode.exactAllowWhileIdle,
          title: item.title,
          body: item.body,
          payload: payload,
        );
        requests[id] = PendingNotificationRequest(
          id,
          item.title,
          item.body,
          payload,
        );
        if (isAndroid) _assertedAndroidRequests[id] = payload;
        changed = true;
      } catch (error) {
        failures++;
        _log(DiagnosticStage.schedule, error);
      }
    }

    if (revision != _revision) return settingUp;
    final observed = changed || failures > 0
        ? await _plugin.pendingNotificationRequests()
        : requests.values;
    final verified = <String, String?>{};
    final dates = <DateTime>[];
    final checkedAt = _clock().toUtc();
    final observedIds = <int>{};
    for (final request in observed) {
      observedIds.add(request.id);
      final record = _record(request.payload);
      if (record == null ||
          record.owner != owner ||
          !record.at.isAfter(checkedAt) ||
          (inexact && record.mode == 'exact')) {
        continue;
      }
      dates.add(campusDateAt(record.at));
      if (request.title == candidates[record.key]?.title &&
          request.body == candidates[record.key]?.body) {
        verified[record.key] = request.payload;
      }
    }
    if (expected.entries.any(
      (entry) =>
          candidates[entry.key]!.at.isAfter(checkedAt) &&
          verified[entry.key] != entry.value,
    )) {
      failures++;
    }
    dates.sort();
    _assertedAndroidRequests.removeWhere((id, _) => !observedIds.contains(id));
    if (changed && failures == 0) {
      diagnostics.record(
        DiagnosticModule.reminders,
        DiagnosticStage.schedule,
        level: DiagnosticSeverity.info,
      );
    }
    return ReminderStatus(
      failures > 0 || (limit == 0 && candidates.isNotEmpty)
          ? (dates.isEmpty
                ? ReminderCondition.failed
                : ReminderCondition.partialFailure)
          : dates.isEmpty
          ? ReminderCondition.noUpcoming
          : condition,
      count: dates.length,
      firstDay: dates.firstOrNull,
      lastDay: dates.lastOrNull,
      inexact: inexact,
    );
  }

  Future<bool> _cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
      _assertedAndroidRequests.remove(id);
      return true;
    } catch (error) {
      _log(DiagnosticStage.cancel, error);
      return false;
    }
  }

  Map<String, _Reminder> _upcoming(
    Timetable timetable,
    int lead,
    DateTime now,
  ) {
    final end = campusDateAt(now).add(Duration(days: isAndroid ? 28 : 14));
    final reminders = <String, _Reminder>{};
    for (final term in timetable.semesters) {
      for (final course in timetable.forSemester(term.id)) {
        for (final week in course.weeks) {
          if (!course.occurs(term, week, course.weekday)) continue;
          final day = term.dateFor(week, course.weekday);
          final at = day
              .add(Duration(minutes: course.startMinute - lead))
              .subtract(campusOffset);
          if (!at.isAfter(now) || !day.isBefore(end)) continue;
          reminders[_digest([term.id, course.id, week])] = (
            at: at,
            title: '$_titlePrefix${course.name}',
            body: [
              course.time,
              course.room,
            ].where((value) => value.isNotEmpty).join(' · '),
          );
        }
      }
    }
    return Map.fromEntries(
      reminders.entries.toList()..sort((a, b) {
        final byTime = a.value.at.compareTo(b.value.at);
        return byTime == 0 ? a.key.compareTo(b.key) : byTime;
      }),
    );
  }

  static int _allocateId(String key, Set<int> reserved) {
    var offset = int.parse(key.substring(0, 8), radix: 16) & 0x1fffffff;
    while (!reserved.add(0x40000000 + offset)) {
      offset = (offset + 1) & 0x1fffffff;
    }
    return 0x40000000 + offset;
  }

  static String _digest(List<Object?> input) =>
      sha256.convert(utf8.encode(jsonEncode(input))).toString();

  static final _payloadPattern = RegExp(
    r'^neuq-course-v1/([0-9a-f]{64})/([0-9a-f]{64})/(exact|inexact|ios)/(\d{1,15})/[0-9a-f]{64}$',
  );

  static ({String owner, String key, String mode, DateTime at})? _record(
    String? payload,
  ) {
    final match = payload == null ? null : _payloadPattern.firstMatch(payload);
    return match == null
        ? null
        : (
            owner: match[1]!,
            key: match[2]!,
            mode: match[3]!,
            at: DateTime.fromMillisecondsSinceEpoch(
              int.parse(match[4]!),
              isUtc: true,
            ),
          );
  }

  static bool _isLegacy(int id, String? title, String? payload) =>
      id >= 1000 &&
      id < 1060 &&
      (payload == null || payload.isEmpty) &&
      (title?.startsWith(_titlePrefix) ?? false);

  static void _log(
    DiagnosticStage stage,
    Object error, {
    DiagnosticSeverity level = DiagnosticSeverity.warn,
  }) => diagnostics.record(
    DiagnosticModule.reminders,
    stage,
    error: error,
    level: level,
  );

  static void _denied() => diagnostics.record(
    DiagnosticModule.reminders,
    DiagnosticStage.permission,
    code: DiagnosticCode.permissionDenied,
  );
}

typedef _Reminder = ({DateTime at, String title, String body});
