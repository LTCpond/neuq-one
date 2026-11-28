import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/local_files.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/school_sync_status.dart';
import '../data/local_timetable.dart';
import '../domain/icalendar.dart';
import '../domain/timetable.dart';
import 'semester_menu.dart';
import 'timetable_date.dart';
import 'timetable_editors.dart';
import 'timetable_palette.dart';
import 'week_timetable.dart';

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key, this.widgetCourse});

  final ({String id, String request})? widgetCourse;

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  String? _semesterId;
  int? _week;
  String? _openedWidgetRequest;

  void _openWidgetCourse(Timetable? data, TimetableRepository repository) {
    final target = widget.widgetCourse;
    if (target == null ||
        data == null ||
        _openedWidgetRequest == target.request) {
      return;
    }
    final course = data.courses
        .where((course) => course.id == target.id)
        .firstOrNull;
    if (course == null) return;
    final term = data.semesters
        .where((term) => term.id == course.semesterId)
        .firstOrNull;
    if (term == null) return;
    _openedWidgetRequest = target.request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.widgetCourse == target) {
        showCourseDetails(context, repository, term, course);
      }
    });
  }

  Future<void> _export(Semester semester, List<Course> courses) async {
    if (courses.isEmpty) {
      showMessage(context, '此学期暂无课程可导出');
      return;
    }
    try {
      final saved = await saveTextFile(
        'neuq-one-timetable.ics',
        exportIcs(semester, courses, DateTime.now()),
      );
      if (saved && mounted) showMessage(context, '日历文件已保存');
    } catch (_) {
      if (mounted) showMessage(context, '无法保存日历文件，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(visibleTimetableProvider);
    final repository = ref.watch(timetableRepositoryProvider);
    _openWidgetCourse(data.asData?.value, repository);
    final terms = data.value?.semesters ?? [];
    final today = ref.watch(timetableDateProvider);
    final semester =
        terms.where((term) => term.id == _semesterId).firstOrNull ??
        currentSemester(terms, today);
    final week = semester == null
        ? 1
        : (_week ?? semester.weekFor(today) ?? 1).clamp(1, semester.weeks);
    final local = semester != null && !isSchoolRecord(semester.id);
    final refreshKey = schoolRefreshProvider(SchoolDataSet.timetable);
    final refresh = ref.watch(refreshKey);
    final sourceReady = ref.watch(schoolDataSourceProvider) != null;
    final restoring = ref.watch(
      schoolConnectionProvider.select(
        (connection) => connection.value == SchoolConnection.restoring,
      ),
    );
    final cache = ref.watch(schoolTimetableCacheProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight:
            88 + (MediaQuery.textScalerOf(context).scale(30) - 30).clamp(0, 36),
        actionsPadding: const EdgeInsets.only(top: 8, right: 13),
        title: WeekMenu(
          semester: semester,
          week: week,
          today: today,
          onChanged: (value) => setState(() => _week = value),
        ),
        actions: [
          if (semester != null) ...[
            SemesterMenu(
              semesters: terms,
              selected: semester,
              onChanged: (id) => setState(() {
                _semesterId = id;
                _week = null;
              }),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '课表选项',
              onSelected: (value) {
                switch (value) {
                  case 'today':
                    setState(() {
                      _semesterId = null;
                      _week = null;
                    });
                  case 'edit':
                    editSemester(context, repository, semester);
                  case 'export':
                    _export(semester, data.value!.forSemester(semester.id));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'today', child: Text('回到本周')),
                if (local)
                  const PopupMenuItem(value: 'edit', child: Text('编辑当前学期')),
                const PopupMenuItem(value: 'export', child: Text('导出 ICS 日历')),
              ],
              child: Ink(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
        children: [
          if (sourceReady && refresh.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (restoring || refresh.hasError || cache.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: SchoolSyncStatus(
                available: sourceReady,
                refresh: refresh,
                syncedAt: cache.value?.syncedAt,
                label: '教务课表同步',
                restoring: restoring,
                cacheError: cache.hasError,
                reconnect: const SchoolReconnectButton(),
              ),
            ),
          DataPanel(
            value: data,
            retry: () {
              ref.invalidate(timetableProvider);
              ref.invalidate(schoolTimetableCacheProvider);
            },
            builder: (timetable) => semester == null
                ? StatePanel(
                    refresh.isLoading && sourceReady ? '正在读取课表' : '还没有课表',
                    '打开课表页时会自动读取教务课表。',
                    icon: Icons.calendar_month_outlined,
                  )
                : WeekTimetable(
                    key: ValueKey((
                      semester.id,
                      semester.start,
                      semester.weeks,
                    )),
                    semester: semester,
                    week: week,
                    today: today,
                    timetable: timetable,
                    onWeekChanged: (value) => setState(() => _week = value),
                    onCourse: (course) => showCourseDetails(
                      context,
                      repository,
                      semester,
                      course,
                    ),
                    onDate: (date) =>
                        _openDate(timetable, semester, repository, date),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDate(
    Timetable timetable,
    Semester term,
    TimetableRepository repository,
    DateTime date,
  ) async {
    final week = term.weekFor(date);
    final entries = week == null
        ? <Course>[]
        : timetable.on(term, week, date.weekday);
    if (entries.length == 1) {
      await showCourseDetails(context, repository, term, entries.single);
      return;
    }

    final selected = await showModalBottomSheet<Course>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionTitle('${shortDate(date)} · ${weekdayLabel(date.weekday)}'),
            if (entries.isEmpty) const Text('当天没有课程'),
            for (final course in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CourseTile(
                  course: course,
                  onTap: () => Navigator.pop(context, course),
                ),
              ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      await showCourseDetails(context, repository, term, selected);
    }
  }
}

class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.course, required this.onTap});
  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      course.time,
      course.room,
      course.teacher,
    ].where((value) => value.isNotEmpty);
    return Card(
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        leading: Container(
          width: 5,
          height: 38,
          decoration: BoxDecoration(
            color: courseBlockColors(context, course.colorIndex).$2,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          course.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(details.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

Future<void> showCourseDetails(
  BuildContext context,
  TimetableRepository repository,
  Semester semester,
  Course course,
) async {
  final (background, foreground) = courseBlockColors(
    context,
    course.colorIndex,
  );
  final local = !isSchoolRecord(course.id);
  final action = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: const Color(0x55111B2F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      final details = [
        (
          Icons.schedule_outlined,
          '上课时间',
          '${weekdayLabel(course.weekday).replaceFirst('周', '星期')} ${course.time}',
        ),
        (Icons.location_on_outlined, '上课地点', course.room),
        (Icons.person_outline, '授课教师', course.teacher),
        (Icons.calendar_month_outlined, '教学周', _courseWeeks(course.weeks)),
      ];
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
          child: Column(
            key: const ValueKey('course-details-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  CampusIconBadge(
                    size: 52,
                    background: background,
                    foreground: foreground,
                    child: const Icon(Icons.school_outlined),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          semester.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              const Divider(height: 1),
              const SizedBox(height: 13),
              for (final (icon, label, value) in details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Row(
                    children: [
                      CampusIconBadge(
                        size: 38,
                        background: colors.surfaceContainerLow,
                        foreground: colors.primary,
                        child: Icon(icon, size: 20),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              value.isEmpty ? '未填写' : value,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (local)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      child: const Text('删除课程'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      child: const Text('编辑课程'),
                    ),
                  ],
                )
              else ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            '教务课表 · 由学校更新',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await editCourse(
      context,
      repository,
      semester,
      course: course,
      defaultDay: course.weekday,
    );
  } else if (action == 'delete' &&
      await confirmAction(context, '删除课程？', '会移除「${course.name}」的全部教学周安排。')) {
    try {
      await repository.deleteCourse(course.id);
      if (context.mounted) showMessage(context, '课程已删除');
    } catch (_) {
      if (context.mounted) showMessage(context, '删除失败，请重试');
    }
  }
}

String _courseWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toSet().toList()..sort();
  final ranges = <String>[];
  var start = sorted.first;
  var end = start;
  for (final week in sorted.skip(1)) {
    if (week != end + 1) {
      ranges.add(start == end ? '$start' : '$start–$end');
      start = week;
    }
    end = week;
  }
  ranges.add(start == end ? '$start' : '$start–$end');
  return '第 ${ranges.join('、')} 周';
}
