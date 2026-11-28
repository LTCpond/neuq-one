import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/database/school_data.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/data/schedule_providers.dart';
import '../../timetable/domain/schedule.dart';
import '../../timetable/presentation/schedule_details.dart';
import '../../timetable/presentation/timetable_palette.dart';
import '../data/local_exams.dart';
import '../domain/exam.dart';
import 'exam_editor.dart';

export 'exam_editor.dart' show currentSemesterSubjects, showExamEditor;

/// Manually managed exams. The section never talks to the school system, so
/// loading, editing and persistence all stay local.
typedef ExamOpenRequest = ({
  String id,
  String request,
  DateTime? date,
  bool conflictOnly,
});

class ExamSection extends ConsumerStatefulWidget {
  const ExamSection({super.key, this.target});

  final ExamOpenRequest? target;

  @override
  ConsumerState<ExamSection> createState() => _ExamSectionState();
}

class _ExamSectionState extends ConsumerState<ExamSection> {
  String? _handledRequest;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = ref.watch(scheduleClockProvider);
    final exams = ref.watch(examsProvider);
    final conflicts = ref.watch(scheduleConflictsProvider);
    final repository = ref.watch(examRepositoryProvider);
    final subjects = currentSemesterSubjects(
      ref.watch(visibleTimetableProvider).value,
    );
    final target = widget.target;
    final waitingForCourses =
        target?.conflictOnly == true &&
        ref.watch(
          schoolTimetableCacheProvider.select(
            (state) => state.isLoading && !state.hasValue,
          ),
        );
    if (target != null &&
        target.request != _handledRequest &&
        exams.hasValue &&
        !waitingForCourses) {
      _handledRequest = target.request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.target != target) return;
        final exam = ref
            .read(examsProvider)
            .value
            ?.where((exam) => exam.id == target.id)
            .firstOrNull;
        if (exam != null) {
          showScheduleExam(
            context,
            ref,
            [ScheduleEvent.exam(exam)],
            date: target.date,
            requireConflict: target.conflictOnly,
          );
        }
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Text(
          '该板块不从教务处同步数据，考试安排由学生手动添加。',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        DataPanel(
          value: exams,
          retry: () => ref.invalidate(examStreamProvider),
          builder: (rows) {
            if (rows.isEmpty) {
              return StatePanel(
                '暂无考试安排',
                '点击右上角添加考试，记录科目、日期、时间和地点。',
                icon: Icons.event_note_outlined,
              );
            }
            final groups = _groupByDate(rows);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, (date, dayExams)) in groups.indexed) ...[
                  Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 18),
                    child: _DateHeading(date: date, now: now),
                  ),
                  const SizedBox(height: 8),
                  for (final exam in dayExams)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ExamCard(
                        exam: exam,
                        finished: exam.isFinishedAt(now),
                        conflicts: conflicts.forExam(exam.id).toList(),
                        onConflict: () => showScheduleExam(context, ref, [
                          ScheduleEvent.exam(exam),
                        ]),
                        onEdit: () => showExamEditor(
                          context,
                          repository: repository,
                          subjects: subjects,
                          exam: exam,
                        ),
                        onDelete: () => deleteExam(context, repository, exam),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

List<(DateTime, List<Exam>)> _groupByDate(List<Exam> exams) {
  final grouped = <DateTime, List<Exam>>{};
  for (final exam in exams) {
    (grouped[exam.campusDate] ??= []).add(exam);
  }
  final dates = grouped.keys.toList()..sort();
  return [for (final date in dates) (date, grouped[date]!)];
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.date, required this.now});

  final DateTime date;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = calendarDate(now);
    final relative = date == today
        ? '今天 · '
        : date == today.add(const Duration(days: 1))
        ? '明天 · '
        : '';
    final year = date.year == today.year ? '' : '${date.year}年';
    return Semantics(
      header: true,
      child: Text(
        '$relative$year${shortDate(date)} ${weekdayLabel(date.weekday)}',
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({
    required this.exam,
    required this.finished,
    required this.conflicts,
    required this.onConflict,
    required this.onEdit,
    required this.onDelete,
  });

  final Exam exam;
  final bool finished;
  final List<ScheduleConflict> conflicts;
  final VoidCallback onConflict;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warning = examPalette(
      Theme.of(context).brightness,
      finished: finished,
    );
    final names = {
      for (final pair in conflicts)
        pair.exam.exam!.id == exam.id ? pair.other.name : pair.exam.name,
    };
    return Opacity(
      opacity: finished ? .62 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ExamMeta(
                            icon: Icons.schedule_rounded,
                            label: exam.campusTimeRange,
                          ),
                          if (exam.room.isNotEmpty)
                            _ExamMeta(
                              icon: Icons.place_outlined,
                              label: exam.room,
                            ),
                        ],
                      ),
                      if (names.isNotEmpty)
                        TextButton.icon(
                          onPressed: onConflict,
                          style: TextButton.styleFrom(
                            foregroundColor: warning.text,
                          ),
                          icon: const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                          ),
                          label: Text(
                            '时间冲突 · ${names.length == 1 ? names.single : '${names.length} 项日程'}',
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<_ExamAction>(
                  tooltip: '考试选项',
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ExamAction.edit:
                        onEdit();
                      case _ExamAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _ExamAction.edit, child: Text('编辑')),
                    PopupMenuItem(value: _ExamAction.delete, child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ExamAction { edit, delete }

class _ExamMeta extends StatelessWidget {
  const _ExamMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12, height: 1.25),
          ),
        ),
      ],
    );
  }
}

class ExamActions extends ConsumerWidget {
  const ExamActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final repository = ref.watch(examRepositoryProvider);
    final subjects = currentSemesterSubjects(
      ref.watch(visibleTimetableProvider).value,
    );
    return IconButton(
      tooltip: '添加考试',
      onPressed: () =>
          showExamEditor(context, repository: repository, subjects: subjects),
      icon: const Icon(Icons.add_rounded, size: 24),
      style: IconButton.styleFrom(
        foregroundColor: colors.primary,
        backgroundColor: colors.primaryContainer,
        padding: EdgeInsets.zero,
        fixedSize: const Size.square(campusToolbarControlSize),
        minimumSize: const Size.square(campusToolbarControlSize),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
