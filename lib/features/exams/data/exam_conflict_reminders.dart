import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/school_auth.dart';
import '../../../core/database/school_data.dart';
import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../../profile/data/course_reminders.dart';
import '../../timetable/data/schedule_providers.dart';
import '../../timetable/domain/schedule.dart';
import 'local_exams.dart';

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

String _owner(String subject) => _digest('neuq-one/exam-conflicts/v1:$subject');

final examConflictWakeProvider = Provider<Object>((ref) => Object());

final examConflictReminderSyncProvider = Provider<void>((ref) {
  final coordinator = _ExamConflictSync(
    () => ref.read(preferencesProvider),
    ref.watch(reminderServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  ref.listen(
    _examConflictFeedProvider,
    (_, feed) => coordinator.apply(feed),
    fireImmediately: true,
  );
});

typedef _Feed = ({
  String? subject,
  String? revision,
  List<ScheduleEvent>? exams,
  List<ScheduleConflict>? conflicts,
  bool? enabled,
});

final _examConflictFeedProvider = Provider.autoDispose<_Feed>((ref) {
  ref.watch(examConflictWakeProvider);
  final subject = ref.watch(
    schoolSessionProvider.select((state) => state.asData?.value?.subject),
  );
  final signingOut = ref.watch(
    schoolNetworkBoundaryProvider.select((state) => state.signingOut),
  );
  if (subject == null || signingOut) {
    return (
      subject: null,
      revision: null,
      exams: null,
      conflicts: null,
      enabled: null,
    );
  }
  final cache = ref.watch(schoolTimetableCacheProvider);
  final exams = ref.watch(examsProvider);
  final enabled = ref.watch(
    settingsProvider.select((state) => state.value?.examConflictReminders),
  );
  if (cache.isLoading ||
      cache.hasError ||
      exams.isLoading ||
      exams.hasError ||
      !exams.hasValue) {
    return (
      subject: subject,
      revision: null,
      exams: null,
      conflicts: null,
      enabled: enabled,
    );
  }
  final schedule = ref.watch(scheduleEventsProvider);
  final conflicts = ref.watch(scheduleConflictsProvider);
  return (
    subject: subject,
    revision: cache.value?.revision ?? cache.value?.syncedAt.toIso8601String(),
    exams: schedule.exams,
    conflicts: conflicts.pairs.where((pair) {
      final course = pair.other.course;
      return course != null && isSchoolRecord(course.semesterId);
    }).toList(),
    enabled: enabled,
  );
});

/// Tracks notification delivery across validated snapshots. Conflict display
/// always derives from the current schedule independently of this ledger.
class ExamConflictLedger {
  const ExamConflictLedger(
    this.revision,
    this.exams,
    this.active,
    this.pending,
  );

  final String? revision;
  final Set<String> exams;
  final Set<String> active;
  final Set<String> pending;

  static ExamConflictLedger? decode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      Set<String> keys(String name) =>
          (data[name] as List).cast<String>().toSet();
      return ExamConflictLedger(
        data['revision'] as String?,
        keys('exams'),
        keys('active'),
        keys('pending'),
      );
    } on Object {
      return null;
    }
  }

  String encode() => jsonEncode({
    'revision': revision,
    'exams': exams.toList()..sort(),
    'active': active.toList()..sort(),
    'pending': pending.toList()..sort(),
  });

  static String conflictKey(ScheduleConflict pair) => _digest(pair.key);

  static String _examKey(ScheduleEvent event) => _digest(
    jsonEncode([
      event.exam!.id,
      event.time.start.millisecondsSinceEpoch,
      event.time.end.millisecondsSinceEpoch,
    ]),
  );

  static ExamConflictLedger reconcile({
    required ExamConflictLedger? previous,
    required String? revision,
    required Iterable<ScheduleEvent> exams,
    required Map<String, ScheduleConflict> active,
    required bool enabled,
  }) {
    final pending = <String>{};
    if (previous != null && enabled) {
      pending.addAll(previous.pending.where(active.containsKey));
      if (revision != null && revision != previous.revision) {
        for (final entry in active.entries) {
          if (!previous.active.contains(entry.key) &&
              previous.exams.contains(_examKey(entry.value.exam))) {
            pending.add(entry.key);
          }
        }
      }
    }
    return ExamConflictLedger(
      revision,
      exams.map(_examKey).toSet(),
      active.keys.toSet(),
      pending,
    );
  }

  ExamConflictLedger delivered() =>
      ExamConflictLedger(revision, exams, active, const {});
}

