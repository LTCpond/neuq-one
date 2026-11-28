import 'timetable.dart';

const courseColorCount = 12;

// The current school response exposes activity identifiers, which change when
// teaching slots are split or moved. The normalized subject label survives
// those changes and groups lectures, labs and teaching weeks of one subject.
String courseSubjectKey(Course course) =>
    course.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Map<String, Map<String, int>> assignCourseColors(
  Timetable timetable, [
  Map<String, Map<String, int>> saved = const {},
]) {
  final result = {
    for (final entry in saved.entries) entry.key: {...entry.value},
  };
  final byTerm = <String, Map<String, Set<DateTime>>>{};
  final terms = {for (final term in timetable.semesters) term.id: term};
  for (final course in timetable.courses) {
    final term = terms[course.semesterId];
    if (term == null) continue;
    final subjects = byTerm.putIfAbsent(term.id, () => {});
    final dates = subjects.putIfAbsent(courseSubjectKey(course), () => {});
    for (final week in course.weeks) {
      if (term.includes(week, course.weekday)) {
        dates.add(term.dateFor(week, course.weekday));
      }
    }
  }

  for (final entry in byTerm.entries) {
    final subjects = entry.value;
    final colors = result.putIfAbsent(entry.key, () => {});
    final keys = subjects.keys.toList()..sort();
    final assigned = List.generate(courseColorCount, (_) => <String>[]);
    final unassigned = <String>[];
    for (final key in keys) {
      final color = colors[key];
      if (color == null ||
          color < 0 ||
          color >= courseColorCount ||
          (subjects.length <= courseColorCount && assigned[color].isNotEmpty)) {
        unassigned.add(key);
      } else {
        assigned[color].add(key);
      }
    }
    for (final key in unassigned) {
      final preferred = courseColorSeed(key);
      var best = preferred;
      var bestOverlap = subjects[key]!.length * subjects.length + 1;
      var bestUsage = subjects.length + 1;
      for (var offset = 0; offset < courseColorCount; offset++) {
        final color = (preferred + offset) % courseColorCount;
        final users = assigned[color];
        final overlap = users.fold(
          0,
          (count, other) =>
              count + subjects[key]!.where(subjects[other]!.contains).length,
        );
        if (overlap < bestOverlap ||
            (overlap == bestOverlap && users.length < bestUsage)) {
          best = color;
          bestOverlap = overlap;
          bestUsage = users.length;
        }
      }
      colors[key] = best;
      assigned[best].add(key);
    }
  }
  return result;
}

int courseColorSeed(String subject) =>
    subject.runes.fold(0, (sum, rune) => (sum * 31 + rune) % courseColorCount);

Timetable withCourseColors(
  Timetable timetable,
  Map<String, Map<String, int>> colors,
) => Timetable(timetable.semesters, [
  for (final course in timetable.courses)
    course.withColor(
      colors[course.semesterId]?[courseSubjectKey(course)] ?? course.colorIndex,
    ),
]);
