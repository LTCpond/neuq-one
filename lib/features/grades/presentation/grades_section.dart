import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/theme/app_theme.dart';
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
import 'grades_view.dart';
import 'semester_gpa_chart.dart';

/// Grades content embedded in the academic center. It owns the school refresh
/// status, semester scope and local grade editing, but no page chrome.
class GradesSection extends ConsumerWidget {
  const GradesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(timetableProvider);
    final semesters = ref.watch(gradeSemestersProvider);
    final selection = ref.watch(gradesSemesterSelectionProvider);
    final term = selectedGradeSemester(semesters, selection);
    final refreshKey = schoolRefreshProvider(SchoolDataSet.grades);
    final refresh = ref.watch(refreshKey);
    final sourceReady = ref.watch(schoolDataSourceProvider) != null;
    final restoring = ref.watch(
      schoolConnectionProvider.select(
        (connection) => connection.value == SchoolConnection.restoring,
      ),
    );
    final cache = ref.watch(schoolGradesCacheProvider);
    final gradeBook = cache.value?.data;
    final grades = ref.watch(gradesProvider);
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
    return ListView(
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
          retry: () => ref.invalidate(timetableStreamProvider),
          builder: (_) => semesters.isEmpty
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
                    final rows = [...?gradeBook?.grades, ...localGrades]
                        .where(
                          (grade) =>
                              !grade.demo &&
                              (term == null || grade.semesterId == term.id),
                        )
                        .toList();
                    final gradesBySemester = <String, List<Grade>>{};
                    for (final grade in rows) {
                      (gradesBySemester[grade.semesterId] ??= []).add(grade);
                    }
                    final visibleSemesters = term == null ? semesters : [term];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CampusSectionHeading('学业概览'),
                        const SizedBox(height: 7),
                        _SummaryCard(
                          summary: GradeSummary(rows, scale),
                          scale: scale,
                          fromSchool: fromSchool,
                          allSemesters: selection.allSemesters,
                          semesterGpa: gradeBook?.semesterGpa[term?.id],
                          cumulativeGpa: gradeBook?.cumulativeGpa,
                          semesterGpaTrend: [
                            if (selection.allSemesters)
                              for (final semester in semesters.reversed)
                                (
                                  semester: semester,
                                  gpa:
                                      gradeBook?.semesterGpa[semester.id] ??
                                      GradeSummary(
                                        gradesBySemester[semester.id] ??
                                            const [],
                                        scale,
                                      ).gpa,
                                ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const CampusSectionHeading('课程成绩'),
                        const SizedBox(height: 8),
                        if (rows.isEmpty)
                          StatePanel(
                            selection.allSemesters ? '暂无成绩' : '此学期暂无成绩',
                            switch ((selection.allSemesters, fromSchool)) {
                              (true, _) => '可同步教务成绩，或选择本地学期录入成绩。',
                              (_, true) => '当前教务快照无此学期成绩。',
                              _ => '录入成绩后可查看平均分、学分和绩点。',
                            },
                            icon: Icons.insights_outlined,
                          ),
                        for (final semester in visibleSemesters)
                          if (gradesBySemester[semester.id]
                              case final grades?) ...[
                            if (selection.allSemesters)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 8,
                                ),
                                child: CampusSectionHeading(semester.name),
                              ),
                            for (final grade in grades)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _GradeTile(
                                  grade: grade,
                                  onTap: () => _detail(
                                    context,
                                    grade,
                                    semester,
                                    scale,
                                    repository,
                                  ),
                                ),
                              ),
                          ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Semester scope and school refresh live in the academic center app bar.
class GradesActions extends ConsumerWidget {
  const GradesActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesters = ref.watch(gradeSemestersProvider);
    final selection = ref.watch(gradesSemesterSelectionProvider);
    final term = selectedGradeSemester(semesters, selection);
    final controller = ref.read(gradesSemesterSelectionProvider.notifier);
    final refreshKey = schoolRefreshProvider(SchoolDataSet.grades);
    final refresh = ref.watch(refreshKey);
    final sourceReady = ref.watch(schoolDataSourceProvider) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (semesters.isNotEmpty) ...[
          SemesterMenu(
            semesters: semesters,
            selected: term,
            onChanged: controller.selectSemester,
            onSelectAll: controller.selectAll,
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.scale,
    required this.fromSchool,
    required this.allSemesters,
    required this.semesterGpaTrend,
    this.semesterGpa,
    this.cumulativeGpa,
  });

  final GradeSummary summary;
  final GpaScale scale;
  final bool fromSchool;
  final bool allSemesters;
  final List<SemesterGpaPoint> semesterGpaTrend;
  final double? semesterGpa;
  final double? cumulativeGpa;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final credits = _CreditsTile(summary: summary, compact: allSemesters);
    final reportedGpa = allSemesters ? cumulativeGpa : semesterGpa;
    final gpaLabel = allSemesters
        ? (reportedGpa == null ? '累计 GPA' : '教务累计 GPA')
        : '学期 GPA';
    final gpa = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GpaTile(
          label: gpaLabel,
          value: (reportedGpa ?? summary.gpa)?.toStringAsFixed(4) ?? '—',
          background: dark ? const Color(0xFF2C4065) : colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
          height: fromSchool || allSemesters ? 86 : 182,
          fontSize: allSemesters ? 28 : 30,
        ),
        if (allSemesters) ...[
          const SizedBox(height: 10),
          credits,
        ] else if (fromSchool) ...[
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
        if (allSemesters)
          SemesterGpaChart(points: semesterGpaTrend)
        else
          credits,
        if (reportedGpa == null && summary.gpa != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$gpaLabel 按${scale.label}本科办法和当前成绩计算',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _CreditsTile extends StatelessWidget {
  const _CreditsTile({required this.summary, required this.compact});

  final GradeSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final passRate = summary.credits == 0
        ? null
        : (summary.passedCredits / summary.credits).clamp(0.0, 1.0);
    final value = Text(
      '${_number(summary.passedCredits)} / ${_number(summary.credits)}',
      style: TextStyle(
        fontSize: compact ? 23 : 27,
        height: compact ? 1.15 : null,
      ),
    );
    const label = Text('通过 / 登记学分');
    final progress = passRate == null
        ? null
        : LinearProgressIndicator(
            value: passRate,
            minHeight: compact ? 5 : 7,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: dark
                ? const Color(0xFF38634C)
                : const Color(0xFFB7D9C7),
            color: const Color(0xFF43886A),
          );
    return Card(
      color: dark ? const Color(0xFF234B3A) : const Color(0xFFD9EFE3),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 86 : 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: dark ? const Color(0xFFBFEBD2) : const Color(0xFF225E43),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            child: compact
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: value,
                            ),
                          ),
                          if (passRate != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${(passRate * 100).round()}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 7),
                        progress,
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 46,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 5), value],
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
                                progress!,
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
    this.fontSize = 30,
  });

  final String label;
  final String value;
  final Color background;
  final Color foreground;
  final double height;
  final double fontSize;

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
                  fontSize: fontSize,
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
    await showGradeEditor(context, repository, term, grade);
  } else if (action == 'delete' &&
      await confirmAction(context, '删除成绩？', '移除「${grade.name}」的本地成绩记录。')) {
    try {
      await repository.delete(grade.id);
    } catch (_) {
      if (context.mounted) showMessage(context, '删除失败，请重试');
    }
  }
}

Future<void> showGradeEditor(
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
