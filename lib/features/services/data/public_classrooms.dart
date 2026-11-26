import 'dart:io' show HttpDate, HttpException;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/public_data_client.dart';
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
  static const _refreshInterval = Duration(minutes: 30);
  ClassroomCacheEntry? _cached;
  DateTime? _lastAttempt;
  Future<void>? _inFlight;
  bool _loadedCache = false;

  @override
  ClassroomsState build() => const ClassroomsState(isLoading: true);

  Future<void> refresh({bool force = false}) =>
      _inFlight ??= _refresh(force).whenComplete(() => _inFlight = null);

  Future<void> _refresh(bool force) async {
    final cache = ref.read(classroomCacheProvider);
    final clock = ref.read(classroomsClockProvider);
    if (!_loadedCache) {
      _loadedCache = true;
      try {
        final stored = await cache.readWeek();
        if (!ref.mounted) return;
        if (stored != null) {
          final snapshot = readClassroomWeek(stored.payload);
          _cached = stored;
          _lastAttempt = stored.checkedAt;
          state = ClassroomsState(snapshot: snapshot);
        }
      } catch (_) {
        // An unreadable cache should not prevent the first public GET.
      }
    }
    if (!ref.mounted) return;
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

    final response = await _fetch(force || newDay, previous);
    if (!ref.mounted) return;
    if (response == null) {
      state = ClassroomsState(snapshot: previous, refreshFailed: true);
      return;
    }
    final (snapshot, payload, headers, notModified) = response;
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
      if (noStore) {
        await cache.removeWeek();
      } else {
        await cache.writeWeek(entry);
      }
    } catch (_) {
      // Keep the validated response available in memory if SQLite fails.
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
        if (cached == null || previous == null) return null;
        return (previous, cached.payload, response.headers, true);
      }
      final parsed = readClassroomWeek(body);
      if (previous != null &&
          parsed.generatedAt.isBefore(previous.generatedAt)) {
        return null;
      }
      return (parsed, body, response.headers, false);
    } catch (_) {
      // A request or decoding failure leaves the previous validated week intact.
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
    final freshUntil = _cached?.freshUntil;
    if (freshUntil != null && now.isBefore(freshUntil)) return false;
    if (now.difference(previousAttempt) >= _refreshInterval) return true;
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
