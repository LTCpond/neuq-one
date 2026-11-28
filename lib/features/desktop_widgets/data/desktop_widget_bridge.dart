import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../exams/data/local_exams.dart';
import '../../exams/domain/exam.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/data/schedule_providers.dart';
import '../../timetable/domain/course_period_span.dart';
import '../../timetable/domain/schedule.dart';
import '../../timetable/domain/schedule_grid.dart';
import '../../timetable/domain/timetable.dart';
import '../../timetable/presentation/timetable_palette.dart';

const desktopWidgetChannel = MethodChannel('org.neuqone.neuq_one/widgets');
bool get supportsDesktopWidgets => !kIsWeb && Platform.isAndroid;

const _bridgeTimeout = Duration(seconds: 6);

final desktopWidgetSyncProvider = Provider<void>((ref) {
  if (!supportsDesktopWidgets) return;
  final sync = _WidgetSync();
  ref.onDispose(sync.dispose);
  ref.listen(
    _widgetFeedProvider,
    (_, next) => sync.apply(next),
    fireImmediately: true,
  );
});

typedef _WidgetFeed = ({
  String? subject,
  bool discard,
  Map<String, String> sections,
});

final _widgetFeedProvider = Provider<_WidgetFeed>((ref) {
  final session = ref.watch(schoolSessionProvider);
  final signingOut = ref.watch(
    schoolNetworkBoundaryProvider.select((state) => state.signingOut),
  );
  final subject = signingOut ? null : session.asData?.value?.subject;
  if (subject == null) {
    return (
      subject: null,
      discard: signingOut || !session.isLoading,
      sections: const {},
    );
  }

  final local = ref.watch(timetableProvider).value;
  final school = ref.watch(schoolTimetableCacheProvider);
  final exams = ref.watch(examsProvider).value;
  final showExams = ref.watch(
    settingsProvider.select((state) => state.value?.showExamsInTimetable),
  );
  final schedule = ref.watch(scheduleEventsProvider);
  final conflicts = ref.watch(scheduleConflictsProvider);
  final sections = <String, String>{};
  if (school.hasValue && (local != null || school.value != null)) {
    final timetable = mergeTimetable(
      local ?? const Timetable([], []),
      school.value?.data,
    );
    sections['timetable'] = jsonEncode(
      widgetTimetableData(
        timetable,
        ready: school.value != null || timetable.semesters.isNotEmpty,
        schedule: exams == null ? null : schedule,
        conflicts: conflicts,
      ),
    );
  }
  if (exams != null && showExams != null) {
    sections['exams'] = jsonEncode(
      widgetExamData(exams, showOnTimetable: showExams, conflicts: conflicts),
    );
  }
  return (subject: subject, discard: false, sections: sections);
});

String _dateKey(DateTime date) => date.toIso8601String().split('T').first;

Map<String, Object?> widgetTimetableData(
  Timetable data, {
  bool? ready,
  ScheduleEvents? schedule,
  ScheduleConflicts? conflicts,
}) {
  final byTerm = <String, List<Course>>{};
  for (final course in data.courses) {
    (byTerm[course.semesterId] ??= []).add(course);
  }
  return {
    'ready': ?ready,
    'periods': [
      for (final period in neuqPeriods) [period.start, period.end],
    ],
    'terms': [
      for (final term in data.semesters)
        {
          'id': term.id,
          'start': _dateKey(calendarDate(term.start)),
          'weeks': term.weeks,
          'courses': [
            for (final course in byTerm[term.id] ?? const <Course>[])
              _widgetCourseData(course, term),
          ],
          if (schedule != null && schedule.exams.isNotEmpty)
            'examDays': _widgetExamDays(term, schedule, conflicts),
        },
    ],
  };
}

