import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
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
    final restoring = ref.watch(
      schoolConnectionProvider.select(
        (connection) => connection.value == SchoolConnection.restoring,
      ),
    );
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight:
            72 + (MediaQuery.textScalerOf(context).scale(30) - 30).clamp(0, 36),
        actionsPadding: const EdgeInsets.only(right: 12),
        title: const FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: CampusPageTitle('成绩中心', eyebrow: 'NEUQ · ACADEMIC'),
        ),
        actions: [
          if (term != null) ...[
            SemesterMenu(
              semesters: semesters,
              selected: term,
              onChanged: (id) => setState(() => _semesterId = id),
            ),
            const SizedBox(width: 6),
          ],
          CampusRefreshButton(
            tooltip: '刷新教务成绩',
            isLoading: sourceReady && refresh.isLoading,
            onPressed: () {
              if (!sourceReady) {
                showMessage(context, '教务成绩查询待校方开通');
                return;
              }
              ref.invalidate(refreshKey);
            },
          ),
        ],
      ),
      floatingActionButton: term == null || fromSchool
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editGrade(context, repository, term),
              icon: const Icon(Icons.add),
              label: const Text('录入成绩'),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          6,
          16,
          term != null && !fromSchool ? 92 : 18,
        ),
        children: [
          SchoolSyncStatus(
            available: sourceReady,
            refresh: refresh,
            syncedAt: cache.value?.syncedAt,
            label: '教务成绩刷新',
            restoring: restoring,
            cacheError: cache.hasError,
            compactSuccessLabel: '教务成绩 · 已同步',
            reconnect: const SchoolReconnectButton(),
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
                          const CampusSectionHeading('学业概览'),
                          const SizedBox(height: 7),
                          _SummaryCard(
                            summary: GradeSummary(rows, scale),
                            scale: scale,
                            fromSchool: fromSchool,
                            semesterGpa: cache.value?.data.semesterGpa[term.id],
                            cumulativeGpa: cache.value?.data.cumulativeGpa,
                          ),
                          const SizedBox(height: 18),
                          const CampusSectionHeading('课程成绩'),
                          const SizedBox(height: 8),
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
    required this.fromSchool,
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
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final green = dark ? const Color(0xFFBFEBD2) : const Color(0xFF225E43);
    final passRate = summary.credits == 0
        ? null
        : (summary.passedCredits / summary.credits).clamp(0.0, 1.0);
    final gpa = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GpaTile(
          label: '学期 GPA',
          value: (semesterGpa ?? summary.gpa)?.toStringAsFixed(4) ?? '—',
          background: dark ? const Color(0xFF2C4065) : colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
          height: fromSchool ? 86 : 182,
        ),
        if (fromSchool) ...[
          const SizedBox(height: 10),
          _GpaTile(
            label: '累计 GPA',
            value: cumulativeGpa?.toStringAsFixed(4) ?? '未提供',
            background: const Color(0xFF202D46),
            foreground: Colors.white,
            height: 86,
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 260
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AverageTile(summary.average),
                    const SizedBox(height: 10),
                    gpa,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 52, child: _AverageTile(summary.average)),
                    const SizedBox(width: 10),
                    Expanded(flex: 48, child: gpa),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Card(
          color: dark ? const Color(0xFF234B3A) : const Color(0xFFD9EFE3),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 46,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('通过 / 登记学分'),
                        const SizedBox(height: 5),
                        Text(
                          '${_number(summary.passedCredits)} / ${_number(summary.credits)}',
                          style: const TextStyle(fontSize: 27),
                        ),
                      ],
                    ),
                  ),
                  if (passRate != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 54,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${(passRate * 100).round()}% 通过'),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: passRate,
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(5),
                              backgroundColor: dark
                                  ? const Color(0xFF38634C)
                                  : const Color(0xFFB7D9C7),
                              color: const Color(0xFF43886A),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (semesterGpa == null && summary.gpa != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '学期 GPA 按${scale.label}本科办法和当前成绩计算',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _AverageTile extends StatelessWidget {
  const _AverageTile(this.average);

  final double? average;

  @override
  Widget build(BuildContext context) => Card(
    color: campusBlue,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '平均分',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 13),
          SizedBox.square(
            dimension: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CircularProgressIndicator(
                    value: (average ?? 0) / 100,
                    strokeWidth: 8,
                    strokeAlign: CircularProgressIndicator.strokeAlignInside,
                    strokeCap: StrokeCap.round,
                    color: Colors.white,
                    backgroundColor: Colors.white30,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        Text(
                          average?.toStringAsFixed(1) ?? '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const Text(
                          '/ 100',
                          style: TextStyle(
                            color: Color(0xFFDCE7FF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'AVERAGE SCORE',
            style: TextStyle(color: Color(0xFFDCE7FF), fontSize: 9),
          ),
        ],
      ),
    ),
  );
}

class _GpaTile extends StatelessWidget {
  const _GpaTile({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
    required this.height,
  });

  final String label;
  final String value;
  final Color background;
  final Color foreground;
  final double height;

  @override
  Widget build(BuildContext context) => Card(
    color: background,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.13,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({required this.grade, required this.onTap});

  final Grade grade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 66),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        grade.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_number(grade.credit)} 学分',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          grade.scoreLabel,
                          style: TextStyle(
                            fontSize: grade.format == ScoreFormat.numeric
                                ? 24
                                : 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (grade.format == ScoreFormat.numeric) ...[
                        const SizedBox(height: 7),
                        LinearProgressIndicator(
                          value: grade.score / 100,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          color: colors.primary,
                          backgroundColor: colors.outlineVariant,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
