import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../domain/schedule.dart';
import '../domain/schedule_grid.dart';
import '../domain/timetable.dart';
import 'timetable_palette.dart';

const _weekHeaderHeight = 54.0;
const _examMarkerWidth = 21.0;
const _examMarkerHeight = 3.0;
const _examMarkerSlotHeight = 9.0;

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
    final muted = theme.colorScheme.onSurfaceVariant;
    final start = term?.dateFor(week, DateTime.monday);
    final end = term?.dateFor(week, DateTime.sunday);
    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NEUQ · TIMETABLE',
          style: TextStyle(
            fontSize: 10,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                term == null ? '课表' : '第 $week 周',
                style: theme.textTheme.headlineMedium,
              ),
              if (term != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down, size: 22),
              ],
            ],
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            start == null
                ? shortDate(today)
                : '${shortDate(start)} – ${shortDate(end!)}',
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
    if (term == null) return heading;
    return PopupMenuButton<int>(
      tooltip: '选择教学周',
      initialValue: week,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var index = 1; index <= term.weeks; index++)
          PopupMenuItem(value: index, child: Text('第 $index 周')),
      ],
      child: heading,
    );
  }
}

class WeekTimetable extends StatefulWidget {
  const WeekTimetable({
    super.key,
    required this.semester,
    required this.week,
    required this.today,
    required this.timetable,
    required this.onWeekChanged,
    required this.onCourse,
    required this.onDate,
    this.schedule,
    this.conflicts,
    this.now,
    this.onExam,
  });

  final Semester semester;
  final int week;
  final DateTime today;
  final Timetable timetable;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<Course> onCourse;
  final ValueChanged<DateTime> onDate;
  final ScheduleEvents? schedule;
  final ScheduleConflicts? conflicts;
  final DateTime? now;
  final void Function(List<ScheduleEvent>, DateTime)? onExam;

  @override
  State<WeekTimetable> createState() => _WeekTimetableState();
}

