import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Equal-width segmented control used by campus filters such as the classroom
/// building picker and the academic center sections.
///
/// The selected segment uses the brand cobalt blue, while the track follows the
/// Material 3 high surface container so both light and dark themes stay legible.
class CampusSegmentedPicker<T> extends StatelessWidget {
  const CampusSegmentedPicker({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  }) : assert(values.length > 0, '至少需要一个选项');

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final value in values)
              Expanded(
                child: _Segment(
                  label: labelOf(value),
                  selected: value == selected,
                  onTap: () => onChanged(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? campusBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
