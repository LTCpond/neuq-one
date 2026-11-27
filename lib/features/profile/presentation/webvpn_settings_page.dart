import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/campus_access/campus_access_providers.dart';
import '../../../core/network/campus_access/campus_resource.dart';
import '../../../core/network/campus_access/webvpn_session_manager.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../../services/presentation/open_campus_service.dart';

class WebVpnSettingsPage extends ConsumerStatefulWidget {
  const WebVpnSettingsPage({super.key});

  @override
  ConsumerState<WebVpnSettingsPage> createState() => _WebVpnSettingsPageState();
}

class _WebVpnSettingsPageState extends ConsumerState<WebVpnSettingsPage> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() write) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await write();
    } catch (_) {
      if (mounted) showMessage(context, '无法保存 WebVPN 设置，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(campusAccessSettingsProvider);
    final manager = ref.watch(webVpnSessionManagerProvider);
    final vpn = ref.watch(webVpnStateProvider);
    final canDisconnect = const {
      WebVpnPhase.connecting,
      WebVpnPhase.connected,
      WebVpnPhase.idle,
    }.contains(vpn.phase);
    final pendingRelease = vpn.idleUntil?.toUtc().add(campusOffset);
    final idleLabel = pendingRelease == null
        ? null
        : clockLabel(pendingRelease.hour * 60 + pendingRelease.minute);
    return CampusScreen(
      title: 'WebVPN',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_lock_outlined),
                  title: Text(vpn.phase.label),
                  subtitle: Text(
                    vpn.failure?.message ??
                        (idleLabel != null
                            ? '预计 $idleLabel 空闲断开（北京时间）'
                            : manager.protocolAvailable
                            ? '访问获授权资源时按需连接'
                            : '应用内访问待学校协议确认，可使用官方门户。'),
                  ),
                ),
                if (vpn.phase == WebVpnPhase.connecting ||
                    vpn.phase == WebVpnPhase.disconnecting)
                  const LinearProgressIndicator(),
                ListTile(
                  title: const Text('断开应用内 WebVPN'),
                  onTap: canDisconnect ? manager.disconnect : null,
                  enabled: canDisconnect,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DataPanel(
            value: settings,
            retry: () => ref.invalidate(campusAccessSettingsProvider),
            builder: (value) {
              final controller = ref.read(
                campusAccessSettingsProvider.notifier,
              );
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('访问策略'),
                      subtitle: const Text('优先 WebVPN 仅适用于已授权且完成适配的资源。'),
                      trailing: DropdownButton<CampusAccessPreference>(
                        value: value.preference,
                        onChanged: _saving
                            ? null
                            : (choice) {
                                if (choice != null) {
                                  _save(() => controller.setPreference(choice));
                                }
                              },
                        items: [
                          for (final choice in CampusAccessPreference.values)
                            DropdownMenuItem(
                              value: choice,
                              child: Text(choice.label),
                            ),
                        ],
                      ),
                    ),
                    ListTile(
                      title: const Text('空闲断开时间'),
                      trailing: DropdownButton<int>(
                        value: value.idleMinutes,
                        onChanged: _saving
                            ? null
                            : (minutes) {
                                if (minutes != null) {
                                  _save(
                                    () => controller.setIdleMinutes(minutes),
                                  );
                                }
                              },
                        items: [
                          for (final minutes in CampusAccessLimits.idleChoices)
                            DropdownMenuItem(
                              value: minutes,
                              child: Text(
                                minutes == 0 ? '立即释放' : '$minutes 分钟',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('打开官方门户'),
                  subtitle: const Text('使用系统浏览器登录和验证。'),
                  onTap: () => openOfficialPage(context, officialWebVpnUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('学校使用说明'),
                  onTap: () => openRegisteredCampusWebsite(
                    context,
                    ref,
                    CampusResourceId.webVpnGuide,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
