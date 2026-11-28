import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:uuid/uuid.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../domain/course_colors.dart';
import '../domain/timetable.dart';

typedef NeuqTimetableEntry = ({String student, String calendarTag});

NeuqTimetableEntry readNeuqTimetableEntry(String source) {
  final page = html.parse(source);
  final tag = page
      .querySelectorAll('[id]')
      .map((node) => node.id)
      .where((id) => RegExp(r'^semesterBar\d+Semester$').hasMatch(id))
      .firstOrNull;
  final student = RegExp(
    r'''bg\.form\.addInput\(\s*form\s*,\s*["']ids["']\s*,\s*["'](\d{1,18})["']\s*\)''',
  ).firstMatch(source)?.group(1);
  if (tag == null || student == null) {
    throw const FormatException('无法识别教务个人课表入口');
  }
  return (student: student, calendarTag: tag);
}

String? neuqTermKey(String year, String name) {
  final years = RegExp(r'(\d{4})\s*[-—–－至]\s*(\d{4})').firstMatch(year);
  final first = int.tryParse(years?.group(1) ?? '');
  if (first == null || int.tryParse(years!.group(2)!) != first + 1) {
    return null;
  }
  final part = name.replaceAll(RegExp(r'\s|学期|学年|第'), '');
  final season = switch (part) {
    '1' || '一' || '秋' || '秋季' || '上' => '秋季',
    '2' || '二' || '春' || '春季' || '下' => '春季',
    _ => null,
  };
  return season == null ? null : '$first-${first + 1} $season学期';
}

// Registration dates and vacation boundaries from the published NEUQ calendars.
final neuqPublishedTerms = <String, Semester>{
  for (final (year, season, start, weeks) in [
    (2024, '秋季', DateTime.utc(2024, 9, 9), 19),
    (2024, '春季', DateTime.utc(2025, 3, 3), 20),
    (2025, '秋季', DateTime.utc(2025, 9, 1), 20),
    (2025, '春季', DateTime.utc(2026, 3, 2), 20),
    (2026, '秋季', DateTime.utc(2026, 8, 31), 20),
    (2026, '春季', DateTime.utc(2027, 3, 1), 20),
  ])
    '$year-${year + 1} $season学期': Semester(
      id: 'school:calendar-$year-$season',
      name: '$year-${year + 1} $season学期',
      start: start,
      weeks: weeks,
    ),
};

