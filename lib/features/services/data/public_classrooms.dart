import 'dart:io' show HttpDate, HttpException;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/public_data_client.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/cache_files.dart';
import '../../../core/time/campus_clock.dart';
import '../domain/classrooms.dart';
import 'classroom_cache.dart';
import 'classroom_week_json.dart';

final classroomsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final classroomsProvider = NotifierProvider<Classrooms, ClassroomsState>(
  Classrooms.new,
);

class ClassroomsState {
  const ClassroomsState({
    this.snapshot,
    this.isLoading = false,
    this.refreshFailed = false,
  });

  final ClassroomWeek? snapshot;
  final bool isLoading;
  final bool refreshFailed;
}

class Classrooms extends Notifier<ClassroomsState> {
  static const _path = '/api/v1/classrooms/week.json';
  static const refreshInterval = Duration(minutes: 5);
  final _writes = CacheWrites();
  ClassroomCacheEntry? _cached;
  DateTime? _lastAttempt;
  Future<void>? _inFlight;
  bool _loadedCache = false;
  int _consecutiveFailures = 0;

  @override
  ClassroomsState build() => const ClassroomsState(isLoading: true);

  Future<void> refresh({bool force = false}) {
    final version = _writes.version;
    if (version == null) return Future.value();
    return _inFlight ??= _refresh(force, version).whenComplete(() {
      if (_writes.current(version)) _inFlight = null;
    });
  }

  Future<void> clearCache() {
    final cache = ref.read(classroomCacheProvider);
    final clearing = _writes.clear(cache.removeWeek);
    _cached = null;
    _lastAttempt = null;
    _inFlight = null;
    _loadedCache = false;
    _consecutiveFailures = 0;
    state = const ClassroomsState();
    return clearing;
  }

  Future<void> _refresh(bool force, int version) async {
    bool current() => ref.mounted && _writes.current(version);
    final cache = ref.read(classroomCacheProvider);
    final clock = ref.read(classroomsClockProvider);
    if (!_loadedCache) {
      _loadedCache = true;
      try {
        final stored = await cache.readWeek();
        if (!current()) return;
        if (stored != null) {
          final snapshot = readClassroomWeek(stored.payload);
          _cached = stored;
          _lastAttempt = stored.checkedAt;
          state = ClassroomsState(snapshot: snapshot);
        }
      } catch (error) {
        diagnostics.record(
          DiagnosticModule.cache,
          DiagnosticStage.read,
          error: error,
        );
      }
    }
    if (!current()) return;
    final now = clock().toUtc();
    final previous = state.snapshot;
    final previousAttempt = _lastAttempt;
    final newDay =
        previousAttempt != null &&
        campusDateAt(now) != campusDateAt(previousAttempt);
    if (!force && !_shouldRefresh(now, previousAttempt, previous, newDay)) {
      return;
    }
    _lastAttempt = now;
    state = ClassroomsState(snapshot: previous, isLoading: true);

    final response = await _fetch(
      force || newDay || previousAttempt != null,
      previous,
    );
    if (!current()) return;
    if (response == null) {
      _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, 4);
      state = ClassroomsState(snapshot: previous, refreshFailed: true);
      return;
    }
    final (snapshot, payload, headers, notModified) = response;
    _consecutiveFailures = 0;
    final checkedAt = clock().toUtc();
    final cacheControl =
        headers['cache-control'] ??
        (notModified ? _cached?.cacheControl : null);
    final policy = _cachePolicy(cacheControl);
    final entry = ClassroomCacheEntry(
      id: 1,
      payload: payload,
      checkedAt: checkedAt,
      etag: headers['etag'] ?? (notModified ? _cached?.etag : null),
      lastModified:
          headers['last-modified'] ??
          (notModified ? _cached?.lastModified : null),
      cacheControl: cacheControl,
      freshUntil: _serverFreshUntil(headers, policy, checkedAt),
    );
    final noStore = policy.containsKey('no-store');
    _cached = noStore ? null : entry;
    _lastAttempt = checkedAt;
    state = ClassroomsState(snapshot: snapshot);
    try {
      await _writes.write(
        version,
        () => noStore ? cache.removeWeek() : cache.writeWeek(entry),
      );
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.write,
        error: error,
      );
    }
  }

  Future<(ClassroomWeek, String, Map<String, String>, bool)?> _fetch(
    bool revalidate,
    ClassroomWeek? previous,
  ) async {
    try {
      final response = await ref
          .read(publicDataClientProvider)
          .getJson(
            _path,
            source: PublicDataSource.data,
            etag: _cached?.etag,
            lastModified: _cached?.lastModified,
            revalidate: revalidate,
          );
      final body = response.body;
      if (body == null) {
        final cached = _cached;
        if (cached == null || previous == null) {
          throw const FormatException('缺少空教室缓存');
        }
        return (previous, cached.payload, response.headers, true);
      }
      final parsed = readClassroomWeek(body);
      if (previous != null &&
          parsed.generatedAt.isBefore(previous.generatedAt)) {
        throw const FormatException('空教室快照早于当前数据');
      }
      return (parsed, body, response.headers, false);
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.publicData,
        error is FormatException
            ? DiagnosticStage.decode
            : DiagnosticStage.request,
        error: error,
      );
      return null;
    }
  }

  bool _shouldRefresh(
    DateTime now,
    DateTime? previousAttempt,
    ClassroomWeek? previous,
    bool newDay,
  ) {
    if (previousAttempt == null || newDay || now.isBefore(previousAttempt)) {
      return true;
    }
    final elapsed = now.difference(previousAttempt);
    if (_consecutiveFailures > 0) {
      return elapsed >= Duration(minutes: 1 << (_consecutiveFailures - 1));
    }
    if (elapsed >= refreshInterval) return true;
    // A slot expiring since the last check makes an early revalidation useful.
    final today = campusDateAt(now);
    return previous?.days.entries.any(
          (day) =>
              !day.key.isBefore(today) &&
              day.value.buildings.values.any(
                (slots) => slots.values.any(
                  (slot) =>
                      slot.isFreshAt(previousAttempt) && !slot.isFreshAt(now),
                ),
              ),
        ) ??
        false;
  }
}

Map<String, String> _cachePolicy(String? value) {
  final directives = <String, String>{};
  for (final directive in value?.split(',') ?? const <String>[]) {
    final parts = directive.split('=');
    directives[parts.first.trim().toLowerCase()] = parts
        .skip(1)
        .join('=')
        .trim()
        .replaceAll('"', '');
  }
  return directives;
}

DateTime? _serverFreshUntil(
  Map<String, String> headers,
  Map<String, String> policy,
  DateTime now,
) {
  final seconds = int.tryParse(policy['max-age'] ?? '');
  if (seconds == null || seconds <= 0 || policy.containsKey('no-cache')) {
    return null;
  }
  var age = int.tryParse(headers['age'] ?? '') ?? 0;
  final date = headers['date'];
  if (date != null) {
    try {
      final apparentAge = now.difference(HttpDate.parse(date)).inSeconds;
      if (apparentAge > age) age = apparentAge;
    } on HttpException {
      // An invalid HTTP Date does not override the reported Age.
    }
  }
  if (age >= seconds) return null;
  const maxDeltaSeconds = 0x7fffffff;
  return now.add(
    Duration(
      seconds:
          seconds.clamp(0, maxDeltaSeconds) - age.clamp(0, maxDeltaSeconds),
    ),
  );
}
