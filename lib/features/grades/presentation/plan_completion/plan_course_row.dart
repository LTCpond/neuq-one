import 'package:material_ui/material_ui.dart';

import '../../domain/plan_completion.dart';
import 'plan_completion_model.dart';
import 'plan_status.dart';

/// A light two-column course row: status icon and course identity on the left,
/// a quiet score/status label and a small affordance on the right. Audit and
/// credit details live in the course sheet.
class PlanCourseRow extends StatelessWidget {
  const PlanCourseRow({
    super.key,
    required this.nodeKey,
    required this.courseIndex,
    required this.course,
    required this.status,
    required this.indent,
    required this.onTap,
  });

  final String nodeKey;
  final int courseIndex;
  final PlanCourse course;
  final PlanCourseStatus status;
  final double indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final score = _score(course.score);
    final numericScore = score == null ? false : double.tryParse(score) != null;
    final semester = course.semester;
    final subtitle = [
      if (semester != null && semester.trim().isNotEmpty)
        formatPlanSemester(semester),
      course.compulsory ? '必修' : '选修',
      '${formatPlanCredits(course.credits.required)} 学分',
    ].join(' · ');

    return InkWell(
      key: ValueKey('plan-course-$nodeKey-$courseIndex-${course.code}'),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PlanStatusIcon(status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _RightLabel(
                  score: score,
                  numeric: numericScore,
                  status: status,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: colors.onSurfaceVariant.withValues(alpha: .65),
            ),
          ],
        ),
      ),
    );
  }
}

class _RightLabel extends StatelessWidget {
  const _RightLabel({
    required this.score,
    required this.numeric,
    required this.status,
  });

  final String? score;
  final bool numeric;
  final PlanCourseStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (score != null) {
      return Text(
        score!,
        maxLines: 1,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: numeric ? 17 : 15.5,
          fontWeight: FontWeight.w500,
          height: 1.1,
          fontFeatures: numeric ? planTabularFigures : null,
        ),
      );
    }
    return Text(
      status.shortLabel,
      maxLines: 1,
      style: TextStyle(
        color: planToneColor(context, status.tone),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.1,
      ),
    );
  }
}

String? _score(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty || const {'-', '--', '—'}.contains(text)
      ? null
      : text;
}
