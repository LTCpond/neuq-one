import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/database/school_data.dart';
import '../../../core/network/neuq_web_client.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../../core/widgets/screen.dart';
import '../domain/classrooms.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});

  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
  var _building = CampusBuilding.engineering;
  var _day = calendarDate(campusNow());
  late final AppLifecycleListener _lifecycle;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkDate);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDate());
  }

  void _checkDate() {
    final date = calendarDate(campusNow());
    if (date != _day) setState(() => _day = date);
  }

  @override
  void dispose() {
    _timer.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = classroomsProvider(_day);
    final result = ref.watch(query);
    final snapshot = result.value;
    final updated = snapshot?.syncedAt.add(campusOffset);
    final error = result.error;
    final needsLogin =
        error == SchoolWebFailure.expired ||
        error == SchoolWebFailure.differentAccount;
    final colors = Theme.of(context).colorScheme;
    final blue = colors.brightness == Brightness.dark
        ? const Color(0xFFA9CBFF)
        : const Color(0xFF1454A1);
    void refresh() => ref.invalidate(query);

    return CampusScreen(
      title: '当日空教室',
      eyebrow: '${shortDate(_day)} · ${weekdayLabel(_day.weekday)}',
      actions: [
        IconButton(
          icon: result.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: '刷新空教室',
          onPressed: result.isLoading ? null : refresh,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final building in CampusBuilding.values)
                ChoiceChip(
                  label: Text(building.label),
                  selected: building == _building,
                  onSelected: (_) {
                    if (building != _building) {
                      setState(() => _building = building);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (updated != null)
            Text(
              '学校教务 · 查询于 ${clockLabel(updated.hour * 60 + updated.minute)}'
              '${result.hasError ? ' · 刷新失败，显示上次结果' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
          if (needsLogin)
            StatePanel(
              '教务会话需要重新连接',
              '登录后将查询本楼栋全天节次。',
              icon: Icons.lock_outline,
              action: SchoolReconnectButton(
                onConnected: () => ref.invalidate(query),
              ),
            )
          else if (snapshot == null &&
              (error == SchoolWebFailure.denied || error is FormatException))
            StatePanel(
              '暂时无法查询空教室',
              error is FormatException ? error.message : '教务系统暂未开放此查询。',
              icon: Icons.error_outline,
              action: OutlinedButton(
                onPressed: refresh,
                child: const Text('重试'),
              ),
            )
          else
            DataPanel(
              value: snapshot == null ? result : AsyncData(snapshot),
              retry: refresh,
              builder: (snapshot) {
                final schedule = snapshot?.buildings[_building];
                if (schedule == null) {
                  return const StatePanel(
                    '空教室查询暂不可用',
                    '请使用支持应用内教务登录的设备。',
                    icon: Icons.meeting_room_outlined,
                  );
                }
                final allDay = schedule.allDay.toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _roomGroup(
                      context,
                      title: '全天空闲',
                      rooms: [
                        for (final name in allDay)
                          (
                            name: name,
                            availability: ClassroomAvailability.allDay,
                          ),
                      ],
                      blue: blue,
                      empty: schedule.complete
                          ? '今日暂无全天空闲教室'
                          : '部分节次查询失败，暂无法确认全天空闲',
                    ),
                    for (final start in schedule.groupStarts) ...[
                      const SizedBox(height: 8),
                      _periodGroup(context, schedule, start, blue),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _periodGroup(
    BuildContext context,
    ClassroomSchedule schedule,
    int start,
    Color blue,
  ) {
    final end = (start + schedule.periodsPerGroup - 1).clamp(
      1,
      neuqPeriods.length,
    );
    return _roomGroup(
      context,
      title: start == end ? '第 $start 节' : '第 $start–$end 节',
      time:
          '${clockLabel(neuqPeriods[start - 1].start)}–'
          '${clockLabel(neuqPeriods[end - 1].end)}',
      rooms: schedule.forPeriod(start),
      blue: blue,
      empty: '这一时段暂无空教室',
    );
  }

  Widget _roomGroup(
    BuildContext context, {
    required String title,
    required List<FreeClassroom>? rooms,
    required Color blue,
    required String empty,
    String? time,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final groupByFloor = _building == CampusBuilding.engineering;
    final byFloor = <int?, List<FreeClassroom>>{};
    for (final room in rooms ?? const <FreeClassroom>[]) {
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
            const SizedBox(height: 7),
            if (floors.isEmpty)
              Text(
                rooms == null ? '本时段查询失败，可刷新重试' : empty,
                style: theme.textTheme.bodySmall,
              )
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
                              _roomTag(context, room, blue),
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

  Widget _roomTag(BuildContext context, FreeClassroom room, Color blue) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (foreground, status) = switch (room.availability) {
      ClassroomAvailability.allDay => (blue, '全天空闲'),
      ClassroomAvailability.nextBooked => (colors.error, '下节有课'),
      ClassroomAvailability.partial => (colors.onSurface, '本时段空闲'),
    };
    final name =
        room.name.startsWith(_building.label) &&
            room.name.length > _building.label.length
        ? room.name.substring(_building.label.length)
        : room.name;
    return Semantics(
      label: '${room.name}，$status',
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
            name,
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
