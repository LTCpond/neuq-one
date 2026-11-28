import '../../../core/time/campus_clock.dart';

/// A manually managed exam record. Instants are stored in UTC and rendered in
/// campus time, matching the rest of the offline timetable data.
class Exam {
  const Exam({
    required this.id,
    required this.name,
    required this.at,
    required this.endsAt,
    this.room = '',
  });

  final String id;
  final String name;
  final DateTime at;
  final DateTime endsAt;
  final String room;

  DateTime get campusStart => at.toUtc().add(campusOffset);
  DateTime get campusEnd => endsAt.toUtc().add(campusOffset);
  DateTime get campusDate => calendarDate(campusStart);

  bool isFinishedAt(DateTime now) => !now.isBefore(campusEnd);

  String get campusTimeRange =>
      '${clockLabel(campusStart.hour * 60 + campusStart.minute)}'
      '–${campusDate == calendarDate(campusEnd) ? '' : '${shortDate(campusEnd)} '}'
      '${clockLabel(campusEnd.hour * 60 + campusEnd.minute)}';
}

abstract interface class ExamRepository {
  Stream<List<Exam>> watch();
  Future<void> save(Exam exam);
  Future<void> delete(String id);
}
