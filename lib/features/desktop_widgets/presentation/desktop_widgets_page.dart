import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/desktop_widget_bridge.dart';

const _layouts = [
  (
    kind: 'today',
    title: '今日课表',
    variants: [
      (label: '2×2', width: 150, height: 152),
      (label: '4×2', width: 304, height: 152),
    ],
  ),
  (
    kind: 'week',
    title: '周课表',
    variants: [
      (label: '4×5', width: 304, height: 380),
      (label: '4×6', width: 304, height: 456),
    ],
  ),
  (
    kind: 'exams',
    title: '考试安排与倒计时',
    variants: [
      (label: '2×1', width: 150, height: 72),
      (label: '2×2', width: 150, height: 152),
      (label: '4×2', width: 304, height: 152),
    ],
  ),
];

class DesktopWidgetsPage extends StatefulWidget {
  const DesktopWidgetsPage({super.key});

  @override
  State<DesktopWidgetsPage> createState() => _DesktopWidgetsPageState();
}

class _DesktopWidgetsPageState extends State<DesktopWidgetsPage> {
  int _revision = 0;
  Brightness? _brightness;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: _reload,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  Future<Uint8List?> _preview(Map<String, Object> arguments) async {
    try {
      return await desktopWidgetChannel
          .invokeMethod<Uint8List>('preview', arguments)
          .timeout(const Duration(seconds: 8));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  void _reload() => setState(() => _revision++);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = MediaQuery.platformBrightnessOf(context);
    if (brightness != _brightness) {
      _brightness = brightness;
      _revision++;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '预览使用已同步的本机数据。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          for (final layout in _layouts) ...[
            const SizedBox(height: 18),
            Text(layout.title, style: theme.textTheme.titleMedium),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final variant in layout.variants)
                  _DesktopPreview(
                    key: ValueKey((layout.kind, variant.label, _revision)),
                    label: variant.label,
                    width: variant.width,
                    height: variant.height,
                    load: () => _preview({
                      'kind': layout.kind,
                      'width': variant.width,
                      'height': variant.height,
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopPreview extends StatefulWidget {
  const _DesktopPreview({
    required super.key,
    required this.label,
    required this.width,
    required this.height,
    required this.load,
  });
  final String label;
  final int width;
  final int height;
  final Future<Uint8List?> Function() load;

  @override
  State<_DesktopPreview> createState() => _DesktopPreviewState();
}

class _DesktopPreviewState extends State<_DesktopPreview> {
  late final _preview = widget.load();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.width.toDouble()),
        child: AspectRatio(
          aspectRatio: widget.width / widget.height,
          child: FutureBuilder(
            future: _preview,
            builder: (context, snapshot) {
              final image = snapshot.data;
              if (image != null) {
                return Image.memory(
                  image,
                  semanticLabel: '${widget.label} 小组件预览',
                  fit: BoxFit.contain,
                );
              }
              return Center(
                child: Text(
                  snapshot.connectionState == ConnectionState.done
                      ? '预览暂不可用'
                      : '正在生成预览…',
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
