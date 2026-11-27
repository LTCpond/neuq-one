import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/network/campus_access/campus_access_client.dart';
import '../../../core/network/campus_access/campus_access_providers.dart';
import '../../../core/network/campus_access/campus_resource.dart';
import '../../../core/network/campus_access/webvpn_session_manager.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/widgets/screen.dart';

final campusVerificationBrowserProvider = Provider((_) => openOfficialPage);
final _campusDialogProvider = Provider((_) => _CampusDialog());

class _CampusDialog {
  bool active = false;

  Future<bool> confirm(BuildContext context, {required bool consent}) async {
    if (active) return false;
    active = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(consent ? '允许按需验证' : '需要学校身份验证'),
              content: Text(
                consent
                    ? '是否允许此设备保存的学校密码也用于学校远程访问服务的按需认证？'
                    : '该资源需要通过学校远程访问服务进行访问，请在系统浏览器中完成学校身份验证并继续访问。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(consent ? '允许' : '前往验证'),
                ),
              ],
            ),
          ) ==
          true;
    } finally {
      active = false;
    }
  }
}

/// A route's read-only content. The caller renders the validated response.
class CampusResourcePanel extends ConsumerStatefulWidget {
  const CampusResourcePanel({
    super.key,
    required this.id,
    required this.builder,
  });

  final CampusResourceId id;
  final Widget Function(CampusAccessResult) builder;

  @override
  ConsumerState<CampusResourcePanel> createState() =>
      _CampusResourcePanelState();
}

class _CampusResourcePanelState extends ConsumerState<CampusResourcePanel> {
  CampusAccessUse? _use;
  CampusAccessResult? _result;
  CampusAccessFailure? _failure;
  bool _visible = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (!_visible && _failure == null && _result == null && _started) {
      _failure = CampusAccessFailure.cancelled;
    }
    if (!_visible) _release();
    if (_visible && !_started) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible && !_started) _read();
      });
    }
  }

  @override
  void didUpdateWidget(CampusResourcePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    _release();
    _result = null;
    _failure = null;
    _started = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible && !_started) _read();
    });
  }

  void _release() {
    _use?.close();
    _use = null;
  }

  Future<void> _read({bool retry = false}) async {
    _release();
    if (_failure case final failure? when retry) {
      ref
          .read(webVpnSessionManagerProvider)
          .allowReconnect(expectedFailure: failure);
    }
    final access = ref.read(campusAccessClientProvider);
    final use = _use = access.openUse();
    setState(() {
      _started = true;
      _result = null;
      _failure = null;
    });
    try {
      final result = await access.read(widget.id, use: use);
      if (!mounted || !identical(_use, use)) return;
      result.ensureCurrent();
      setState(() => _result = result);
    } on CampusAccessFailure catch (failure) {
      if (!mounted || !identical(_use, use)) return;
      _release();
      setState(() => _failure = failure);
      if (_visible && _canVerify(failure, access)) await _verify(failure);
    }
  }

  bool _canVerify(CampusAccessFailure failure, CampusAccessClient access) =>
      (failure.requiresSchoolVerification ||
          failure == CampusAccessFailure.credentialConsentRequired) &&
      access.webVpnBrowserEntry(widget.id) != null;

  Future<void> _verify(CampusAccessFailure failure) async {
    final manager = ref.read(webVpnSessionManagerProvider);
    final identity = manager.identity;
    final subject = manager.subject;
    final id = widget.id;
    final consent = failure == CampusAccessFailure.credentialConsentRequired;
    if (!await ref
            .read(_campusDialogProvider)
            .confirm(context, consent: consent) ||
        !mounted ||
        widget.id != id ||
        !identical(manager.identity, identity)) {
      return;
    }
    if (!consent) {
      await _openBrowser();
      return;
    }
    try {
      if (subject != null &&
          await ref
              .read(schoolSessionProvider.notifier)
              .allowRememberedPasswordForWebVpn(subject)) {
        if (mounted && identical(manager.identity, identity)) {
          await _read(retry: true);
        }
        return;
      }
    } catch (_) {
      if (mounted) showMessage(context, '无法保存授权，请稍后重试。');
      return;
    }
    if (mounted && identical(manager.identity, identity)) {
      setState(() => _failure = CampusAccessFailure.credentialsRequired);
    }
  }

  Future<void> _openBrowser() async {
    final entry = ref
        .read(campusAccessClientProvider)
        .webVpnBrowserEntry(widget.id);
    if (entry != null) {
      await ref.read(campusVerificationBrowserProvider)(
        context,
        entry.toString(),
      );
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void clearIdentity() {
      if (!_started) return;
      _release();
      setState(() {
        _result = null;
        _failure = CampusAccessFailure.cancelled;
      });
    }

    ref.listen(
      schoolNetworkBoundaryProvider.select((value) => value.signingOut),
      (_, signingOut) {
        if (signingOut) clearIdentity();
      },
    );
    ref.listen(
      schoolSessionProvider.select((value) => value.asData?.value?.subject),
      (before, after) {
        if (before != after) clearIdentity();
      },
    );
    if (_result case final result?) return widget.builder(result);
    if (_failure case final failure?) {
      final access = ref.read(campusAccessClientProvider);
      return StatePanel(
        '暂时无法访问校园资源',
        failure.message,
        icon: Icons.error_outline,
        action: Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _read(retry: true),
              child: Text(
                failure == CampusAccessFailure.vpnDisplaced ? '重新连接' : '重试',
              ),
            ),
            if (_canVerify(failure, access))
              TextButton(
                onPressed: () => _verify(failure),
                child: Text(
                  failure == CampusAccessFailure.credentialConsentRequired
                      ? '确认授权'
                      : '前往验证',
                ),
              )
            else if (failure == CampusAccessFailure.unsupported &&
                access.webVpnBrowserEntry(widget.id) != null)
              TextButton(onPressed: _openBrowser, child: const Text('在浏览器中继续')),
          ],
        ),
      );
    }
    final connecting = ref.watch(
      webVpnStateProvider.select(
        (state) => state.phase == WebVpnPhase.connecting,
      ),
    );
    return Center(child: Text(connecting ? '正在连接学校服务…' : '正在加载校园资源…'));
  }
}
