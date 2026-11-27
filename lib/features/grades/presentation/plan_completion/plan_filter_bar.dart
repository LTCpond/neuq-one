import 'package:material_ui/material_ui.dart';

import 'plan_completion_model.dart';

/// Segmented filter with a shared track and a sliding cobalt selection thumb.
/// The control keeps the existing four local filter values.
class PlanFilterBar extends StatelessWidget {
  const PlanFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PlanCourseFilter selected;
  final ValueChanged<PlanCourseFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = DefaultTextStyle.of(context).style;
    final values = PlanCourseFilter.values;
    final selectedIndex = values.indexOf(selected);
    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / values.length;
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * segmentWidth,
                  top: 3,
                  bottom: 3,
                  width: segmentWidth,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      for (final filter in values)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: filter == selected,
                            child: InkWell(
                              key: ValueKey('plan-filter-${filter.name}'),
                              onTap: filter == selected
                                  ? null
                                  : () => onChanged(filter),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    style: baseStyle.copyWith(
                                      color: filter == selected
                                          ? colors.onPrimary
                                          : colors.onSurfaceVariant,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                    child: Text(filter.label),
                                  ),
                                ),
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
        },
      ),
    );
  }
}
