import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/school_sync_status.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';
import '../../timetable/presentation/semester_menu.dart';
import '../../timetable/presentation/timetable_editors.dart';
import '../data/local_grades.dart';
import '../domain/grades.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  String? _semesterId;

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(timetableProvider);
    final refreshKey = schoolRefreshProvider(SchoolDataSet.grades);
    final refresh = ref.watch(refreshKey);
    final sourceReady = ref.watch(schoolDataSourceProvider) != null;
    final cache = ref.watch(schoolGradesCacheProvider);
    final grades = ref.watch(gradesProvider);
    final semesters = [
      ...?cache.value?.data.semesters,
      ...?terms.value?.semesters,
    ]..sort((a, b) => b.start.compareTo(a.start));
    final term =
        semesters.where((entry) => entry.id == _semesterId).firstOrNull ??
        currentSemester(semesters, campusNow());
    final fromSchool = term != null && isSchoolRecord(term.id);
    final repository = ref.watch(gradesRepositoryProvider);
    final admissionYear = ref
        .watch(schoolSessionProvider)
        .asData
        ?.value
        ?.admissionYear;
    final scale = GpaScale.forAdmission(
      admissionYear ?? ref.watch(settingsProvider).value?.admissionYear ?? 2025,
    );
    return CampusScreen(
      title: '成绩中心',
      eyebrow: '东秦本科绩点',
      actions: [
        IconButton(
          tooltip: '刷新教务成绩',
          icon: const Icon(Icons.refresh),
          onPressed: sourceReady && refresh.isLoading
              ? null
              : () {
                  if (!sourceReady) {
                    showMessage(context, '教务成绩查询待校方开通');
                    return;
                  }
                  ref.invalidate(refreshKey);
                },
        ),
        if (term != null)
          SemesterMenu(
            semesters: semesters,
            selected: term,
            onChanged: (id) => setState(() => _semesterId = id),
          ),
      ],
      floatingActionButton: term == null || fromSchool
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editGrade(context, repository, term),
              icon: const Icon(Icons.add),
              label: const Text('录入成绩'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
        children: [
          SchoolSyncStatus(
            available: sourceReady,
            refresh: refresh,
            syncedAt: cache.value?.syncedAt,
            label: '教务成绩刷新',
            cacheError: cache.hasError,
            reconnect: SchoolReconnectButton(
              onConnected: () => ref.invalidate(refreshKey),
            ),
          ),
          const SizedBox(height: 10),
          DataPanel(
            value: terms,
            retry: () => ref.invalidate(timetableProvider),
            builder: (_) => term == null
                ? StatePanel(
                    '先创建一个学期',
                    '课表和成绩共享学期设置。',
                    icon: Icons.school_outlined,
                    action: FilledButton(
                      onPressed: () => editSemester(
                        context,
                        ref.read(timetableRepositoryProvider),
                      ),
                      child: const Text('新增学期'),
                    ),
                  )
                : DataPanel(
                    value: grades,
                    retry: () => ref.invalidate(gradesProvider),
                    builder: (localGrades) {
                      final real = [
                        ...?cache.value?.data.grades,
                        ...localGrades,
                      ].where((grade) => !grade.demo).toList();
                      final rows = real
                          .where((grade) => grade.semesterId == term.id)
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryCard(
                            summary: GradeSummary(rows, scale),
                            scale: scale,
                            fromSchool: fromSchool,
                            semesterGpa: cache.value?.data.semesterGpa[term.id],
                            cumulativeGpa: cache.value?.data.cumulativeGpa,
                          ),
                          const SectionTitle('课程成绩'),
                          if (rows.isEmpty)
                            StatePanel(
                              '此学期暂无成绩',
                              isSchoolRecord(term.id)
                                  ? '当前教务快照无此学期成绩。'
                                  : '录入成绩后可查看平均分、学分和绩点。',
                              icon: Icons.insights_outlined,
                            ),
                          for (final grade in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _GradeTile(
                                grade: grade,
                                onTap: () => _detail(
                                  context,
                                  grade,
                                  term,
                                  scale,
                                  repository,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.scale,
    this.fromSchool = false,
    this.semesterGpa,
    this.cumulativeGpa,
  });
  final GradeSummary summary;
  final GpaScale scale;
  final bool fromSchool;
  final double? semesterGpa;
  final double? cumulativeGpa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学业概览', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                _metric(
                  context,
                  '平均分',
                  summary.average?.toStringAsFixed(1) ?? '—',
                ),
                _metric(
                  context,
                  '通过 / 登记学分',
                  '${_number(summary.passedCredits)} / ${_number(summary.credits)}',
                ),
                _metric(
                  context,
                  '学期 GPA',
                  (semesterGpa ?? summary.gpa)?.toStringAsFixed(4) ?? '—',
                ),
                if (fromSchool)
                  _metric(
                    context,
                    '累计 GPA',
                    cumulativeGpa?.toStringAsFixed(4) ?? '未提供',
                  ),
              ],
            ),
            if (semesterGpa == null && summary.gpa != null) ...[
              const SizedBox(height: 8),
              Text(
                '学期 GPA 按${scale.label}本科办法和当前成绩计算',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
      Text(label),
    ],
  );
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({required this.grade, this.onTap});
  final Grade grade;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(grade.name),
      subtitle: Text('${_number(grade.credit)} 学分'),
      trailing: Text(
        grade.scoreLabel,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      onTap: onTap,
    ),
  );
}

String _number(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

Future<void> _detail(
  BuildContext context,
  Grade grade,
  Semester term,
  GpaScale scale,
  GradesRepository repository,
) async {
  final fromSchool = isSchoolRecord(grade.id);
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(grade.name),
      content: Text(
        '${term.name}\n${_number(grade.credit)} 学分\n成绩 ${grade.scoreLabel}'
        '${fromSchool ? '' : '\n本地计算绩点 ${scale.pointsFor(grade)?.toStringAsFixed(scale == GpaScale.current ? 4 : 2) ?? '不纳入'}'}',
      ),
      actions: fromSchool
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: const Text('删除'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: const Text('编辑'),
              ),
            ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await _editGrade(context, repository, term, grade);
  } else if (action == 'delete' &&
      await confirmAction(context, '删除成绩？', '移除「${grade.name}」的本地成绩记录。')) {
    try {
      await repository.delete(grade.id);
    } catch (_) {
      if (context.mounted) showMessage(context, '删除失败，请重试');
    }
  }
}

Future<void> _editGrade(
  BuildContext context,
  GradesRepository repository,
  Semester semester, [
  Grade? grade,
]) {
  var name = grade?.name ?? '';
  var credit = grade?.credit ?? 0;
  var score = grade?.score ?? 0;
  var kind = grade?.kind ?? GradeKind.required;
  var format = grade?.format ?? ScoreFormat.numeric;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => RecordEditor(
        title: grade == null ? '录入成绩' : '编辑成绩',
        onSave: () => repository.save(
          Grade(
            id: grade?.id ?? const Uuid().v4(),
            semesterId: semester.id,
            name: name,
            credit: credit,
            score: score,
            kind: kind,
            format: format,
          ),
        ),
        children: [
          TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '课程名称'),
            validator: requireText,
            onSaved: (value) => name = value!.trim(),
          ),
          TextFormField(
            initialValue: grade == null ? null : _number(credit),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '学分'),
            validator: (value) =>
                double.tryParse(value ?? '') == null ? '请输入数字' : null,
            onSaved: (value) => credit = double.parse(value!),
          ),
          if (format == ScoreFormat.numeric)
            TextFormField(
              initialValue: grade == null ? null : _number(score),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '成绩（百分制）'),
              validator: (value) =>
                  double.tryParse(value ?? '') == null ? '请输入数字' : null,
              onSaved: (value) => score = double.parse(value!),
            ),
          DropdownButtonFormField<ScoreFormat>(
            initialValue: format,
            decoration: const InputDecoration(labelText: '记分方式'),
            items: [
              for (final entry in ScoreFormat.values)
                DropdownMenuItem(value: entry, child: Text(entry.label)),
            ],
            onChanged: (value) => update(() {
              format = value!;
              score = format.choices.firstOrNull?.$2 ?? 0;
            }),
          ),
          if (format.choices.isNotEmpty)
            DropdownButtonFormField<double>(
              key: ValueKey(format),
              initialValue: score,
              decoration: const InputDecoration(labelText: '成绩等级'),
              items: [
                for (final (label, points) in format.choices)
                  DropdownMenuItem(value: points, child: Text(label)),
              ],
              onChanged: (value) => score = value!,
            ),
          DropdownButtonFormField<GradeKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: '课程属性'),
            items: [
              for (final option in GradeKind.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (value) => kind = value!,
          ),
        ],
      ),
    ),
  );
}
