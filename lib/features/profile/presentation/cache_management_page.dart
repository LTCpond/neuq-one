import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/screen.dart';
import '../data/cache_management.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  Map<CacheCategory, int?>? _sizes;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _refresh(ref.read(cacheManagerProvider));
  }

  Future<void> _refresh(CacheManager manager) async {
    final sizes = await manager.sizes();
    if (mounted) {
      setState(() {
        _sizes = sizes;
        _busy = false;
      });
    }
  }

  Future<void> _clear([CacheCategory? category]) async {
    if (_busy) return;
    final manager = ref.read(cacheManagerProvider);
    setState(() => _busy = true);
    final failed = await manager.clear(category);
    await _refresh(manager);
    if (!mounted) return;
    showMessage(
      context,
      failed.isEmpty
          ? '缓存已清除'
          : '清理未完成，请重试：${failed.map((item) => item.label).join('、')}',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('缓存管理')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(semanticsLabel: '正在处理缓存'),
        for (final entry
            in _sizes?.entries ?? const <MapEntry<CacheCategory, int?>>[])
          Card(
            child: ListTile(
              title: Text(entry.key.label),
              subtitle: Text(_sizeLabel(entry.value)),
              trailing: TextButton(
                onPressed: _busy ? null : () => _clear(entry.key),
                child: const Text('清理'),
              ),
            ),
          ),
        if (_sizes != null) ...[
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : () => _clear(),
            child: const Text('清理全部缓存'),
          ),
        ],
      ],
    ),
  );
}

String _sizeLabel(int? bytes) {
  if (bytes == null) return '暂时无法读取大小';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
