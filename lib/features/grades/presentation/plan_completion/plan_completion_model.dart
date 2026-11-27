import '../../domain/plan_completion.dart';

/// Local filters for the course list. Filtering never changes the official
/// category credit totals, it only decides which course rows are visible.
enum PlanCourseFilter {
  all('全部'),
  incomplete('未完成'),
  inProgress('在读'),
  passed('已通过');

  const PlanCourseFilter(this.label);

  final String label;
}

extension PlanCourseFilterMatch on PlanCourseFilter {
  bool matchesStatus(PlanCourseStatus status) {
    return switch (this) {
      PlanCourseFilter.all => true,
      PlanCourseFilter.incomplete =>
        status.kind == PlanCourseStatusKind.failed ||
            status.kind == PlanCourseStatusKind.notStarted ||
            status.kind == PlanCourseStatusKind.unknown,
      PlanCourseFilter.inProgress =>
        status.kind == PlanCourseStatusKind.inProgress,
      PlanCourseFilter.passed => status.kind == PlanCourseStatusKind.passed,
    };
  }
}

/// Computes the displayed status for a plan course. The page supplies a
/// resolver backed by the cached grades so substitute confirmation is included
/// in filtering and category visibility.
typedef PlanCourseStatusResolver = PlanCourseStatus Function(PlanCourse course);

/// Semantic tone used for audit results, study statuses and progress bars.
enum PlanStatusTone { positive, caution, danger, info, muted }

enum PlanCourseStatusKind { passed, inProgress, failed, notStarted, unknown }

class PlanCourseStatus {
  const PlanCourseStatus._(this.kind, {this.substituted = false});

  final PlanCourseStatusKind kind;

  /// True only when a cached passing grade confirms that the planned course
  /// was completed through its substitute course. A mere substitution remark
  /// is not enough.
  final bool substituted;

  factory PlanCourseStatus.of(
    PlanCourse course, {
    bool substitutePassed = false,
  }) {
    final score = _nonEmpty(course.score);
    if (course.passed == true) {
      if (score != null) {
        return const PlanCourseStatus._(PlanCourseStatusKind.passed);
      }
      if (substitutePassed) {
        return const PlanCourseStatus._(
          PlanCourseStatusKind.passed,
          substituted: true,
        );
      }
      return const PlanCourseStatus._(PlanCourseStatusKind.inProgress);
    }
    if (course.passed == false) {
      return const PlanCourseStatus._(PlanCourseStatusKind.failed);
    }
    return PlanCourseStatus._(
      score != null
          ? PlanCourseStatusKind.unknown
          : PlanCourseStatusKind.notStarted,
    );
  }

  String get label => substituted
      ? '替代通过'
      : switch (kind) {
          PlanCourseStatusKind.passed => '已通过',
          PlanCourseStatusKind.inProgress => '暂计完成',
          PlanCourseStatusKind.failed => '未通过',
          PlanCourseStatusKind.notStarted => '未修读',
          PlanCourseStatusKind.unknown => '待确认',
        };

  /// Compact form used by the course row. The detail sheet keeps the more
  /// precise "暂计完成" wording for tentatively counted credits.
  String get shortLabel => substituted
      ? '替代通过'
      : switch (kind) {
          PlanCourseStatusKind.inProgress => '在读',
          _ => label,
        };

  PlanStatusTone get tone => substituted
      ? PlanStatusTone.positive
      : switch (kind) {
          PlanCourseStatusKind.passed => PlanStatusTone.positive,
          PlanCourseStatusKind.inProgress => PlanStatusTone.info,
          PlanCourseStatusKind.failed => PlanStatusTone.danger,
          PlanCourseStatusKind.notStarted => PlanStatusTone.muted,
          PlanCourseStatusKind.unknown => PlanStatusTone.muted,
        };
}

/// Audit state of a category. [label] is null when the school did not provide
/// enough information and a gap cannot be derived safely.
class PlanGroupStatus {
  const PlanGroupStatus({
    required this.tone,
    this.label,
    this.raw,
    this.missingCredits,
    this.missingCourses,
  });

  final PlanStatusTone tone;
  final String? label;
  final String? raw;
  final double? missingCredits;
  final int? missingCourses;

  bool get isUnknown => label == null;
}

/// A category node mirrors the flat groups returned by the school. Subgroups are
/// attached to the top-level category that precedes them. No category is
/// invented when the endpoint does not return one.
class PlanCategoryNode {
  PlanCategoryNode({
    required this.key,
    required this.name,
    required this.path,
    required this.credits,
    required this.result,
    required this.courses,
    required this.children,
    required this.isExtra,
  });

  final String key;
  final String name;
  final String path;
  final PlanProgress? credits;
  final String result;
  final List<PlanCourse> courses;
  final List<PlanCategoryNode> children;
  final bool isExtra;

  bool get isEmpty => credits == null && courses.isEmpty && children.isEmpty;

