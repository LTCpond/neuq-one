import 'package:json_annotation/json_annotation.dart';

import '../../timetable/domain/timetable.dart';

part 'grades.g.dart';

enum GradeKind {
  required('必修'),
  elective('选修'),
  general('通识'),
  cultureElective('文化素质类选修'),
  extracurricular('课外实践'),
  minor('辅修'),
  microMajor('微专业'),
  dualDegree('双学位'),
  other('其他');

  const GradeKind(this.label);
  final String label;
}

enum ScoreFormat {
  numeric('百分制'),
  fiveLevel('五级分制'),
  binary('两级分制'),
  deferred('缓考');

  const ScoreFormat(this.label);
  final String label;

  List<(String, double)> get choices => switch (this) {
    fiveLevel => [('优秀', 95), ('良好', 85), ('中等', 75), ('及格', 65), ('不及格', 0)],
    binary => [('合格', 60), ('不合格', 0)],
    _ => const [],
  };
}

@JsonSerializable()
class Grade {
  const Grade({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.credit,
    required this.score,
    required this.kind,
    this.demo = false,
    this.format = ScoreFormat.numeric,
  });

  factory Grade.fromJson(Map<String, dynamic> json) => _$GradeFromJson(json);

  final String id;
  final String semesterId;
  final String name;
  final double credit;
  final double score;
  final GradeKind kind;
  final bool demo;
  final ScoreFormat format;

  String get scoreLabel => switch (format) {
    ScoreFormat.numeric => score.toString().replaceFirst(RegExp(r'\.0$'), ''),
    ScoreFormat.deferred => format.label,
    _ =>
      format.choices.where((choice) => choice.$2 == score).firstOrNull?.$1 ??
          '—',
  };

  bool get validScore => switch (format) {
    ScoreFormat.numeric => score.isFinite && score >= 0 && score <= 100,
    ScoreFormat.deferred => score == 0,
    _ => format.choices.any((choice) => choice.$2 == score),
  };

  Map<String, dynamic> toJson() => _$GradeToJson(this);
}

abstract interface class GradesRepository {
  Stream<List<Grade>> watch();
  Future<void> save(Grade grade);
  Future<void> delete(String id);
}

class SchoolGradeBook {
  const SchoolGradeBook(
    this.semesters,
    this.grades, {
    this.semesterGpa = const {},
    this.cumulativeGpa,
  });
  final List<Semester> semesters;
  final List<Grade> grades;
  final Map<String, double> semesterGpa;
  final double? cumulativeGpa;
}

abstract interface class SchoolGradesDataSource {
  Future<SchoolGradeBook> fetchGrades();
}

enum GpaScale {
  current('2025 级起', 10000),
  legacy('2025 级以前', 100);

  const GpaScale(this.label, this.precision);
  final String label;
  final int precision;

  static GpaScale forAdmission(int year) => year >= 2025 ? current : legacy;

  double? pointsFor(Grade grade) {
    if (grade.format == ScoreFormat.deferred ||
        grade.kind == GradeKind.minor ||
        grade.kind == GradeKind.dualDegree ||
        grade.kind == GradeKind.cultureElective) {
      return null;
    }
    if (this == current &&
        (grade.kind == GradeKind.general ||
            grade.kind == GradeKind.microMajor ||
            grade.format == ScoreFormat.binary)) {
      return null;
    }
    if (this == legacy && grade.kind == GradeKind.extracurricular) return null;
    if (grade.format == ScoreFormat.binary) return grade.score == 60 ? 3 : 0;
    if (grade.score < 60) return 0;
    return ((grade.score / 10 - 5) * precision + 1e-8).round() / precision;
  }
}

class GradeSummary {
  GradeSummary(Iterable<Grade> grades, GpaScale? scale) {
    for (final grade in grades) {
      if (grade.format == ScoreFormat.deferred) continue;
      credits += grade.credit;
      if (grade.score >= 60) passedCredits += grade.credit;
      if (grade.format != ScoreFormat.binary) {
        _scores += grade.score;
        count++;
      }
      final points = scale?.pointsFor(grade);
      if (points == null) continue;
      _gpaCredits += grade.credit;
      _points += points * grade.credit;
    }
  }

  double credits = 0;
  double passedCredits = 0;
  int count = 0;
  double _scores = 0;
  double _points = 0;
  double _gpaCredits = 0;

  double? get average => count == 0 ? null : _scores / count;
  double? get gpa => _gpaCredits == 0 ? null : _points / _gpaCredits;
}
