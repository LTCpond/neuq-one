import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/storage/settings.dart';
import '../../../core/widgets/screen.dart';
import '../data/course_reminders.dart';

const _repositoryUrl = String.fromEnvironment(
  'NEUQ_ONE_REPOSITORY_URL',
  defaultValue: 'https://github.com/LTCpond/neuq-one',
);

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await operation();
      if (message != null && mounted) showMessage(context, message);
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, '操作失败，请检查设备设置后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final connection = ref.watch(schoolConnectionProvider);
    final reminders = ref.watch(reminderSyncProvider);
    return CampusScreen(
      title: '我的',
      eyebrow: '账号与设置',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SectionTitle('统一身份认证'),
          DataPanel(
            value: connection,
            retry: () => ref.invalidate(schoolConnectionProvider),
            builder: (status) => Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(switch (status) {
                  SchoolConnection.unavailable => '认证待接入',
                  SchoolConnection.disconnected => '未连接',
                  SchoolConnection.connected => '学校身份已验证',
                }),
                subtitle: const Text('在学校网站办理业务'),
                trailing: IconButton(
                  tooltip: '退出统一身份认证',
                  icon: const Icon(Icons.logout),
                  onPressed: status == SchoolConnection.connected
                      ? () => _run(() async {
                          await ref
                              .read(schoolSessionProvider.notifier)
                              .disconnect();
                          return null;
                        })
                      : null,
                ),
                onTap: () =>
                    openOfficialPage(context, 'https://eone.neuq.edu.cn/'),
              ),
            ),
          ),
          DataPanel(
            value: settings,
            retry: () => ref.invalidate(settingsProvider),
            builder: (value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('偏好'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('外观'),
                        subtitle: Text(_themeLabel(value.theme)),
                        trailing: PopupMenuButton<ThemeMode>(
                          enabled: !_busy,
                          tooltip: '切换主题',
                          initialValue: value.theme,
                          onSelected: (mode) => _run(() async {
                            await controller.setTheme(mode);
                            return null;
                          }),
                          itemBuilder: (_) => [
                            for (final mode in ThemeMode.values)
                              PopupMenuItem(
                                value: mode,
                                child: Text(_themeLabel(mode)),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('课程提醒'),
                        subtitle: Text(
                          reminders.hasError && value.reminderMinutes > 0
                              ? '排程失败，请重试'
                              : value.reminderMinutes == 0
                              ? '关闭'
                              : '提前 ${value.reminderMinutes} 分钟 · 系统可能延迟',
                        ),
                        trailing: PopupMenuButton<int>(
                          enabled: !_busy,
                          tooltip: '设置课程提醒',
                          initialValue: value.reminderMinutes,
                          onSelected: (minute) => _run(() async {
                            if (minute != 0 &&
                                !await ref
                                    .read(reminderServiceProvider)
                                    .requestPermission()) {
                              return '请在设备设置中允许通知后重试';
                            }
                            await controller.setReminder(minute);
                            ref.invalidate(reminderSyncProvider);
                            await ref.read(reminderSyncProvider.future);
                            return minute == 0 ? '课程提醒已关闭' : '已保存课程提醒设置';
                          }),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 0, child: Text('关闭')),
                            for (final minute in [5, 10, 15, 30])
                              PopupMenuItem(
                                value: minute,
                                child: Text('提前 $minute 分钟'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('数据管理'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清除缓存'),
                  subtitle: const Text('移除文件选择产生的临时副本'),
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                          await FilePicker.clearTemporaryFiles();
                          return '临时文件已清除';
                        }),
                ),
              ],
            ),
          ),
          const SectionTitle('关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私说明'),
                  onTap: () => _showInfo(
                    '隐私说明',
                    '学期、课表、考试和成绩保存在设备数据库。学校官网处理密码和验证码。校园卡余额和读取时间按账号加密保存在本机。应用使用派生标识隔离账号，无应用内统计。导出的 ICS 文件含明文课表数据，请妥善保管。',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 NEUQ One'),
                  subtitle: const Text('免费开源 · 非官方'),
                  onTap: () => _showInfo(
                    '关于 NEUQ One',
                    'NEUQ One 是面向东北大学秦皇岛分校学生的非官方开源校园工作台。学校的正式通知、成绩和业务办理以官方系统为准。',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub 仓库'),
                  subtitle: Text(
                    _repositoryUrl.isEmpty ? '发布地址待配置' : '源代码与问题反馈',
                  ),
                  trailing: _repositoryUrl.isEmpty
                      ? null
                      : const Icon(Icons.open_in_new),
                  onTap: _repositoryUrl.isEmpty
                      ? null
                      : () => openOfficialPage(context, _repositoryUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInfo(String title, String content) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String _themeLabel(ThemeMode theme) => switch (theme) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};
