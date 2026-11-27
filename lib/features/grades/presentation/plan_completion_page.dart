import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/school_reconnect_button.dart';
import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/widgets/school_sync_status.dart';
import '../../../core/widgets/screen.dart';
import '../domain/plan_completion.dart';
import 'plan_completion/plan_category_section.dart';
import 'plan_completion/plan_completion_model.dart';
import 'plan_completion/plan_completion_states.dart';
import 'plan_completion/plan_course_sheet.dart';
import 'plan_completion/plan_filter_bar.dart';
import 'plan_completion/plan_progress_card.dart';
import 'plan_completion/plan_substitute_index.dart';

class PlanCompletionPage extends ConsumerStatefulWidget {
  const PlanCompletionPage({super.key});

  @override
  ConsumerState<PlanCompletionPage> createState() => _PlanCompletionPageState();
}

class _PlanCompletionPageState extends ConsumerState<PlanCompletionPage> {
  final _expanded = <String>{};
  var _filter = PlanCourseFilter.all;

  Future<void> _refresh() async {
    if (ref.read(schoolDataSourceProvider) == null) return;
    final key = schoolRefreshProvider(SchoolDataSet.planCompletion);
    if (ref.read(key).isLoading) return;
    if (ref.read(schoolPlanCompletionCacheProvider).hasError) {
      ref.invalidate(schoolPlanCompletionCacheProvider);
    }
    try {
      final refreshed = ref.refresh(key.future);
      await refreshed;
    } catch (_) {
      // SchoolSyncStatus reports the failure while cached data stays visible.
    }
  }

  void _toggle(PlanCategoryNode node) {
    setState(() {
      if (!_expanded.add(node.key)) _expanded.remove(node.key);
    });
  }

  void _changeFilter(
    PlanCourseFilter filter,
    PlanCompletionTree tree,
    PlanCourseStatusResolver statusOf,
  ) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      if (filter == PlanCourseFilter.all) return;
      for (final root in tree.roots) {
        if (!root.hasMatches(filter, statusOf)) continue;
        _expanded.add(root.key);
        for (final child in root.children) {
          if (child.hasMatches(filter, statusOf)) _expanded.add(child.key);
        }
      }
    });
  }

  void _openCourse(PlanCategoryNode node, PlanCourse course) {
    final status = node.isExtra
        ? const PlanGroupStatus(tone: PlanStatusTone.muted, label: '不适用（计划外课程）')
        : resolvePlanGroupStatus(
            node.credits,
            node.result,
            allowComputedGap: node.children.isEmpty && node.courses.isNotEmpty,
          );
    showPlanCourseDetail(
      context,
      course: course,
      categoryPath: node.path,
      groupStatus: status,
      groupResult: node.result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final refreshKey = schoolRefreshProvider(SchoolDataSet.planCompletion);
    final refresh = ref.watch(refreshKey);
    final cache = ref.watch(schoolPlanCompletionCacheProvider);
    final available = ref.watch(schoolDataSourceProvider) != null;
    final restoring = ref.watch(
      schoolConnectionProvider.select(
        (connection) => connection.value == SchoolConnection.restoring,
      ),
    );
    final report = cache.value?.data;
    final tree = report == null ? null : PlanCompletionTree.fromReport(report);
    final substituteIndex = ref.watch(planSubstituteIndexProvider);
    final statusOf = substituteIndex.statusFor;
    final hasContent = tree != null && tree.roots.isNotEmpty;
    final loading =
        available && report == null && (cache.isLoading || refresh.isLoading);
    final titleSize = 22.0;
    final scaledTitle = MediaQuery.textScalerOf(context).scale(titleSize);
    final toolbarHeight =
        56.0 + (scaledTitle - titleSize).clamp(0.0, 16.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        title: Text(
          '培养方案',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: titleSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        actions: [
          if (available)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                tooltip: refresh.isLoading ? '正在刷新' : '刷新培养方案',
                onPressed: refresh.isLoading ? null : _refresh,
                icon: refresh.isLoading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 22,
                        color: colors.primary,
                      ),
                style: IconButton.styleFrom(
                  foregroundColor: colors.primary,
                  disabledForegroundColor: colors.primary.withValues(
                    alpha: .55,
                  ),
                  visualDensity: VisualDensity.standard,
                ),
              ),
            ),
        ],
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: colors.primary,
            backgroundColor: colors.surface,
            onRefresh: _refresh,
            child: CustomScrollView(
              key: const PageStorageKey('plan-completion-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _slivers(
                refresh: refresh,
                cache: cache,
                report: report,
                tree: tree,
                available: available,
                restoring: restoring,
                hasContent: hasContent,
                loading: loading,
                statusOf: statusOf,
              ),
            ),
          ),
          if (report != null && refresh.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  List<Widget> _slivers({
    required AsyncValue<void> refresh,
    required AsyncValue<SchoolCache<PlanCompletion>?> cache,
    required PlanCompletion? report,
    required PlanCompletionTree? tree,
    required bool available,
    required bool restoring,
    required bool hasContent,
    required bool loading,
    required PlanCourseStatusResolver statusOf,
  }) {
    if (report != null) {
      if (!hasContent || tree == null) {
        return [
          _stateSliver(
            '暂无培养方案数据',
            '教务暂未返回课程类别，请稍后刷新重试。',
            icon: Icons.school_outlined,
            action: available
                ? OutlinedButton(onPressed: _refresh, child: const Text('刷新'))
                : null,
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.list(
            children: [
              PlanProgressCard(report: report),
              const SizedBox(height: 10),
              const PlanInfoNote(),
              const SizedBox(height: 4),
              SchoolSyncStatus(
                available: available,
                refresh: refresh,
                syncedAt: cache.value?.syncedAt,
                cacheError: cache.hasError,
                restoring: restoring,
                label: '培养方案同步',
                reconnect: const SchoolReconnectButton(),
              ),
              const SizedBox(height: 22),
              _PlanSectionHeading(
                '课程类别',
                caption: '${tree.categories.length} 个大类',
              ),
              const SizedBox(height: 12),
              PlanFilterBar(
                selected: _filter,
                onChanged: (filter) => _changeFilter(filter, tree, statusOf),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
        PlanCategorySection(
          tree: tree,
          filter: _filter,
          statusOf: statusOf,
          expandedKeys: _expanded,
          onToggle: _toggle,
          onCourseTap: _openCourse,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ];
    }
    if (!available) {
      return [
        _stateSliver(
          '培养方案暂不可用',
          '请使用学校账号在支持原生教务查询的设备上查看。',
          icon: Icons.checklist_rounded,
        ),
      ];
    }
    if (loading) return [_loadingSliver()];
    return [
      _stateSliver(
        '未能读取培养方案',
        '请检查教务连接后重试，本地缓存会保留。',
        icon: Icons.cloud_off_outlined,
        action: OutlinedButton(onPressed: _refresh, child: const Text('重试')),
      ),
    ];
  }

  Widget _loadingSliver() => const SliverPadding(
    padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
    sliver: SliverToBoxAdapter(child: PlanCompletionSkeleton()),
  );

  Widget _stateSliver(
    String title,
    String description, {
    required IconData icon,
    Widget? action,
  }) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      child: Center(
        child: StatePanel(title, description, icon: icon, action: action),
      ),
    ),
  );
}

class _PlanSectionHeading extends StatelessWidget {
  const _PlanSectionHeading(this.title, {this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        if (caption case final label?)
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }
}