class _ExamConflictSync {
  _ExamConflictSync(this._preferences, this._service);

  final SharedPreferencesAsync Function() _preferences;
  final CourseReminderService _service;
  _Feed? _latest;
  String? _ownerInUse;
  bool _running = false;
  bool _disposed = false;

  void apply(_Feed feed) {
    if (!_service.supported) return;
    _latest = feed;
    if (!_running) _drain().ignore();
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _latest != null) {
        final feed = _latest!;
        _latest = null;
        try {
          await _reconcile(feed);
        } on Object {
          // Keep the last durable snapshot and retry on the next valid event.
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _reconcile(_Feed feed) async {
    final subject = feed.subject;
    final owner = subject == null ? null : _owner(subject);
    final changedOwner = _ownerInUse != null && _ownerInUse != owner;
    _ownerInUse = owner;
    if (changedOwner) {
      try {
        await _service.dismissExamConflict();
      } on Object {
        // A system notification failure cannot prevent the new account from syncing.
      }
    }
    final exams = feed.exams;
    final conflicts = feed.conflicts;
    final enabled = feed.enabled;
    if (owner == null ||
        exams == null ||
        conflicts == null ||
        enabled == null) {
      return;
    }
    final prefs = _preferences();
    final key = 'schedule.examConflicts.$owner';
    final raw = await prefs.getString(key);
    final now = DateTime.now().toUtc();
    final active = {
      for (final pair in conflicts)
        if (pair.exam.time.end.isAfter(now))
          ExamConflictLedger.conflictKey(pair): pair,
    };
    final next = ExamConflictLedger.reconcile(
      previous: ExamConflictLedger.decode(raw),
      revision: feed.revision,
      exams: exams,
      active: active,
      enabled: enabled,
    );
    final encoded = next.encode();
    if (encoded != raw) await prefs.setString(key, encoded);
    bool isCurrent() {
      if (_disposed) return false;
      final latest = _latest;
      if (latest == null) return true;
      if (latest.subject != subject ||
          latest.enabled != true ||
          latest.conflicts == null) {
        return false;
      }
      final current = latest.conflicts!
          .map(ExamConflictLedger.conflictKey)
          .toSet();
      return current.containsAll(next.pending);
    }

    if (next.pending.isEmpty || !isCurrent()) return;
    final first = active[next.pending.first]!;
    final date = campusDateAt(first.overlap.start);
    final exam = first.exam.exam!;
    final extra = next.pending.length - 1;
    final sent = await _service.showExamConflict(
      body:
          '教务课表发生变化，${shortDate(date)}的${exam.name}考试与${first.other.name}课程存在时间冲突'
          '${extra > 0 ? '，另有 $extra 处新增冲突' : ''}，请及时确认。',
      payload:
          CourseReminderService.examConflictPayloadPrefix +
          jsonEncode({
            'owner': owner,
            'exam': exam.id,
            'date': date.toIso8601String().split('T').first,
          }),
      isCurrent: isCurrent,
    );
    if (sent) await prefs.setString(key, next.delivered().encode());
  }

  void dispose() => _disposed = true;
}

Uri? examConflictNotificationLocation(
  String payload,
  String subject,
  int request,
) {
  final prefix = CourseReminderService.examConflictPayloadPrefix;
  if (!payload.startsWith(prefix)) return null;
  try {
    final data =
        jsonDecode(payload.substring(prefix.length)) as Map<String, dynamic>;
    final exam = data['exam'];
    final date = data['date'];
    if (data['owner'] != _owner(subject) ||
        exam is! String ||
        exam.isEmpty ||
        exam.length > 512 ||
        date is! String ||
        DateTime.tryParse(date) == null) {
      return null;
    }
    return Uri(
      path: '/grades',
      queryParameters: {
        'section': 'exams',
        'widget': '$request',
        'exam': exam,
        'date': date,
        'conflict': '1',
      },
    );
  } on Object {
    return null;
  }
}
