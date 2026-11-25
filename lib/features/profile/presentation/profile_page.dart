import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/storage/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../data/course_reminders.dart';

const _repositoryUrl = String.fromEnvironment(
  'NEUQ_ONE_REPOSITORY_URL',
  defaultValue: 'https://github.com/LTCpond/neuq-one',
);

const _sectionStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w800);

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
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ProfileHeader(
            connection: DataPanel(
              value: connection,
              retry: () => ref.invalidate(schoolConnectionProvider),
              builder: (status) => _AccountCard(
                status: status,
                onLogout: status == SchoolConnection.connected && !_busy
                    ? () => _run(() async {
                        await ref
                            .read(schoolSessionProvider.notifier)
                            .disconnect();
                        return null;
                      })
                    : null,
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              15,
              16,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('偏好设置', style: _sectionStyle),
                const SizedBox(height: 6),
                if (ref.watch(rememberedSchoolPasswordProvider).value == true)
                  ListTile(
                    leading: const Icon(Icons.lock_reset),
                    title: const Text('删除已记住的学校密码'),
                    onTap: _busy
                        ? null
                        : () => _run(() async {
                            final subject = ref
                                .read(schoolSessionProvider)
                                .asData
                                ?.value
                                ?.subject;
                            if (subject == null) return null;
                            await ref
                                .read(schoolAuthRepositoryProvider)
                                .forgetPassword(subject);
                            if (mounted) {
                              ref.invalidate(rememberedSchoolPasswordProvider);
                            }
                            return '已删除本机保存的学校密码';
                          }),
                  ),
                DataPanel(
                  value: settings,
                  retry: () => ref.invalidate(settingsProvider),
                  builder: (value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PopupMenuButton<ThemeMode>(
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
                        child: _ProfileTile(
                          icon: const Icon(Icons.light_mode_outlined),
                          title: '外观',
                          subtitle: _themeLabel(value.theme),
                          accent: (colors.primaryContainer, colors.primary),
                        ),
                      ),
                      const SizedBox(height: 6),
                      PopupMenuButton<int>(
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
                        child: _ProfileTile(
                          icon: const Icon(Icons.notifications_none_outlined),
                          title: '课程提醒',
                          subtitle:
                              reminders.hasError && value.reminderMinutes > 0
                              ? '排程失败，请重试'
                              : value.reminderMinutes == 0
                              ? '关闭'
                              : '提前 ${value.reminderMinutes} 分钟 · 系统可能延迟',
                          accent: dark
                              ? (
                                  const Color(0xFF563D25),
                                  const Color(0xFFFFD1A4),
                                )
                              : (
                                  const Color(0xFFFFE8CF),
                                  const Color(0xFFA45717),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text('数据管理', style: _sectionStyle),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.delete_outline),
                  title: '清除缓存',
                  subtitle: '移除文件选择产生的临时副本',
                  accent: dark
                      ? (const Color(0xFF214D3B), const Color(0xFFADE3CA))
                      : (const Color(0xFFDCF2E7), const Color(0xFF288264)),
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                          await FilePicker.clearTemporaryFiles();
                          return '临时文件已清除';
                        }),
                ),
                const SizedBox(height: 6),
                const Text('关于', style: _sectionStyle),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.verified_user_outlined),
                  title: '隐私说明',
                  accent: dark
                      ? (const Color(0xFF47365F), const Color(0xFFE2CCFF))
                      : (const Color(0xFFE9E1FA), const Color(0xFF744BB4)),
                  onTap: () => _showInfo(
                    '隐私说明',
                    '学期、课表、成绩和旧版考试记录保存在设备数据库。学校官网处理密码和验证码。校园卡余额和读取时间按账号加密保存在本机。应用使用派生标识隔离账号，无应用内统计。导出的 ICS 文件含明文课表数据，请妥善保管。',
                  ),
                ),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.info_outline),
                  title: '关于 NEUQ One',
                  subtitle: '免费开源 · 非官方',
                  accent: dark
                      ? (const Color(0xFF25495A), const Color(0xFFAEE5FA))
                      : (const Color(0xFFDDF0F8), const Color(0xFF267795)),
                  onTap: () => _showInfo(
                    '关于 NEUQ One',
                    'NEUQ One 是面向东北大学秦皇岛分校学生的非官方开源校园工作台。学校的正式通知、成绩和业务办理以官方系统为准。',
                  ),
                ),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: Image.asset(
                    'assets/ui/github.png',
                    width: 23,
                    height: 22,
                    color: dark
                        ? const Color(0xFFD7E2F0)
                        : const Color(0xFF344158),
                    excludeFromSemantics: true,
                  ),
                  title: 'GitHub 仓库',
                  subtitle: _repositoryUrl.isEmpty ? '发布地址待配置' : '源代码与问题反馈',
                  accent: dark
                      ? (const Color(0xFF343F51), const Color(0xFFD7E2F0))
                      : (const Color(0xFFE4E8EF), const Color(0xFF344158)),
                  trailing: Icons.open_in_new,
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.connection});

  final Widget connection;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        bottom: 55,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: ColoredBox(
            color: campusBlue,
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  top: 0,
                  child: Image.asset(
                    'assets/ui/profile-stripes.png',
                    width: 168,
                    height: 212,
                    excludeFromSemantics: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 20,
              16,
              16,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR CAMPUS. YOUR WAY.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFDCE7FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 15),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: 'NEUQ',
                      children: [
                        TextSpan(
                          text: ' One',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 48,
                      color: Colors.white,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: 11),
                Text(
                  '个人中心 · 账号与设置',
                  style: TextStyle(fontSize: 13, color: Color(0xFFDCE7FF)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: connection,
          ),
        ],
      ),
    ],
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.status, required this.onLogout});

  final SchoolConnection status;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF293812);
    return Card(
      color: campusLime,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 83,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 13,
        textColor: ink,
        leading: const CampusIconBadge(
          background: Color(0xFFBEDF50),
          foreground: Color(0xFF354814),
          size: 47,
          child: Icon(Icons.verified_user_outlined),
        ),
        title: Text(switch (status) {
          SchoolConnection.unavailable => '认证待接入',
          SchoolConnection.disconnected => '未连接',
          SchoolConnection.connected => '学校身份已验证',
        }, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Text(
            '统一身份认证',
            style: TextStyle(color: Color(0xFF466020), fontSize: 12),
          ),
        ),
        trailing: status != SchoolConnection.connected
            ? null
            : Tooltip(
                message: '退出统一身份认证',
                child: TextButton(
                  onPressed: onLogout,
                  style: TextButton.styleFrom(
                    foregroundColor: ink,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('退出'),
                      SizedBox(width: 3),
                      Icon(Icons.chevron_right, size: 17),
                    ],
                  ),
                ),
              ),
        onTap: () => openOfficialPage(context, 'https://eone.neuq.edu.cn/'),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.accent,
    this.subtitle,
    this.onTap,
    this.trailing = Icons.chevron_right,
  });

  final Widget icon;
  final String title;
  final (Color, Color) accent;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 67,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 12,
        leading: CampusIconBadge(
          size: 43,
          background: accent.$1,
          foreground: accent.$2,
          child: icon,
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
        trailing: Icon(trailing, size: 17, color: colors.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
