import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/timetable/domain/icalendar.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';

void main() {
  final term = Semester(
    id: 'term',
    name: '测试学期',
    start: DateTime.utc(2026, 9, 2),
    weeks: 4,
  );

  test('teaching weeks use the opening week and stop at both ends', () {
    expect(term.weekFor(DateTime(2026, 9, 1)), isNull);
    expect(term.weekFor(DateTime(2026, 9, 2)), 1);
    expect(term.weekFor(DateTime(2026, 9, 6)), 1);
    expect(term.weekFor(DateTime(2026, 9, 7)), 2);
    expect(term.weekFor(DateTime(2026, 9, 27)), 4);
    expect(term.weekFor(DateTime(2026, 9, 28)), isNull);
    expect(term.includes(1, DateTime.monday), isFalse);
  });

  test(
    'week ranges combine with parity and reject empty or invalid selections',
    () {
      expect(parseWeeks('1-5，7, 3, 10', 12, WeekParity.odd), [1, 3, 5, 7]);
      expect(parseWeeks('1-5 8、12', 12, WeekParity.even), [2, 4, 8, 12]);
      expect(
        () => parseWeeks('3-2', 12, WeekParity.all),
        throwsFormatException,
      );
      expect(() => parseWeeks('1,9', 8, WeekParity.all), throwsFormatException);
      expect(() => parseWeeks('1', 12, WeekParity.even), throwsFormatException);
    },
  );

  test(
    'conflict requires intersecting real occurrences and half-open time ranges',
    () {
      final first = course('1', [1, 2], start: 480, end: 540);
      expect(first.conflictsWith(course('2', [1], start: 500), term), isFalse);
      expect(first.conflictsWith(course('2', [2], start: 540), term), isFalse);
      expect(first.conflictsWith(course('2', [2], start: 539), term), isTrue);
      expect(first.conflictsWith(course('2', [3], start: 539), term), isFalse);
    },
  );

  test('ICS represents Beijing class time as UTC and folds UTF-8 safely', () {
    final title = '数据结构,专题;第一讲\n${List.filled(30, '课程').join()}';
    final calendar = exportIcs(term, [
      course('1', [1, 2, 4], name: title),
    ], DateTime.utc(2026, 9));
    expect(RegExp('BEGIN:VEVENT').allMatches(calendar), hasLength(2));
    expect(calendar, contains('DTSTART:20260907T000000Z\r\n'));
    expect(calendar, contains('DTSTART:20260921T000000Z\r\n'));
    expect(
      calendar.replaceAll('\r\n ', ''),
      contains(r'SUMMARY:数据结构\,专题\;第一讲\n'),
    );
    expect(
      calendar.split('\r\n').every((line) => utf8.encode(line).length <= 75),
      isTrue,
    );
    expect(calendar, endsWith('END:VCALENDAR\r\n'));
  });
}

Course course(
  String id,
  List<int> weeks, {
  int start = 480,
  int end = 600,
  String name = '本地课程',
}) => Course(
  id: id,
  semesterId: 'term',
  name: name,
  teacher: '任课教师',
  room: '教室',
  weekday: DateTime.monday,
  startMinute: start,
  endMinute: end,
  weeks: weeks,
  colorIndex: 0,
);
