import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/storage/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../../desktop_widgets/data/desktop_widget_bridge.dart';
import '../../desktop_widgets/presentation/desktop_widgets_page.dart';
import '../data/app_updates.dart';
import '../data/course_reminders.dart';
import 'cache_management_page.dart';
import 'diagnostics_page.dart';
import 'reminder_settings_page.dart';
import 'update_prompt.dart';

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
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        DiagnosticStage.clear,
        error: error,
      );
      if (mounted) showMessage(context, '操作失败，请检查设备设置后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgetCredentials() => _run(() async {
    final deleted = await ref
        .read(schoolSessionProvider.notifier)
        .forgetPassword();
    if (deleted && mounted) ref.invalidate(rememberedSchoolPasswordProvider);
    return deleted ? '已删除本地保存的学号与密码' : null;
  });

  Future<void> _checkForUpdate() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      await checkAndPresentAppUpdate(
        context,
        ref.read(appUpdateCoordinatorProvider),
        onChecked: () {
          if (mounted) setState(() => _checkingForUpdate = false);
        },
      );
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.updates,
        DiagnosticStage.initialize,
        error: error,
      );
      if (mounted) showMessage(context, '检查更新失败，请稍后重试');
    } finally {
      if (mounted && _checkingForUpdate) {
        setState(() => _checkingForUpdate = false);
      }
    }
  }

  void _openSettings(Widget page) => Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final connection = ref.watch(schoolConnectionProvider);
    final remembered = ref.watch(rememberedSchoolPasswordProvider);
    final reminders = ref.watch(reminderSyncProvider);
    final installedVersion = ref.watch(installedAppVersionProvider);
    final availableUpdate = ref.watch(availableAppUpdateProvider).value;
    final developmentBuild = ref.watch(androidDebugBuildProvider);
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
                onReconnect:
                    !_busy &&
                        (status == SchoolConnection.restoring ||
                            status == SchoolConnection.expired ||
                            status == SchoolConnection.offline ||
                            status == SchoolConnection.unknown)
                    ? const SchoolReconnectButton()
                    : null,
                onLogout:
                    status != SchoolConnection.unavailable &&
                        status != SchoolConnection.disconnected &&
                        !_busy
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
                      _ProfileTile(
                        icon: const Icon(Icons.notifications_none_outlined),
                        title: '课程提醒',
                        subtitle: reminderStatusLabel(reminders),
                        accent: dark
                            ? (const Color(0xFF563D25), const Color(0xFFFFD1A4))
                            : (
                                const Color(0xFFFFE8CF),
                                const Color(0xFFA45717),
                              ),
                        onTap: () =>
                            _openSettings(const ReminderSettingsPage()),
                      ),
                      if (supportsDesktopWidgets) ...[
                        const SizedBox(height: 6),
                        _ProfileTile(
                          icon: const Icon(Icons.widgets_outlined),
                          title: '桌面小组件',
                          subtitle: '预览 Android 桌面小组件',
                          accent: (colors.primaryContainer, colors.primary),
                          onTap: () =>
                              _openSettings(const DesktopWidgetsPage()),
                        ),
                      ],
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
                  title: '缓存管理',
                  subtitle: '查看占用并清理公共数据或临时文件',
                  accent: dark
                      ? (const Color(0xFF214D3B), const Color(0xFFADE3CA))
                      : (const Color(0xFFDCF2E7), const Color(0xFF288264)),
                  onTap: () => _openSettings(const CacheManagementPage()),
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
                        '本应用不会向项目维护者的服务器上传用户个人数据，不包含广告、行为追踪或用户数据统计功能，源代码公开可查。诊断信息只保存在本次运行的内存中，由用户手动复制。',
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
                  trailingLabel: availableUpdate == null
                      ? null
                      : 'v${availableUpdate.latestVersion} 可用',
                  onTap: _checkForUpdate,
                ),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.info_outline),
                  title: '关于 NEUQ One',
                  subtitle: '免费开源 · 非官方',
                  trailingLabel: developmentBuild ? 'DEV' : null,
                  accent: dark
                      ? (const Color(0xFF25495A), const Color(0xFFAEE5FA))
                      : (const Color(0xFFDDF0F8), const Color(0xFF267795)),
                  onTap: _showAbout,
                ),
                const SizedBox(height: 6),
                _ProfileTile(
                  icon: const Icon(Icons.bug_report_outlined),
                  title: '诊断信息',
                  accent: (colors.primaryContainer, colors.onPrimaryContainer),
                  onTap: () => _openSettings(const DiagnosticsPage()),
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

  Future<void> _showAbout() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(
        ref.read(androidDebugBuildProvider)
            ? '关于 NEUQ One · DEV'
            : '关于 NEUQ One',
      ),
      content: const Text(
        'NEUQ One 是面向东北大学秦皇岛分校学生的非官方开源校园工作台，学校的正式通知、成绩及业务办理均以官方系统为准。\n\n'
        '如果您在使用过程中遇到问题，或有任何意见与建议，欢迎在 GitHub 提交 Issue，也欢迎通过 Pull Request（PR）参与开发，共同完善 NEUQ One。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: _repositoryUrl.isEmpty
              ? null
              : () => openOfficialPage(context, '$_repositoryUrl/issues'),
          child: const Text('问题反馈'),
        ),
        TextButton(
          onPressed: _repositoryUrl.isEmpty
              ? null
              : () => openOfficialPage(context, '$_repositoryUrl/pulls'),
          child: const Text('参与贡献'),
        ),
      ],
    ),
  );

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
  const _AccountCard({
    required this.status,
    required this.onLogout,
    this.onReconnect,
  });

  final SchoolConnection status;
  final VoidCallback? onLogout;
  final Widget? onReconnect;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF293812);
    return Card(
      color: campusLime,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
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
            title: Text(
              switch (status) {
                SchoolConnection.unavailable => '认证待接入',
                SchoolConnection.disconnected => '未登录',
                _ => '学校身份已验证',
              },
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                switch (status) {
                  SchoolConnection.unavailable ||
                  SchoolConnection.disconnected => '统一身份认证',
                  SchoolConnection.connected => '教务会话正常',
                  SchoolConnection.restoring => '正在自动恢复教务连接',
                  SchoolConnection.expired => '教务会话待恢复，正在使用本地数据',
                  SchoolConnection.offline => '教务连接失败，正在使用本地数据',
                  SchoolConnection.unknown => '教务状态尚未确认',
                },
                style: const TextStyle(color: Color(0xFF466020), fontSize: 12),
              ),
            ),
            trailing: onLogout == null
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
          if (onReconnect case final action?)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
        ],
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
    this.trailingLabel,
  });

  final Widget icon;
  final String title;
  final (Color, Color) accent;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailing;
  final String? loadingLabel;
  final String? trailingLabel;

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
            ? trailingLabel == null
                  ? Icon(trailing, size: 17, color: colors.onSurfaceVariant)
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Text(
                        trailingLabel!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.primary),
                      ),
                    )
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
