import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../data/local_exams.dart';
import '../domain/exams.dart';

class ExamsPage extends ConsumerWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(examRepositoryProvider);
    return CampusScreen(
      title: '考试安排',
      eyebrow: '本地记录',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editExam(context, repository),
        icon: const Icon(Icons.add),
        label: const Text('添加考试'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
        children: [
          DataPanel(
            value: ref.watch(examsProvider),
            retry: () => ref.invalidate(examsProvider),
            builder: (exams) => exams.isEmpty
                ? const StatePanel(
                    '暂无考试记录',
                    '手动添加后，最近一场考试会显示在首页。',
                    icon: Icons.assignment_outlined,
                  )
                : Column(
                    children: [
                      for (final exam in exams)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              title: Text(exam.name),
                              subtitle: Text(_examWhen(exam)),
                              onTap: () => _editExam(context, repository, exam),
                              trailing: IconButton(
                                tooltip: '删除${exam.name}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (!await confirmAction(
                                    context,
                                    '删除考试？',
                                    '移除「${exam.name}」的本地考试安排。',
                                  )) {
                                    return;
                                  }
                                  try {
                                    await repository.delete(exam.id);
                                  } catch (_) {
                                    if (context.mounted) {
                                      showMessage(context, '删除失败，请重试');
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _examWhen(Exam exam) {
  final time = exam.campusTime;
  return '${time.year}年${shortDate(time)} ${clockLabel(time.hour * 60 + time.minute)}${exam.room.isEmpty ? '' : ' · ${exam.room}'}';
}

Future<void> _editExam(
  BuildContext context,
  ExamRepository repository, [
  Exam? exam,
]) {
  final now = exam?.campusTime ?? campusNow();
  var date = calendarDate(now);
  var minute = exam == null ? 540 : now.hour * 60 + now.minute;
  var name = exam?.name ?? '';
  var room = exam?.room ?? '';
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => RecordEditor(
        title: exam == null ? '添加考试' : '编辑考试',
        onSave: () => repository.save(
          Exam(
            id: exam?.id ?? const Uuid().v4(),
            name: name,
            room: room,
            at: date.add(Duration(minutes: minute)).subtract(campusOffset),
          ),
        ),
        children: [
          TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '考试名称'),
            validator: requireText,
            onSaved: (value) => name = value!.trim(),
          ),
          TextFormField(
            initialValue: room,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '考场（选填）'),
            onSaved: (value) => room = value!.trim(),
          ),
          ListTile(
            title: Text('${date.year}年${shortDate(date)}'),
            subtitle: const Text('考试日期'),
            leading: const Icon(Icons.event_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked != null && context.mounted) {
                setDialogState(() => date = calendarDate(picked));
              }
            },
          ),
          ListTile(
            title: Text(clockLabel(minute)),
            subtitle: const Text('考试时间（北京时间）'),
            leading: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await pickCampusTime(context, minute);
              if (picked != null && context.mounted) {
                setDialogState(() => minute = picked.hour * 60 + picked.minute);
              }
            },
          ),
        ],
      ),
    ),
  );
}