Map<String, Object?> _widgetExamDays(
  Semester term,
  ScheduleEvents schedule,
  ScheduleConflicts? conflicts,
) {
  final result = <String, Object?>{};
  for (var offset = 0; offset < term.weeks * 7; offset++) {
    final date = term.dateFor(1, DateTime.monday).add(Duration(days: offset));
    final events = schedule.examsOverlapping(ScheduleInterval.day(date));
    final groups = groupExamsOn(date, events);
    if (groups.isEmpty) continue;
    final items = <Map<String, Object?>>[];
    for (final event in schedule.courses.on(date, semesterId: term.id)) {
      for (final span in visibleCourseSpans(date, event, groups)) {
        if (span.end - span.start < .16) continue;
        items.add({
          ..._widgetCourseData(event.course!, term),
          'gridFrom': span.start,
          'gridTo': span.end,
        });
      }
    }
    var supplement = false;
    for (final group in groups) {
      final span = examGridSpan(date, group.time);
      supplement |= examNeedsSupplement(date, group);
      if (span.end - span.start < .5) continue;
      final midnight = campusInstant(date, 0);
      final courseCount = {
        for (final event in group.events)
          for (final pair
              in conflicts?.forExam(event.exam!.id, date: date) ??
                  const <ScheduleConflict>[])
            if (pair.other.course case final course?)
              (course.semesterId, course.name),
      }.length;
      items.add({
        'id': group.events.first.exam!.id,
        'name': String.fromCharCodes(
          group.events.map((event) => event.name).join('、').runes.take(240),
        ),
        'room': group.events.length == 1 ? group.events.single.room : '',
        'from': group.time.start.difference(midnight).inMinutes,
        'to': group.time.end.difference(midnight).inMinutes,
        'gridFrom': span.start,
        'gridTo': span.end,
        'examCount': group.events.length,
        'conflicts': courseCount,
        'end': group.time.end.millisecondsSinceEpoch,
        'examEnd': group.events
            .map((event) => event.time.end.millisecondsSinceEpoch)
            .reduce((a, b) => a > b ? a : b),
      });
    }
    result[_dateKey(date)] = {'items': items, 'supplement': supplement};
  }
  return result;
}

Map<String, Object?> _widgetCourseData(Course course, Semester term) {
  final span = coursePeriodSpan(course);
  return {
    'id': course.id,
    'name': course.name,
    'room': course.room,
    'day': course.weekday,
    'from': course.startMinute,
    'to': course.endMinute,
    'first': span.start,
    'last': span.end,
    'weeks': [
      for (final week in course.weeks)
        if (term.includes(week, course.weekday)) week,
    ],
    'colors': [
      for (final brightness in [Brightness.light, Brightness.dark])
        for (final color in coursePaletteColors(brightness, course.colorIndex))
          color.toARGB32(),
    ],
  };
}

List<int> _widgetExamPalette({bool finished = false}) => [
  for (final brightness in [Brightness.light, Brightness.dark]) ...[
    examPalette(brightness, finished: finished).background.toARGB32(),
    examPalette(brightness, finished: finished).text.toARGB32(),
  ],
];

Map<String, Object?> widgetExamData(
  List<Exam> exams, {
  bool? showOnTimetable,
  ScheduleConflicts? conflicts,
}) => {
  if (showOnTimetable != null) ...{
    'showOnTimetable': showOnTimetable,
    'colors': _widgetExamPalette(),
    'finishedColors': _widgetExamPalette(finished: true),
  },
  'items': [
    for (final exam in exams)
      {
        'id': exam.id,
        'name': exam.name,
        'room': exam.room,
        'start': exam.at.millisecondsSinceEpoch,
        'end': exam.endsAt.millisecondsSinceEpoch,
        if (conflicts != null) ..._widgetExamConflicts(exam, conflicts),
      },
  ],
};

Map<String, Object?> _widgetExamConflicts(
  Exam exam,
  ScheduleConflicts conflicts,
) {
  final pairs = conflicts.forExam(exam.id).toList();
  final covered = <String, Set<String>>{};
  for (final pair in pairs) {
    final other = pair.other;
    if (other.course != null &&
        pair.overlap.start == other.time.start &&
        pair.overlap.end == other.time.end) {
      (covered[_dateKey(other.date)] ??= {}).add(other.course!.id);
    }
  }
  return {
    'conflicts': pairs.length,
    if (covered.isNotEmpty)
      'covered': {
        for (final entry in covered.entries) entry.key: entry.value.toList(),
      },
  };
}

