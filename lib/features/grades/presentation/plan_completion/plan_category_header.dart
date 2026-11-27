import 'package:material_ui/material_ui.dart';

import 'plan_completion_model.dart';
import 'plan_status.dart';

/// Header shared by top-level categories and their subgroups. Category-level
/// totals come from the school, but aggregate completion is intentionally not
/// rendered because the endpoint only publishes reliable completion for leaves.
class PlanCategoryHeader extends StatelessWidget {
  const PlanCategoryHeader({
    super.key,
    required this.node,
    required this.isChild,
    required this.expanded,
    required this.canExpand,
    required this.onTap,
  });

  final PlanCategoryNode node;
  final bool isChild;
  final bool expanded;
  final bool canExpand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = node.isExtra
        ? null
        : resolvePlanGroupStatus(
            node.credits,
            node.result,
            allowComputedGap: !node.isAggregate && node.courses.isNotEmpty,
          );
    final progress = planCategoryProgress(node);
    final statusWidget = _statusWidget(context, status, isChild: isChild);
    final indent = isChild ? 28.0 : 16.0;

    return Semantics(
      button: canExpand,
      expanded: canExpand ? expanded : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            indent,
            isChild ? 10 : 12,
            16,
            isChild ? 8 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isChild ? 15 : 16,
                        fontWeight: isChild ? FontWeight.w500 : FontWeight.w600,
                        height: 1.25,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant.withValues(alpha: .8),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: isChild ? 3 : 5),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    formatPlanCategoryCredits(node),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                      fontFeatures: planTabularFigures,
                    ),
                  ),
                  ?statusWidget,
                ],
              ),
              if (progress != null) ...[
                SizedBox(height: isChild ? 6 : 8),
                PlanProgressBar(value: progress, height: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget? _statusWidget(
  BuildContext context,
  PlanGroupStatus? status, {
  required bool isChild,
}) {
  final label = status?.label;
  if (label == null || status == null) return null;
  if (isChild && status.tone == PlanStatusTone.positive) {
    return Icon(
      Icons.check_rounded,
      size: 15,
      color: planToneColor(context, PlanStatusTone.positive),
      semanticLabel: label,
    );
  }
  return PlanStatusText(
    label,
    tone: status.tone,
    fontSize: 12,
    fontWeight: isChild ? FontWeight.w400 : FontWeight.w500,
  );
}
