import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../../services/data/campus_card_balance.dart';
import '../../services/domain/services.dart';
import '../../services/presentation/open_campus_service.dart';
import '../../profile/data/course_reminders.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';
import '../../timetable/presentation/timetable_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  var _now = campusNow();
  late final Timer _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateClock());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _updateClock();
        ref.invalidate(reminderSyncProvider);
        ref.invalidate(schoolRefreshProvider(SchoolDataSet.timetable));
      },
    );
  }

  void _updateClock() => setState(() => _now = campusNow());

  @override
  void dispose() {
    _timer.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh({required bool refreshCampusCard}) async {
    _updateClock();
    try {
      await Future.wait([
        ref.refresh(timetableProvider.future),
        ref.refresh(settingsProvider.future),
        if (refreshCampusCard) ref.refresh(campusCardRefreshProvider.future),
      ]);
    } catch (_) {
      if (mounted) showMessage(context, '部分本地数据暂时无法读取，可下拉重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = ref.watch(visibleTimetableProvider);
    final settings = ref.watch(settingsProvider);
    final preferences = settings.value;
    final shortcuts = preferences == null
        ? const <CampusService>[]
        : shortcutsInOrder(
            preferences.quickLinks,
            customized: preferences.quickLinksCustomized,
          );
    final showCampusCard = shortcuts.contains(campusCardService);
    if (showCampusCard) ref.watch(campusCardRefreshProvider);
    final balance = showCampusCard
        ? ref.watch(campusCardBalanceProvider).value
        : null;
    final semester = currentSemester(
      timetable.value?.semesters ?? const [],
      _now,
    );
    final week = semester?.weekFor(_now);
    final teachingWeek = week == null ? '非教学周' : '第 $week 教学周';
    final theme = Theme.of(context);
    return CampusScreen(
      title: 'NEUQ One',
      body: RefreshIndicator(
        onRefresh: () => _refresh(refreshCampusCard: showCampusCard),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(
                '${shortDate(_now)} · ${weekdayLabel(_now.weekday)}'
                '${timetable.hasValue ? ' · $teachingWeek' : ''}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            DataPanel(
              value: timetable,
              retry: () => ref.invalidate(timetableProvider),
              builder: (data) {
                final courses = semester == null || week == null
                    ? <Course>[]
                    : data.on(semester, week, _now.weekday);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle(
                      '今日课程',
                      action: TextButton(
                        onPressed: () => context.go('/timetable'),
                        child: const Text('查看课表'),
                      ),
                    ),
                    if (courses.isEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_available_outlined),
                          title: Text(semester == null ? '还没有学期' : '今天没有课程'),
                          subtitle: Text(
                            semester == null ? '创建学期后即可添加课程' : '课表可随时离线查看',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/timetable'),
                        ),
                      ),
                    for (final item in courses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: CourseTile(
                          course: item,
                          onTap: () => showCourseDetails(
                            context,
                            ref.read(timetableRepositoryProvider),
                            semester!,
                            item,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            SectionTitle(
              '快捷入口',
              action: TextButton(
                onPressed: settings.hasValue
                    ? () => _configureShortcuts(shortcuts)
                    : null,
                child: const Text('调整快捷入口'),
              ),
            ),
            if (settings.isLoading && preferences == null)
              const LinearProgressIndicator()
            else if (preferences != null && shortcuts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('还没有快捷入口'),
              )
            else if (shortcuts.isNotEmpty)
              _ShortcutGrid(services: shortcuts, balance: balance),
            if (settings.hasError)
              TextButton(
                onPressed: () => ref.invalidate(settingsProvider),
                child: const Text('重新读取快捷入口'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _configureShortcuts(List<CampusService> shortcuts) async {
    final selected = shortcuts.map((service) => service.id).toSet();
    final items = [
      ...shortcuts,
      ...campusServices.values.where(
        (service) => !selected.contains(service.id),
      ),
    ];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('调整快捷入口'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (from, to) =>
                  setDialogState(() => items.insert(to, items.removeAt(from))),
              itemBuilder: (context, index) {
                final service = items[index];
                void toggle() {
                  setDialogState(() {
                    if (!selected.add(service.id)) selected.remove(service.id);
                  });
                }

                return ListTile(
                  key: ValueKey(service.id),
                  leading: Checkbox(
                    value: selected.contains(service.id),
                    onChanged: (_) => toggle(),
                  ),
                  title: Row(
                    children: [
                      Icon(service.icon, size: 20),
                      const SizedBox(width: 8),
                      Flexible(child: Text(service.name)),
                    ],
                  ),
                  onTap: toggle,
                  contentPadding: EdgeInsets.zero,
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, semanticLabel: '拖动排序'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (final item in items)
                  if (selected.contains(item.id)) item.id,
              ]),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(settingsProvider.notifier).setQuickLinks(result);
    } catch (_) {
      if (mounted) showMessage(context, '快捷入口保存失败，请重试');
    }
  }
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({required this.services, required this.balance});

  final List<CampusService> services;
  final CampusCardBalance? balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 300 ? 3 : 4;
            final cellWidth = constraints.maxWidth / columns;
            return Wrap(
              runSpacing: 4,
              children: [
                for (final service in services)
                  SizedBox(
                    width: cellWidth,
                    child: InkWell(
                      key: ValueKey('home-shortcut-${service.id}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => openCampusService(context, service),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onSecondaryContainer,
                              child: Icon(service.icon),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              service == campusCardService
                                  ? '校园卡余额'
                                  : service.name,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelMedium,
                            ),
                            if (service == campusCardService && balance != null)
                              Text(
                                campusCardMoney(balance!.cents),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelMedium,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