class _WidgetSync {
  String? _subject;
  String? _lease;
  bool? _discard;
  bool _disposed = false;
  int _revision = 0;
  Map<String, String> _pending = const {};
  final _published = <String, String>{};
  Future<void>? _verification;
  bool _publishing = false;
  Timer? _retry;
  int _attempts = 0;

  void apply(_WidgetFeed feed) {
    final changed = _subject != feed.subject || _discard != feed.discard;
    _subject = feed.subject;
    _discard = feed.discard;
    _pending = feed.sections;
    if (changed) {
      _revision++;
      _lease = null;
      _published.clear();
      _verification = null;
      _attempts = 0;
      _retry?.cancel();
    }
    if ((changed || (_lease == null && feed.subject != null)) &&
        _verification == null) {
      final revision = _revision;
      _verification = _verify(feed, revision).whenComplete(() {
        if (_revision != revision) return;
        _verification = null;
        _drain();
      });
    } else {
      _drain();
    }
  }

  Future<void> _verify(_WidgetFeed feed, int revision) async {
    final subject = feed.subject;
    final owner = subject == null
        ? null
        : sha256
              .convert(utf8.encode('neuq-one/desktop-widget/v1:$subject'))
              .toString();
    final lease = await _invoke<String>('verify', {
      'owner': owner,
      'discard': feed.discard,
    });
    if (_disposed || _revision != revision) return;
    _lease = subject == null ? null : lease;
    if (lease == null) {
      _retryLater(() => _verify(feed, revision).then((_) => _drain()));
    }
  }

  void _drain() {
    final lease = _lease;
    if (_disposed || lease == null || _publishing) return;
    if (_pending.entries.every(
      (entry) => _published[entry.key] == entry.value,
    )) {
      return;
    }
    _publishing = true;
    final revision = _revision;
    _publish(lease, revision).then((success) {
      _publishing = false;
      if (_revision != revision || success) {
        _drain();
      } else {
        _retryLater(_drain);
      }
    }).ignore();
  }

  Future<bool> _publish(String lease, int revision) async {
    final attempted = <String, String>{};
    var success = true;
    while (!_disposed && _revision == revision) {
      final next = Map.fromEntries(
        _pending.entries.where(
          (entry) =>
              _published[entry.key] != entry.value &&
              attempted[entry.key] != entry.value,
        ),
      );
      if (next.isEmpty) return success;
      attempted.addAll(next);
      final result = await _invoke<bool>('publishBatch', {
        'lease': lease,
        'sections': next,
      });
      if (_disposed || _revision != revision) return false;
      if (result != null) {
        _published.addAll(next);
      } else {
        success = false;
      }
    }
    return false;
  }

  void _retryLater(void Function() callback) {
    if (_disposed || _retry?.isActive == true || _attempts >= 3) return;
    _retry = Timer(Duration(seconds: 2 << _attempts++), callback);
  }

  void dispose() {
    _disposed = true;
    _revision++;
    _retry?.cancel();
  }
}

Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
  try {
    return await desktopWidgetChannel
        .invokeMethod<T>(method, arguments)
        .timeout(_bridgeTimeout);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  } on TimeoutException {
    return null;
  }
}

Uri? desktopWidgetLocation(Map<Object?, Object?> navigation, int request) {
  final target = navigation['target'];
  return switch (target) {
    'timetable' => Uri(path: '/timetable'),
    'course'
        when navigation['course'] is String &&
            (navigation['course'] as String).isNotEmpty =>
      Uri(
        path: '/timetable',
        queryParameters: {
          'course': navigation['course'] as String,
          'widget': '$request',
        },
      ),
    'exams' || 'add-exam' => Uri(
      path: '/grades',
      queryParameters: {
        'section': 'exams',
        'widget': '$request',
        if (target == 'add-exam') 'add': '1',
      },
    ),
    'exam' when navigation['exam'] is String => Uri(
      path: '/grades',
      queryParameters: {
        'section': 'exams',
        'widget': '$request',
        'exam': navigation['exam'] as String,
      },
    ),
    'day'
        when navigation['date'] is String &&
            DateTime.tryParse(navigation['date'] as String) != null =>
      Uri(
        path: '/timetable',
        queryParameters: {
          'date': navigation['date'] as String,
          'widget': '$request',
        },
      ),
    _ => null,
  };
}
