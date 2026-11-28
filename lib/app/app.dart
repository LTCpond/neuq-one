import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import '../core/diagnostics/diagnostics.dart';
import '../core/network/campus_access/campus_access_providers.dart';
import '../core/network/campus_access/webvpn_session_manager.dart';
import '../core/storage/settings.dart';
import '../core/theme/app_theme.dart';
import '../features/desktop_widgets/data/desktop_widget_bridge.dart';
import '../features/profile/data/course_reminders.dart';
import '../features/profile/data/app_updates.dart';
import 'router.dart';

class NeuqOneApp extends ConsumerStatefulWidget {
  const NeuqOneApp({super.key});

  @override
  ConsumerState<NeuqOneApp> createState() => _NeuqOneAppState();
}

class _NeuqOneAppState extends ConsumerState<NeuqOneApp> {
  bool _restoringSession = true;
  bool _updateStarted = false;
  static const _schoolResumeInterval = Duration(minutes: 5);
  DateTime? _backgroundedAt;
  late final AppLifecycleListener _lifecycle;
  late final WebVpnSessionManager _webVpn;
  int _widgetRequest = 0;

  @override
  void initState() {
    super.initState();
    if (supportsDesktopWidgets) {
      desktopWidgetChannel.setMethodCallHandler(_onWidgetMessage);
    }
    _webVpn = ref.read(webVpnSessionManagerProvider);
    final state = WidgetsBinding.instance.lifecycleState;
    _setCampusForeground(state == null || state == AppLifecycleState.resumed);
    _lifecycle = AppLifecycleListener(
      onHide: _recordBackgroundTime,
      onPause: _recordBackgroundTime,
      onResume: () {
        _setCampusForeground(true);
        final session = ref.read(schoolSessionProvider).asData?.value;
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (session != null) _resumeSchool(session, backgroundedAt).ignore();
        final reminders = ref.read(reminderSyncProvider).asData?.value;
        if (session != null || reminders?.condition != ReminderCondition.off) {
          ref.invalidate(reminderSyncProvider);
        }
        _startUpdateCheck();
      },
    );
  }

  Future<void> _onWidgetMessage(MethodCall call) async {
    if (call.method != 'navigationAvailable' || !mounted) return;
    final subject = ref.read(schoolSessionProvider).asData?.value?.subject;
    if (subject == null) return;
    try {
      final target = await desktopWidgetChannel
          .invokeMapMethod<Object?, Object?>('takeNavigation');
      if (!mounted ||
          target == null ||
          ref.read(schoolSessionProvider).asData?.value?.subject != subject ||
          ref.read(schoolNetworkBoundaryProvider).signingOut) {
        return;
      }
      final location = desktopWidgetLocation(target, ++_widgetRequest);
      if (location != null) ref.read(routerProvider).go(location.toString());
    } on PlatformException {
      // The regular app route remains available if the widget state expired.
    }
  }

  void _recordBackgroundTime() {
    _setCampusForeground(false);
    _backgroundedAt ??= ref.read(schoolSessionClockProvider)();
  }

  void _setCampusForeground(bool foreground) {
    _webVpn.setForeground(foreground);
    ref.read(campusAccessClientProvider).setForeground(foreground);
  }

  bool get _isForeground =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _resumeSchool(
    SchoolSession session,
    DateTime? backgroundedAt,
  ) async {
    final status = ref.read(schoolSessionStatusProvider);
    final now = ref.read(schoolSessionClockProvider)();
    if (status.subject == session.subject &&
        status.health == SchoolSessionHealth.connected &&
        (backgroundedAt == null ||
            now.difference(backgroundedAt) < _schoolResumeInterval)) {
      ref.invalidate(schoolRefreshProvider(SchoolDataSet.timetable));
      return;
    }
    if (status.subject == session.subject &&
        status.health == SchoolSessionHealth.restoring) {
      return;
    }
    try {
      final recovered = await ref
          .read(schoolSessionProvider.notifier)
          .recoverSession(
            trigger: SchoolRecoveryTrigger.foreground,
            isForeground: () => _isForeground,
          );
      if (recovered && _isForeground) ref.read(refreshSchoolDataProvider)();
    } on SchoolRequestFailure {
      // The client publishes connection status and retry eligibility.
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        DiagnosticStage.foregroundRecovery,
        error: error,
      );
    }
  }

  void _startUpdateCheck() {
    if (!mounted ||
        _restoringSession ||
        _updateStarted ||
        kIsWeb ||
        ref.read(androidDebugBuildProvider) ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _updateStarted = true;
    try {
      // The shared service records asynchronous failures.
      ref.read(appUpdateCoordinatorProvider).checkAtStartup().ignore();
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.updates,
        DiagnosticStage.initialize,
        error: error,
      );
    }
  }

  @override
  void dispose() {
    if (supportsDesktopWidgets) desktopWidgetChannel.setMethodCallHandler(null);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(desktopWidgetSyncProvider);
    if (_restoringSession) {
      _restoringSession = ref.watch(
        schoolSessionProvider.select((session) => session.isLoading),
      );
    }
    final settings = ref.watch(settingsProvider).value;
    final developmentBuild = ref.watch(androidDebugBuildProvider);
    if (!developmentBuild && !_restoringSession && !_updateStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startUpdateCheck());
    }
    ref.listen(reminderSyncProvider, (_, _) {});
    return MaterialApp.router(
      title: developmentBuild ? 'NEUQ One Dev' : 'NEUQ One',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: settings?.theme ?? ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      builder: _restoringSession
          ? (context, child) => const Scaffold(
              body: Center(
                child: CircularProgressIndicator(semanticsLabel: '正在恢复登录状态'),
              ),
            )
          : null,
    );
  }
}
