import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/grades/domain/plan_completion.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_completion_model.dart';

void main() {
  PlanCourse course({
    required String code,
    required bool? passed,
    String? score,
    double required = 3,
    double completed = 0,
    String? semester,
    String? remark,
  }) => PlanCourse(
    code: code,
    name: '课程$code',
    compulsory: true,
    credits: PlanProgress(required: required, completed: completed),
    passed: passed,
    score: score,
    semester: semester,
    remark: remark,
  );

  PlanCompletion report() => PlanCompletion(
    credits: const PlanProgress(required: 167, completed: 136),
    compulsoryCredits: const PlanProgress(required: 150, completed: 128),
    compulsoryCourses: const PlanProgress(required: 63, completed: 54),
    internalGpa: 3.0069,
    groups: [
      const PlanGroup(
        name: '通识类课程',
        isSubgroup: false,
        credits: PlanProgress(required: 67, completed: 65),
        result: '缺2分',
        courses: [],
      ),
      PlanGroup(
        name: '数学与自然科学类',
        isSubgroup: true,
        credits: const PlanProgress(required: 20.5, completed: 20.5),
        result: '是',
        courses: [
          course(code: 'A', passed: true, score: '92', semester: '1-1'),
        ],
      ),
      PlanGroup(
        name: '人文与社会科学类',
        isSubgroup: true,
        credits: const PlanProgress(required: 40.5, completed: 38.5),
        result: '缺2分 缺1门',
        courses: [
          course(code: 'B', passed: true, semester: '2-1'),
          course(code: 'C', passed: false, semester: '2-2'),
        ],
      ),
      const PlanGroup(
        name: '学科基础类课程',
        isSubgroup: false,
        credits: PlanProgress(required: 29.5, completed: 29.5),
        result: '是',
        courses: [],
      ),
    ],
    extraCourses: [course(code: 'X', passed: true, score: '合格')],
  );

  test(
    'tree keeps the server ordering and nests subgroups under the category',
    () {
      final tree = PlanCompletionTree.fromReport(report());

      expect(tree.categories.map((node) => node.name), ['通识类课程', '学科基础类课程']);
      expect(tree.roots.map((node) => node.name), [
        '通识类课程',
        '学科基础类课程',
        '计划外课程',
      ]);
      expect(tree.categories.first.children.map((node) => node.name), [
        '数学与自然科学类',
        '人文与社会科学类',
      ]);
      expect(tree.categories.first.children.first.path, '通识类课程 / 数学与自然科学类');
      expect(tree.roots.last.isExtra, isTrue);
      expect(tree.roots.last.courses, hasLength(1));
      expect(tree.roots.last.credits, isNull);
    },
  );

  test(
    'aggregate categories do not publish placeholder completion credits',
    () {
      final emptyLeaf = PlanCategoryNode(
        key: 'leaf-empty',
        name: '通识选修类',
        path: '通识类课程 / 通识选修类',
        credits: const PlanProgress(required: 6, completed: 6),
        result: '是',
        courses: const [],
        children: const [],
        isExtra: false,
      );
      final aggregate = PlanCategoryNode(
        key: 'parent',
        name: '通识类课程',
        path: '通识类课程',
        credits: const PlanProgress(required: 67, completed: 0),
        result: '缺2分',
        courses: const [],
        children: [emptyLeaf],
        isExtra: false,
      );
      expect(aggregate.isAggregate, isTrue);
      expect(formatPlanCategoryCredits(aggregate), '计划 67 学分');
      expect(planCategoryProgress(aggregate), isNull);

      final reportedAggregate = PlanCategoryNode(
        key: 'parent-reported',
        name: '通识类课程',
        path: '通识类课程',
        credits: const PlanProgress(required: 67, completed: 30),
        result: '缺37分',
        courses: const [],
        children: [emptyLeaf],
        isExtra: false,
      );
      expect(formatPlanCategoryCredits(reportedAggregate), '30 / 67 学分');
      expect(planCategoryProgress(reportedAggregate), closeTo(30 / 67, 0.0001));
      expect(formatPlanCategoryCredits(emptyLeaf), '计划 6 学分');
      expect(planCategoryProgress(emptyLeaf), isNull);

      final leaf = PlanCategoryNode(
        key: 'leaf',
        name: '数学与自然科学类',
        path: '通识类课程 / 数学与自然科学类',
        credits: const PlanProgress(required: 12.5, completed: 8.5),
        result: '是',
        courses: [course(code: 'M', passed: true, score: '90')],
        children: const [],
        isExtra: false,
      );
      expect(formatPlanCategoryCredits(leaf), '8.5 / 12.5 学分');
      expect(planCategoryProgress(leaf), closeTo(0.68, 0.0001));

      final explicitZero = PlanCategoryNode(
        key: 'leaf-zero',
        name: '零完成',
        path: '零完成',
        credits: const PlanProgress(required: 12.5, completed: 0),
        result: '',
        courses: [course(code: 'Z', passed: false)],
        children: const [],
        isExtra: false,
      );
      expect(formatPlanCategoryCredits(explicitZero), '0 / 12.5 学分');
      expect(planCategoryProgress(explicitZero), 0.0);

      final zeroPlan = PlanCategoryNode(
        key: 'leaf-zero-plan',
        name: '零计划',
        path: '零计划',
        credits: const PlanProgress(required: 0, completed: 0),
        result: '',
        courses: [course(code: 'Z0', passed: true)],
        children: const [],
        isExtra: false,
      );
      expect(formatPlanCategoryCredits(zeroPlan), '计划 0 学分');
      expect(planCategoryProgress(zeroPlan), isNull);

      final extra = PlanCategoryNode(
        key: 'extra',
        name: '计划外课程',
        path: '计划外课程',
        credits: null,
        result: '',
        courses: [course(code: 'X', passed: true, score: '合格')],
        children: const [],
        isExtra: true,
      );
      expect(formatPlanCategoryCredits(extra), '1 门课程');
      expect(planCategoryProgress(extra), isNull);
    },
  );

  test('filters use explicit study status and keep the original category', () {
    final passed = course(code: 'P', passed: true, score: '90');
    final inProgress = course(code: 'I', passed: true);
    final failed = course(code: 'F', passed: false);
    final notStarted = course(code: 'N', passed: null);
    final unknown = course(code: 'U', passed: null, score: '75');
    PlanCourseStatus plainStatus(PlanCourse item) => PlanCourseStatus.of(item);

    expect(PlanCourseStatus.of(passed).label, '已通过');
    expect(PlanCourseStatus.of(passed).tone, PlanStatusTone.positive);
    expect(
      PlanCourseFilter.passed.matchesStatus(PlanCourseStatus.of(passed)),
      isTrue,
    );
    expect(
      PlanCourseFilter.incomplete.matchesStatus(PlanCourseStatus.of(passed)),
      isFalse,
    );

    expect(PlanCourseStatus.of(inProgress).label, '暂计完成');
    expect(
      PlanCourseFilter.inProgress.matchesStatus(
        PlanCourseStatus.of(inProgress),
      ),
      isTrue,
    );
    expect(
      PlanCourseFilter.passed.matchesStatus(PlanCourseStatus.of(inProgress)),
      isFalse,
    );

    expect(PlanCourseStatus.of(failed).label, '未通过');
    expect(
      PlanCourseFilter.incomplete.matchesStatus(PlanCourseStatus.of(failed)),
      isTrue,
    );

    expect(PlanCourseStatus.of(notStarted).label, '未修读');
    expect(
      PlanCourseFilter.incomplete.matchesStatus(
        PlanCourseStatus.of(notStarted),
      ),
      isTrue,
    );

    expect(PlanCourseStatus.of(unknown).label, '待确认');
    expect(
      PlanCourseFilter.incomplete.matchesStatus(PlanCourseStatus.of(unknown)),
      isTrue,
    );

    for (final item in [passed, inProgress, failed, notStarted, unknown]) {
      expect(
        PlanCourseFilter.all.matchesStatus(PlanCourseStatus.of(item)),
        isTrue,
      );
    }

    final tree = PlanCompletionTree.fromReport(report());
    expect(
      tree
          .visibleFor(PlanCourseFilter.inProgress, plainStatus)
          .map((node) => node.name),
      ['通识类课程'],
    );
    expect(
      tree
          .visibleFor(PlanCourseFilter.inProgress, plainStatus)
          .first
          .childrenFor(PlanCourseFilter.inProgress, plainStatus)
          .map((node) => node.name),
      ['人文与社会科学类'],
    );
    expect(
      tree
          .visibleFor(PlanCourseFilter.passed, plainStatus)
          .map((node) => node.name),
      ['通识类课程', '计划外课程'],
    );
  });

  test(
    'substitute status only becomes passed when a grade confirms a pass',
    () {
      final noScore = course(code: 'S', passed: true, remark: '替代课程：线性代数 A');
      final confirmed = PlanCourseStatus.of(noScore, substitutePassed: true);
      expect(confirmed.kind, PlanCourseStatusKind.passed);
      expect(confirmed.substituted, isTrue);
      expect(confirmed.label, '替代通过');
      expect(confirmed.shortLabel, '替代通过');
      expect(confirmed.tone, PlanStatusTone.positive);
      expect(PlanCourseFilter.passed.matchesStatus(confirmed), isTrue);
      expect(PlanCourseFilter.inProgress.matchesStatus(confirmed), isFalse);
      expect(PlanCourseFilter.incomplete.matchesStatus(confirmed), isFalse);

      final unconfirmed = PlanCourseStatus.of(noScore);
      expect(unconfirmed.kind, PlanCourseStatusKind.inProgress);
      expect(unconfirmed.substituted, isFalse);
      expect(unconfirmed.label, '暂计完成');
      expect(unconfirmed.shortLabel, '在读');
      expect(PlanCourseFilter.inProgress.matchesStatus(unconfirmed), isTrue);
      expect(PlanCourseFilter.passed.matchesStatus(unconfirmed), isFalse);

      final failed = course(code: 'F', passed: false, remark: '替代课程：线性代数 A');
      expect(
        PlanCourseStatus.of(failed, substitutePassed: true).kind,
        PlanCourseStatusKind.failed,
      );
      final notStarted = course(code: 'N', passed: null, remark: '替代课程：线性代数 A');
      expect(
        PlanCourseStatus.of(notStarted, substitutePassed: true).kind,
        PlanCourseStatusKind.notStarted,
      );

      final scored = course(
        code: 'G',
        passed: true,
        score: '0',
        remark: '替代课程：线性代数 A',
      );
      final scoredStatus = PlanCourseStatus.of(scored, substitutePassed: true);
      expect(scoredStatus.kind, PlanCourseStatusKind.passed);
      expect(scoredStatus.substituted, isFalse);
      expect(scoredStatus.label, '已通过');

      final placeholder = course(
        code: 'T',
        passed: true,
        score: '--',
        remark: '替代课程：线性代数 A',
      );
      expect(
        PlanCourseStatus.of(placeholder, substitutePassed: true).substituted,
        isTrue,
      );
    },
  );

  test(
    'group audit status distinguishes official results from computed gaps',
    () {
      final approved = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 10),
        '是',
        allowComputedGap: true,
      );
      expect(approved.tone, PlanStatusTone.positive);
      expect(approved.label, '审核通过');

      final rejected = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 8),
        '否',
        allowComputedGap: true,
      );
      expect(rejected.tone, PlanStatusTone.danger);
      expect(rejected.label, '审核未通过');

      final shortage = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 8.5),
        '缺1.5分 缺1门',
        allowComputedGap: true,
      );
      expect(shortage.tone, PlanStatusTone.caution);
      expect(shortage.label, '缺 1.5 学分 · 1 门');
      expect(shortage.missingCredits, 1.5);
      expect(shortage.missingCourses, 1);

      final courseShortage = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 8.5),
        '缺1门',
        allowComputedGap: false,
      );
      expect(courseShortage.label, '缺 1 门');

      final computedShortage = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 8),
        '',
        allowComputedGap: true,
      );
      expect(computedShortage.tone, PlanStatusTone.caution);
      expect(computedShortage.label, '缺 2 学分');

      final computedFull = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 10),
        '',
        allowComputedGap: true,
      );
      expect(computedFull.tone, PlanStatusTone.info);
      expect(computedFull.label, '学分已满');

      final rawInProgress = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 4),
        '在修',
        allowComputedGap: false,
      );
      expect(rawInProgress.tone, PlanStatusTone.info);
      expect(rawInProgress.label, '在修');

      final unknown = resolvePlanGroupStatus(
        const PlanProgress(required: 10, completed: 4),
        '',
        allowComputedGap: false,
      );
      expect(unknown.label, isNull);
    },
  );

  test(
    'number, percentage and semester formatting handles school variants',
    () {
      expect(formatPlanCredits(0), '0');
      expect(formatPlanCredits(8.5), '8.5');
      expect(formatPlanCredits(4.25), '4.25');
      expect(formatPlanCredits(12), '12');

      expect(formatPlanPercent(.814), '81.4%');
      expect(formatPlanPercent(1), '100%');
      expect(formatPlanPercent(1.125), '112.5%');
      expect(formatPlanPercent(0), '0%');

      expect(formatPlanSemester('1-1'), '大一上');
      expect(formatPlanSemester('1-2'), '大一下');
      expect(formatPlanSemester('2-2'), '大二下');
      expect(formatPlanSemester('2024-2025-1'), '2024-2025 学年 上');
      expect(formatPlanSemester('大一上'), '大一上');
      expect(formatPlanSemester('1-1,2-1'), '大一上、大二上');
      expect(formatPlanSemester(null), '未提供');
    },
  );

  test('remarks expose substitutions without discarding the raw text', () {
    final substitution = PlanCourseRemark.parse('替代课程：示例基础');
    expect(substitution?.substitute, '示例基础');
    expect(substitution?.raw, '替代课程：示例基础');

    final note = PlanCourseRemark.parse('需完成企业实习后认定');
    expect(note?.substitute, isNull);
    expect(note?.raw, '需完成企业实习后认定');

    expect(PlanCourseRemark.parse('--'), isNull);
  });
}
