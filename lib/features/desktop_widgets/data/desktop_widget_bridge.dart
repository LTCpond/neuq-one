import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../exams/data/local_exams.dart';
import '../../exams/domain/exam.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/course_period_span.dart';
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

  final local = ref.watch(timetableProvider).asData?.value;
  final school = ref.watch(schoolTimetableCacheProvider).asData;
  final exams = ref.watch(examsProvider).asData?.value;
  final sections = <String, String>{};
  if (local != null && school != null) {
    sections['timetable'] = jsonEncode(
      widgetTimetableData(mergeTimetable(local, school.value?.data)),
    );
  }
  if (exams != null) sections['exams'] = jsonEncode(widgetExamData(exams));
  return (subject: subject, discard: false, sections: sections);
});

Map<String, Object?> widgetTimetableData(Timetable data) {
  final byTerm = <String, List<Course>>{};
  for (final course in data.courses) {
    (byTerm[course.semesterId] ??= []).add(course);
  }
  return {
    'periods': [
      for (final period in neuqPeriods) [period.start, period.end],
    ],
    'terms': [
      for (final term in data.semesters)
        {
          'id': term.id,
          'start': calendarDate(term.start).toIso8601String().split('T').first,
          'weeks': term.weeks,
          'courses': [
            for (final course in byTerm[term.id] ?? const <Course>[])
              _widgetCourseData(course, term),
          ],
        },
    ],
  };
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

Map<String, Object?> widgetExamData(List<Exam> exams) => {
  'items': [
    for (final exam in exams)
      {
        'id': exam.id,
        'name': exam.name,
        'room': exam.room,
        'start': exam.at.millisecondsSinceEpoch,
        'end': exam.endsAt.millisecondsSinceEpoch,
      },
  ],
};

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
      final next = _pending.entries
          .where(
            (entry) =>
                _published[entry.key] != entry.value &&
                attempted[entry.key] != entry.value,
          )
          .firstOrNull;
      if (next == null) return success;
      attempted[next.key] = next.value;
      final result = await _invoke<bool>('publish', {
        'lease': lease,
        'section': next.key,
        'json': next.value,
      });
      if (_disposed || _revision != revision) return false;
      if (result != null) {
        _published[next.key] = next.value;
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
    _ => null,
  };
}
