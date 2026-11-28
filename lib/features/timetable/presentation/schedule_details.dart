import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/screen.dart';
import '../../exams/data/local_exams.dart';
import '../../exams/domain/exam.dart';
import '../../exams/presentation/exam_editor.dart';
import '../data/local_timetable.dart';
import '../data/schedule_providers.dart';
import '../domain/schedule.dart';
import 'course_details.dart';
import 'timetable_palette.dart';

Future<void> showScheduleExam(
  BuildContext context,
  WidgetRef ref,
  List<ScheduleEvent> exams, {
  DateTime? date,
  bool requireConflict = false,
}) async {
  if (exams.isEmpty) return;
  final conflicts = ref.read(scheduleConflictsProvider);
  final pairs = exams
      .expand((event) => conflicts.forExam(event.exam!.id, date: date))
      .toSet();
  if (pairs.isEmpty) {
    if (!requireConflict) {
      await _showExamDetails(context, ref, exams.first.exam!);
    }
    return;
  }
  final first = pairs
      .map((pair) => pair.overlap.start)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final day = date ?? campusDateAt(first);
  final related = conflicts.relatedTo(exams, date: date);
  final hasCourses = related.any((event) => event.course != null);
  final hasExamConflict =
      related.where((event) => event.exam != null).length > 1;
  final picked = await _showScheduleSheet(
    context,
    title: '时间冲突',
    date: day,
    events: [
      ...related.where((event) => event.exam != null),
      ...related.where((event) => event.course != null),
    ],
    footer: [
      if (hasCourses) '考试与课程存在时间重叠，请自行确认原课程是否正常进行。',
      if (hasExamConflict) '考试之间存在时间重叠，请确认各场考试的安排。',
    ],
  );
  if (!context.mounted || picked == null) return;
  if (picked.exam case final exam?) {
    await _showExamDetails(context, ref, exam);
  } else {
    await _openCourse(context, ref, picked);
  }
}

Future<void> showDateSchedule(
  BuildContext context,
  WidgetRef ref,
  DateTime date, {
  String? semesterId,
  bool showExams = true,
}) async {
  final events = ref
      .read(scheduleEventsProvider)
      .on(date, semesterId: semesterId, showExams: showExams);
  if (events.length == 1 && events.single.course != null) {
    await _openCourse(context, ref, events.single);
    return;
  }
  final conflicts = ref.read(scheduleConflictsProvider);
  final picked = await _showScheduleSheet(
    context,
    title: '当日日程',
    date: date,
    events: events,
    conflicts: conflicts,
    emptyLabel: semesterId == null ? '当天没有日程' : '当天没有课程',
  );
  if (!context.mounted || picked == null) return;
  if (picked.exam != null) {
    await showScheduleExam(context, ref, [picked], date: date);
  } else {
    await _openCourse(context, ref, picked);
  }
}

Future<void> _openCourse(
  BuildContext context,
  WidgetRef ref,
  ScheduleEvent event,
) => showCourseDetails(
  context,
  ref.read(timetableRepositoryProvider),
  event.semester!,
  event.course!,
);

Future<ScheduleEvent?> _showScheduleSheet(
  BuildContext context, {
  required String title,
  required DateTime date,
  required List<ScheduleEvent> events,
  ScheduleConflicts? conflicts,
  String emptyLabel = '当天没有日程',
  List<String> footer = const [],
}) => showModalBottomSheet<ScheduleEvent>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        Text('${date.year}年${shortDate(date)} · ${weekdayLabel(date.weekday)}'),
        const SizedBox(height: 12),
        if (events.isEmpty) Text(emptyLabel),
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ScheduleTile(
              event: event,
              hasConflict:
                  event.exam != null &&
                  (conflicts?.forExam(event.exam!.id, date: date).isNotEmpty ??
                      false),
              onTap: () => Navigator.pop(context, event),
            ),
          ),
        for (final message in footer)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
  ),
);

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.event,
    required this.onTap,
    this.hasConflict = false,
  });

  final ScheduleEvent event;
  final VoidCallback onTap;
  final bool hasConflict;

  @override
  Widget build(BuildContext context) {
    final exam = event.exam;
    final palette = examPalette(
      Theme.of(context).brightness,
      finished: exam?.isFinishedAt(campusNow()) ?? false,
    );
    final (background, foreground) = exam != null
        ? (palette.background, palette.text)
        : courseBlockColors(context, event.colorIndex!);
    final details = [
      '${shortDate(event.date)} ${event.timeLabel}',
      event.room,
      event.teacher,
      if (hasConflict) '⚠ 时间冲突',
      exam == null ? '查看课程详情' : '查看考试详情',
    ].where((value) => value.isNotEmpty);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        textColor: foreground,
        iconColor: foreground,
        leading: Icon(
          exam == null ? Icons.school_outlined : Icons.event_note_outlined,
        ),
        title: Text(
          event.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details.join('\n')),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

Future<void> _showExamDetails(
  BuildContext context,
  WidgetRef ref,
  Exam exam,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(exam.name),
          Text(
            '${exam.campusDate.year}年${shortDate(exam.campusDate)} · ${weekdayLabel(exam.campusDate.weekday)}',
          ),
          const SizedBox(height: 6),
          Text(exam.campusTimeRange),
          if (exam.room.isNotEmpty) Text(exam.room),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'date'),
                child: const Text('查看当日日程'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: const Text('删除考试'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: const Text('编辑考试'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final repository = ref.read(examRepositoryProvider);
  switch (action) {
    case 'edit':
      await showExamEditor(
        context,
        repository: repository,
        subjects: currentSemesterSubjects(
          ref.read(visibleTimetableProvider).value,
        ),
        exam: exam,
      );
    case 'delete':
      await deleteExam(context, repository, exam);
    case 'date':
      await showDateSchedule(context, ref, exam.campusDate);
  }
}
