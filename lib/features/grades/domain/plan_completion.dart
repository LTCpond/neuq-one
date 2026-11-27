import 'package:json_annotation/json_annotation.dart';

part 'plan_completion.g.dart';

@JsonSerializable(explicitToJson: true)
class PlanCompletion {
  const PlanCompletion({
    required this.credits,
    required this.compulsoryCredits,
    required this.compulsoryCourses,
    required this.groups,
    required this.extraCourses,
    this.internalGpa,
  });

  factory PlanCompletion.fromJson(Map<String, dynamic> json) =>
      _$PlanCompletionFromJson(json);

  final PlanProgress credits;
  final PlanProgress compulsoryCredits;
  final PlanProgress compulsoryCourses;
  final double? internalGpa;
  final List<PlanGroup> groups;
  final List<PlanCourse> extraCourses;

  Map<String, dynamic> toJson() => _$PlanCompletionToJson(this);
}

@JsonSerializable()
class PlanProgress {
  const PlanProgress({required this.required, required this.completed});

  factory PlanProgress.fromJson(Map<String, dynamic> json) =>
      _$PlanProgressFromJson(json);

  final double required;
  final double completed;

  Map<String, dynamic> toJson() => _$PlanProgressToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PlanGroup {
  const PlanGroup({
    required this.name,
    required this.isSubgroup,
    required this.credits,
    required this.result,
    required this.courses,
  });

  factory PlanGroup.fromJson(Map<String, dynamic> json) =>
      _$PlanGroupFromJson(json);

  final String name;
  final bool isSubgroup;
  final PlanProgress credits;
  final String result;
  final List<PlanCourse> courses;

  Map<String, dynamic> toJson() => _$PlanGroupToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PlanCourse {
  const PlanCourse({
    required this.code,
    required this.name,
    required this.compulsory,
    required this.credits,
    required this.passed,
    this.semester,
    this.score,
    this.remark,
  });

  factory PlanCourse.fromJson(Map<String, dynamic> json) =>
      _$PlanCourseFromJson(json);

  final String code;
  final String name;
  final bool compulsory;
  final PlanProgress credits;
  final bool? passed;
  final String? semester;
  final String? score;
  final String? remark;

  Map<String, dynamic> toJson() => _$PlanCourseToJson(this);
}
