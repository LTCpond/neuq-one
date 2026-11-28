import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../../timetable/data/schedule_providers.dart';
import '../../timetable/domain/schedule.dart';
import '../../timetable/domain/timetable.dart';
import '../../timetable/presentation/timetable_palette.dart';
import '../data/local_exams.dart';
import '../domain/exam.dart';

Future<void> deleteExam(
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

class _ExamEditor extends ConsumerStatefulWidget {
  const _ExamEditor({
    required this.repository,
    required this.subjects,
    this.exam,
  });

  final ExamRepository repository;
  final List<String> subjects;
  final Exam? exam;

  @override
  ConsumerState<_ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends ConsumerState<_ExamEditor> {
  static const _customSubject = '';
  late final TextEditingController _name;
  late final TextEditingController _room;
  late DateTime _date;
  late int _startMinute;
  late int _endMinute;
  late String _subject;
  late final _id = widget.exam?.id ?? const Uuid().v4();

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

  ScheduleInterval get _time => ScheduleInterval(
    campusInstant(_date, _startMinute),
    campusInstant(_date, _endMinute),
  );

  String _conflictKey(ScheduleEvent event) =>
      '${event.id}:${event.time.start.microsecondsSinceEpoch}:${event.time.end.microsecondsSinceEpoch}';

  Future<void> _save(List<ScheduleEvent> preview) async {
    final time = _time;
    if (examTimeValidation(time.start, time.end) case final error?) {
      throw FormatException(error);
    }
    final name = _custom ? _name.text.trim() : _subject;
    if (name.isEmpty) throw const FormatException('请输入考试科目');
    final shown = preview.map(_conflictKey).toSet();
    while (mounted) {
      final latest = ref
          .read(scheduleEventsProvider)
          .conflictsForDraft(time, excludeExamId: _id);
      if (latest.every((event) => shown.contains(_conflictKey(event)))) break;
      if (!await confirmAction(
        context,
        '考试时间冲突已更新',
        latest
            .map(
              (event) =>
                  '${event.name} · ${shortDate(event.date)} ${event.timeLabel}',
            )
            .join('\n'),
        label: '仍然保存',
      )) {
        throw const FormatException('请核对最新冲突提示后再保存');
      }
      shown.addAll(latest.map(_conflictKey));
    }
    if (!mounted) return;
    await widget.repository.save(
      Exam(
        id: _id,
        name: name,
        at: time.start,
        endsAt: time.end,
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
    final schedule = ref.watch(scheduleEventsProvider);
    final conflicts = schedule.conflictsForDraft(_time, excludeExamId: _id);
    final courseCheck = ref.watch(scheduleCourseCheckProvider);
    final examCheck = ref.watch(
      examsProvider.select((state) => state.hasError),
    );
    final palette = examPalette(Theme.of(context).brightness);
    return RecordEditor(
      title: widget.exam == null ? '添加考试' : '编辑考试',
      onSave: () => _save(conflicts),
      saveLabel: conflicts.isEmpty ? '保存' : '仍然保存',
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
        if (conflicts.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: palette.text),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠ 存在时间冲突',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final event in conflicts) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${event.name} · ${shortDate(event.date)} ${event.timeLabel}',
                      ),
                      if (event.room.isNotEmpty || event.teacher.isNotEmpty)
                        Text(
                          [
                            event.room,
                            event.teacher,
                          ].where((value) => value.isNotEmpty).join(' · '),
                        ),
                    ],
                    const SizedBox(height: 6),
                    const Text('仍可保存考试，请确认相关日程。'),
                  ],
                ),
              ),
            ),
          ),
        if (courseCheck.message case final message?)
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (examCheck)
          Text(
            '本地考试暂时无法完整读取，可能遗漏考试之间的冲突。',
            style: Theme.of(context).textTheme.bodySmall,
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
