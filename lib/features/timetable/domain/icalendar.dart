import 'dart:convert';

import '../../../core/time/campus_clock.dart';
import 'timetable.dart';

String exportIcs(Semester semester, List<Course> courses, DateTime timestamp) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//NEUQ One//Timetable//ZH-CN',
    'CALSCALE:GREGORIAN',
  ];
  for (final course in courses) {
    for (final week in course.weeks) {
      if (!course.occurs(semester, week, course.weekday)) continue;
      final day = semester.dateFor(week, course.weekday);
      String instant(int minute) =>
          _icsDate(day.add(Duration(minutes: minute)).subtract(campusOffset));
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${_escape(course.id)}-$week@neuq-one.local',
        'DTSTAMP:${_icsDate(timestamp.toUtc())}',
        'DTSTART:${instant(course.startMinute)}',
        'DTEND:${instant(course.endMinute)}',
        'SUMMARY:${_escape(course.name)}',
        if (course.room.isNotEmpty) 'LOCATION:${_escape(course.room)}',
        if (course.teacher.isNotEmpty) 'DESCRIPTION:${_escape(course.teacher)}',
        'END:VEVENT',
      ]);
    }
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String _icsDate(DateTime date) =>
    '${date.toIso8601String().split('.').first.replaceAll(RegExp(r'[-:]'), '')}Z';

String _escape(String text) => text
    .replaceAll('\\', '\\\\')
    .replaceAll(RegExp(r'\r\n|\r|\n'), r'\n')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;');

String _fold(String line) {
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (bytes + size > 75) {
      out.write('\r\n ');
      bytes = 1;
    }
    out.write(character);
    bytes += size;
  }
  return out.toString();
}
