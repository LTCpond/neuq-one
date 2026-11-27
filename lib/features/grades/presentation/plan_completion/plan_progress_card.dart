import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/plan_completion.dart';
import 'plan_completion_model.dart';
import 'plan_status.dart';

/// The cobalt academic dashboard. Every number comes from the cached school
/// report; missing values are rendered as placeholders instead of being
/// replaced with invented zeros.
class PlanProgressCard extends StatelessWidget {
  const PlanProgressCard({super.key, required this.report});

  final PlanCompletion report;

  @override
  Widget build(BuildContext context) {
    final credits = report.credits;
    final completed = credits.completed;
    final required = credits.required;
    final ratio = required > 0 ? completed / required : null;
    final ringProgress = ratio == null ? 0.0 : ratio.clamp(0.0, 1.0).toDouble();
    final percentLabel = ratio == null ? null : formatPlanPercent(ratio);
    final metrics = <(String, String)>[
      (
        '必修学分',
        '${formatPlanCredits(report.compulsoryCredits.completed)}/'
            '${formatPlanCredits(report.compulsoryCredits.required)}',
      ),
      (
        '必修门数',
        '${formatPlanCredits(report.compulsoryCourses.completed)}/'
            '${formatPlanCredits(report.compulsoryCourses.required)}',
      ),
      (
        '校内专用绩点',
        report.internalGpa == null ? '—' : formatPlanGpa(report.internalGpa!),
      ),
    ];

    return Container(
      key: const ValueKey('plan-overview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: campusBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ringSize = (constraints.maxWidth * 0.31)
              .clamp(82.0, 108.0)
              .toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _OverviewSummary(
                      completed: completed,
                      required: required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CreditRing(
                    progress: ringProgress,
                    percentLabel: percentLabel,
                    size: ringSize,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: .18),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < metrics.length; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
                        child: _OverviewMetric(
                          label: metrics[index].$1,
                          value: metrics[index].$2,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.completed, required this.required});

  final double completed;
  final double required;

  @override
  Widget build(BuildContext context) {
    final hasPlan = required > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '学业修读进度',
          style: TextStyle(
            color: Color(0xFFDCE7FF),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatPlanCredits(completed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: planTabularFigures,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                hasPlan ? '/ ${formatPlanCredits(required)} 学分' : '学分',
                style: const TextStyle(
                  color: Color(0xFFDCE7FF),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text.rich(
          _gapMessage(required, completed),
          style: const TextStyle(
            color: Color(0xFFDCE7FF),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

TextSpan _gapMessage(double required, double completed) {
  if (required <= 0) {
    return const TextSpan(text: '计划总学分尚未提供');
  }
  final difference = required - completed;
  const epsilon = 0.000001;
  if (difference > epsilon) {
    return TextSpan(
      children: [
        const TextSpan(text: '距离计划要求还差 '),
        TextSpan(
          text: '${formatPlanCredits(difference)} 学分',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  if (difference < -epsilon) {
    return TextSpan(
      children: [
        const TextSpan(text: '已超过计划要求 '),
        TextSpan(
          text: '${formatPlanCredits(-difference)} 学分',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  return const TextSpan(text: '已达到计划学分要求');
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFDCE7FF),
          fontSize: 10.5,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 4),
      FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            height: 1.15,
            fontFeatures: planTabularFigures,
          ),
        ),
      ),
    ],
  );
}

class _CreditRing extends StatelessWidget {
  const _CreditRing({
    required this.progress,
    required this.percentLabel,
    required this.size,
  });

  final double progress;
  final String? percentLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final strokeWidth = (size * .09).clamp(6.0, 9.5).toDouble();
    return Semantics(
      container: true,
      label: percentLabel == null ? '学分完成进度暂无数据' : '学分完成进度 $percentLabel',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CreditRingPainter(
                    progress: progress,
                    strokeWidth: strokeWidth,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(size * .16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        percentLabel ?? '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          fontFeatures: planTabularFigures,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '暂计进度',
                        style: TextStyle(
                          color: Color(0xFFDCE7FF),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditRingPainter extends CustomPainter {
  const _CreditRingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white.withValues(alpha: .24),
    );
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    if (progress >= 1) {
      canvas.drawCircle(center, radius, arc);
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _CreditRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth;
}
