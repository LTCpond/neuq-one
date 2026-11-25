import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../data/classroom_view_preferences.dart';
import '../data/public_classrooms.dart';
import '../domain/classrooms.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});

  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
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
    setState(() => _today = today);
    if (dayChanged &&
        (ref.read(classroomViewProvider).date?.isBefore(today) ?? false)) {
      ref.read(classroomViewProvider.notifier).selectDate(null);
    }
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
    final view = ref.watch(classroomViewProvider);
    final selection = ref.read(classroomViewProvider.notifier);
    final now = ref.watch(classroomsClockProvider)().toUtc();
    final dates = List.generate(
      7,
      (index) => _today.add(Duration(days: index)),
    );
    final selected = dates.contains(view.date) ? view.date! : _today;
    final day = state.snapshot?.days[selected];
    final slots = day?.buildings[view.building];
    final updated = day?.updatedAt;
    _watchClock(now, slots);

    final colors = Theme.of(context).colorScheme;
    final caption = Theme.of(context).textTheme.bodySmall!
        .copyWith(fontSize: 11, color: colors.onSurfaceVariant);
    void refresh() => _refresh(force: true);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BackButton(
                style: IconButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.square(36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.only(left: 1),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CampusPageTitle('空教室'),
                      const SizedBox(height: 4),
                      Semantics(
                        label: '选择查询日期',
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DateTime>(
                            value: selected,
                            isDense: true,
                            iconSize: 15,
                            iconEnabledColor: colors.onSurfaceVariant,
                            style: caption.copyWith(fontSize: 12),
                            selectedItemBuilder: (context) => [
                              for (final date in dates)
                                Text(
                                  '${shortDate(date)} · ${weekdayLabel(date.weekday).replaceFirst('周', '星期')}',
                                ),
                            ],
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
                            onChanged: (date) => selection.selectDate(
                              date == _today ? null : date,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                CampusRefreshButton(
                  tooltip: '刷新空教室',
                  isLoading: state.isLoading,
                  onPressed: refresh,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _BuildingPicker(
              selected: view.building,
              onChanged: selection.selectBuilding,
            ),
            const SizedBox(height: 8),
            if (updated != null)
              Text('数据更新于 ${_collectionTime(updated)}', style: caption),
            if (state.isLoading) Text('正在更新空教室数据', style: caption),
            if (state.refreshFailed && slots != null)
              Text('更新失败，正在显示上次数据', style: caption),
            const SizedBox(height: 10),
            if (slots != null)
              ..._schedule(slots, now, view, selection.selectTable)
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
              style: caption,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _schedule(
    Map<int, ClassroomSlot> slots,
    DateTime now,
    ClassroomView view,
    ValueChanged<bool> selectTable,
  ) {
    final schedule = classroomScheduleAt(slots, now);
    final groupByFloor = view.building == CampusBuilding.engineering;
    return [
      _AllDayCard(schedule: schedule),
      const SizedBox(height: 17),
      Row(
        children: [
          Expanded(child: CampusSectionHeading(view.table ? '教室空闲表' : '分时段查询')),
          _ScheduleViewToggle(showTable: view.table, onChanged: selectTable),
        ],
      ),
      const SizedBox(height: 11),
      if (schedule.freeByPeriod.isEmpty &&
          slots.values.any(
            (slot) => slot.statusAt(now) == ClassroomSlotStatus.stale,
          ))
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('此楼栋所选日期的已有记录均已过期，暂无法确认空闲时段。'),
        ),
      if (view.table)
        _ClassroomTable(
          schedule: schedule,
          slots: slots,
          groupByFloor: groupByFloor,
        )
      else ...[
        const _RoomLegend(),
        const SizedBox(height: 14),
        for (final start in schedule.groupStarts)
          _periodGroup(schedule, slots[start], start, now, groupByFloor),
      ],
    ];
  }

  Widget _periodGroup(
    ClassroomSchedule schedule,
    ClassroomSlot? slot,
    int start,
    DateTime now,
    bool groupByFloor,
  ) {
    final end = start + schedule.periodsPerGroup - 1;
    final status = slot?.statusAt(now) ?? ClassroomSlotStatus.unavailable;
    final historical = status == ClassroomSlotStatus.stale;
    final collected = slot?.collectedAt;
    final rooms = historical
        ? [
            for (final name in slot?.rooms ?? const <String>{})
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
    return _PeriodCard(
      title: '$start–$end 节',
      time:
          '${clockLabel(neuqPeriods[start - 1].start)}–${clockLabel(neuqPeriods[end - 1].end)}',
      rooms: rooms,
      empty: empty,
      timestamp: timestamp,
      historical: historical,
      groupByFloor: groupByFloor,
    );
  }

  String _collectionTime(DateTime instant) {
    final time = instant.toUtc().add(campusOffset);
    final clock = clockLabel(time.hour * 60 + time.minute);
    return calendarDate(time) == _today ? clock : '${shortDate(time)} $clock';
  }
}

class _BuildingPicker extends StatelessWidget {
  const _BuildingPicker({required this.selected, required this.onChanged});

  final CampusBuilding selected;
  final ValueChanged<CampusBuilding> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final building in CampusBuilding.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: building == selected,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: building == selected
                          ? campusBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => onChanged(building),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 38),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 4,
                          ),
                          child: Center(
                            child: Text(
                              building.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: building == selected
                                    ? Colors.white
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AllDayCard extends StatelessWidget {
  const _AllDayCard({required this.schedule});

  final ClassroomSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final rooms = schedule.allDay.toList()..sort();
    return Card(
      color: campusBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 18),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('全天空闲', style: TextStyle(fontSize: 19)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      schedule.complete
                          ? '${rooms.length.toString().padLeft(2, '0')} 间'
                          : '— 间',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 34, height: 1.16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              if (rooms.isEmpty)
                Text(
                  schedule.complete ? '所选日期暂无全天空闲教室' : '部分时段缺少有效数据，暂无法确认全天空闲',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final room in rooms)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F79ED),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 76),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              room,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleViewToggle extends StatelessWidget {
  const _ScheduleViewToggle({required this.showTable, required this.onChanged});

  final bool showTable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (table, icon, label) in [
              (false, Icons.format_list_bulleted, '时间轴视图'),
              (true, Icons.grid_on, '表格视图'),
            ])
              Semantics(
                selected: showTable == table,
                child: IconButton(
                  tooltip: label,
                  onPressed: () => onChanged(table),
                  icon: Icon(icon, size: 19),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(42, 32),
                    foregroundColor: showTable == table
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    backgroundColor: showTable == table
                        ? colors.surface
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _roomStatuses = {
  ClassroomAvailability.allDay: '全天空闲',
  ClassroomAvailability.partial: '本时段空闲',
  ClassroomAvailability.nextBooked: '下节有课',
};

(Color, Color) _roomColors(ColorScheme colors, ClassroomAvailability status) {
  final dark = colors.brightness == Brightness.dark;
  return switch (status) {
    ClassroomAvailability.allDay => (colors.primaryContainer, colors.primary),
    ClassroomAvailability.partial =>
      dark
          ? (const Color(0xFF303B4A), const Color(0xFFBDC9DB))
          : (const Color(0xFFEEF1F6), const Color(0xFF54647D)),
    ClassroomAvailability.nextBooked =>
      dark
          ? (const Color(0xFF522E38), const Color(0xFFFFAAA7))
          : (const Color(0xFFFCE4E3), const Color(0xFFA53232)),
  };
}

class _RoomLegend extends StatelessWidget {
  const _RoomLegend();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 13,
      runSpacing: 6,
      children: [
        for (final entry in _roomStatuses.entries)
          SizedBox(
            width: 107,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _roomColors(colors, entry.key).$2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.title,
    required this.time,
    required this.rooms,
    required this.empty,
    required this.timestamp,
    required this.historical,
    required this.groupByFloor,
  });

  final String title;
  final String time;
  final List<FreeClassroom> rooms;
  final String empty;
  final String? timestamp;
  final bool historical;
  final bool groupByFloor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    final byFloor = <int?, List<FreeClassroom>>{};
    for (final room in rooms) {
      final floor = groupByFloor ? engineeringRoomFloor(room.name) : null;
      (byFloor[floor] ??= []).add(room);
    }
    final floors = byFloor.keys.toList()
      ..sort((a, b) => (a ?? 100).compareTo(b ?? 100));
    final timeLabel = Text(time, style: muted);
    return Stack(
      children: [
        Positioned(
          top: 17,
          bottom: 0,
          left: 12,
          width: 1,
          child: ColoredBox(
            color: colors.brightness == Brightness.dark
                ? const Color(0xFF3A4D68)
                : const Color(0xFFCCD7EC),
          ),
        ),
        const Positioned(
          left: 7,
          top: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: campusBlue,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 11),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 16, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (timestamp case final note?)
                        Tooltip(message: note, child: timeLabel)
                      else
                        timeLabel,
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (historical) ...[
                    Text(
                      '数据已过期，仅供参考${timestamp == null ? '' : ' · $timestamp'}',
                      style: muted,
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (floors.isEmpty)
                    Text(empty, style: muted)
                  else
                    for (final (index, floor) in floors.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (groupByFloor)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  right: 7,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                  ),
                                  child: Text(
                                    floor == null ? '其他' : '$floor层',
                                    style: muted.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 5,
                                children: [
                                  for (final room in byFloor[floor]!)
                                    _RoomTag(room, historical: historical),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomTag extends StatelessWidget {
  const _RoomTag(this.room, {required this.historical});

  final FreeClassroom room;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = _roomColors(colors, room.availability);
    return Semantics(
      label:
          '${room.name}，${historical ? '上次记录为空闲' : _roomStatuses[room.availability]}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              room.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassroomTable extends StatelessWidget {
  const _ClassroomTable({
    required this.schedule,
    required this.slots,
    required this.groupByFloor,
  });

  final ClassroomSchedule schedule;
  final Map<int, ClassroomSlot> slots;
  final bool groupByFloor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final freeColor = dark ? const Color(0xFF527EF0) : campusBlue;
    final unknownColor = dark
        ? const Color(0xFF3B4759)
        : const Color(0xFFDCE1E9);
    final rowColor = dark ? const Color(0xFF202A38) : Colors.white;
    final altColor = dark ? const Color(0xFF25303F) : const Color(0xFFF7F8FB);
    final headerColor = dark
        ? const Color(0xFF283444)
        : const Color(0xFFE8EDF5);
    final line = BorderSide(
      color: dark ? const Color(0xFF344154) : const Color(0xFFE0E5ED),
    );
    final periods = schedule.groupStarts.toList();
    int floor(String room) =>
        groupByFloor ? engineeringRoomFloor(room) ?? 100 : 0;
    final rooms = {for (final slot in slots.values) ...?slot.rooms}.toList()
      ..sort((a, b) {
        final order = floor(a).compareTo(floor(b));
        return order == 0 ? a.compareTo(b) : order;
      });
    const columns = {0: FixedColumnWidth(64)};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth.clamp(328.0, double.infinity),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Table(
                      columnWidths: columns,
                      border: TableBorder(bottom: line, verticalInside: line),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: headerColor),
                          children: [
                            const _TableLabel('教室', header: true),
                            for (final period in periods)
                              _TableLabel(
                                '$period–${period + schedule.periodsPerGroup - 1}',
                                header: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (rooms.isEmpty)
                      ColoredBox(
                        color: rowColor,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            schedule.complete ? '所选日期暂无空教室' : '暂无可用教室记录',
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (MediaQuery.sizeOf(context).height * .46)
                              .clamp(180.0, 400.0),
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Table(
                            columnWidths: columns,
                            border: TableBorder(
                              bottom: line,
                              horizontalInside: line,
                              verticalInside: line,
                            ),
                            children: [
                              for (final (index, room) in rooms.indexed)
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: index.isEven ? rowColor : altColor,
                                    border:
                                        index > 0 &&
                                            floor(room) !=
                                                floor(rooms[index - 1])
                                        ? Border(top: line.copyWith(width: 2))
                                        : null,
                                  ),
                                  children: [
                                    _TableLabel(room),
                                    for (final period in periods)
                                      TableCell(
                                        verticalAlignment:
                                            TableCellVerticalAlignment.fill,
                                        child: _AvailabilityCell(
                                          room: room,
                                          period: period,
                                          available: schedule
                                              .freeByPeriod[period]
                                              ?.contains(room),
                                          freeColor: freeColor,
                                          unknownColor: unknownColor,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        DefaultTextStyle.merge(
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          child: Wrap(
            spacing: 13,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MatrixLegendItem(color: freeColor, label: '空闲'),
              const Text('空白 · 未列为空闲'),
              _MatrixLegendItem(color: unknownColor, label: '? · 暂无有效数据'),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.label, {this.header = false});

  final String label;
  final bool header;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: header ? 42 : 36),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: header ? 11 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _AvailabilityCell extends StatelessWidget {
  const _AvailabilityCell({
    required this.room,
    required this.period,
    required this.available,
    required this.freeColor,
    required this.unknownColor,
  });

  final String room;
  final int period;
  final bool? available;
  final Color freeColor;
  final Color unknownColor;

  @override
  Widget build(BuildContext context) {
    final status = switch (available) {
      true => '空闲',
      false => '未列为空闲',
      null => '暂无有效数据',
    };
    return Semantics(
      label: '$room，第 $period 节开始，$status',
      excludeSemantics: true,
      child: available == false
          ? const SizedBox.expand()
          : Padding(
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: available == true ? freeColor : unknownColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: available == null
                    ? const Center(
                        child: Text(
                          '?',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
    );
  }
}

class _MatrixLegendItem extends StatelessWidget {
  const _MatrixLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const SizedBox(width: 16, height: 12),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}
