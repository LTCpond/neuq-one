import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../../profile/data/course_reminders.dart';

/// Unified timetable preferences: exam display, course reminders and exam
/// conflict notifications. All three switches use the existing settings fields
/// so upgrades keep the user's previous choices.
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() =>
      _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends ConsumerState<TimetableSettingsPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool? _notificationsAllowed;

  SettingsController get _settings => ref.read(settingsProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshNotificationPermission(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNotificationPermission();
  }

  Future<void> _refreshNotificationPermission() async {
    if (!mounted) return;
    final service = ref.read(reminderServiceProvider);
    if (!service.supported) return;
    var allowed = false;
    try {
      allowed = await service.notificationsAllowed();
    } on Object {
      // Diagnostics already record platform failures; keep the request entry.
    }
    if (mounted) setState(() => _notificationsAllowed = allowed);
  }

  Future<void> _run(
    Future<String?> Function(CourseReminderService) action, {
    bool refreshReminders = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action(ref.read(reminderServiceProvider));
      if (mounted && message != null) showMessage(context, message);
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.reminders,
        DiagnosticStage.sync,
        error: error,
      );
      final message = switch (error) {
        PlatformException(code: 'invalid_icon') => '通知图标无法加载，请更新或重新安装 App。',
        MissingPluginException() ||
        PlatformException(
          code: 'notification_initialization_failed',
        ) => '通知组件初始化失败，请重启 App 后重试。',
        _ => '本地通知操作失败，请检查系统通知设置后重试。',
      };
      if (mounted) showMessage(context, message);
    } finally {
      if (mounted) {
        if (refreshReminders) ref.invalidate(reminderSyncProvider);
        setState(() => _busy = false);
        _refreshNotificationPermission();
      }
    }
  }

  Future<void> _setShowExams(bool enabled) => _run((_) async {
    await _settings.setShowExamsInTimetable(enabled);
    return null;
  }, refreshReminders: false);

  Future<void> _setCourseReminders(bool enabled) => _run((service) async {
    if (!enabled) {
      await _settings.setReminder(0);
      return null;
    }
    await _settings.setReminder(10);
    return await service.requestPermission()
        ? null
        : '请在系统设置中允许 NEUQ One 的课程提醒通知。';
  });

  Future<void> _setLead(int minutes) => _run((service) async {
    final previous = ref.read(settingsProvider).value?.reminderMinutes ?? 0;
    await _settings.setReminder(minutes);
    if (minutes == 0 || previous > 0) return null;
    return await service.requestPermission()
        ? null
        : '请在系统设置中允许 NEUQ One 的课程提醒通知。';
  });

  Future<void> _setExamConflictReminders(bool enabled) => _run((service) async {
    await _settings.setExamConflictReminders(enabled);
    if (!enabled) return null;
    return await service.requestPermission()
        ? null
        : '请在系统设置中允许 NEUQ One 的考试冲突提醒通知。';
  }, refreshReminders: false);

  Future<void> _requestNotificationPermission() => _run(
    (service) async => await service.requestPermission()
        ? '通知权限已开启。'
        : '通知权限未开启，请在系统设置中允许 NEUQ One 的通知。',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final settings = ref.watch(settingsProvider).value;
    final status = ref.watch(reminderSyncProvider);
    final result = status.value;
    final service = ref.watch(reminderServiceProvider);
    final lead = settings?.reminderMinutes ?? 0;
    final failed =
        result?.condition == ReminderCondition.failed ||
        result?.condition == ReminderCondition.partialFailure;
    final loading = _busy || status.isLoading;
    final locked = _busy || settings == null;
    final remindersAvailable = !locked && service.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('课表设置')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  const _SettingsHeading('显示设置'),
                  const SizedBox(height: 8),
                  Card(
                    child: SwitchListTile(
                      title: const Text('在课表中显示考试'),
                      subtitle: const Text('在周课表中展示考试安排'),
                      value: settings?.showExamsInTimetable ?? true,
                      onChanged: locked ? null : _setShowExams,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SettingsHeading('通知提醒'),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('课程提醒'),
                          subtitle: const Text('在课程开始前发送通知'),
                          value: lead > 0,
                          onChanged: remindersAvailable
                              ? _setCourseReminders
                              : null,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 20,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '上课前提醒',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    lead == 0 ? '已关闭' : '提前 $lead 分钟',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                service.supported
                                    ? '选择在课程开始前多久推送本地通知。'
                                    : '当前设备不支持本地通知，无法接收课程提醒。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final minutes in const [
                                    0,
                                    5,
                                    10,
                                    15,
                                    30,
                                  ])
                                    ChoiceChip(
                                      label: Text(
                                        minutes == 0 ? '关闭' : '$minutes 分钟',
                                      ),
                                      selected: lead == minutes,
                                      showCheckmark: false,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: remindersAvailable
                                          ? (_) => _setLead(minutes)
                                          : null,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (service.isAndroid && lead > 0) ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            leading: const Icon(Icons.alarm_on_outlined),
                            title: const Text('允许精确定时'),
                            subtitle: const Text('在系统的「闹钟和提醒」中授权，避免提醒被延迟'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _busy
                                ? null
                                : () => _run(
                                    (service) async =>
                                        await service.requestExactPermission()
                                        ? null
                                        : '精确定时未授权，可选择允许非精确定时。',
                                  ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            title: const Text('允许非精确定时'),
                            subtitle: const Text('精确定时不可用时采用，系统可能延迟提醒'),
                            value: settings?.allowInexactReminders ?? false,
                            onChanged: _busy
                                ? null
                                : (enabled) => _run((_) async {
                                    await _settings.setInexactReminders(
                                      enabled,
                                    );
                                    return null;
                                  }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ReminderStatusCard(
                    status: result,
                    loading: loading,
                    busy: _busy,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: SwitchListTile(
                      title: const Text('考试冲突提醒'),
                      subtitle: const Text('教务课表更新后发现新增考试冲突时通知'),
                      value: settings?.examConflictReminders ?? true,
                      onChanged: remindersAvailable
                          ? _setExamConflictReminders
                          : null,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SettingsHeading('通知诊断'),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text('通知权限'),
                          subtitle: Text(
                            !service.supported
                                ? '当前设备不支持本地通知'
                                : switch (_notificationsAllowed) {
                                    null => '正在检查通知权限…',
                                    true => '已允许，课程提醒与考试冲突提醒可正常送达',
                                    false => '未允许，点击申请通知权限',
                                  },
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: remindersAvailable
                              ? _requestNotificationPermission
                              : null,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: const Icon(Icons.send_outlined),
                          title: const Text('发送测试通知'),
                          subtitle: const Text('立即验证提醒能否送达通知中心'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: remindersAvailable
                              ? () => _run((service) async {
                                  return switch (await service.sendTest()) {
                                    ReminderTestResult.submitted =>
                                      '已向系统提交测试通知，请查看通知中心。',
                                    ReminderTestResult.permissionDenied =>
                                      '请在系统设置中允许 NEUQ One 的通知。',
                                    ReminderTestResult.unsupported =>
                                      '当前设备不支持测试通知。',
                                  };
                                })
                              : null,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('打开系统通知设置'),
                          subtitle: const Text('管理通知权限与提醒渠道'),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: remindersAvailable
                              ? () => _run(
                                  (service) async =>
                                      await service.openNotificationSettings()
                                      ? null
                                      : '请在设备设置中找到 NEUQ One，打开通知。',
                                )
                              : null,
                        ),
                        if (failed) ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            leading: const Icon(Icons.refresh_rounded),
                            title: const Text('重试排程'),
                            subtitle: const Text('重新核对课表并安排后续提醒'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _busy
                                ? null
                                : () => ref.invalidate(reminderSyncProvider),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '打开 App 或回到前台时会补排后续课程，所有提醒时间均为北京时间。'
                          '通知能否准时显示也取决于设备设置。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(
      label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
  );
}

class _ReminderStatusCard extends StatelessWidget {
  const _ReminderStatusCard({
    required this.status,
    required this.loading,
    required this.busy,
  });

  final ReminderStatus? status;
  final bool loading;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final condition = status?.condition;
    final (background, foreground) = switch (condition) {
      ReminderCondition.permissionDenied ||
      ReminderCondition.failed ||
      ReminderCondition.partialFailure => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      ReminderCondition.active ||
      ReminderCondition.inexact ||
      ReminderCondition.settingUp ||
      null => (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainerHigh, colors.onSurfaceVariant),
    };
    final icon = switch (condition) {
      ReminderCondition.active => Icons.notifications_active_outlined,
      ReminderCondition.inexact => Icons.notifications_paused_outlined,
      ReminderCondition.off => Icons.notifications_off_outlined,
      ReminderCondition.permissionDenied => Icons.lock_outline_rounded,
      ReminderCondition.exactPermissionNeeded => Icons.alarm_on_outlined,
      ReminderCondition.partialFailure ||
      ReminderCondition.failed => Icons.error_outline_rounded,
      ReminderCondition.noUpcoming => Icons.event_busy_outlined,
      ReminderCondition.unsupported => Icons.block_outlined,
      ReminderCondition.settingUp || null => Icons.hourglass_empty_rounded,
    };
    final title = busy || loading ? '正在设置' : status?.label ?? '排程失败，可重试';
    final hint = switch (condition) {
      null => '正在核对课表与通知排程…',
      ReminderCondition.off => '开启后可在上课前收到本地提醒。',
      ReminderCondition.active => '课程提醒已就绪，会在课前准时送达。',
      ReminderCondition.inexact => '系统可能延迟几分钟送达提醒。',
      ReminderCondition.permissionDenied => '在系统设置中允许通知后即可正常提醒。',
      ReminderCondition.exactPermissionNeeded => '可授权精确定时，或允许非精确定时。',
      ReminderCondition.partialFailure => '部分课程排程失败，可重新核对。',
      ReminderCondition.failed => '排程未完成，请检查通知权限后重试。',
      ReminderCondition.noUpcoming => '当前排程范围内没有待提醒的课程。',
      ReminderCondition.unsupported => '当前设备不支持本地通知。',
      ReminderCondition.settingUp => '正在核对课表与通知排程…',
    };
    final first = status?.firstDay;
    final last = status?.lastDay;
    final count = status?.count ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CampusIconBadge(
                  size: 46,
                  background: background,
                  foreground: foreground,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (count > 0 || (first != null && last != null)) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (count > 0)
                    _StatusChip(
                      icon: Icons.notifications_none_rounded,
                      label: '已排程 $count 条',
                    ),
                  if (first != null && last != null)
                    _StatusChip(
                      icon: Icons.date_range_outlined,
                      label: '${shortDate(first)} – ${shortDate(last)}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
