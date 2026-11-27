import 'package:material_ui/material_ui.dart';

/// A static skeleton that follows the final page rhythm: dashboard, note,
/// sync line, section heading, segmented filter and grouped categories.
class PlanCompletionSkeleton extends StatelessWidget {
  const PlanCompletionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final block = colors.surfaceContainerHigh;
    return Semantics(
      container: true,
      label: '正在加载培养方案',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SkeletonBlock(height: 178, radius: 16, color: block),
            const SizedBox(height: 10),
            _SkeletonBlock(width: 238, height: 10, radius: 5, color: block),
            const SizedBox(height: 4),
            _SkeletonBlock(width: 180, height: 10, radius: 5, color: block),
            const SizedBox(height: 22),
            Row(
              children: [
                _SkeletonBlock(width: 86, height: 18, radius: 6, color: block),
                const Spacer(),
                _SkeletonBlock(width: 52, height: 10, radius: 5, color: block),
              ],
            ),
            const SizedBox(height: 12),
            _SkeletonBlock(height: 40, radius: 12, color: block),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < 4; index++) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.outlineVariant,
                      ),
                    _SkeletonCategoryRow(color: block),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCategoryRow extends StatelessWidget {
  const _SkeletonCategoryRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SkeletonBlock(
                  width: 150,
                  height: 15,
                  radius: 4,
                  color: color,
                ),
              ),
            ),
            _SkeletonBlock(width: 18, height: 18, radius: 5, color: color),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _SkeletonBlock(width: 96, height: 10, radius: 5, color: color),
            const Spacer(),
            _SkeletonBlock(width: 58, height: 10, radius: 5, color: color),
          ],
        ),
        const SizedBox(height: 8),
        _SkeletonBlock(height: 4, radius: 2, color: color),
      ],
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.color,
    this.width = double.infinity,
    this.height = double.infinity,
    this.radius = 8,
  });

  final Color color;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class PlanInfoNote extends StatelessWidget {
  const PlanInfoNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      '教务会暂计本学期在读课程的学分；最终学分以课程成绩为准。',
      style: TextStyle(
        color: colors.onSurfaceVariant,
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        height: 1.35,
      ),
    );
  }
}
