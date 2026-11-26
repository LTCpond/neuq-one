import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/official_browser.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
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
    final visible = TickerMode.valuesOf(context).enabled;
    final AsyncValue<EmploymentSnapshot?> current = visible
        ? ref.watch(employmentRefreshProvider(_force))
        : const AsyncData<EmploymentSnapshot?>(null);
    final cache = visible
        ? ref.watch(employmentCacheProvider)
        : const AsyncData<EmploymentSnapshot?>(null);
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
        CampusRefreshButton(
          tooltip: '刷新就业活动',
          isLoading: current.isLoading,
          onPressed: refresh,
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
          DataPanel<EmploymentSnapshot?>(
            value: snapshot == null ? current : AsyncData(snapshot),
            retry: refresh,
            builder: (snapshot) {
              final events = (snapshot?.events ?? const <EmploymentEvent>[])
                  .where((event) => event.kind == _kind);
              if (events.isEmpty) {
                return StatePanel(
                  '暂无${_kind.label}',
                  '可打开学校就业信息网查看完整列表。',
                  icon: Icons.event_outlined,
                );
              }
              return Column(
                children: [
                  for (final event in events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EmploymentEventCard(event: event),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmploymentEventCard extends StatelessWidget {
  const _EmploymentEventCard({required this.event});

  final EmploymentEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget detail(IconData icon, String label) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 16, color: colors.primary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openOfficialPage(context, event.url.toString()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.open_in_new, size: 18, color: colors.primary),
                ],
              ),
              const SizedBox(height: 10),
              detail(Icons.schedule_outlined, event.when),
              if (event.where.isNotEmpty) ...[
                const SizedBox(height: 6),
                detail(Icons.location_on_outlined, event.where),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