Map<String, Semester> readNeuqSemesters(String source) {
  // Normalize JavaScript object literals into JSON without evaluating code.
  var literal = source.trim().replaceFirst(RegExp(r';$'), '').trim();
  if (literal.startsWith('(') && literal.endsWith(')')) {
    literal = literal.substring(1, literal.length - 1);
  }
  final normalized = literal.replaceAllMapped(
    RegExp(
      r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:[A-Za-z_$][\w$]*|\d+)(?=\s*:)|,(?=\s*[}\]])''',
    ),
    (match) {
      final token = match[0]!;
      if (token == ',') return '';
      if (token.startsWith('"')) return token;
      return jsonEncode(token.startsWith("'") ? _jsString(token) : token);
    },
  );
  final decoded = jsonDecode(normalized);
  final semesters = decoded is Map ? decoded['semesters'] : null;
  if (semesters is! Map) throw const FormatException('无法识别教务学期列表');
  final result = <String, Semester>{};
  for (final entry in semesters.entries) {
    final records = entry.value;
    if (records is! List) continue;
    for (final row in records.whereType<Map>()) {
      final id = row['id']?.toString();
      if (id == null || !RegExp(r'^\d{1,12}$').hasMatch(id)) continue;
      final year = (row['schoolYear'] ?? entry.key).toString();
      final part = row['name']?.toString() ?? '';
      final key = neuqTermKey(year, part);
      final published = neuqPublishedTerms[key];
      final first =
          _termDate(
            row['beginOn'] ??
                row['startOn'] ??
                row['startDate'] ??
                row['beginDate'],
          ) ??
          published?.start;
      final last = _termDate(row['endOn'] ?? row['endDate']);
      final length =
          int.tryParse((row['weeks'] ?? row['weekCount'] ?? '').toString()) ??
          (last != null && first != null
              ? last.difference(mondayOf(first)).inDays ~/ 7 + 1
              : published?.weeks);
      if (first == null || length == null || length < 1 || length > 30) {
        continue;
      }
      result[id] = Semester(
        id: 'school:$id',
        name: key ?? '$year $part'.trim(),
        start: first,
        weeks: length,
      );
    }
  }
  if (result.isEmpty) throw const FormatException('教务学期缺少有效的起止日期');
  return result;
}

DateTime? _termDate(Object? value) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|[ T])')
      .firstMatch(value?.toString() ?? '');
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime.utc(year, month, day);
  return year >= 2000 &&
          year <= 2100 &&
          parsed.month == month &&
          parsed.day == day
      ? parsed
      : null;
}

List<Course> readNeuqCourses(String source, Semester term) {
  final scripts = html
      .parse(source)
      .querySelectorAll('script')
      .map((node) => node.text)
      .join('\n');
  final maker = RegExp(r'\bnew\s+TaskActivity\s*\(');
  final activities = maker.allMatches(scripts).toList();
  if (activities.isEmpty) {
    if (RegExp(r'暂无(?:课程|课表|排课)|无排课信息').hasMatch(source)) return [];
    throw const FormatException('无法识别教务课表数据');
  }

  final teachingSlots = <_TeachingAssignment, Map<int, Set<int>>>{};
  final task = RegExp(r'\b(?:var\s+)?taskId\s*=\s*([^;\r\n]+)');
  final indexes = RegExp(r'\bindex\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)');
  String? taskId;
  for (var i = 0; i < activities.length; i++) {
    final activity = activities[i];
    final next = i + 1 == activities.length
        ? scripts.length
        : activities[i + 1].start;
    final (arguments, end) = _jsArguments(scripts, activity.end);
    if (arguments.length < 7 || end > next) {
      throw const FormatException('教务课表活动格式已变化');
    }
    final prefix = scripts.substring(
      i == 0 ? 0 : activities[i - 1].end,
      activity.start,
    );
    taskId = task.allMatches(prefix).lastOrNull?.group(1)?.trim() ?? taskId;
    final name =
        (_jsString(arguments[3]) ??
                (arguments[3].startsWith('courseName')
                    ? _lastString(prefix, 'courseName')
                    : null))
            ?.replaceFirst(RegExp(r'\s*\([\d.]+\)$'), '')
            .trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('教务课表有课程缺少名称');
    }
    final teacher =
        _jsString(arguments[1]) ??
        (arguments[1].contains('join(') ? _teacherNames(prefix) : '');
    final room = _jsString(arguments[5]) ?? '';
    final bitmap = _jsString(arguments[6]);
    if (bitmap == null || !RegExp(r'^[01]{2,64}$').hasMatch(bitmap)) {
      throw const FormatException('教务课表的教学周格式已变化');
    }
    final weeks = [
      for (var week = 1; week < bitmap.length; week++)
        if (bitmap[week] == '1') week,
    ];
    final suffix = scripts.substring(end, next);
    final nextTask = task.firstMatch(suffix);
    final slots = indexes
        .allMatches(
          nextTask == null ? suffix : suffix.substring(0, nextTask.start),
        )
        .toList();
    if (weeks.isEmpty || weeks.last > term.weeks || slots.isEmpty) {
      throw const FormatException('教务课表包含无效的教学周或节次');
    }
    for (final match in slots) {
      final day = int.parse(match[1]!) + 1;
      final slot = int.parse(match[2]!);
      if (day > 7 || slot >= neuqPeriods.length) {
        throw const FormatException('教务课表包含未知的星期或节次');
      }
      final assignment = (
        task: taskId ?? arguments[2],
        name: name,
        teacher: teacher,
        room: room,
        weekday: day,
      );
      final byWeek = teachingSlots.putIfAbsent(assignment, () => {});
      for (final week in weeks) {
        byWeek.putIfAbsent(week, () => {}).add(slot);
      }
    }
  }

  final courses = <String, Course>{};
  for (final assignment in teachingSlots.entries) {
    final details = assignment.key;
    final byRange = <(int, int), List<int>>{};
    for (final entry in assignment.value.entries) {
      final periods = entry.value.toList()..sort();
      for (var first = 0; first < periods.length;) {
        var last = first;
        while (last + 1 < periods.length &&
            periods[last + 1] == periods[last] + 1) {
          last++;
        }
        byRange
            .putIfAbsent((periods[first], periods[last]), () => [])
            .add(entry.key);
        first = last + 1;
      }
    }
    for (final range in byRange.entries) {
      final (first, last) = range.key;
      final weeks = range.value..sort();
      final identity = jsonEncode([
        term.id,
        details.name,
        details.teacher,
        details.room,
        details.weekday,
        first,
        last,
        weeks,
      ]);
      final id = 'school:${const Uuid().v5(Namespace.url.value, identity)}';
      courses[id] = Course(
        id: id,
        semesterId: term.id,
        name: details.name,
        teacher: details.teacher,
        room: details.room,
        weekday: details.weekday,
        startMinute: neuqPeriods[first].start,
        endMinute: neuqPeriods[last].end,
        weeks: weeks,
        colorIndex: courseColorSeed(details.name),
      );
    }
  }
  return courses.values.toList();
}

typedef _TeachingAssignment = ({
  String task,
  String name,
  String teacher,
  String room,
  int weekday,
});

const _quoted = r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''';

String? _lastString(String prefix, String name) {
  final match = RegExp('\\b$name\\s*=\\s*(${_quoted.trim()})')
      .allMatches(prefix)
      .lastOrNull;
  return _jsString(match?.group(1) ?? '');
}

String _teacherNames(String prefix) {
  final teachers =
      RegExp(r'\bactTeachers\s*=\s*\[([^\]]*)\]')
          .allMatches(prefix)
          .lastOrNull
          ?.group(1) ??
      '';
  final names = RegExp('["\u0027]?name["\u0027]?\\s*:\\s*(${_quoted.trim()})')
      .allMatches(teachers)
      .map((match) => _jsString(match[1]!))
      .whereType<String>();
  return names.toSet().join('、');
}

String? _jsString(String token) {
  if (!RegExp(
    '^(?:${_quoted.trim()})'
    r'$',
  ).hasMatch(token)) {
    return null;
  }
  return token.substring(1, token.length - 1).replaceAllMapped(
    RegExp(r'\\(?:u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|(.))'),
    (match) {
      final hex = match[1] ?? match[2];
      if (hex != null) return String.fromCharCode(int.parse(hex, radix: 16));
      return switch (match[3]!) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        final escaped => escaped,
      };
    },
  );
}

(List<String>, int) _jsArguments(String script, int start) {
  final args = <String>[];
  var field = start;
  var nested = 0;
  String? quote;
  for (var i = start; i < script.length; i++) {
    final char = script[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '(' || char == '[' || char == '{') {
      nested++;
    } else if (char == ')' && nested == 0) {
      args.add(script.substring(field, i).trim());
      return (args, i + 1);
    } else if (char == ')' || char == ']' || char == '}') {
      nested--;
    } else if (char == ',' && nested == 0) {
      args.add(script.substring(field, i).trim());
      field = i + 1;
    }
  }
  throw const FormatException('教务课表活动字段不完整');
}
