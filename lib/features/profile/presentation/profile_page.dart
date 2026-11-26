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
import '../data/app_updates.dart';
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
  bool _checkingForUpdate = false;

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

  Future<void> _forgetCredentials() => _run(() async {
    final subject = ref.read(schoolSessionProvider).asData?.value?.subject;
    if (subject == null) return null;
    await ref.read(schoolAuthRepositoryProvider).forgetPassword(subject);
    if (mounted) ref.invalidate(rememberedSchoolPasswordProvider);
    return '已删除本地保存的学号与密码';
  });

  Future<void> _checkForUpdate() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    final AppUpdateResult result;
    try {
      result = await ref.read(appUpdatesProvider).checkForUpdate();
    } catch (_) {
      if (mounted) showMessage(context, '检查更新失败，请稍后重试');
      return;
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
    if (!mounted) return;
    switch (result) {
      case NoPublishedAppRelease():
        showMessage(context, '暂无可用更新');
      case AppUpToDate():
        showMessage(context, '当前已是最新版本');
      case AppUpdateAvailable(
        :final currentVersion,
        :final latestVersion,
        :final url,
      ):
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('发现新版本'),
            content: Text('当前版本 v$currentVersion\n最新版本 v$latestVersion'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('前往 GitHub 下载'),
              ),
            ],
          ),
        );
        if (open == true && mounted) await openOfficialPage(context, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final connection = ref.watch(schoolConnectionProvider);
    final remembered = ref.watch(rememberedSchoolPasswordProvider);
    final reminders = ref.watch(reminderSyncProvider);
    final installedVersion = ref.watch(installedAppVersionProvider);
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
                if (remembered.value == true) ...[
                  _ProfileTile(
                    icon: const Icon(Icons.lock_reset),
                    title: '删除本地保存的学号与密码',
                    subtitle: '清除用于自动续登的凭据',
                    accent: (colors.errorContainer, colors.onErrorContainer),
                    onTap: _busy || remembered.isLoading
                        ? null
                        : _forgetCredentials,
                  ),
                  const SizedBox(height: 6),
                ],
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
                    'NEUQ One 尊重并保护用户隐私。用户相关信息均在本地设备处理和存储，仅在使用相关功能时与学校系统或对应服务提供方进行必要的数据交互。\n\n'
                        '本应用不会向项目维护者的服务器上传用户个人数据，不包含广告、行为追踪或用户数据统计功能，源代码公开可查。',
                  ),
                ),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.system_update_alt_rounded),
                  title: '检查更新',
                  subtitle: installedVersion.when(
                    data: (version) => '当前版本 v$version',
                    loading: () => '正在读取当前版本…',
                    error: (_, _) => '无法读取当前版本',
                  ),
                  accent: (colors.primaryContainer, colors.onPrimaryContainer),
                  loadingLabel: _checkingForUpdate ? '正在检查更新' : null,
                  onTap: _checkForUpdate,
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
                  title: 'GitHub',
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
                      Icon(Icons.logout_rounded, size: 17),
                    ],
                  ),
                ),
              ),
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
    this.loadingLabel,
  });

  final Widget icon;
  final String title;
  final (Color, Color) accent;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailing;
  final String? loadingLabel;

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
        trailing: loadingLabel == null
            ? Icon(trailing, size: 17, color: colors.onSurfaceVariant)
            : SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: loadingLabel,
                ),
              ),
        onTap: loadingLabel == null ? onTap : null,
      ),
    );
  }
}