  bool get hasAnyContent => courses.isNotEmpty || children.isNotEmpty;

  /// Subgroup aggregates may only expose a planned total plus a separately
  /// reported gap. Their completed-credit cell is often a placeholder zero, so
  /// it must not be presented as an actual completed total.
  bool get isAggregate => children.isNotEmpty;

  bool hasMatches(PlanCourseFilter filter, PlanCourseStatusResolver statusOf) {
    if (filter == PlanCourseFilter.all) return true;
    if (courses.any((course) => filter.matchesStatus(statusOf(course)))) {
      return true;
    }
    return children.any((child) => child.hasMatches(filter, statusOf));
  }

  List<PlanCourse> coursesFor(
    PlanCourseFilter filter,
    PlanCourseStatusResolver statusOf,
  ) => filter == PlanCourseFilter.all
      ? courses
      : courses
            .where((course) => filter.matchesStatus(statusOf(course)))
            .toList(growable: false);

  List<PlanCategoryNode> childrenFor(
    PlanCourseFilter filter,
    PlanCourseStatusResolver statusOf,
  ) => filter == PlanCourseFilter.all
      ? children
      : children
            .where((child) => child.hasMatches(filter, statusOf))
            .toList(growable: false);
}

class PlanCompletionTree {
  PlanCompletionTree._({required this.roots, required this.categories});

  factory PlanCompletionTree.fromReport(PlanCompletion report) {
    final categories = <PlanCategoryNode>[];
    PlanCategoryNode? current;
    for (final group in report.groups) {
      if (!group.isSubgroup || current == null) {
        final key = 'category-${categories.length}-${group.name}';
        current = PlanCategoryNode(
          key: key,
          name: group.name,
          path: group.name,
          credits: group.credits,
          result: group.result,
          courses: group.courses,
          children: <PlanCategoryNode>[],
          isExtra: false,
        );
        categories.add(current);
      } else {
        final index = current.children.length;
        current.children.add(
          PlanCategoryNode(
            key: '${current.key}/subgroup-$index-${group.name}',
            name: group.name,
            path: '${current.path} / ${group.name}',
            credits: group.credits,
            result: group.result,
            courses: group.courses,
            children: <PlanCategoryNode>[],
            isExtra: false,
          ),
        );
      }
    }
    final extra = report.extraCourses.isEmpty
        ? null
        : PlanCategoryNode(
            key: 'extra-courses',
            name: '计划外课程',
            path: '计划外课程',
            credits: null,
            result: '',
            courses: report.extraCourses,
            children: const <PlanCategoryNode>[],
            isExtra: true,
          );
    return PlanCompletionTree._(
      roots: [...categories, ?extra],
      categories: categories,
    );
  }

  /// Top-level categories including the synthetic "计划外课程" group.
  final List<PlanCategoryNode> roots;

  /// Official top-level categories, excluding extra courses. Used for the
  /// "N 个大类" caption so extra courses do not inflate the plan structure.
  final List<PlanCategoryNode> categories;

  bool get isEmpty => roots.isEmpty;

  List<PlanCategoryNode> visibleFor(
    PlanCourseFilter filter,
    PlanCourseStatusResolver statusOf,
  ) => filter == PlanCourseFilter.all
      ? roots
      : roots
            .where((root) => root.hasMatches(filter, statusOf))
            .toList(growable: false);
}

/// Category credits are shown as `completed / required` when the school
/// returned a usable completion figure. Aggregate categories whose completion
/// cell is still zero are treated as missing, which avoids presenting a
/// placeholder zero as an actual completed total. A non-zero aggregate value
/// is still official data and is shown.
String formatPlanCategoryCredits(PlanCategoryNode node) {
  if (node.isExtra) return '${node.courses.length} 门课程';
  final credits = node.credits;
  if (credits == null) return '—';
  if (!node.hasAnyContent ||
      credits.required <= 0 ||
      (node.isAggregate && credits.completed <= 0)) {
    return '计划 ${formatPlanCredits(credits.required)} 学分';
  }
  return '${formatPlanCredits(credits.completed)} / '
      '${formatPlanCredits(credits.required)} 学分';
}

/// Null when the API did not provide a reliable completion figure for this
/// category. Aggregate zero-completion categories and empty categories hide
/// the bar.
double? planCategoryProgress(PlanCategoryNode node) {
  final credits = node.credits;
  if (node.isExtra ||
      !node.hasAnyContent ||
      credits == null ||
      credits.required <= 0 ||
      (node.isAggregate && credits.completed <= 0)) {
    return null;
  }
  return (credits.completed / credits.required).clamp(0.0, 1.0).toDouble();
}

