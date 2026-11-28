import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/widgets/screen.dart';
import '../data/app_updates.dart';

/// Watches a single Navigator, including imperatively opened routes.
class AppUpdateRouteObserver extends NavigatorObserver with ChangeNotifier {
  Route<dynamic>? _top;
  int _closing = 0;
  bool _disposed = false;

  bool get idle =>
      !_disposed &&
      _closing == 0 &&
      _top is PageRoute &&
      _top!.isCurrent &&
      (_top as PageRoute).animation?.isCompleted == true;
  bool get onFirstPage => idle && _top!.isFirst;
  bool isTop(Route<dynamic>? route) => idle && identical(_top, route);

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    if (_disposed || topRoute.navigator != navigator) return;
    final previous = _top;
    if (previous is TransitionRoute) {
      previous.animation?.removeStatusListener(_changed);
    }
    _top = topRoute;
    if (topRoute is TransitionRoute) {
      topRoute.animation?.addStatusListener(_changed);
    }
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_disposed ||
        route is! TransitionRoute ||
        previousRoute?.navigator != navigator) {
      return;
    }
    _closing++;
    unawaited(
      route.completed.then((_) {
        if (_disposed) return;
        _closing--;
        notifyListeners();
      }),
    );
  }

  void _changed(AnimationStatus _) {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final route = _top;
    if (route is TransitionRoute) {
      route.animation?.removeStatusListener(_changed);
    }
    super.dispose();
  }
}

bool _foreground() {
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  return lifecycle == null || lifecycle == AppLifecycleState.resumed;
}

/// Exists only in the authenticated shell. Offers remain available in the
/// profile while the user is signing in, backgrounded or on a modal route.
class AppUpdatePromptHost extends ConsumerStatefulWidget {
  const AppUpdatePromptHost({
    super.key,
    required this.root,
    required this.branch,
    required this.child,
  });

  final AppUpdateRouteObserver root;
  final AppUpdateRouteObserver branch;
  final Widget child;

  @override
  ConsumerState<AppUpdatePromptHost> createState() =>
      _AppUpdatePromptHostState();
}

class _AppUpdatePromptHostState extends ConsumerState<AppUpdatePromptHost> {
  late final AppLifecycleListener _lifecycle;
  bool _queued = false;
  Route<dynamic>? _hostRoute;

  @override
  void initState() {
    super.initState();
    widget.root.addListener(_queue);
    widget.branch.addListener(_queue);
    _lifecycle = AppLifecycleListener(onResume: _queue);
  }

  @override
  void didUpdateWidget(AppUpdatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.root, widget.root)) {
      oldWidget.root.removeListener(_queue);
      widget.root.addListener(_queue);
    }
    if (!identical(oldWidget.branch, widget.branch)) {
      oldWidget.branch.removeListener(_queue);
      widget.branch.addListener(_queue);
    }
    _queue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hostRoute = ModalRoute.of(context);
    _queue();
  }

  bool _canShow() =>
      mounted &&
      _foreground() &&
      widget.root.isTop(_hostRoute) &&
      widget.branch.onFirstPage;

  bool _canShowFrom(BuildContext caller) =>
      _canShow() && Navigator.maybeOf(caller) == widget.branch.navigator;

  void _queue() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      unawaited(_present());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _present() async {
    try {
      final coordinator = ref.read(appUpdateCoordinatorProvider);
      await coordinator.presentAutomatically(
        canShow: _canShow,
        show: (offer, shown) => _showUpdate(context, offer, shown),
      );
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.updates,
        DiagnosticStage.show,
        error: error,
      );
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.root.removeListener(_queue);
    widget.branch.removeListener(_queue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(availableAppUpdateProvider, (_, _) => _queue());
    return _UpdatePromptScope(canShow: _canShowFrom, child: widget.child);
  }
}

class _UpdatePromptScope extends InheritedWidget {
  const _UpdatePromptScope({required this.canShow, required super.child});

  final bool Function(BuildContext) canShow;

  @override
  bool updateShouldNotify(_UpdatePromptScope oldWidget) => false;
}

bool _canPresentFrom(BuildContext context) =>
    context.mounted &&
    _foreground() &&
    ModalRoute.isCurrentOf(context) != false &&
    (context.getInheritedWidgetOfExactType<_UpdatePromptScope>()?.canShow(
          context,
        ) ??
        true);

Future<void> checkAndPresentAppUpdate(
  BuildContext context,
  AppUpdateCoordinator coordinator, {
  VoidCallback? onChecked,
}) async {
  if (!coordinator.beginPresentation()) return;
  try {
    final result = await coordinator.check(automatic: false);
    onChecked?.call();
    if (!context.mounted || !_canPresentFrom(context)) return;
    switch (result) {
      case null:
        return;
      case NoPublishedAppRelease():
        showMessage(context, '暂无可用更新');
      case AppUpToDate():
        showMessage(context, '当前已是最新版本');
      case PublishedAppVersion(:final version, :final prerelease):
        showMessage(
          context,
          '发布渠道最新版本 v$version${prerelease ? '（公测版）' : ''}。开发版需重新构建。',
        );
      case AppUpdateAvailable():
        Future<void>? persisted;
        try {
          await _showUpdate(context, result, () {
            persisted = coordinator.noteManualPresentation(
              result.latestVersion,
            );
          });
        } finally {
          await persisted;
        }
    }
  } catch (error) {
    if (context.mounted && _canPresentFrom(context)) {
      showMessage(context, '检查更新失败，请稍后重试');
    }
  } finally {
    coordinator.endPresentation();
  }
}

Future<void> _showUpdate(
  BuildContext context,
  AppUpdateAvailable offer,
  VoidCallback onShown,
) async {
  final dialog = showDialog<String>(
    context: context,
    builder: (context) => _AppUpdateDialog(offer),
  );
  onShown();
  final url = await dialog;
  if (url != null && context.mounted) {
    await openOfficialPage(context, url);
  }
}

class _AppUpdateDialog extends StatelessWidget {
  const _AppUpdateDialog(this.offer);

  final AppUpdateAvailable offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final download = offer.download;
    final title =
        'NEUQ One v${offer.latestVersion}${offer.prerelease ? ' 公测版' : ''}';
    return AlertDialog(
      scrollable: true,
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('当前版本：v${offer.currentVersion}'),
          Text('最新版本：v${offer.latestVersion}'),
          if (offer.changelog.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('本次更新', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final entry in offer.changelog)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', semanticsLabel: ''),
                    Expanded(child: Text(entry)),
                  ],
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后更新'),
        ),
        if (download != null)
          TextButton(
            onPressed: () => Navigator.pop(context, download.fallbackUrl),
            child: const Text('GitHub 备用下载'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, download?.url ?? offer.url),
          child: Text(download == null ? '前往下载' : '立即更新'),
        ),
      ],
    );
  }
}
