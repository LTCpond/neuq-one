// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timetable.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Semester _$SemesterFromJson(Map<String, dynamic> json) => Semester(
  id: json['id'] as String,
  name: json['name'] as String,
  start: DateTime.parse(json['start'] as String),
  weeks: (json['weeks'] as num).toInt(),
);

Map<String, dynamic> _$SemesterToJson(Semester instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'start': instance.start.toIso8601String(),
  'weeks': instance.weeks,
};

Course _$CourseFromJson(Map<String, dynamic> json) => Course(
  id: json['id'] as String,
  semesterId: json['semesterId'] as String,
  name: json['name'] as String,
  teacher: json['teacher'] as String,
  room: json['room'] as String,
  weekday: (json['weekday'] as num).toInt(),
  startMinute: (json['startMinute'] as num).toInt(),
  endMinute: (json['endMinute'] as num).toInt(),
  weeks: (json['weeks'] as List<dynamic>)
      .map((e) => (e as num).toInt())
      .toList(),
  colorIndex: (json['colorIndex'] as num).toInt(),
);

Map<String, dynamic> _$CourseToJson(Course instance) => <String, dynamic>{
  'id': instance.id,
  'semesterId': instance.semesterId,
  'name': instance.name,
  'teacher': instance.teacher,
  'room': instance.room,
  'weekday': instance.weekday,
  'startMinute': instance.startMinute,
  'endMinute': instance.endMinute,
  'weeks': instance.weeks,
  'colorIndex': instance.colorIndex,
};
