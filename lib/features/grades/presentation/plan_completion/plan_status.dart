import 'package:material_ui/material_ui.dart';

import 'plan_completion_model.dart';

/// Numerals use tabular figures so the many credit and score columns line up.
const planTabularFigures = <FontFeature>[FontFeature.tabularFigures()];

Color planToneColor(BuildContext context, PlanStatusTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final colors = Theme.of(context).colorScheme;
  return switch (tone) {
    PlanStatusTone.positive =>
      dark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
    PlanStatusTone.caution =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    PlanStatusTone.danger =>
      dark ? const Color(0xFFFCA5A5) : const Color(0xFFD14343),
    PlanStatusTone.info => colors.primary,
    PlanStatusTone.muted => colors.onSurfaceVariant,
  };
}

/// Plain semantic text. No status dot or background is used; the tone is the
/// only emphasis so statuses stay quiet in the list.
class PlanStatusText extends StatelessWidget {
  const PlanStatusText(
    this.label, {
    super.key,
    required this.tone,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w500,
    this.maxLines = 1,
  });

  final String label;
  final PlanStatusTone tone;
  final double fontSize;
  final FontWeight fontWeight;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: planToneColor(context, tone),
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.2,
    ),
  );
}

/// Small linear icon used at the start of every course row. The label is
/// exposed to assistive technology so status never relies on color alone.
class PlanStatusIcon extends StatelessWidget {
  const PlanStatusIcon(this.status, {super.key, this.size = 18});

  final PlanCourseStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status.kind) {
      PlanCourseStatusKind.passed => (Icons.check_rounded, status.shortLabel),
      PlanCourseStatusKind.inProgress => (
        Icons.schedule_rounded,
        status.shortLabel,
      ),
      PlanCourseStatusKind.failed => (
        Icons.error_outline_rounded,
        status.shortLabel,
      ),
      PlanCourseStatusKind.notStarted => (
        Icons.radio_button_unchecked_rounded,
        status.shortLabel,
      ),
      PlanCourseStatusKind.unknown => (
        Icons.help_outline_rounded,
        status.shortLabel,
      ),
    };
    return Icon(
      icon,
      size: size,
      color: planToneColor(context, status.tone),
      semanticLabel: label,
    );
  }
}

/// Category bars are always brand blue, independent of the audit state. The
/// audit state is communicated only by the small status text.
class PlanProgressBar extends StatelessWidget {
  const PlanProgressBar({super.key, required this.value, this.height = 4});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LinearProgressIndicator(
      value: value.clamp(0.0, 1.0).toDouble(),
      minHeight: height,
      borderRadius: BorderRadius.circular(height / 2),
      color: colors.primary,
      backgroundColor: colors.outlineVariant,
      semanticsLabel: '类别学分完成比例',
    );
  }
}
