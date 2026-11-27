import 'package:material_ui/material_ui.dart';

import '../../domain/plan_completion.dart';
import 'plan_category_header.dart';
import 'plan_completion_model.dart';
import 'plan_course_row.dart';

/// Sliver that lazily builds one top-level category at a time. Only expanded
/// categories construct their course rows; collapsed categories stay a single
/// header.
class PlanCategorySection extends StatelessWidget {
  const PlanCategorySection({
    super.key,
    required this.tree,
    required this.filter,
    required this.statusOf,
    required this.expandedKeys,
    required this.onToggle,
    required this.onCourseTap,
  });

  final PlanCompletionTree tree;
  final PlanCourseFilter filter;
  final PlanCourseStatusResolver statusOf;
  final Set<String> expandedKeys;
  final ValueChanged<PlanCategoryNode> onToggle;
  final void Function(PlanCategoryNode node, PlanCourse course) onCourseTap;

  @override
  Widget build(BuildContext context) {
    final roots = tree.visibleFor(filter, statusOf);
    if (roots.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _PlanFilterEmptyState(filter: filter),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: roots.length,
        itemBuilder: (context, index) => _PlanCategoryBlock(
          key: ValueKey(roots[index].key),
          node: roots[index],
          filter: filter,
          statusOf: statusOf,
          expandedKeys: expandedKeys,
          onToggle: onToggle,
          onCourseTap: onCourseTap,
          isFirst: index == 0,
          isLast: index == roots.length - 1,
        ),
      ),
    );
  }
}

class _PlanCategoryBlock extends StatelessWidget {
  const _PlanCategoryBlock({
    super.key,
    required this.node,
    required this.filter,
    required this.statusOf,
    required this.expandedKeys,
    required this.onToggle,
    required this.onCourseTap,
    required this.isFirst,
    required this.isLast,
  });

  final PlanCategoryNode node;
  final PlanCourseFilter filter;
  final PlanCourseStatusResolver statusOf;
  final Set<String> expandedKeys;
  final ValueChanged<PlanCategoryNode> onToggle;
  final void Function(PlanCategoryNode node, PlanCourse course) onCourseTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final courses = node.coursesFor(filter, statusOf);
    final children = node.childrenFor(filter, statusOf);
    final hasContent = courses.isNotEmpty || children.isNotEmpty;
    final expanded = hasContent && expandedKeys.contains(node.key);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isFirst ? 16 : 0),
          bottom: Radius.circular(isLast ? 16 : 0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanCategoryHeader(
            node: node,
            isChild: false,
            expanded: expanded,
            canExpand: hasContent,
            onTap: hasContent ? () => onToggle(node) : null,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, course) in courses.indexed)
                        PlanCourseRow(
                          nodeKey: node.key,
                          courseIndex: index,
                          course: course,
                          status: statusOf(course),
                          indent: 16,
                          onTap: () => onCourseTap(node, course),
                        ),
                      for (final child in children)
                        _PlanSubcategory(
                          key: ValueKey(child.key),
                          node: child,
                          filter: filter,
                          statusOf: statusOf,
                          expandedKeys: expandedKeys,
                          onToggle: onToggle,
                          onCourseTap: onCourseTap,
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (!isLast)
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        ],
      ),
    );
  }
}

class _PlanSubcategory extends StatelessWidget {
  const _PlanSubcategory({
    super.key,
    required this.node,
    required this.filter,
    required this.statusOf,
    required this.expandedKeys,
    required this.onToggle,
    required this.onCourseTap,
  });

  final PlanCategoryNode node;
  final PlanCourseFilter filter;
  final PlanCourseStatusResolver statusOf;
  final Set<String> expandedKeys;
  final ValueChanged<PlanCategoryNode> onToggle;
  final void Function(PlanCategoryNode node, PlanCourse course) onCourseTap;

  @override
  Widget build(BuildContext context) {
    final courses = node.coursesFor(filter, statusOf);
    final expanded = courses.isNotEmpty && expandedKeys.contains(node.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanCategoryHeader(
          node: node,
          isChild: true,
          expanded: expanded,
          canExpand: courses.isNotEmpty,
          onTap: courses.isEmpty ? null : () => onToggle(node),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, course) in courses.indexed)
                      PlanCourseRow(
                        nodeKey: node.key,
                        courseIndex: index,
                        course: course,
                        status: statusOf(course),
                        indent: 28,
                        onTap: () => onCourseTap(node, course),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _PlanFilterEmptyState extends StatelessWidget {
  const _PlanFilterEmptyState({required this.filter});

  final PlanCourseFilter filter;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 26,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          const Text(
            '当前筛选下没有课程',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            '「${filter.label}」没有匹配课程，切换筛选条件即可查看。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
