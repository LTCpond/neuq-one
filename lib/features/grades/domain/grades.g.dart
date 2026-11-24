// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grades.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Grade _$GradeFromJson(Map<String, dynamic> json) => Grade(
  id: json['id'] as String,
  semesterId: json['semesterId'] as String,
  name: json['name'] as String,
  credit: (json['credit'] as num).toDouble(),
  score: (json['score'] as num).toDouble(),
  kind: $enumDecode(_$GradeKindEnumMap, json['kind']),
  demo: json['demo'] as bool? ?? false,
  format:
      $enumDecodeNullable(_$ScoreFormatEnumMap, json['format']) ??
      ScoreFormat.numeric,
);

Map<String, dynamic> _$GradeToJson(Grade instance) => <String, dynamic>{
  'id': instance.id,
  'semesterId': instance.semesterId,
  'name': instance.name,
  'credit': instance.credit,
  'score': instance.score,
  'kind': _$GradeKindEnumMap[instance.kind]!,
  'demo': instance.demo,
  'format': _$ScoreFormatEnumMap[instance.format]!,
};

const _$GradeKindEnumMap = {
  GradeKind.required: 'required',
  GradeKind.elective: 'elective',
  GradeKind.general: 'general',
  GradeKind.cultureElective: 'cultureElective',
  GradeKind.extracurricular: 'extracurricular',
  GradeKind.minor: 'minor',
  GradeKind.microMajor: 'microMajor',
  GradeKind.dualDegree: 'dualDegree',
  GradeKind.other: 'other',
};

const _$ScoreFormatEnumMap = {
  ScoreFormat.numeric: 'numeric',
  ScoreFormat.fiveLevel: 'fiveLevel',
  ScoreFormat.binary: 'binary',
  ScoreFormat.deferred: 'deferred',
};
