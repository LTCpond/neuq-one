// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_completion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanCompletion _$PlanCompletionFromJson(Map<String, dynamic> json) =>
    PlanCompletion(
      credits: PlanProgress.fromJson(json['credits'] as Map<String, dynamic>),
      compulsoryCredits: PlanProgress.fromJson(
        json['compulsoryCredits'] as Map<String, dynamic>,
      ),
      compulsoryCourses: PlanProgress.fromJson(
        json['compulsoryCourses'] as Map<String, dynamic>,
      ),
      groups: (json['groups'] as List<dynamic>)
          .map((e) => PlanGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
      extraCourses: (json['extraCourses'] as List<dynamic>)
          .map((e) => PlanCourse.fromJson(e as Map<String, dynamic>))
          .toList(),
      internalGpa: (json['internalGpa'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$PlanCompletionToJson(PlanCompletion instance) =>
    <String, dynamic>{
      'credits': instance.credits.toJson(),
      'compulsoryCredits': instance.compulsoryCredits.toJson(),
      'compulsoryCourses': instance.compulsoryCourses.toJson(),
      'internalGpa': instance.internalGpa,
      'groups': instance.groups.map((e) => e.toJson()).toList(),
      'extraCourses': instance.extraCourses.map((e) => e.toJson()).toList(),
    };

PlanProgress _$PlanProgressFromJson(Map<String, dynamic> json) => PlanProgress(
  required: (json['required'] as num).toDouble(),
  completed: (json['completed'] as num).toDouble(),
);

Map<String, dynamic> _$PlanProgressToJson(PlanProgress instance) =>
    <String, dynamic>{
      'required': instance.required,
      'completed': instance.completed,
    };

PlanGroup _$PlanGroupFromJson(Map<String, dynamic> json) => PlanGroup(
  name: json['name'] as String,
  isSubgroup: json['isSubgroup'] as bool,
  credits: PlanProgress.fromJson(json['credits'] as Map<String, dynamic>),
  result: json['result'] as String,
  courses: (json['courses'] as List<dynamic>)
      .map((e) => PlanCourse.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$PlanGroupToJson(PlanGroup instance) => <String, dynamic>{
  'name': instance.name,
  'isSubgroup': instance.isSubgroup,
  'credits': instance.credits.toJson(),
  'result': instance.result,
  'courses': instance.courses.map((e) => e.toJson()).toList(),
};

PlanCourse _$PlanCourseFromJson(Map<String, dynamic> json) => PlanCourse(
  code: json['code'] as String,
  name: json['name'] as String,
  compulsory: json['compulsory'] as bool,
  credits: PlanProgress.fromJson(json['credits'] as Map<String, dynamic>),
  passed: json['passed'] as bool?,
  semester: json['semester'] as String?,
  score: json['score'] as String?,
  remark: json['remark'] as String?,
);

Map<String, dynamic> _$PlanCourseToJson(PlanCourse instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'compulsory': instance.compulsory,
      'credits': instance.credits.toJson(),
      'passed': instance.passed,
      'semester': instance.semester,
      'score': instance.score,
      'remark': instance.remark,
    };