/// Keep official audit results verbatim where possible, but make the common
/// "缺 X 分 缺 Y 门" form scan quickly.
PlanGroupStatus resolvePlanGroupStatus(
  PlanProgress? credits,
  String result, {
  required bool allowComputedGap,
}) {
  final raw = _nonEmpty(result);
  if (raw == null) {
    if (allowComputedGap &&
        credits != null &&
        credits.required > 0 &&
        credits.completed < credits.required) {
      final missing = credits.required - credits.completed;
      return PlanGroupStatus(
        tone: PlanStatusTone.caution,
        label: _shortageLabel(missing, null),
        missingCredits: missing,
      );
    }
    if (allowComputedGap &&
        credits != null &&
        credits.required > 0 &&
        credits.completed >= credits.required) {
      return const PlanGroupStatus(tone: PlanStatusTone.info, label: '学分已满');
    }
    return const PlanGroupStatus(tone: PlanStatusTone.muted);
  }
  if (raw == '是') {
    return PlanGroupStatus(
      tone: PlanStatusTone.positive,
      label: '审核通过',
      raw: raw,
    );
  }
  if (raw == '否' || raw.contains('未通过') || raw.contains('不通过')) {
    return PlanGroupStatus(
      tone: PlanStatusTone.danger,
      label: '审核未通过',
      raw: raw,
    );
  }
  final missingCreditsText = _missingCredits.firstMatch(raw)?.group(1);
  final missingCoursesText = _missingCourses.firstMatch(raw)?.group(1);
  final missingCredits = missingCreditsText == null
      ? null
      : double.tryParse(missingCreditsText);
  final missingCourses = missingCoursesText == null
      ? null
      : int.tryParse(missingCoursesText);
  if (raw.contains('缺') || missingCredits != null || missingCourses != null) {
    final gap =
        missingCredits ??
        (allowComputedGap &&
                credits != null &&
                credits.required > credits.completed
            ? credits.required - credits.completed
            : null);
    return PlanGroupStatus(
      tone: PlanStatusTone.caution,
      label: _shortageLabel(gap, missingCourses),
      raw: raw,
      missingCredits: gap,
      missingCourses: missingCourses,
    );
  }
  if (raw.contains('通过')) {
    return PlanGroupStatus(tone: PlanStatusTone.positive, label: raw, raw: raw);
  }
  return PlanGroupStatus(tone: PlanStatusTone.info, label: raw, raw: raw);
}

class PlanCourseRemark {
  const PlanCourseRemark({required this.raw, this.substitute});

  final String raw;
  final String? substitute;

  static PlanCourseRemark? parse(String? value) {
    final raw = _nonEmpty(value);
    if (raw == null) return null;
    final match = RegExp(r'替代课程\s*[：:]\s*([^；;。\n]+)').firstMatch(raw);
    final substitute = _nonEmpty(match?.group(1));
    return PlanCourseRemark(raw: raw, substitute: substitute);
  }
}

String formatPlanCredits(double value) {
  if (!value.isFinite) return '—';
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatPlanGpa(double value) => value.toStringAsFixed(4);

String formatPlanPercent(double ratio) {
  if (!ratio.isFinite) return '—';
  final text = (ratio * 100).toStringAsFixed(1);
  return '${text.replaceFirst(RegExp(r'\.0$'), '')}%';
}

/// "1-1" means first year, first term. Other formats are preserved so unusual
/// school values never disappear from the UI.
String formatPlanSemester(String? value) {
  final raw = _nonEmpty(value);
  if (raw == null) return '未提供';
  final parts = raw.split(RegExp(r'\s*[,，、;；]\s*'));
  return parts.map(_formatSingleSemester).join('、');
}

String _formatSingleSemester(String value) {
  final text = value.trim();
  final short = RegExp(r'^([1-8])\s*[-－—~～]\s*([12])$').firstMatch(text);
  if (short != null) {
    final year = int.parse(short.group(1)!);
    final term = short.group(2) == '1' ? '上' : '下';
    return '大${_chineseYear[year - 1]}$term';
  }
  final academic = RegExp(r'^(\d{4})\s*[-－—]\s*(\d{4})\s*[-－—]\s*([12])$')
      .firstMatch(text);
  if (academic != null) {
    final term = academic.group(3) == '1' ? '上' : '下';
    return '${academic.group(1)}-${academic.group(2)} 学年 $term';
  }
  return text;
}

const _chineseYear = ['一', '二', '三', '四', '五', '六', '七', '八'];

final _missingCredits = RegExp(r'缺\s*([0-9]+(?:\.[0-9]+)?)\s*(?:分|学分)');
final _missingCourses = RegExp(r'缺\s*([0-9]+)\s*门');

String _shortageLabel(double? credits, int? courses) {
  final parts = <String>[];
  if (credits != null && credits > 0) {
    parts.add('缺 ${formatPlanCredits(credits)} 学分');
  }
  if (courses != null && courses > 0) {
    parts.add(parts.isEmpty ? '缺 $courses 门' : '$courses 门');
  }
  return parts.isEmpty ? '学分不足' : parts.join(' · ');
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty || const {'-', '--', '—'}.contains(text)
      ? null
      : text;
}
