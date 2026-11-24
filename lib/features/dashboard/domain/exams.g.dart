// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exams.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Exam _$ExamFromJson(Map<String, dynamic> json) => Exam(
  id: json['id'] as String,
  name: json['name'] as String,
  at: DateTime.parse(json['at'] as String),
  room: json['room'] as String,
);

Map<String, dynamic> _$ExamToJson(Exam instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'at': instance.at.toIso8601String(),
  'room': instance.room,
};
