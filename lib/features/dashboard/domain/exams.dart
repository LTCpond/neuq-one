import 'package:json_annotation/json_annotation.dart';

import '../../../core/time/campus_clock.dart';

part 'exams.g.dart';

@JsonSerializable()
class Exam {
  const Exam({
    required this.id,
    required this.name,
    required this.at,
    required this.room,
  });

  factory Exam.fromJson(Map<String, dynamic> json) => _$ExamFromJson(json);

  final String id;
  final String name;

  /// UTC instant, displayed in campus time.
  final DateTime at;
  final String room;

  DateTime get campusTime => at.toUtc().add(campusOffset);
  Map<String, dynamic> toJson() => _$ExamToJson(this);
}

abstract interface class ExamRepository {
  Stream<List<Exam>> watch();
  Future<void> save(Exam exam);
  Future<void> delete(String id);
}
