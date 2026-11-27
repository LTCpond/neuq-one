import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/widgets/screen.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  String _line(DiagnosticEntry entry) => [
    entry.time.toIso8601String(),
    entry.level.name.toUpperCase(),
    '${entry.module.name}.${entry.stage.name}.${entry.code.name}',
    ?entry.endpoint?.name,
    ?entry.resource?.name,
    ?entry.route?.name,
    if (entry.elapsedMs case final ms?) '${ms}ms',
    if (entry.httpStatus case final status?) 'HTTP $status',
    ?entry.exceptionType,
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    final entries = diagnostics.entries.reversed.map(_line).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('诊断信息')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('最多保留本次运行的 150 条诊断记录，包括操作、错误分类、公共数据源和请求耗时。'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: entries.join('\n')),
                        );
                        if (context.mounted) showMessage(context, '已复制诊断信息');
                      },
                child: const Text('复制诊断信息'),
              ),
              TextButton(
                onPressed: entries.isEmpty
                    ? null
                    : () => setState(diagnostics.clear),
                child: const Text('清除记录'),
              ),
            ],
          ),
          if (entries.isEmpty) const Text('暂无诊断记录'),
          for (final entry in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(entry),
              ),
            ),
        ],
      ),
    );
  }
}
