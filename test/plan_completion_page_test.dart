import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/grades/domain/plan_completion.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_category_header.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_completion_states.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_course_row.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_progress_card.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_status.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion_page.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

void main() {
  PlanCourse course(
    String code,
    String name,
    double credits,
    String? semester,
    String? score, {
    bool? passed = true,
    double? completed,
    String? remark,
  }) => PlanCourse(
    code: code,
    name: name,
    compulsory: true,
    credits: PlanProgress(
      required: credits,
      completed: completed ?? (passed == true ? credits : 0),
    ),
    passed: passed,
    semester: semester,
    score: score,
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
          course('MATH101', '高等数学（上）', 4, '1-1', '92'),
          course('MATH102', '线性代数', 3, '2-1', null),
        ],
      ),
      PlanGroup(
        name: '人文与社会科学类',
        isSubgroup: true,
        credits: const PlanProgress(required: 40.5, completed: 38.5),
        result: '缺2分 缺1门',
        courses: [
          course('HUM101', '大学英语（一）', 4, '1-1', '90'),
          course('HUM201', '中国近现代史纲要', 3, '2-1', null, passed: false),
        ],
      ),
      const PlanGroup(
        name: '通识选修类',
        isSubgroup: true,
        credits: PlanProgress(required: 6, completed: 6),
        result: '是',
        courses: [],
      ),
      PlanGroup(
        name: '学科基础类课程',
        isSubgroup: false,
        credits: const PlanProgress(required: 29.5, completed: 29.5),
        result: '是',
        courses: [
          course('CS101', '计算机导论', 2, '1-1', '85', remark: '替代课程：程序设计基础'),
        ],
      ),
      PlanGroup(
        name: '专业方向类课程',
        isSubgroup: false,
        credits: const PlanProgress(required: 43, completed: 29),
        result: '缺14分 缺3门',
        courses: [
          course('CS301', '编译原理', 4, '3-1', '86'),
          course('CS302', '分布式系统', 3, '3-2', null, passed: null),
        ],
      ),
      PlanGroup(
        name: '实践类课程',
        isSubgroup: false,
        credits: const PlanProgress(required: 27.5, completed: 12.5),
        result: '否',
        courses: [course('PRAC201', '生产实习', 8, '4-1', null, passed: false)],
      ),
    ],
    extraCourses: [course('EXTRA1', '创新创业实践', 1, null, '合格')],
  );

  PlanCompletion placeholderParentReport() {
    final base = report();
    return PlanCompletion(
      credits: base.credits,
      compulsoryCredits: base.compulsoryCredits,
      compulsoryCourses: base.compulsoryCourses,
      internalGpa: base.internalGpa,
      groups: [
        const PlanGroup(
          name: '通识类课程',
          isSubgroup: false,
          credits: PlanProgress(required: 67, completed: 0),
          result: '缺2分',
          courses: [],
        ),
        ...base.groups.skip(1),
      ],
      extraCourses: base.extraCourses,
    );
  }

  PlanCompletion passedOnlyReport() => PlanCompletion(
    credits: const PlanProgress(required: 4, completed: 4),
    compulsoryCredits: const PlanProgress(required: 4, completed: 4),
    compulsoryCourses: const PlanProgress(required: 1, completed: 1),
    groups: [
      PlanGroup(
        name: '学科基础类课程',
        isSubgroup: false,
        credits: const PlanProgress(required: 4, completed: 4),
        result: '是',
        courses: [course('CS101', '计算机导论', 4, '1-1', '85')],
      ),
    ],
    extraCourses: const [],
  );

  PlanCompletion substituteReport() {
    final base = report();
    return PlanCompletion(
      credits: base.credits,
      compulsoryCredits: base.compulsoryCredits,
      compulsoryCourses: base.compulsoryCourses,
      internalGpa: base.internalGpa,
      groups: [
        for (final group in base.groups)
          group.name == '学科基础类课程'
              ? PlanGroup(
                  name: group.name,
                  isSubgroup: group.isSubgroup,
                  credits: group.credits,
                  result: group.result,
                  courses: [
                    ...group.courses,
                    course(
                      'MATH201',
                      '线性代数 B',
                      3,
                      '2-1',
                      null,
                      remark: '替代课程：线性代数 A',
                    ),
                  ],
                )
              : group,
      ],
      extraCourses: base.extraCourses,
    );
  }

  Semester gradeTerm() => Semester(
    id: 'school:grade-term',
    name: '2025-2026 上',
    start: DateTime.utc(2025, 9, 1),
    weeks: 18,
  );

  SchoolGradeBook substituteGrades({
    double score = 95,
    ScoreFormat format = ScoreFormat.numeric,
  }) => SchoolGradeBook(
    [gradeTerm()],
    [
      Grade(
        id: 'school:la-a',
        semesterId: 'school:grade-term',
        name: '线性代数 A',
        credit: 4,
        score: score,
        kind: GradeKind.required,
        format: format,
      ),
    ],
  );

  testWidgets('overview derives credits, gap and metrics from the report', (
    tester,
  ) async {
    await _pumpPage(tester, report(), size: const Size(390, 1400));

    expect(find.text('培养方案'), findsOneWidget);
    expect(find.text('136'), findsOneWidget);
    expect(find.text('/ 167 学分'), findsOneWidget);
    expect(find.text('距离计划要求还差 31 学分'), findsOneWidget);
    expect(find.text('81.4%'), findsOneWidget);
    expect(find.text('暂计进度'), findsOneWidget);
    expect(find.text('128/150'), findsOneWidget);
    expect(find.text('54/63'), findsOneWidget);
    expect(find.text('3.0069'), findsOneWidget);
    expect(find.text('4 个大类'), findsOneWidget);
    expect(find.text('通识类课程'), findsOneWidget);
    expect(find.text('计划外课程'), findsOneWidget);

    // First-level categories are collapsed by default.
    expect(find.text('数学与自然科学类'), findsNothing);
    expect(find.text('高等数学（上）'), findsNothing);
  });

  testWidgets('aggregate category shows planned credits and hides its bar', (
    tester,
  ) async {
    await _pumpPage(tester, placeholderParentReport());

    final parent = find.ancestor(
      of: find.text('通识类课程'),
      matching: find.byType(PlanCategoryHeader),
    );
    expect(find.text('计划 67 学分'), findsOneWidget);
    expect(find.text('0 / 67 学分'), findsNothing);
    expect(
      find.descendant(of: parent, matching: find.byType(PlanProgressBar)),
      findsNothing,
    );

    await tester.tap(find.text('通识类课程'));
    await tester.pumpAndSettle();
    expect(find.text('数学与自然科学类'), findsOneWidget);
    expect(
      find.descendant(of: parent, matching: find.byType(PlanProgressBar)),
      findsNothing,
    );
    final math = find.ancestor(
      of: find.text('数学与自然科学类'),
      matching: find.byType(PlanCategoryHeader),
    );
    expect(
      find.descendant(of: math, matching: find.byType(PlanProgressBar)),
      findsOneWidget,
    );
    expect(find.text('20.5 / 20.5 学分'), findsOneWidget);
  });

  testWidgets('categories expand independently and course rows stay compact', (
    tester,
  ) async {
    await _pumpPage(tester, report());

    await tester.tap(find.text('通识类课程'));
    await tester.pumpAndSettle();
    expect(find.text('数学与自然科学类'), findsOneWidget);
    expect(find.text('人文与社会科学类'), findsOneWidget);
    expect(find.text('通识选修类'), findsOneWidget);
    expect(find.text('高等数学（上）'), findsNothing);

    await tester.tap(find.text('数学与自然科学类'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学（上）'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);
    expect(find.text('大一上 · 必修 · 4 学分'), findsOneWidget);
    // The only '已通过' text left is the filter chip; the course status is
    // conveyed by its semantic icon.
    expect(find.text('已通过'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('高等数学（上）'),
          matching: find.byType(PlanCourseRow),
        ),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('线性代数'),
          matching: find.byType(PlanCourseRow),
        ),
        matching: find.byIcon(Icons.schedule_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('学科基础类课程'));
    await tester.pumpAndSettle();
    expect(find.text('计算机导论'), findsOneWidget);
    expect(find.text('数学与自然科学类'), findsOneWidget);

    await tester.tap(find.text('通识类课程'));
    await tester.pumpAndSettle();
    expect(find.text('数学与自然科学类'), findsNothing);
    expect(find.text('计算机导论'), findsOneWidget);
  });

  testWidgets('filters narrow the course rows without changing totals', (
    tester,
  ) async {
    await _pumpPage(tester, report());

    await tester.tap(find.byKey(const ValueKey('plan-filter-incomplete')));
    await tester.pumpAndSettle();
    expect(find.text('通识类课程'), findsOneWidget);
    expect(find.text('数学与自然科学类'), findsNothing);
    expect(find.text('人文与社会科学类'), findsOneWidget);
    expect(find.text('中国近现代史纲要'), findsOneWidget);
    expect(find.text('分布式系统'), findsOneWidget);
    expect(find.text('生产实习'), findsOneWidget);
    expect(find.text('计算机导论'), findsNothing);
    expect(find.text('计划外课程'), findsNothing);
    expect(find.text('38.5 / 40.5 学分'), findsOneWidget);
    expect(find.text('29 / 43 学分'), findsOneWidget);
    expect(find.text('12.5 / 27.5 学分'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-filter-inProgress')));
    await tester.pumpAndSettle();
    expect(find.text('线性代数'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('线性代数'),
          matching: find.byType(PlanCourseRow),
        ),
        matching: find.byIcon(Icons.schedule_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('高等数学（上）'), findsNothing);
    expect(find.text('中国近现代史纲要'), findsNothing);
    expect(find.text('学科基础类课程'), findsNothing);
    expect(find.text('计划外课程'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-filter-passed')));
    await tester.pumpAndSettle();
    expect(find.text('高等数学（上）'), findsOneWidget);
    expect(find.text('计算机导论'), findsOneWidget);
    expect(find.text('创新创业实践'), findsOneWidget);
    expect(find.text('线性代数'), findsNothing);
    expect(find.text('中国近现代史纲要'), findsNothing);
    expect(find.text('分布式系统'), findsNothing);
  });

  testWidgets('filter with no matches shows a compact empty state', (
    tester,
  ) async {
    await _pumpPage(tester, passedOnlyReport());

    await tester.tap(find.byKey(const ValueKey('plan-filter-incomplete')));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选下没有课程'), findsOneWidget);
    expect(find.text('计算机导论'), findsNothing);
  });

  testWidgets('empty plan data shows a refreshed-friendly empty state', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const PlanCompletion(
        credits: PlanProgress(required: 0, completed: 0),
        compulsoryCredits: PlanProgress(required: 0, completed: 0),
        compulsoryCourses: PlanProgress(required: 0, completed: 0),
        groups: [],
        extraCourses: [],
      ),
    );

    expect(find.text('暂无培养方案数据'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-overview')), findsNothing);
  });

  testWidgets('course details preserve fields and substitution relationship', (
    tester,
  ) async {
    await _pumpPage(tester, report());

    await tester.tap(find.text('学科基础类课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算机导论'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('plan-course-detail'));
    expect(sheet, findsOneWidget);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));

    expect(inSheet('CS101'), findsOneWidget);
    expect(inSheet('计算机导论'), findsNWidgets(2));
    expect(inSheet('学科基础类课程'), findsNWidgets(2));
    expect(inSheet('必修'), findsOneWidget);
    expect(inSheet('大一上'), findsOneWidget);
    expect(inSheet('2 学分'), findsNWidgets(2));
    expect(inSheet('85'), findsOneWidget);
    expect(inSheet('已通过'), findsNWidgets(2));
    expect(inSheet('审核通过'), findsOneWidget);
    expect(inSheet('教务原文：是'), findsOneWidget);
    expect(inSheet('替代课程'), findsOneWidget);
    expect(inSheet('原计划课程'), findsOneWidget);
    expect(inSheet('实际替代课程'), findsOneWidget);
    expect(inSheet('程序设计基础'), findsOneWidget);
  });

  testWidgets('missing scores and extra courses stay explicit', (tester) async {
    await _pumpPage(tester, report());

    await tester.tap(find.text('专业方向类课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分布式系统'));
    await tester.pumpAndSettle();

    var sheet = find.byKey(const ValueKey('plan-course-detail'));
    expect(
      find.descendant(of: sheet, matching: find.text('未提供')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('未修读')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: sheet, matching: find.text('0 学分')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('计划外课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划外课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创新创业实践'));
    await tester.pumpAndSettle();

    sheet = find.byKey(const ValueKey('plan-course-detail'));
    expect(
      find.descendant(of: sheet, matching: find.text('不适用（计划外课程）')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('未提供')),
      findsOneWidget,
    );
  });

  testWidgets('passing substitute grade confirms alternative completion', (
    tester,
  ) async {
    await _pumpPage(tester, substituteReport(), grades: substituteGrades());

    await tester.tap(find.text('学科基础类课程'));
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('线性代数 B'),
      matching: find.byType(PlanCourseRow),
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.schedule_rounded)),
      findsNothing,
    );
    expect(find.text('替代通过'), findsOneWidget);

    await tester.tap(find.text('线性代数 B'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('plan-course-detail'));
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet('替代通过'), findsNWidgets(2));
    expect(inSheet('完成学分'), findsOneWidget);
    expect(inSheet('暂计完成学分'), findsNothing);
    expect(inSheet('替代课程成绩'), findsOneWidget);
    expect(inSheet('4 学分 · 成绩 95 · 2025-2026 上'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-filter-inProgress')));
    await tester.pumpAndSettle();
    expect(find.text('线性代数 B'), findsNothing);
    expect(find.text('学科基础类课程'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-filter-passed')));
    await tester.pumpAndSettle();
    expect(find.text('线性代数 B'), findsOneWidget);
  });

  testWidgets('non-passing substitute grade keeps course in progress', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      substituteReport(),
      grades: substituteGrades(score: 58),
    );

    await tester.tap(find.text('学科基础类课程'));
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('线性代数 B'),
      matching: find.byType(PlanCourseRow),
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.schedule_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.check_rounded)),
      findsNothing,
    );
    expect(find.text('在读'), findsNWidgets(2));

    await tester.tap(find.text('线性代数 B'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('plan-course-detail'));
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet('暂计完成'), findsNWidgets(2));
    expect(inSheet('暂计完成学分'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.textContaining('成绩 58')),
      findsOneWidget,
    );
    expect(inSheet('该替代课程成绩未通过或为缓考，仍按在读处理。'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-filter-inProgress')));
    await tester.pumpAndSettle();
    expect(find.text('线性代数 B'), findsOneWidget);
    expect(find.text('学科基础类课程'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-filter-passed')));
    await tester.pumpAndSettle();
    expect(find.text('线性代数 B'), findsNothing);
  });

  testWidgets('without synced grades the substitute stays in progress', (
    tester,
  ) async {
    await _pumpPage(tester, substituteReport());

    await tester.tap(find.text('学科基础类课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('线性代数 B'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('plan-course-detail'));
    expect(
      find.descendant(of: sheet, matching: find.text('尚未同步成绩，仍按在读处理。')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('同步成绩')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a missing substitute grade record keeps the course in progress',
    (tester) async {
      await _pumpPage(
        tester,
        substituteReport(),
        grades: SchoolGradeBook([gradeTerm()], const []),
      );

      await tester.tap(find.text('学科基础类课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('线性代数 B'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('plan-course-detail'));
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('未找到该替代课程的成绩记录，仍按在读处理。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('同步成绩')),
        findsOneWidget,
      );
    },
  );

  testWidgets('loading state uses a layout-shaped skeleton', (tester) async {
    final cache = StreamController<SchoolCache<PlanCompletion>?>();
    addTearDown(cache.close);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        cache: (ref) => cache.stream,
        refresh: (ref, section) => Completer<void>().future,
        dataSource: _TestPlanSource(report()),
      ),
    );
    await tester.pump();

    expect(find.byType(PlanCompletionSkeleton), findsOneWidget);
    expect(find.text('培养方案'), findsOneWidget);
  });

  testWidgets('failed request without cache offers retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        cache: (ref) => Stream<SchoolCache<PlanCompletion>?>.value(null),
        refresh: (ref, section) async => throw SchoolRequestFailure.unavailable,
        dataSource: _TestPlanSource(report()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未能读取培养方案'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('manual refresh keeps data and expansion state', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await _pumpPage(
      tester,
      report(),
      size: const Size(390, 1200),
      refresh: (call) {
        calls = call;
        return call == 1 ? Future<void>.value() : pending.future;
      },
    );

    await tester.tap(find.text('通识类课程'));
    await tester.pumpAndSettle();
    expect(find.text('数学与自然科学类'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新培养方案'));
    await tester.pump();
    expect(find.byTooltip('正在刷新'), findsOneWidget);
    expect(find.text('数学与自然科学类'), findsOneWidget);
    expect(find.text('136'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('刷新培养方案'), findsOneWidget);
    expect(find.text('数学与自然科学类'), findsOneWidget);
    expect(calls, greaterThanOrEqualTo(2));
  });

  for (final brightness in Brightness.values) {
    testWidgets('narrow layout stays overflow-free in $brightness', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        report(),
        brightness: brightness,
        size: const Size(320, 800),
        textScale: 1.35,
      );
      await tester.tap(find.text('通识类课程'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('数学与自然科学类'));
      await tester.tap(find.text('数学与自然科学类'));
      await tester.pumpAndSettle();
      expect(find.text('高等数学（上）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('overview handles zero and over-credit plans', (tester) async {
    await tester.pumpWidget(
      _card(
        const PlanCompletion(
          credits: PlanProgress(required: 0, completed: 0),
          compulsoryCredits: PlanProgress(required: 0, completed: 0),
          compulsoryCourses: PlanProgress(required: 0, completed: 0),
          groups: [],
          extraCourses: [],
        ),
      ),
    );
    expect(find.text('计划总学分尚未提供'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('/ 0 学分'), findsNothing);

    await tester.pumpWidget(
      _card(
        const PlanCompletion(
          credits: PlanProgress(required: 100, completed: 120),
          compulsoryCredits: PlanProgress(required: 100, completed: 120),
          compulsoryCourses: PlanProgress(required: 10, completed: 10),
          internalGpa: 3.5,
          groups: [],
          extraCourses: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('120'), findsOneWidget);
    expect(find.text('/ 100 学分'), findsOneWidget);
    expect(find.text('已超过计划要求 20 学分'), findsOneWidget);
    expect(find.text('120%'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  PlanCompletion plan, {
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 1400),
  double textScale = 1,
  Future<void> Function(int call)? refresh,
  SchoolGradeBook? grades,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var calls = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        schoolDataSourceProvider.overrideWithValue(_TestPlanSource(plan)),
        schoolRefreshProvider.overrideWith((ref, section) {
          calls++;
          return refresh?.call(calls) ?? Future<void>.value();
        }),
        schoolPlanCompletionCacheProvider.overrideWith(
          (ref) => Stream.value(
            SchoolCache(plan, DateTime.utc(2026, 11, 27, 3, 36)),
          ),
        ),
        schoolGradesCacheProvider.overrideWith(
          (ref) => Stream<SchoolCache<SchoolGradeBook>?>.value(
            grades == null
                ? null
                : SchoolCache(grades, DateTime.utc(2026, 11, 27, 3, 36)),
          ),
        ),
        schoolConnectionProvider.overrideWith(
          (ref) async => SchoolConnection.connected,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(brightness),
        builder: textScale == 1
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: const PlanCompletionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app({
  required Stream<SchoolCache<PlanCompletion>?> Function(Ref) cache,
  required Future<void> Function(Ref, SchoolDataSet) refresh,
  required SchoolDataSource dataSource,
}) => ProviderScope(
  overrides: [
    schoolDataSourceProvider.overrideWithValue(dataSource),
    schoolRefreshProvider.overrideWith((ref, section) => refresh(ref, section)),
    schoolPlanCompletionCacheProvider.overrideWith((ref) => cache(ref)),
    schoolGradesCacheProvider.overrideWith(
      (ref) => Stream<SchoolCache<SchoolGradeBook>?>.value(null),
    ),
    schoolConnectionProvider.overrideWith(
      (ref) async => SchoolConnection.connected,
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(Brightness.light),
    home: const PlanCompletionPage(),
  ),
);

Widget _card(PlanCompletion plan) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appTheme(Brightness.light),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: PlanProgressCard(report: plan),
    ),
  ),
);

class _TestPlanSource implements SchoolDataSource {
  _TestPlanSource(this.plan);

  final PlanCompletion plan;

  @override
  Future<PlanCompletion> fetchPlanCompletion() async => plan;

  @override
  Future<SchoolGradeBook> fetchGrades() async => throw UnimplementedError();

  @override
  Future<Timetable> fetchTimetable() async => throw UnimplementedError();
}
