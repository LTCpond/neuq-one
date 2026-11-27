import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/database/school_data.dart';
import '../../domain/plan_completion.dart';
import 'plan_completion_model.dart';
import 'plan_status.dart';
import 'plan_substitute_index.dart';

Future<void> showPlanCourseDetail(
  BuildContext context, {
  required PlanCourse course,
  required String categoryPath,
  required PlanGroupStatus? groupStatus,
  required String groupResult,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Theme.of(context).colorScheme.surface,
  barrierColor: const Color(0x55111B2F),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => _PlanCourseDetailSheet(
    course: course,
    categoryPath: categoryPath,
    groupStatus: groupStatus,
    groupResult: groupResult,
  ),
);

class _PlanCourseDetailSheet extends ConsumerStatefulWidget {
  const _PlanCourseDetailSheet({
    required this.course,
    required this.categoryPath,
    required this.groupStatus,
    required this.groupResult,
  });

  final PlanCourse course;
  final String categoryPath;
  final PlanGroupStatus? groupStatus;
  final String groupResult;

  @override
  ConsumerState<_PlanCourseDetailSheet> createState() =>
      _PlanCourseDetailSheetState();
}

class _PlanCourseDetailSheetState
    extends ConsumerState<_PlanCourseDetailSheet> {
  var _syncing = false;
  var _syncFailed = false;

  Future<void> _syncGrades() async {
    if (_syncing || ref.read(schoolDataSourceProvider) == null) return;
    setState(() {
      _syncing = true;
      _syncFailed = false;
    });
    try {
      final refresh = ref.refresh(
        schoolRefreshProvider(SchoolDataSet.grades).future,
      );
      await refresh;
    } catch (_) {
      if (mounted) setState(() => _syncFailed = true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final substituteIndex = ref.watch(planSubstituteIndexProvider);
    final status = substituteIndex.statusFor(widget.course);
    final match = substituteIndex.matchFor(widget.course);
    final grades = ref.watch(schoolGradesCacheProvider);
    final canSync = ref.watch(schoolDataSourceProvider) != null;
    final remark = PlanCourseRemark.parse(widget.course.remark);
    final score = _score(widget.course.score);
    final auditLabel = widget.groupStatus?.label ?? '教务未标注';
    final auditRaw = _auditRaw(widget.groupResult, auditLabel);
    final extraRemark = _extraRemark(remark);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            key: const ValueKey('plan-course-detail'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.categoryPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.course.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: PlanStatusText(
                  status.label,
                  tone: status.tone,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 6),
              _PlanDetailRow(label: '课程编号', value: widget.course.code),
              _PlanDetailRow(
                label: '课程性质',
                value: widget.course.compulsory ? '必修' : '选修',
              ),
              _PlanDetailRow(label: '课程所属类别', value: widget.categoryPath),
              _PlanDetailRow(
                label: '计划修读学期',
                value: formatPlanSemester(widget.course.semester),
              ),
              _PlanDetailRow(
                label: '计划学分',
                value:
                    '${formatPlanCredits(widget.course.credits.required)} 学分',
              ),
              _PlanDetailRow(
                label: status.kind == PlanCourseStatusKind.inProgress
                    ? '暂计完成学分'
                    : '完成学分',
                value:
                    '${formatPlanCredits(widget.course.credits.completed)} 学分',
              ),
              _PlanDetailRow(
                label: '课程成绩',
                value: score ?? '未提供',
                muted: score == null,
              ),
              _PlanDetailRow(
                label: '修读状态',
                value: status.label,
                color: planToneColor(context, status.tone),
              ),
              _PlanDetailRow(
                label: '审核状态',
                value: auditLabel,
                secondary: auditRaw,
              ),
              if (extraRemark != null)
                _PlanDetailRow(label: '教务备注', value: extraRemark),
              if (remark?.substitute case final substitute?) ...[
                const SizedBox(height: 10),
                _SubstitutionPanel(
                  courseName: widget.course.name,
                  substitute: stripPlanCourseCode(substitute),
                  status: status,
                  match: match,
                  gradesLoading: grades.isLoading,
                  hasGradeData: grades.value?.data != null,
                  gradesError: grades.hasError,
                  canSync: canSync,
                  syncing: _syncing,
                  syncFailed: _syncFailed,
                  onSync: _syncGrades,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '学分与审核结果以教务系统为准。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanDetailRow extends StatelessWidget {
  const _PlanDetailRow({
    required this.label,
    required this.value,
    this.secondary,
    this.muted = false,
    this.color,
  });

  final String label;
  final String value;
  final String? secondary;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: muted
                        ? colors.onSurfaceVariant
                        : color ?? colors.onSurface,
                    fontSize: 14,
                    fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                if (secondary != null && secondary!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondary!,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubstitutionPanel extends StatelessWidget {
  const _SubstitutionPanel({
    required this.courseName,
    required this.substitute,
    required this.status,
    required this.match,
    required this.gradesLoading,
    required this.hasGradeData,
    required this.gradesError,
    required this.canSync,
    required this.syncing,
    required this.syncFailed,
    required this.onSync,
  });

  final String courseName;
  final String substitute;
  final PlanCourseStatus status;
  final PlanSubstituteMatch? match;
  final bool gradesLoading;
  final bool hasGradeData;
  final bool gradesError;
  final bool canSync;
  final bool syncing;
  final bool syncFailed;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 17, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '替代课程',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SubstitutionLine(label: '原计划课程', value: courseName),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Icon(Icons.south_rounded, size: 15, color: colors.primary),
          ),
          _SubstitutionLine(label: '实际替代课程', value: substitute),
          const SizedBox(height: 10),
          _SubstituteGradeInfo(
            status: status,
            match: match,
            gradesLoading: gradesLoading,
            hasGradeData: hasGradeData,
            gradesError: gradesError,
            canSync: canSync,
            syncing: syncing,
            syncFailed: syncFailed,
            onSync: onSync,
          ),
        ],
      ),
    );
  }
}

class _SubstituteGradeInfo extends StatelessWidget {
  const _SubstituteGradeInfo({
    required this.status,
    required this.match,
    required this.gradesLoading,
    required this.hasGradeData,
    required this.gradesError,
    required this.canSync,
    required this.syncing,
    required this.syncFailed,
    required this.onSync,
  });

  final PlanCourseStatus status;
  final PlanSubstituteMatch? match;
  final bool gradesLoading;
  final bool hasGradeData;
  final bool gradesError;
  final bool canSync;
  final bool syncing;
  final bool syncFailed;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final inProgress = status.kind == PlanCourseStatusKind.inProgress;
    if (match case final matched?) {
      final semester = matched.semesterLabel;
      final detail = [
        matched.creditLabel,
        '成绩 ${matched.scoreLabel}',
        ?semester,
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '替代课程成绩',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          if (!matched.isPassing) ...[
            const SizedBox(height: 4),
            Text(
              inProgress ? '该替代课程成绩未通过或为缓考，仍按在读处理。' : '该替代课程成绩未通过或为缓考。',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      );
    }

    if (syncing) {
      return Text(
        '正在同步成绩记录…',
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          height: 1.35,
        ),
      );
    }
    if (gradesLoading) {
      return Text(
        '正在读取成绩记录…',
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          height: 1.35,
        ),
      );
    }

    final reason = gradesError
        ? '成绩缓存不可用'
        : hasGradeData
        ? '未找到该替代课程的成绩记录'
        : '尚未同步成绩';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          inProgress ? '$reason，仍按在读处理。' : '$reason。',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (syncFailed) ...[
          const SizedBox(height: 3),
          Text(
            '成绩同步失败。',
            style: TextStyle(
              color: planToneColor(context, PlanStatusTone.danger),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
        if (canSync)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: syncing ? null : onSync,
              icon: syncing
                  ? SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : Icon(Icons.sync_rounded, size: 16, color: colors.primary),
              label: Text(syncFailed ? '重试' : '同步成绩'),
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '当前无法同步成绩。',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

class _SubstitutionLine extends StatelessWidget {
  const _SubstitutionLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

String? _score(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty || const {'-', '--', '—'}.contains(text)
      ? null
      : text;
}

String? _auditRaw(String raw, String label) {
  final text = raw.trim();
  if (text.isEmpty || text == label) return null;
  return '教务原文：$text';
}

String? _extraRemark(PlanCourseRemark? remark) {
  if (remark == null) return null;
  if (remark.substitute == null) return remark.raw;
  final remainder = remark.raw
      .replaceFirst(RegExp(r'替代课程\s*[：:]\s*([^；;。\n]+)'), '')
      .trim();
  return remainder.isEmpty ? null : remark.raw;
}
