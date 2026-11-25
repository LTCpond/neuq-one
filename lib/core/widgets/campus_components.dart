import 'package:material_ui/material_ui.dart';

const campusToolbarControlSize = 44.0;

class CampusPageTitle extends StatelessWidget {
  const CampusPageTitle(this.title, {super.key, this.eyebrow});

  final String title;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow case final label?) ...[
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(title, style: theme.textTheme.headlineMedium),
      ],
    );
  }
}

class CampusSectionHeading extends StatelessWidget {
  const CampusSectionHeading(this.title, {super.key, this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      if (caption case final label?)
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
    ],
  );
}

class CampusRefreshButton extends StatelessWidget {
  const CampusRefreshButton({
    super.key,
    required this.tooltip,
    required this.isLoading,
    required this.onPressed,
  });

  final String tooltip;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: isLoading ? '正在刷新' : tooltip,
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(
                color: colors.primary,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 24),
      style: IconButton.styleFrom(
        foregroundColor: colors.primary,
        backgroundColor: colors.primaryContainer,
        disabledBackgroundColor: colors.primaryContainer,
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.zero,
        fixedSize: const Size.square(campusToolbarControlSize),
        minimumSize: const Size.square(campusToolbarControlSize),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class CampusIconBadge extends StatelessWidget {
  const CampusIconBadge({
    super.key,
    required this.child,
    required this.background,
    required this.foreground,
    this.size = 40,
  });

  final Widget child;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size >= 46 ? 14 : 12),
    ),
    child: IconTheme(
      data: IconThemeData(size: size >= 46 ? 24 : 22, color: foreground),
      child: child,
    ),
  );
}
