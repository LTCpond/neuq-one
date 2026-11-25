import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../../core/widgets/screen.dart';
import '../data/public_classrooms.dart';
import '../domain/classrooms.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});

  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
  var _building = CampusBuilding.engineering;
  DateTime? _selectedDate;
  late DateTime _today;
  late final AppLifecycleListener _lifecycle;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _today = campusDateAt(ref.read(classroomsClockProvider)());
    _lifecycle = AppLifecycleListener(
      onResume: () => _updateClock(resumed: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh({bool force = false}) {
    unawaited(ref.read(classroomsProvider.notifier).refresh(force: force));
  }

  void _updateClock({bool resumed = false}) {
    final today = campusDateAt(ref.read(classroomsClockProvider)());
    final dayChanged = today != _today;
    setState(() {
      _today = today;
      if (_selectedDate?.isBefore(today) ?? false) _selectedDate = null;
    });
    if (dayChanged || resumed) _refresh();
  }

  void _watchClock(DateTime now, Map<int, ClassroomSlot>? slots) {
    var next = _today.add(const Duration(days: 1)).subtract(campusOffset);
    if (slots != null) {
      for (final slot in slots.values) {
        if (slot.isFreshAt(now) && slot.expiresAt!.isBefore(next)) {
          next = slot.expiresAt!;
        }
      }
    }
    _clockTimer?.cancel();
    _clockTimer = Timer(next.difference(now), _updateClock);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(classroomsProvider);
    final now = ref.watch(classroomsClockProvider)().toUtc();
    final dates = List.generate(
      7,
      (index) => _today.add(Duration(days: index)),
    );
    final selected = dates.contains(_selectedDate) ? _selectedDate! : _today;
    final day = state.snapshot?.days[selected];
    final slots = day?.buildings[_building];
    _watchClock(now, slots);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final blue = colors.brightness == Brightness.dark
        ? const Color(0xFFA9CBFF)
        : const Color(0xFF1454A1);
    final updated = day?.updatedAt;
    void refresh() => _refresh(force: true);

    return CampusScreen(
      title: '空教室',
      eyebrow: '${shortDate(selected)} · ${weekdayLabel(selected.weekday)}',
      actions: [
        IconButton(
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: '刷新空教室',
          onPressed: state.isLoading ? null : refresh,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          DropdownButton<DateTime>(
            value: selected,
            isExpanded: true,
            items: [
              for (final date in dates)
                DropdownMenuItem(
                  value: date,
                  child: Text(
                    date == _today
                        ? '今天 · ${shortDate(date)}'
                        : '${shortDate(date)} · ${weekdayLabel(date.weekday)}',
                  ),
                ),
            ],
            onChanged: (date) =>
                setState(() => _selectedDate = date == _today ? null : date),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final building in CampusBuilding.values)
                ChoiceChip(
                  label: Text(building.label),
                  selected: building == _building,
                  onSelected: (_) => setState(() => _building = building),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (updated != null)
            Text(
              '数据更新于 ${_collectionTime(updated)}',
              style: theme.textTheme.bodySmall,
            ),
          if (state.isLoading)
            Text('正在更新空教室数据', style: theme.textTheme.bodySmall),
          if (state.refreshFailed && slots != null)
            Text('更新失败，正在显示上次数据', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text('蓝色 · 全天空闲', style: TextStyle(color: blue)),
              Text('红色 · 下节有课', style: TextStyle(color: colors.error)),
            ],
          ),
          const SizedBox(height: 12),
          if (slots != null)
            ..._scheduleGroups(context, slots, now, blue)
          else if (state.isLoading)
            DataPanel<void>(
              value: const AsyncLoading(),
              retry: refresh,
              builder: (_) => const SizedBox.shrink(),
            )
          else
            StatePanel(
              '空教室数据暂不可用',
              '所选日期和楼栋暂无可用数据，请稍后重试。',
              icon: Icons.meeting_room_outlined,
              action: OutlinedButton(
                onPressed: refresh,
                child: const Text('重试'),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '数据由 NEUQ One Data 提供，来源于学校教务系统，仅供参考，实际教室安排以学校通知为准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _scheduleGroups(
    BuildContext context,
    Map<int, ClassroomSlot> slots,
    DateTime now,
    Color blue,
  ) {
    final schedule = classroomScheduleAt(slots, now);
    final allDay = schedule.allDay.toList()..sort();
    return [
      _roomGroup(
        context,
        title: '全天空闲',
        rooms: [
          for (final name in allDay)
            (name: name, availability: ClassroomAvailability.allDay),
        ],
        blue: blue,
        empty: schedule.complete ? '所选日期暂无全天空闲教室' : '部分时段缺少有效数据，暂无法确认全天空闲',
      ),
      for (final start in schedule.groupStarts) ...[
        const SizedBox(height: 8),
        _periodGroup(context, schedule, slots[start]!, start, now, blue),
      ],
    ];
  }

  Widget _periodGroup(
    BuildContext context,
    ClassroomSchedule schedule,
    ClassroomSlot slot,
    int start,
    DateTime now,
    Color blue,
  ) {
    final end = start + schedule.periodsPerGroup - 1;
    final status = slot.statusAt(now);
    final historical = status == ClassroomSlotStatus.stale;
    final collected = slot.collectedAt;
    final rooms = historical
        ? [
            for (final name in slot.rooms!)
              (name: name, availability: ClassroomAvailability.partial),
          ]
        : schedule.forPeriod(start) ?? const <FreeClassroom>[];
    final empty = switch (status) {
      ClassroomSlotStatus.success => '这一时段暂无空教室',
      ClassroomSlotStatus.stale => '上次采集时未发现空教室',
      ClassroomSlotStatus.unavailable => '当前时段暂无可用数据',
    };
    final timestamp = collected == null
        ? null
        : '采集于 ${_collectionTime(collected)}';
    return _roomGroup(
      context,
      title: '第 $start–$end 节',
      time:
          '${clockLabel(neuqPeriods[start - 1].start)}–'
          '${clockLabel(neuqPeriods[end - 1].end)}',
      rooms: rooms,
      blue: blue,
      empty: empty,
      note: historical ? '数据已过期，仅供参考 · $timestamp' : timestamp,
      historical: historical,
    );
  }

  String _collectionTime(DateTime instant) {
    final time = instant.toUtc().add(campusOffset);
    final clock = clockLabel(time.hour * 60 + time.minute);
    return calendarDate(time) == _today ? clock : '${shortDate(time)} $clock';
  }

  Widget _roomGroup(
    BuildContext context, {
    required String title,
    required List<FreeClassroom> rooms,
    required Color blue,
    required String empty,
    String? time,
    String? note,
    bool historical = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final groupByFloor = _building == CampusBuilding.engineering;
    final byFloor = <int?, List<FreeClassroom>>{};
    for (final room in rooms) {
      final floor = groupByFloor ? engineeringRoomFloor(room.name) : null;
      (byFloor[floor] ??= []).add(room);
    }
    final floors = byFloor.keys.toList()
      ..sort((a, b) => (a ?? 100).compareTo(b ?? 100));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (time != null)
                  Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (note != null) Text(note, style: theme.textTheme.bodySmall),
            const SizedBox(height: 7),
            if (floors.isEmpty)
              Text(empty, style: theme.textTheme.bodySmall)
            else
              for (final (index, floor) in floors.indexed)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groupByFloor)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, right: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 32),
                            child: Text(
                              floor == null ? '其他' : '$floor层',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final room in byFloor[floor]!)
                              _roomTag(context, room, blue, historical),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _roomTag(
    BuildContext context,
    FreeClassroom room,
    Color blue,
    bool historical,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (foreground, status) = switch (room.availability) {
      ClassroomAvailability.allDay => (blue, '全天空闲'),
      ClassroomAvailability.nextBooked => (colors.error, '下节有课'),
      ClassroomAvailability.partial => (colors.onSurface, '本时段空闲'),
    };
    return Semantics(
      label: '${room.name}，${historical ? '上次记录为空闲' : status}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: room.availability == ClassroomAvailability.partial
              ? colors.surfaceContainerLow
              : foreground.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            room.name,
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
