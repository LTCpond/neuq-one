import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/grades/domain/plan_completion.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_completion_model.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion/plan_substitute_index.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

void main() {
  final autumn = Semester(
    id: 'school:autumn',
    name: '2025-2026 上',
    start: DateTime.utc(2025, 9, 1),
    weeks: 18,
  );
  final spring = Semester(
    id: 'school:spring',
    name: '2025-2026 下',
    start: DateTime.utc(2026, 2, 23),
    weeks: 18,
  );

  Grade grade(
    String id, {
    required String name,
    required double score,
    required String semesterId,
    double credit = 3,
    ScoreFormat format = ScoreFormat.numeric,
    bool demo = false,
  }) => Grade(
    id: id,
    semesterId: semesterId,
    name: name,
    credit: credit,
    score: score,
    kind: GradeKind.required,
    format: format,
    demo: demo,
  );

  PlanCourse planCourse({
    String code = 'PLAN',
    String name = '线性代数 B',
    double credit = 3,
    double completed = 3,
    bool? passed = true,
    String? score,
    String? remark,
  }) => PlanCourse(
    code: code,
    name: name,
    compulsory: true,
    credits: PlanProgress(required: credit, completed: completed),
    passed: passed,
    score: score,
    remark: remark,
  );

  PlanSubstituteIndex indexWith(List<Grade> grades) =>
      PlanSubstituteIndex.fromGradeBook(
        SchoolGradeBook([autumn, spring], grades),
      );

  test('normalizes whitespace, parentheses, brackets and Latin case', () {
    expect(
      normalizePlanCourseName(' 线性代数（A） '),
      normalizePlanCourseName('线性代数 A'),
    );
    expect(
      normalizePlanCourseName('C++程序设计'),
      normalizePlanCourseName('c++ 程序设计'),
    );
    expect(stripPlanCourseCode('线性代数A[306011201]'), '线性代数A');
    expect(
      normalizePlanCourseName('线性代数A[306011201]'),
      normalizePlanCourseName('线性代数A'),
    );
    expect(
      normalizePlanCourseName('线性代数A【306011201】'),
      normalizePlanCourseName('线性代数A'),
    );
    expect(
      normalizePlanCourseName('线性代数 A'),
      isNot(normalizePlanCourseName('线性代数 B')),
    );
  });

  test('matches a substitute grade after removing its bracketed code', () {
    final index = indexWith([
      grade('school:la-a', name: '线性代数A', score: 92, semesterId: autumn.id),
    ]);
    final course = planCourse(remark: '替代课程：线性代数A[306011201]');
    final match = index.matchFor(course);
    expect(match, isNotNull);
    expect(match!.grade.name, '线性代数A');
    expect(match.isPassing, isTrue);
    expect(match.creditLabel, '3 学分');
    expect(match.scoreLabel, '92');
    expect(match.semesterLabel, '2025-2026 上');
    expect(index.statusFor(course).label, '替代通过');
    expect(index.statusFor(course).substituted, isTrue);
  });

  test('does not match a different teaching section or missing remark', () {
    final index = indexWith([
      grade('school:la-a', name: '线性代数 A', score: 92, semesterId: autumn.id),
    ]);
    expect(index.matchFor(planCourse(remark: '替代课程：线性代数 B')), isNull);
    expect(index.matchFor(planCourse()), isNull);
    expect(
      index.statusFor(planCourse(remark: '替代课程：线性代数 B')).kind,
      PlanCourseStatusKind.inProgress,
    );
  });

  test('prefers passing records, then latest semester, then higher score', () {
    final index = indexWith([
      grade(
        'school:old-pass',
        name: '线性代数 A',
        score: 80,
        semesterId: autumn.id,
        credit: 3,
      ),
      grade(
        'school:new-pass',
        name: '线性代数 A',
        score: 90,
        semesterId: spring.id,
        credit: 4,
      ),
      grade(
        'school:new-fail',
        name: '线性代数 A',
        score: 50,
        semesterId: spring.id,
      ),
    ]);
    final course = planCourse(remark: '替代课程：线性代数 A');
    final match = index.matchFor(course);
    expect(match!.grade.id, 'school:new-pass');
    expect(match.grade.credit, 4);
    expect(match.semesterLabel, '2025-2026 下');
    expect(match.isPassing, isTrue);
    expect(index.statusFor(course).label, '替代通过');
  });

  test('failing and deferred substitutes keep the course in progress', () {
    final failed = indexWith([
      grade('school:fail', name: '线性代数 A', score: 58, semesterId: autumn.id),
    ]);
    final failedMatch = failed.matchFor(planCourse(remark: '替代课程：线性代数 A'));
    expect(failedMatch, isNotNull);
    expect(failedMatch!.isPassing, isFalse);
    expect(failedMatch.scoreLabel, '58');
    final failedStatus = failed.statusFor(planCourse(remark: '替代课程：线性代数 A'));
    expect(failedStatus.kind, PlanCourseStatusKind.inProgress);
    expect(failedStatus.substituted, isFalse);
    expect(failedStatus.shortLabel, '在读');

    final deferred = indexWith([
      grade(
        'school:deferred',
        name: '线性代数 A',
        score: 0,
        semesterId: autumn.id,
        format: ScoreFormat.deferred,
      ),
    ]);
    final deferredMatch = deferred.matchFor(planCourse(remark: '替代课程：线性代数 A'));
    expect(deferredMatch, isNotNull);
    expect(deferredMatch!.isPassing, isFalse);
    expect(deferredMatch.scoreLabel, '缓考');
    expect(
      deferred.statusFor(planCourse(remark: '替代课程：线性代数 A')).kind,
      PlanCourseStatusKind.inProgress,
    );
  });

  test('only no-score passing substitutions become substituted', () {
    final index = indexWith([
      grade('school:pass', name: '线性代数 A', score: 95, semesterId: autumn.id),
    ]);
    final scored = planCourse(score: '0', remark: '替代课程：线性代数 A');
    final scoredStatus = index.statusFor(scored);
    expect(scoredStatus.kind, PlanCourseStatusKind.passed);
    expect(scoredStatus.substituted, isFalse);
    expect(scoredStatus.label, '已通过');

    final failedPlan = planCourse(passed: false, remark: '替代课程：线性代数 A');
    final failedStatus = index.statusFor(failedPlan);
    expect(failedStatus.kind, PlanCourseStatusKind.failed);
    expect(failedStatus.substituted, isFalse);

    final notStartedPlan = planCourse(passed: null, remark: '替代课程：线性代数 A');
    expect(
      index.statusFor(notStartedPlan).kind,
      PlanCourseStatusKind.notStarted,
    );
  });

  test('skips demo and invalid grades and handles an empty book', () {
    final index = indexWith([
      grade(
        'school:demo',
        name: '线性代数 A',
        score: 95,
        semesterId: autumn.id,
        demo: true,
      ),
      grade(
        'school:invalid',
        name: '线性代数 A',
        score: 150,
        semesterId: autumn.id,
      ),
    ]);
    expect(index.matchFor(planCourse(remark: '替代课程：线性代数 A')), isNull);
    expect(
      PlanSubstituteIndex.fromGradeBook(null).matchFor(planCourse()),
      isNull,
    );
    expect(
      PlanSubstituteIndex.empty
          .statusFor(planCourse(remark: '替代课程：线性代数 A'))
          .kind,
      PlanCourseStatusKind.inProgress,
    );
  });
}
