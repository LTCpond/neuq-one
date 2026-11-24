import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../domain/timetable.dart';
import 'timetable_editors.dart';

class WeekMenu extends StatelessWidget {
  const WeekMenu({
    super.key,
    required this.semester,
    required this.week,
    required this.today,
    required this.onChanged,
  });

  final Semester? semester;
  final int week;
  final DateTime today;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final term = semester;
    if (term == null) {
      return Text(_dateLabel(today), style: theme.textTheme.titleMedium);
    }
    final date = term.weekFor(today) == week
        ? today
        : week == 1
        ? term.start
        : term.dateFor(week, DateTime.monday);
    return PopupMenuButton<int>(
      tooltip: '选择教学周',
      initialValue: week,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var index = 1; index <= term.weeks; index++)
          PopupMenuItem(value: index, child: Text('第 $index 周')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('第 $week 周', style: theme.textTheme.titleLarge),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            Text(
              '${_dateLabel(date)} · ${weekdayLabel(date.weekday)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date) => '${date.year}/${date.month}/${date.day}';

class WeekTimetable extends StatelessWidget {
  const WeekTimetable({
    super.key,
    required this.semester,
    required this.week,
    required this.today,
    required this.days,
    required this.onWeekChanged,
    required this.onCourse,
    required this.onDate,
  });

  final Semester semester;
  final int week;
  final DateTime today;
  final List<List<Course>> days;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<Course> onCourse;
  final ValueChanged<DateTime> onDate;

  void _turn(int delta) {
    final next = week + delta;
    if (next >= 1 && next <= semester.weeks) onWeekChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = semester.dateFor(week, DateTime.monday);
    final end = semester.dateFor(week, DateTime.sunday);
    final todayInWeek = !today.isBefore(start) && !today.isAfter(end);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (days.every((day) => day.isEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('本周暂无课程', style: theme.textTheme.labelMedium),
            ),
          const Divider(height: 1),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() > 180) _turn(velocity < 0 ? 1 : -1);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rail = constraints.maxWidth < 365 ? 37.0 : 43.0;
                  final rowHeight =
                      ((MediaQuery.sizeOf(context).height - 220) / 10).clamp(
                        52.0,
                        72.0,
                      );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: rail,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 61,
                              child: Center(
                                child: Text(
                                  '${start.month}月',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ),
                            for (final (index, period) in neuqPeriods.indexed)
                              _PeriodNumber(
                                period: index + 1,
                                start: period.start,
                                end: period.end,
                                height: rowHeight,
                              ),
                          ],
                        ),
                      ),
                      for (final (index, courses) in days.indexed)
                        Expanded(
                          child: _DayColumn(
                            date: start.add(Duration(days: index)),
                            current: todayInWeek && today.weekday == index + 1,
                            height: rowHeight,
                            courses: courses,
                            onDate: onDate,
                            onCourse: onCourse,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodNumber extends StatelessWidget {
  const _PeriodNumber({
    required this.period,
    required this.start,
    required this.end,
    required this.height,
  });

  final int period;
  final int start;
  final int end;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final clockStyle = TextStyle(
      fontSize: 9,
      height: 1.25,
      color: colors.onSurfaceVariant,
    );
    Widget clock(int minutes) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(clockLabel(minutes), style: clockStyle, maxLines: 1),
    );
    return Container(
      key: ValueKey('timetable-period-$period'),
      height: height,
      decoration: BoxDecoration(border: _rowBorder(colors, period - 1)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$period',
            style: TextStyle(
              fontSize: 14,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          clock(start),
          clock(end),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.date,
    required this.current,
    required this.height,
    required this.courses,
    required this.onDate,
    required this.onCourse,
  });

  final DateTime date;
  final bool current;
  final double height;
  final List<Course> courses;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<Course> onCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final blocks = _placeCourses(courses);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        color: current ? colors.primaryContainer.withValues(alpha: .23) : null,
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey(date),
            onTap: () => onDate(date),
            child: SizedBox(
              height: 61,
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayLabel(date.weekday),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                      color: current ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    alignment: Alignment.center,
                    height: 22,
                    width: 24,
                    decoration: BoxDecoration(
                      color: current ? colors.primary : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: current ? colors.onPrimary : colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, size) => SizedBox(
              height: height * neuqPeriods.length,
              child: Stack(
                children: [
                  Column(
                    children: [
                      for (var index = 0; index < neuqPeriods.length; index++)
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            border: _rowBorder(colors, index),
                          ),
                        ),
                    ],
                  ),
                  for (final block in blocks)
                    Positioned(
                      left: 2 + size.maxWidth * block.lane / block.lanes,
                      top: height * block.start + 2,
                      width: (size.maxWidth / block.lanes - 4).clamp(
                        1.0,
                        double.infinity,
                      ),
                      height: height * (block.end - block.start) - 4,
                      child: _CourseBlock(
                        course: block.course,
                        onTap: () => onCourse(block.course),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Border _rowBorder(ColorScheme colors, int index) => Border(
  top: BorderSide(
    color: colors.outlineVariant.withValues(
      alpha: index == 0 || index == 4 || index == 8 ? .85 : .40,
    ),
  ),
);

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.course, required this.onTap});

  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hue = courseColors[course.colorIndex % courseColors.length];
    final dark = theme.brightness == Brightness.dark;
    final surface = Color.alphaBlend(
      hue.withValues(alpha: dark ? .39 : .17),
      colors.surface,
    );
    final text = dark
        ? colors.onSurface
        : Color.alphaBlend(Colors.black.withValues(alpha: .68), hue);
    return Semantics(
      button: true,
      label: '${course.name}，${course.time}，${course.room}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('timetable-course-${course.id}'),
        color: surface,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: hue, width: 2)),
            ),
            padding: const EdgeInsets.fromLTRB(3, 4, 3, 3),
            child: LayoutBuilder(
              builder: (context, size) {
                final scale = MediaQuery.textScalerOf(context);
                final detailLine = scale.scale(9) * 1.2;
                final titleLines = size.maxHeight >= 70 ? 2 : 1;
                final titleHeight = scale.scale(11) * 1.15 * titleLines;
                final showTeacher =
                    course.teacher.isNotEmpty &&
                    size.maxHeight >= 82 &&
                    size.maxHeight >= titleHeight + detailLine * 3;
                final roomHeight =
                    size.maxHeight -
                    titleHeight -
                    (showTeacher ? detailLine : 0);
                final roomLines = (roomHeight / detailLine).floor();
                final detailStyle = TextStyle(
                  fontSize: 9,
                  height: 1.2,
                  color: text,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        course.name,
                        maxLines: size.maxHeight >= 70 ? 4 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: text,
                        ),
                      ),
                    ),
                    if (course.room.isNotEmpty && roomLines > 0)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: roomHeight),
                        child: Text(
                          course.room,
                          maxLines: roomLines,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: detailStyle,
                        ),
                      ),
                    if (showTeacher)
                      Text(
                        course.teacher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Block = ({Course course, int start, int end, int lane, int lanes});

List<_Block> _placeCourses(List<Course> courses) {
  final positions = [
    for (final course in courses)
      (
        course: course,
        start:
            (periodAtStart(course.startMinute) ??
                    neuqPeriods
                            .where((period) => course.startMinute >= period.end)
                            .length +
                        1)
                .clamp(1, neuqPeriods.length) -
            1,
        end:
            periodAtEnd(course.endMinute) ??
            neuqPeriods
                .where((period) => course.endMinute > period.start)
                .length,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final result = <_Block>[];
  final ends = <int>[];
  final group = <_Block>[];
  void finishGroup() {
    for (final block in group) {
      result.add((
        course: block.course,
        start: block.start,
        end: block.end,
        lane: block.lane,
        lanes: ends.length,
      ));
    }
    ends.clear();
    group.clear();
  }

  for (final position in positions) {
    final start = position.start;
    final end = position.end.clamp(start + 1, neuqPeriods.length);
    if (ends.every((point) => point <= start)) finishGroup();
    var lane = ends.indexWhere((point) => point <= start);
    if (lane == -1) {
      lane = ends.length;
      ends.add(end);
    } else {
      ends[lane] = end;
    }
    group.add((
      course: position.course,
      start: start,
      end: end,
      lane: lane,
      lanes: 0,
    ));
  }
  finishGroup();
  return result;
}
