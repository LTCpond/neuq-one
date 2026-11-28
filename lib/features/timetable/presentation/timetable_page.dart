import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/local_files.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/school_sync_status.dart';
import '../../exams/data/local_exams.dart';
import '../data/local_timetable.dart';
import '../data/schedule_providers.dart';
import '../domain/icalendar.dart';
import '../domain/schedule.dart';
import '../domain/timetable.dart';
import 'semester_menu.dart';
import 'timetable_date.dart';
import 'timetable_editors.dart';
import 'course_details.dart';
import 'schedule_details.dart';
import 'week_timetable.dart';

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key, this.widgetCourse, this.widgetDate});

  final ({String id, String request})? widgetCourse;
  final ({DateTime date, String request})? widgetDate;

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
    final showExams = ref.watch(
      settingsProvider.select(
        (state) => state.value?.showExamsInTimetable ?? true,
      ),
    );
    final schedule = showExams ? ref.watch(scheduleEventsProvider) : null;
    final conflicts = showExams ? ref.watch(scheduleConflictsProvider) : null;
    final now = showExams ? ref.watch(scheduleClockProvider) : null;
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
    final target = widget.widgetDate;
    if (target != null &&
        _openedWidgetRequest != target.request &&
        (data.hasValue || data.hasError) &&
        (!showExams ||
            ref.watch(examsProvider).hasValue ||
            ref.watch(examsProvider).hasError)) {
      _openedWidgetRequest = target.request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.widgetDate == target) {
          showDateSchedule(context, ref, target.date, showExams: showExams);
        }
      });
    }

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
          ],
          if (semester != null || sourceReady)
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
                    if (semester != null) {
                      editSemester(context, repository, semester);
                    }
                  case 'export':
                    if (semester != null) {
                      _export(semester, data.value!.forSemester(semester.id));
                    }
                  case 'refresh':
                    ref.invalidate(refreshKey);
                  case 'date':
                    _pickDate(today, showExams);
                }
              },
              itemBuilder: (_) => [
                if (semester != null)
                  const PopupMenuItem(value: 'today', child: Text('回到本周')),
                if (local)
                  const PopupMenuItem(value: 'edit', child: Text('编辑当前学期')),
                if (sourceReady)
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !refresh.isLoading,
                    child: const Text('刷新教务课表'),
                  ),
                if (semester != null)
                  const PopupMenuItem(
                    value: 'export',
                    child: Text('导出 ICS 日历'),
                  ),
                const PopupMenuItem(value: 'date', child: Text('按日期查看日程')),
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
          if (semester != null && data.value != null)
            WeekTimetable(
              key: ValueKey((semester.id, semester.start, semester.weeks)),
              semester: semester,
              week: week,
              today: today,
              timetable: data.value!,
              schedule: schedule,
              conflicts: conflicts,
              now: now,
              onWeekChanged: (value) => setState(() => _week = value),
              onCourse: (course) =>
                  showCourseDetails(context, repository, semester, course),
              onExam: (events, date) =>
                  showScheduleExam(context, ref, events, date: date),
              onDate: (date) => showDateSchedule(
                context,
                ref,
                date,
                semesterId: semester.id,
                showExams: showExams,
              ),
            )
          else
            DataPanel(
              value: data,
              retry: () {
                ref.invalidate(timetableStreamProvider);
                ref.invalidate(schoolTimetableCacheStreamProvider);
              },
              builder: (_) => StatePanel(
                refresh.isLoading && sourceReady ? '正在读取课表' : '还没有课表',
                '打开课表页时会自动读取教务课表。',
                icon: Icons.calendar_month_outlined,
              ),
            ),
          if (schedule != null) ...[
            if (semester == null)
              TextButton.icon(
                onPressed: () => _pickDate(today, showExams),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('按日期查看日程'),
              ),
            _outsideTermExams(schedule, terms),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDate(DateTime today, bool showExams) async {
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (!mounted || date == null) return;
    await showDateSchedule(
      context,
      ref,
      calendarDate(date),
      showExams: showExams,
    );
  }

  Widget _outsideTermExams(ScheduleEvents schedule, List<Semester> terms) {
    final entries = [
      for (final event in schedule.exams)
        for (final date in {
          event.date,
          campusDateAt(
            event.time.end.subtract(const Duration(microseconds: 1)),
          ),
        })
          if (!terms.any((term) {
            final week = term.weekFor(date);
            // The seven-column grid also displays exams earlier in week one.
            return week != null || mondayOf(date) == mondayOf(term.start);
          }))
            (event: event, date: date),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(terms.isEmpty ? '考试安排' : '教学周外考试'),
        for (final entry in entries)
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: Text(entry.event.name),
            subtitle: Text(
              '${shortDate(entry.date)} · ${entry.event.timeLabel}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDateSchedule(context, ref, entry.date),
          ),
      ],
    );
  }
}
