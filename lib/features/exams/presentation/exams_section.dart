import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';
import '../data/local_exams.dart';
import '../domain/exam.dart';

/// Manually managed exams. The section never talks to the school system, so
/// loading, editing and persistence all stay local.
class ExamSection extends ConsumerWidget {
  const ExamSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final now = campusNow();
    final exams = ref.watch(examsProvider);
    final repository = ref.watch(examRepositoryProvider);
    final subjects = currentSemesterSubjects(
      ref.watch(visibleTimetableProvider).value,
    );

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
          retry: () => ref.invalidate(examsProvider),
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
                        onEdit: () => showExamEditor(
                          context,
                          repository: repository,
                          subjects: subjects,
                          exam: exam,
                        ),
                        onDelete: () => _deleteExam(context, repository, exam),
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

Future<void> _deleteExam(
  BuildContext context,
  ExamRepository repository,
  Exam exam,
) async {
  if (!await confirmAction(context, '删除考试？', '移除「${exam.name}」的本地考试安排。')) {
    return;
  }
  try {
    await repository.delete(exam.id);
  } catch (_) {
    if (context.mounted) showMessage(context, '删除失败，请重试');
  }
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
    required this.onEdit,
    required this.onDelete,
  });

  final Exam exam;
  final bool finished;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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

List<String> currentSemesterSubjects(Timetable? timetable) {
  if (timetable == null || timetable.semesters.isEmpty) return const [];
  final term = currentSemester(timetable.semesters, campusNow());
  if (term == null) return const [];
  final seen = <String>{};
  final subjects = <String>[];
  for (final course in timetable.forSemester(term.id)) {
    final name = course.name.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    subjects.add(name);
  }
  return subjects;
}

Future<void> showExamEditor(
  BuildContext context, {
  required ExamRepository repository,
  required List<String> subjects,
  Exam? exam,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _ExamEditor(repository: repository, subjects: subjects, exam: exam),
);

class _ExamEditor extends StatefulWidget {
  const _ExamEditor({
    required this.repository,
    required this.subjects,
    this.exam,
  });

  final ExamRepository repository;
  final List<String> subjects;
  final Exam? exam;

  @override
  State<_ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends State<_ExamEditor> {
  static const _customSubject = '';
  late final TextEditingController _name;
  late final TextEditingController _room;
  late DateTime _date;
  late int _startMinute;
  late int _endMinute;
  late String _subject;

  bool get _custom => widget.subjects.isEmpty || _subject == _customSubject;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    final name = exam?.name.trim() ?? '';
    _subject = widget.subjects.contains(name) ? name : _customSubject;
    _name = TextEditingController(text: _custom ? name : '');
    _room = TextEditingController(text: exam?.room ?? '');
    if (exam == null) {
      _date = calendarDate(campusNow());
      _startMinute = 9 * 60;
      _endMinute = 11 * 60;
    } else {
      _date = exam.campusDate;
      _startMinute = exam.campusStart.hour * 60 + exam.campusStart.minute;
      _endMinute = exam.campusEnd.hour * 60 + exam.campusEnd.minute;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _save() {
    if (_endMinute <= _startMinute) {
      throw const FormatException('结束时间需晚于开始时间');
    }
    final name = _custom ? _name.text.trim() : _subject;
    if (name.isEmpty) throw const FormatException('请输入考试科目');
    return widget.repository.save(
      Exam(
        id: widget.exam?.id ?? const Uuid().v4(),
        name: name,
        at: campusInstant(_date, _startMinute),
        endsAt: campusInstant(_date, _endMinute),
        room: _room.text,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _date = calendarDate(picked));
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await pickCampusTime(
      context,
      start ? _startMinute : _endMinute,
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _startMinute = picked.hour * 60 + picked.minute;
        } else {
          _endMinute = picked.hour * 60 + picked.minute;
        }
      });
    }
  }

  InputDecoration _fieldDecoration(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.circular(12),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surfaceContainerHigh,
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RecordEditor(
      title: widget.exam == null ? '添加考试' : '编辑考试',
      onSave: _save,
      children: [
        if (widget.subjects.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const ValueKey('exam-subject-dropdown'),
            initialValue: _subject,
            isExpanded: true,
            decoration: _fieldDecoration(context, '考试科目'),
            items: [
              const DropdownMenuItem(
                value: _customSubject,
                child: Text('自定义科目'),
              ),
              for (final subject in widget.subjects)
                DropdownMenuItem(
                  value: subject,
                  child: Text(subject, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _subject = value;
                _name.clear();
              });
            },
          ),
        if (widget.subjects.isEmpty || _custom)
          TextFormField(
            key: const ValueKey('exam-subject-name'),
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: _fieldDecoration(
              context,
              widget.subjects.isEmpty ? '考试科目' : '自定义科目名称',
            ),
            validator: requireText,
          ),
        _ExamValueField(
          key: const ValueKey('exam-date'),
          label: '考试日期',
          value: '${_date.year}年${shortDate(_date)}',
          onTap: _pickDate,
        ),
        Row(
          children: [
            Expanded(
              child: _ExamValueField(
                key: const ValueKey('exam-start-time'),
                label: '开始时间',
                value: clockLabel(_startMinute),
                onTap: () => _pickTime(start: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ExamValueField(
                key: const ValueKey('exam-end-time'),
                label: '结束时间',
                value: clockLabel(_endMinute),
                onTap: () => _pickTime(start: false),
              ),
            ),
          ],
        ),
        TextFormField(
          key: const ValueKey('exam-room'),
          controller: _room,
          maxLength: 80,
          decoration: _fieldDecoration(context, '考试地点（选填）'),
        ),
      ],
    );
  }
}

class _ExamValueField extends StatelessWidget {
  const _ExamValueField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        button: true,
        label: '$label $value',
        excludeSemantics: true,
        child: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
