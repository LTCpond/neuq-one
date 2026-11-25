import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/official_browser.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../data/employment_feed.dart';

class EmploymentPage extends ConsumerStatefulWidget {
  const EmploymentPage({super.key});

  @override
  ConsumerState<EmploymentPage> createState() => _EmploymentPageState();
}

class _EmploymentPageState extends ConsumerState<EmploymentPage> {
  var _kind = EmploymentKind.talk;
  var _force = false;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(employmentRefreshProvider(_force));
    final cache = ref.watch(employmentCacheProvider);
    final snapshot = current.value ?? cache.value;
    final updated = snapshot?.syncedAt.toUtc().add(campusOffset);
    void refresh() {
      if (_force) {
        ref.invalidate(employmentRefreshProvider(true));
      } else {
        setState(() => _force = true);
      }
    }

    return CampusScreen(
      title: '宣讲会与招聘会',
      eyebrow: '学校就业信息网',
      actions: [
        IconButton(
          onPressed: current.isLoading ? null : refresh,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新就业活动',
        ),
        IconButton(
          onPressed: () => openOfficialPage(context, _kind.uri.toString()),
          icon: const Icon(Icons.open_in_new),
          tooltip: '查看学校完整列表',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          SegmentedButton<EmploymentKind>(
            segments: [
              for (final kind in EmploymentKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.single),
          ),
          const SizedBox(height: 12),
          if (updated != null)
            Text(
              '${current.hasError ? '刷新失败 · ' : ''}'
              '更新于 ${shortDate(updated)} ${clockLabel(updated.hour * 60 + updated.minute)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (current.isLoading && snapshot != null)
            const LinearProgressIndicator(),
          const SizedBox(height: 8),
          DataPanel(
            value: snapshot == null ? current : AsyncData(snapshot),
            retry: refresh,
            builder: (snapshot) => Column(
              children: [
                for (final event in snapshot.events.where(
                  (event) => event.kind == _kind,
                ))
                  Card(
                    child: ListTile(
                      title: Text(event.title),
                      subtitle: Text(
                        [
                          event.when,
                          if (event.where.isNotEmpty) event.where,
                        ].join('\n'),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () =>
                          openOfficialPage(context, event.url.toString()),
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
