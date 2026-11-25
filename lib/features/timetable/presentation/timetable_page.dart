import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/local_files.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/school_sync_status.dart';
import '../data/local_timetable.dart';
import '../domain/icalendar.dart';
import '../domain/timetable.dart';
import 'semester_menu.dart';
import 'timetable_date.dart';
import 'timetable_editors.dart';
import 'week_timetable.dart';

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  String? _semesterId;
  int? _week;

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
    final cache = ref.watch(schoolTimetableCacheProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 62,
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
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
        children: [
          if (sourceReady && refresh.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (refresh.hasError || cache.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: SchoolSyncStatus(
                available: sourceReady,
                refresh: refresh,
                syncedAt: cache.value?.syncedAt,
                label: '教务课表同步',
                cacheError: cache.hasError,
                reconnect: SchoolReconnectButton(
                  onConnected: () => ref.invalidate(refreshKey),
                ),
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
                    semester: semester,
                    week: week,
                    today: today,
                    days: List.generate(
                      7,
                      (index) => timetable.on(semester, week, index + 1),
                    ),
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

Color _courseColor(Course course) =>
    courseColors[course.colorIndex % courseColors.length];

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
            color: _courseColor(course),
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
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      alignment: Alignment.center,
      title: Text(course.name),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${semester.name} · ${weekdayLabel(course.weekday)} ${course.time}',
          ),
          Text('教师  ${course.teacher.isEmpty ? '未填写' : course.teacher}'),
          Text('教室  ${course.room.isEmpty ? '未填写' : course.room}'),
          Text('教学周  ${course.weeks.join('、')}'),
          if (isSchoolRecord(course.id)) ...[
            const SizedBox(height: 10),
            const Text('教务课表 · 由学校更新'),
          ],
        ],
      ),
      actions: [
        if (!isSchoolRecord(course.id)) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('删除课程'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('编辑课程'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
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
