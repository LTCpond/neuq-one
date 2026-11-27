import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/school_data.dart';
import '../../../timetable/domain/timetable.dart';
import '../../domain/grades.dart';
import '../../domain/plan_completion.dart';
import 'plan_completion_model.dart';

/// A substitute course grade found in the cached school grade book.
class PlanSubstituteMatch {
  const PlanSubstituteMatch({required this.grade, this.semester});

  final Grade grade;
  final Semester? semester;

  bool get isPassing =>
      grade.format != ScoreFormat.deferred && grade.score >= 60;

  String get creditLabel => '${formatPlanCredits(grade.credit)} 学分';

  String get scoreLabel => grade.scoreLabel;

  String? get semesterLabel => semester?.name;
}

/// Presentation-only index from normalized course names to cached school
/// grades. The grade book has no course code, so matching is deliberately
/// exact after whitespace/parenthesis/case normalization.
class PlanSubstituteIndex {
  PlanSubstituteIndex._(this._entries);

  factory PlanSubstituteIndex.fromGradeBook(SchoolGradeBook? book) {
    if (book == null) return empty;
    final semesters = {
      for (final semester in book.semesters) semester.id: semester,
    };
    final entries = <String, List<PlanSubstituteMatch>>{};
    for (final grade in book.grades) {
      if (grade.demo || !grade.validScore) continue;
      final key = normalizePlanCourseName(grade.name);
      if (key.isEmpty) continue;
      (entries[key] ??= <PlanSubstituteMatch>[]).add(
        PlanSubstituteMatch(
          grade: grade,
          semester: semesters[grade.semesterId],
        ),
      );
    }
    return PlanSubstituteIndex._(entries);
  }

  static final empty = PlanSubstituteIndex._(
    const <String, List<PlanSubstituteMatch>>{},
  );

  final Map<String, List<PlanSubstituteMatch>> _entries;

  PlanSubstituteMatch? matchFor(PlanCourse course) {
    final substitute = PlanCourseRemark.parse(course.remark)?.substitute;
    if (substitute == null) return null;
    final candidates = _entries[normalizePlanCourseName(substitute)];
    if (candidates == null || candidates.isEmpty) return null;
    final sorted = [...candidates]..sort(_compareMatches);
    return sorted.first;
  }

  /// The course is only considered a completed substitution when the cached
  /// grade record actually confirms a pass.
  PlanCourseStatus statusFor(PlanCourse course) => PlanCourseStatus.of(
    course,
    substitutePassed: matchFor(course)?.isPassing == true,
  );
}

int _compareMatches(PlanSubstituteMatch a, PlanSubstituteMatch b) {
  if (a.isPassing != b.isPassing) return a.isPassing ? -1 : 1;
  final aStart = a.semester?.start;
  final bStart = b.semester?.start;
  if (aStart == null && bStart != null) return 1;
  if (aStart != null && bStart == null) return -1;
  if (aStart != null && bStart != null) {
    final bySemester = bStart.compareTo(aStart);
    if (bySemester != 0) return bySemester;
  }
  final byScore = b.grade.score.compareTo(a.grade.score);
  if (byScore != 0) return byScore;
  return a.grade.id.compareTo(b.grade.id);
}

/// Whitespace, full-width parentheses and Latin case are normalized before
/// exact matching. Parentheses are removed but their content is kept, so
/// "线性代数（A）" and "线性代数 A" match.
String normalizePlanCourseName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u00a0\u3000]+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'[()]'), '');

final planSubstituteIndexProvider = Provider.autoDispose<PlanSubstituteIndex>((
  ref,
) {
  final book = ref.watch(schoolGradesCacheProvider).value?.data;
  return PlanSubstituteIndex.fromGradeBook(book);
});
