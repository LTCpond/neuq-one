import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/campus_map.dart';

class CampusMapPage extends ConsumerStatefulWidget {
  const CampusMapPage({super.key});

  @override
  ConsumerState<CampusMapPage> createState() => _CampusMapPageState();
}

class _CampusMapPageState extends ConsumerState<CampusMapPage> {
  static const _fullscreenChannel = MethodChannel(
    'org.neuqone.neuq_one/campus_map',
  );
  bool _fullscreen = false;

  void _setFullscreen(bool fullscreen) {
    setState(() => _fullscreen = fullscreen);
    unawaited(_setSystemBars(fullscreen));
  }

  Future<void> _setSystemBars(bool fullscreen) async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _fullscreenChannel.invokeMethod<void>(
            'setFullscreen',
            fullscreen,
          );
        case TargetPlatform.iOS:
          await SystemChrome.setEnabledSystemUIMode(
            fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          );
        default:
          break;
      }
    } on MissingPluginException {
      // The map can still fill the app window without a platform handler.
    } on PlatformException {
      // Keep the app-level fullscreen controls available if the platform fails.
    }
  }

  @override
  void dispose() {
    if (_fullscreen) unawaited(_setSystemBars(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = ref.watch(campusMapProvider);
    return PopScope<void>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _setFullscreen(false);
      },
      child: Scaffold(
        appBar: _fullscreen
            ? null
            : AppBar(
                title: const Text('校园地图'),
                actions: [
                  IconButton(
                    tooltip: '全屏查看',
                    onPressed: map.hasValue ? () => _setFullscreen(true) : null,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ],
              ),
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              map.when(
                skipLoadingOnRefresh: false,
                data: (data) => LayoutBuilder(
                  builder: (context, constraints) => _MapViewport(
                    key: ValueKey(constraints.biggest),
                    size: constraints.biggest,
                    map: data,
                  ),
                ),
                loading: () => const Center(
                  child: CircularProgressIndicator(semanticsLabel: '正在加载校园地图'),
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('校园地图加载失败'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(campusMapProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_fullscreen)
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filledTonal(
                    tooltip: '退出全屏',
                    onPressed: () => _setFullscreen(false),
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapViewport extends StatefulWidget {
  const _MapViewport({super.key, required this.size, required this.map});

  final Size size;
  final CampusMap map;

  @override
  State<_MapViewport> createState() => _MapViewportState();
}

class _MapViewportState extends State<_MapViewport> {
  static const _maxScale = 16.0;
  final _transform = TransformationController();
  Offset? _doubleTapPosition;

  void _zoom(double factor, Offset anchor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, _maxScale);
    if (scale == current) return;
    final translation = anchor - _transform.toScene(anchor) * scale;
    final size = widget.size;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        translation.dx.clamp(size.width * (1 - scale), 0.0),
        translation.dy.clamp(size.height * (1 - scale), 0.0),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.size.center(Offset.zero);
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: () => _zoom(2, _doubleTapPosition ?? center),
          child: InteractiveViewer(
            transformationController: _transform,
            maxScale: _maxScale,
            child: SizedBox.expand(
              child: Image.memory(
                widget.map.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                semanticLabel: '校园地图',
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: _transform,
              builder: (context, matrix, _) {
                final scale = matrix.getMaxScaleOnAxis();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '放大地图',
                      color: colors.primary,
                      onPressed: scale < _maxScale
                          ? () => _zoom(1.5, center)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                    IconButton(
                      tooltip: '缩小地图',
                      color: colors.primary,
                      onPressed: scale > 1
                          ? () => _zoom(1 / 1.5, center)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    IconButton(
                      tooltip: '恢复初始视角',
                      color: colors.primary,
                      onPressed: matrix.isIdentity()
                          ? null
                          : () => _transform.value = Matrix4.identity(),
                      icon: const Icon(Icons.fit_screen_rounded),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