class _WeekTimetableState extends State<WeekTimetable> {
  late final PageController _controller;
  final _daysByWeek = <int, List<_WeekDay>>{};
  int? _reportedWeek;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.week - 1, keepPage: false);
  }

  @override
  void didUpdateWidget(WeekTimetable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timetable != widget.timetable ||
        oldWidget.schedule != widget.schedule ||
        oldWidget.conflicts != widget.conflicts ||
        oldWidget.semester != widget.semester) {
      _daysByWeek.clear();
    }
    final week = widget.week;
    if (week == oldWidget.week) return;
    // The parent also updates its week in response to a settled swipe.
    final reportedWeek = _reportedWeek;
    _reportedWeek = null;
    if (week == reportedWeek) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || widget.week != week) return;
      final target = week - 1;
      final page = _controller.page;
      if (page != null &&
          page != target &&
          (page.round() - target).abs() <= 1 &&
          !MediaQuery.disableAnimationsOf(context)) {
        _controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _controller.jumpToPage(target);
      }
    });
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controller.hasClients ||
          _controller.position.isScrollingNotifier.value) {
        return;
      }
      final page = _controller.page;
      // Touching a moving page can stop the scroll between page boundaries.
      if (page == null || page != page.roundToDouble()) return;
      final week = page.round() + 1;
      if (week == widget.week || week == _reportedWeek) return;
      _reportedWeek = week;
      widget.onWeekChanged(week);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_WeekDay> _days(int week) => _daysByWeek.putIfAbsent(week, () {
    final semester = widget.semester;
    return List.generate(DateTime.daysPerWeek, (dayIndex) {
      final weekday = dayIndex + 1;
      final date = semester.dateFor(week, weekday);
      final schedule = widget.schedule;
      final events =
          schedule?.on(date, semesterId: semester.id) ??
          [
            for (final course in widget.timetable.on(semester, week, weekday))
              ScheduleEvent.course(course, semester, date),
          ];
      final groups = groupExamsOn(
        date,
        events.where((event) => event.exam != null),
      );
      return _WeekDay(
        date,
        _placeCourses([
          for (final event in events)
            if (event.course case final course?)
              for (final span in visibleCourseSpans(date, event, groups))
                (
                  course: course,
                  span: span,
                  fragment: groups.any(
                    (exam) => exam.time.overlaps(event.time),
                  ),
                ),
        ]),
        [
          for (final group in groups)
            (
              group: group,
              span: examGridSpan(date, group.time),
              supplement: examNeedsSupplement(date, group),
              courses: {
                for (final event in group.events)
                  for (final pair
                      in widget.conflicts?.forExam(
                            event.exam!.id,
                            date: date,
                          ) ??
                          const <ScheduleConflict>[])
                    if (pair.other.course case final course?)
                      (course.semesterId, course.name),
              }.length,
            ),
        ],
      );
    });
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semester = widget.semester;
    final month = semester.dateFor(widget.week, DateTime.monday).month;
    final supplemental = [
      for (final day in _days(widget.week))
        for (final exam in day.exams)
          if (exam.supplement) (date: day.date, exam: exam),
    ];
    final now = widget.now ?? campusNow();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      clipBehavior: Clip.antiAlias,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final rail = constraints.maxWidth < 340 ? 33.0 : 38.0;
                final rowHeight =
                    ((MediaQuery.sizeOf(context).height - 220) / 10).clamp(
                      52.0,
                      72.0,
                    );
                return Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: rail,
                        child: Column(
                          children: [
                            SizedBox(
                              height: _weekHeaderHeight,
                              child: Center(
                                child: Text(
                                  '$month月',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
                      Expanded(
                        child: SizedBox(
                          height:
                              _weekHeaderHeight +
                              rowHeight * neuqPeriods.length,
                          child: NotificationListener<ScrollEndNotification>(
                            onNotification: _onScrollEnd,
                            child: PageView.builder(
                              controller: _controller,
                              itemCount: semester.weeks,
                              itemBuilder: (context, index) {
                                final week = index + 1;
                                return _WeekGrid(
                                  start: semester.dateFor(
                                    week,
                                    DateTime.monday,
                                  ),
                                  today: widget.today,
                                  now: now,
                                  height: rowHeight,
                                  days: _days(week),
                                  onDate: widget.onDate,
                                  onCourse: widget.onCourse,
                                  onExam: widget.onExam,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (supplemental.isNotEmpty && widget.onExam != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Text('补充考试时段', style: theme.textTheme.labelLarge),
              ),
              for (final item in supplemental)
                _SupplementExamTile(
                  block: item.exam,
                  date: item.date,
                  now: now,
                  onTap: () =>
                      widget.onExam!(item.exam.group.events, item.date),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _dayTime(DateTime date, ScheduleInterval time) {
  final midnight = campusInstant(date, 0);
  return '${clockLabel(time.start.difference(midnight).inMinutes)}–'
      '${clockLabel(time.end.difference(midnight).inMinutes)}';
}

typedef _ExamBlock = ({
  ExamGroup group,
  GridSpan span,
  bool supplement,
  int courses,
});

class _SupplementExamTile extends StatelessWidget {
  const _SupplementExamTile({
    required this.block,
    required this.date,
    required this.now,
    required this.onTap,
  });

  final _ExamBlock block;
  final DateTime date;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final events = block.group.events;
    final palette = examPalette(
      Theme.of(context).brightness,
      finished: events.every((event) => event.exam!.isFinishedAt(now)),
    );
    final conflict = block.courses > 0 || events.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 5),
      child: Material(
        color: palette.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: conflict ? BorderSide(color: palette.border) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          textColor: palette.text,
          iconColor: palette.text,
          leading: Icon(
            conflict ? Icons.warning_amber_rounded : Icons.event_note_outlined,
          ),
          title: Text(events.map((event) => event.name).join('、')),
          subtitle: Text(
            [
              '${weekdayLabel(date.weekday)} · ${shortDate(date)}',
              _dayTime(date, block.group.time),
              _examLabel(block),
              if (events.length == 1 && events.single.room.isNotEmpty)
                events.single.room,
            ].join(' · '),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _WeekDay {
  const _WeekDay(this.date, this.courses, this.exams);

  final DateTime date;
  final List<_Block> courses;
  final List<_ExamBlock> exams;
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.start,
    required this.today,
    required this.now,
    required this.height,
    required this.days,
    required this.onDate,
    required this.onCourse,
    required this.onExam,
  });

  final DateTime start;
  final DateTime today;
  final DateTime now;
  final double height;
  final List<_WeekDay> days;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<Course> onCourse;
  final void Function(List<ScheduleEvent>, DateTime)? onExam;

  @override
  Widget build(BuildContext context) {
    final todayInWeek = mondayOf(today) == start;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Row(
            children: [
              for (final (index, day) in days.indexed)
                Expanded(
                  child: _DayColumn(
                    day: day,
                    current: todayInWeek && today.weekday == index + 1,
                    height: height,
                    now: now,
                    onDate: onDate,
                    onCourse: onCourse,
                    onExam: onExam,
                  ),
                ),
            ],
          ),
          if (days.every((day) => day.courses.isEmpty && day.exams.isEmpty))
            Positioned(
              top: _weekHeaderHeight,
              left: 0,
              right: 0,
              height: height,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '本周暂无课程',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
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
      fontSize: 8,
      height: 1.35,
      color: colors.onSurfaceVariant,
    );
    Widget clock(int minutes) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(clockLabel(minutes), style: clockStyle, maxLines: 1),
    );
    return Container(
      key: ValueKey('timetable-period-$period'),
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(border: _rowBorder(colors, period - 1)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$period',
            style: TextStyle(
              fontSize: 12,
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
    required this.day,
    required this.current,
    required this.height,
    required this.now,
    required this.onDate,
    required this.onCourse,
    required this.onExam,
  });

  final _WeekDay day;
  DateTime get date => day.date;
  final DateTime now;
  final bool current;
  final double height;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<Course> onCourse;
  final void Function(List<ScheduleEvent>, DateTime)? onExam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final examEvents = [for (final block in day.exams) ...block.group.events];
    final hasExams = examEvents.isNotEmpty;
    final examsFinished =
        hasExams && examEvents.every((event) => event.exam!.isFinishedAt(now));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        color: current
            ? (theme.brightness == Brightness.dark
                  ? const Color(0xFF202D45)
                  : const Color(0xFFEEF2FF))
            : null,
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey(date),
            onTap: () => onDate(date),
            child: SizedBox(
              height: _weekHeaderHeight,
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
                  const SizedBox(height: 2),
                  Container(
                    key: ValueKey('timetable-date-badge-$date'),
                    alignment: Alignment.center,
                    height: 22,
                    width: 24,
                    decoration: BoxDecoration(
                      color: current ? campusBlue : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: current ? Colors.white : colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    key: ValueKey('timetable-exam-marker-slot-$date'),
                    height: _examMarkerSlotHeight,
                    child: hasExams
                        ? Semantics(
                            label: examsFinished ? '当天考试已结束' : '当天有考试',
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Container(
                                  key: ValueKey('timetable-exam-marker-$date'),
                                  width: _examMarkerWidth,
                                  height: _examMarkerHeight,
                                  decoration: BoxDecoration(
                                    color: examDateMarkerColor(
                                      context,
                                      finished: examsFinished,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
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
                  for (final block in day.courses)
                    Positioned(
                      left: 1 + size.maxWidth * block.lane / block.lanes,
                      top: height * block.start,
                      width: (size.maxWidth / block.lanes - 2).clamp(
                        1.0,
                        double.infinity,
                      ),
                      height: height * (block.end - block.start),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: block.end - block.start > .15 ? 2 : 0,
                        ),
                        child: _CourseBlock(
                          course: block.course,
                          fragment: block.fragment,
                          onTap: () => onCourse(block.course),
                        ),
                      ),
                    ),
                  if (onExam != null)
                    for (final exam in day.exams)
                      if (exam.span.end > exam.span.start)
                        Positioned(
                          left: 1,
                          right: 1,
                          top: height * exam.span.start,
                          height: height * (exam.span.end - exam.span.start),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: exam.span.end - exam.span.start > .15
                                  ? 2
                                  : 0,
                            ),
                            child: _ExamGridBlock(
                              block: exam,
                              date: date,
                              now: now,
                              onTap: () => onExam!(exam.group.events, date),
                            ),
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

String _examLabel(_ExamBlock block) => [
  block.group.events.length == 1 ? '考试' : '${block.group.events.length} 场考试',
  if (block.courses > 0)
    '⚠ 冲突 ${block.courses} 门'
  else if (block.group.events.length > 1)
    '⚠ 时间冲突',
].join(' · ');

class _ExamGridBlock extends StatelessWidget {
  const _ExamGridBlock({
    required this.block,
    required this.date,
    required this.now,
    required this.onTap,
  });

  final _ExamBlock block;
  final DateTime date;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final events = block.group.events;
    final palette = examPalette(
      Theme.of(context).brightness,
      finished: events.every((event) => event.exam!.isFinishedAt(now)),
    );
    final conflict = block.courses > 0 || events.length > 1;
    final names = events.map((event) => event.name).join('、');
    final time = _dayTime(date, block.group.time);
    final style = TextStyle(fontSize: 9, height: 1.14, color: palette.text);
    final room = events.length == 1 ? events.single.room : '';
    const radius = BorderRadius.all(Radius.circular(7));
    return Semantics(
      button: true,
      label: [
        '${_examLabel(block)}，$names',
        room,
        time,
      ].where((value) => value.isNotEmpty).join('，'),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: ValueKey('timetable-exam-${events.first.exam!.id}-$date'),
        color: palette.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: conflict ? BorderSide(color: palette.border) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, size) {
              const padding = EdgeInsets.fromLTRB(3, 3, 3, 2);
              if (size.maxHeight < 16) return const SizedBox.shrink();
              return Padding(
                padding: padding,
                child: _courseText(context, padding.deflateSize(size.biggest), [
                  (
                    events.length == 1 ? '考试' : '⚠ ${events.length} 场考试',
                    style,
                    1,
                  ),
                  (
                    names,
                    style.copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                    3,
                  ),
                  if (block.courses > 0) ('⚠ 冲突 ${block.courses} 门', style, 1),
                  if (room.isNotEmpty) (room, style, 2),
                  (time, style, 2),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}

Border _rowBorder(ColorScheme colors, int index) => Border(
  top: BorderSide(
    color: colors.outlineVariant,
    width: index == 0 || index == 4 || index == 8 ? 1.2 : .65,
  ),
);

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.course,
    required this.onTap,
    required this.fragment,
  });

  final Course course;
  final bool fragment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (surface, text) = courseBlockColors(context, course.colorIndex);
    final details = [
      course.name,
      course.time,
      course.room,
      course.teacher,
      if (fragment) '部分课时与考试重叠，点击查看完整课程',
    ];
    return Semantics(
      button: true,
      label: details.where((value) => value.isNotEmpty).join('，'),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('timetable-course-${course.id}'),
        color: surface,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, size) {
              final narrow = size.maxWidth < 34;
              final horizontalPadding = narrow
                  ? 2.0
                  : (size.maxWidth < 40 ? 3.0 : 4.0);
              final padding = EdgeInsets.fromLTRB(
                horizontalPadding,
                5,
                horizontalPadding,
                3,
              );
              final compact = narrow || size.maxHeight < 55;
              final phoneWidth = size.maxWidth < 48;
              final detailStyle = TextStyle(
                fontSize: compact ? 9 : (phoneWidth ? 9.5 : 10),
                height: 1.14,
                fontWeight: FontWeight.w400,
                color: text,
              );
              return Padding(
                padding: padding,
                child: _courseText(context, padding.deflateSize(size.biggest), [
                  (
                    course.name,
                    detailStyle.copyWith(
                      fontSize: compact ? 10 : (phoneWidth ? 11 : 12),
                      fontWeight: FontWeight.w700,
                    ),
                    compact ? 2 : 4,
                  ),
                  if (fragment) ('部分重叠', detailStyle, 1),
                  if (course.room.isNotEmpty)
                    (_timetableRoom(course.room), detailStyle, compact ? 2 : 4),
                  if (course.teacher.isNotEmpty)
                    (course.teacher, detailStyle, compact ? 1 : 2),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}

final _mainCampusRoom = RegExp(
  r'^((?:工学馆|科技楼|人文楼)[^（）()、，,;/／]*\d)\s*(?:\(学校本部\)|（学校本部）)$',
);

String _timetableRoom(String room) =>
    _mainCampusRoom.firstMatch(room.trim())?.group(1) ?? room;

Widget _courseText(
  BuildContext context,
  Size size,
  List<(String, TextStyle, int)> fields,
) {
  if (size.width < 9) return const SizedBox.shrink();
  final defaults = DefaultTextStyle.of(context);
  final bold = MediaQuery.boldTextOf(context);
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: defaults.textHeightBehavior,
    ellipsis: '…',
  );
  final lineCounts = <int>[];
  final heights = <double>[];
  var remaining = size.height;

  double measure((String, TextStyle, int) field, int lines) {
    final style = defaults.style.merge(field.$2);
    painter
      ..text = TextSpan(
        text: field.$1,
        style: bold
            ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
            : style,
      )
      ..maxLines = lines
      ..layout(maxWidth: size.width);
    return painter.height;
  }

  // Reserve one line for each detail before giving longer fields more space.
  for (final field in fields) {
    final height = measure(field, 1);
    if (height > remaining) break;
    lineCounts.add(1);
    heights.add(height);
    remaining -= height;
  }
  for (final (index, field) in fields.take(lineCounts.length).indexed) {
    for (var lines = 2; lines <= field.$3; lines++) {
      final height = measure(field, lines);
      final extra = height - heights[index];
      if (extra > remaining) break;
      lineCounts[index] = lines;
      heights[index] = height;
      remaining -= extra;
      if (!painter.didExceedMaxLines) break;
    }
  }
  painter.dispose();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, lines) in lineCounts.indexed)
        Text(
          fields[index].$1,
          style: fields[index].$2,
          textAlign: TextAlign.start,
          maxLines: lines,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
        ),
    ],
  );
}

typedef _Block = ({
  Course course,
  double start,
  double end,
  int lane,
  int lanes,
  bool fragment,
});

List<_Block> _placeCourses(
  List<({Course course, GridSpan span, bool fragment})> positions,
) {
  positions.sort((a, b) => a.span.start.compareTo(b.span.start));
  final result = <_Block>[];
  final ends = <double>[];
  final group = <_Block>[];
  void finishGroup() {
    for (final block in group) {
      result.add((
        course: block.course,
        start: block.start,
        end: block.end,
        lane: block.lane,
        lanes: ends.length,
        fragment: block.fragment,
      ));
    }
    ends.clear();
    group.clear();
  }

  for (final position in positions) {
    final (start: start, end: end) = position.span;
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
      fragment: position.fragment,
    ));
  }
  finishGroup();
  return result;
}
