import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../data/course_reminders.dart';

String reminderStatusLabel(AsyncValue<ReminderStatus> status) =>
    status.isLoading ? '正在设置' : status.value?.label ?? '排程失败，可重试';

class ReminderSettingsPage extends ConsumerStatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  ConsumerState<ReminderSettingsPage> createState() =>
      _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends ConsumerState<ReminderSettingsPage> {
  bool _busy = false;

  Future<void> _run(
    Future<String?> Function(CourseReminderService) action,
  ) async {
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
        ref.invalidate(reminderSyncProvider);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final status = ref.watch(reminderSyncProvider);
    final result = status.value;
    final service = ref.watch(reminderServiceProvider);
    final lead = settings?.reminderMinutes ?? 0;
    final first = result?.firstDay;
    final last = result?.lastDay;
    final failed =
        result?.condition == ReminderCondition.failed ||
        result?.condition == ReminderCondition.partialFailure;
    return Scaffold(
      appBar: AppBar(title: const Text('课程提醒')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_none_outlined),
              title: Text(_busy ? '正在设置' : reminderStatusLabel(status)),
              subtitle: first != null && last != null
                  ? Text(
                      '已核对 ${result!.count} 条待处理提醒 · ${shortDate(first)}至${shortDate(last)}（北京时间）',
                    )
                  : null,
            ),
          ),
          if (_busy || status.isLoading) const LinearProgressIndicator(),
          Card(
            child: ListTile(
              title: const Text('提醒时间'),
              trailing: DropdownButton<int>(
                value: [0, 5, 10, 15, 30].contains(lead) ? lead : 0,
                onChanged: _busy || settings == null || !service.supported
                    ? null
                    : (value) {
                        if (value == null) return;
                        _run((service) async {
                          await ref
                              .read(settingsProvider.notifier)
                              .setReminder(value);
                          if (value == 0 || lead > 0) return null;
                          return await service.requestPermission()
                              ? null
                              : '请在系统设置中允许 NEUQ One 的课程提醒通知。';
                        });
                      },
                items: [
                  const DropdownMenuItem(value: 0, child: Text('关闭')),
                  for (final minutes in [5, 10, 15, 30])
                    DropdownMenuItem(
                      value: minutes,
                      child: Text('提前 $minutes 分钟'),
                    ),
                ],
              ),
            ),
          ),
          if (service.isAndroid && lead > 0)
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('允许精确定时'),
                    subtitle: const Text('在系统的「闹钟和提醒」设置中授权'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: _busy
                        ? null
                        : () => _run(
                            (service) async =>
                                await service.requestExactPermission()
                                ? null
                                : '精确定时未授权，可选择允许非精确定时。',
                          ),
                  ),
                  SwitchListTile(
                    title: const Text('允许非精确定时'),
                    subtitle: const Text('精确定时不可用时采用，系统可能延迟提醒'),
                    value: settings?.allowInexactReminders ?? false,
                    onChanged: _busy
                        ? null
                        : (enabled) => _run((_) async {
                            await ref
                                .read(settingsProvider.notifier)
                                .setInexactReminders(enabled);
                            return null;
                          }),
                  ),
                ],
              ),
            ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.send_outlined),
                  title: const Text('发送测试通知'),
                  onTap: _busy || !service.supported
                      ? null
                      : () => _run((service) async {
                          return switch (await service.sendTest()) {
                            ReminderTestResult.submitted =>
                              '已向系统提交测试通知，请查看通知中心。',
                            ReminderTestResult.permissionDenied =>
                              '请在系统设置中允许 NEUQ One 的课程提醒通知。',
                            ReminderTestResult.unsupported => '当前设备不支持测试通知。',
                          };
                        }),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('打开系统通知设置'),
                  onTap: _busy || !service.supported
                      ? null
                      : () => _run(
                          (service) async =>
                              await service.openNotificationSettings()
                              ? null
                              : '请在设备设置中找到 NEUQ One，打开课程提醒通知。',
                        ),
                ),
                if (failed)
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('重试排程'),
                    onTap: _busy
                        ? null
                        : () => ref.invalidate(reminderSyncProvider),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('打开 App 或回到前台时会补排后续课程。通知能否准时显示也取决于设备设置。'),
          ),
        ],
      ),
    );
  }
}
