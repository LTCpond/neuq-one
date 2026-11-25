import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/features/services/data/classroom_cache.dart';
import 'package:neuq_one/features/services/data/classroom_week_json.dart';
import 'package:neuq_one/features/services/data/public_classrooms.dart';
import 'package:neuq_one/features/services/domain/classrooms.dart';

import 'fixtures/classroom_week.dart';

void main() {
  test(
    'decodes seven consecutive Beijing dates, buildings and period keys',
    () {
      final week = readClassroomWeek(classroomWeekBody());
      expect(week.generatedAt, DateTime.utc(2026, 11, 25, 8, 19, 12, 440, 823));
      expect(week.days.keys, [
        for (var i = 0; i < 7; i++) classroomToday.add(Duration(days: i)),
      ]);
      final day = week.days[classroomToday]!;
      expect(day.updatedAt, DateTime.utc(2026, 11, 25, 8, 19));
      expect(day.complete, isTrue);
      expect(day.buildings.keys, unorderedEquals(CampusBuilding.values));
      final engineering = day.buildings[CampusBuilding.engineering]!;
      expect(engineering.keys, [1, 3, 5, 7, 9, 11]);
      expect(engineering[1]!.roomDetails!['101'], (
        capacity: 60,
        equipment: '普通教室',
      ));
      expect(engineering[5]!.rooms, isEmpty);
      expect(engineering[5]!.roomDetails, isEmpty);
      expect(
        classroomScheduleAt(engineering, classroomNow).forPeriod(5),
        isEmpty,
      );
      expect(day.buildings[CampusBuilding.humanities]![1]!.rooms, {'210'});
      expect(
        week
            .days[DateTime.utc(2026, 12, 1)]!
            .buildings[CampusBuilding.engineering]![1]!
            .rooms,
        {'301'},
      );
    },
  );

  test('distinguishes stale, unavailable and locally expired periods', () {
    final fixture = classroomWeekFixture();
    fixtureDay(fixture)['complete'] = false;
    final periods = fixturePeriods(fixture);
    periods['3-4'] = classroomSlotFixture(null, status: 'unavailable');
    periods['5-6'] = classroomSlotFixture([], status: 'stale');
    periods['7-8'] = classroomSlotFixture(['102'], status: 'stale');
    periods['9-10'] = classroomSlotFixture([
      '102',
    ], expiresAt: '2026-11-25T16:20:00+08:00');
    final slots = readClassroomWeek(jsonEncode(fixture))
        .days[classroomToday]!
        .buildings[CampusBuilding.engineering]!;
    expect(slots[3]!.rooms, isNull);
    expect(slots[3]!.roomDetails, isNull);
    expect(slots[5]!.rooms, isEmpty);
    expect(slots[5]!.statusAt(classroomNow), ClassroomSlotStatus.stale);
    expect(slots[7]!.rooms, {'102'});
    expect(slots[9]!.status, ClassroomSlotStatus.success);
    expect(slots[9]!.statusAt(classroomNow), ClassroomSlotStatus.stale);
    final schedule = classroomScheduleAt(slots, classroomNow);
    expect(schedule.allDay, isEmpty);
    expect(
      schedule.forPeriod(1)!.map((room) => room.availability),
      everyElement(ClassroomAvailability.partial),
    );
    expect(schedule.forPeriod(3), isNull);
    expect(schedule.forPeriod(5), isNull);
    expect(schedule.forPeriod(9), isNull);
  });

  test('derives full-day and next-period labels only from valid slots', () {
    final day = readClassroomWeek(classroomWeekBody()).days[classroomToday]!;
    final science = classroomScheduleAt(
      day.buildings[CampusBuilding.science]!,
      classroomNow,
    );
    expect(science.allDay, {'6077'});
    expect(
      science.forPeriod(11)!.single.availability,
      ClassroomAvailability.allDay,
    );
    final engineering = classroomScheduleAt(
      day.buildings[CampusBuilding.engineering]!,
      classroomNow,
    );
    expect(engineering.forPeriod(1), [
      (name: '101', availability: ClassroomAvailability.nextBooked),
      (name: '102', availability: ClassroomAvailability.partial),
      (name: '207', availability: ClassroomAvailability.nextBooked),
    ]);
    expect(
      engineering.forPeriod(3)!.single.availability,
      ClassroomAvailability.nextBooked,
    );
    expect(
      engineering.forPeriod(11)!.single.availability,
      ClassroomAvailability.partial,
    );

    final expiry = DateTime.utc(2026, 11, 25, 9, 19);
    final expired = classroomScheduleAt(
      day.buildings[CampusBuilding.science]!,
      expiry,
    );
    expect(expired.allDay, isEmpty);
    expect(expired.forPeriod(1), isNull);
  });

  test('preserves engineering floor grouping for the public room names', () {
    expect(engineeringRoomFloor('G410'), 4);
    expect(engineeringRoomFloor('803'), 8);
    expect(engineeringRoomFloor('1201'), isNull);
  });

  test(
    'rejects malformed JSON and invalid schema fields and relationships',
    () {
      expect(() => readClassroomWeek('{"days":'), throwsFormatException);
      final mutations = <void Function(Map<String, dynamic>)>[
        (root) => root['schemaVersion'] = 2,
        (root) => root['timezone'] = 'UTC',
        (root) => root['source'] = '其他来源',
        (root) => root['generatedAt'] = '2026-11-25T16:19:00Z',
        (root) => root['generatedAt'] = '2026-02-30T16:19:00+08:00',
        (root) => fixtureDay(root, 1)['date'] = '2026-11-25',
        (root) => fixtureDay(root)['complete'] = false,
        (root) => fixtureDay(root)['updatedAt'] = '2026-11-25T16:18:00+08:00',
        (root) => fixtureDay(root)['buildings'].remove('工学馆'),
        (root) => fixturePeriods(root).remove('11-12'),
        (root) => fixturePeriods(root)['1-2']!['rooms'] = ['101', '101', '207'],
        (root) =>
            fixturePeriods(root)['1-2']!['roomDetails']['101']['capacity'] = 0,
        (root) =>
            fixturePeriods(root)['1-2']!['roomDetails']['101']['equipment'] =
                '机房',
        (root) => fixturePeriods(root)['1-2']!['roomDetails'].remove('101'),
        (root) => fixturePeriods(root)['1-2']!['collectedAt'] =
            '2026-11-25T16:20:00+08:00',
        (root) =>
            fixturePeriods(root)['1-2']!['expiresAt'] = classroomCollectedAt,
        (root) => fixturePeriods(root)['1-2']!['status'] = 'unavailable',
        (root) => fixturePeriods(root)['1-2']!['status'] = 'pending',
      ];
      for (final (index, mutate) in mutations.indexed) {
        final body = classroomWeekFixture();
        mutate(body);
        expect(
          () => readClassroomWeek(jsonEncode(body)),
          throwsFormatException,
          reason: 'mutation $index',
        );
      }
    },
  );

  test('accepts fully unavailable dates with null collection metadata', () {
    final fixture = classroomWeekFixture();
    final day = fixtureDay(fixture, 6);
    day['complete'] = false;
    day['updatedAt'] = null;
    for (final periods in (day['buildings'] as Map).values) {
      for (final name in classroomPeriods.values) {
        periods[name] = classroomSlotFixture(null, status: 'unavailable');
      }
    }
    final parsed = readClassroomWeek(jsonEncode(fixture))
        .days[DateTime.utc(2026, 12, 1)]!;
    expect(parsed.updatedAt, isNull);
    expect(parsed.complete, isFalse);
  });

  test(
    'shares concurrent preload and manual operations without a school session',
    () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      var requests = 0;
      final scope = _scope((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(
          request.url,
          publicDataRoot.replace(path: '/api/v1/classrooms/week.json'),
        );
        expect(request.followRedirects, isFalse);
        expect(
          request.headers.keys.map((name) => name.toLowerCase()),
          unorderedEquals(['accept']),
        );
        requested.complete();
        return pending.future;
      });
      final controller = scope.read(classroomsProvider.notifier);
      final first = controller.refresh();
      final manual = controller.refresh(force: true);
      expect(identical(first, manual), isTrue);
      await requested.future;
      expect(scope.read(classroomsProvider).isLoading, isTrue);
      pending.complete(_json());
      await Future.wait([first, manual]);
      expect(scope.read(classroomsProvider).snapshot!.days, hasLength(7));
      await controller.refresh();
      expect(requests, 1);
    },
  );

  test('restores SQLite cache, revalidates with ETag and Last-Modified, and keeps slot expiry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'public_classrooms_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/classrooms.sqlite');
    const etag = '"rooms-v1"';
    const lastModified = 'Wed, 25 Nov 2026 08:19:12 GMT';
    final initialCache = ClassroomCache(NativeDatabase(file));
    final initial = _scope(
      (_) async => _json(
        headers: {
          'etag': etag,
          'last-modified': lastModified,
          'cache-control': 'public, max-age=60, must-revalidate',
        },
      ),
      cache: initialCache,
    );
    await initial.read(classroomsProvider.notifier).refresh();
    await initialCache.close();

    var now = classroomNow;
    var calls = 0;
    final cache = ClassroomCache(NativeDatabase(file));
    addTearDown(cache.close);
    final reopened = _scope(
      (request) async {
        calls++;
        expect(request.headers['if-none-match'], etag);
        expect(request.headers['if-modified-since'], lastModified);
        expect(request.headers['cache-control'], 'no-cache');
        return http.Response(
          '',
          304,
          headers: {'age': '10', 'date': 'invalid'},
        );
      },
      clock: () => now,
      cache: cache,
    );
    final controller = reopened.read(classroomsProvider.notifier);
    await controller.refresh();
    expect(calls, 0);
    final restored = reopened.read(classroomsProvider).snapshot!;
    expect(
      restored
          .days[classroomToday]!
          .buildings[CampusBuilding.engineering]![1]!
          .rooms,
      contains('101'),
    );
    now = DateTime.utc(2026, 11, 25, 9, 19);
    await controller.refresh(force: true);
    expect(calls, 1);
    expect(reopened.read(classroomsProvider).snapshot, same(restored));
    final saved = (await cache.readWeek())!;
    expect(saved.etag, etag);
    expect(saved.payload, classroomWeekBody());
    expect(saved.freshUntil!.toUtc(), now.add(const Duration(seconds: 50)));
    expect(
      restored.days[classroomToday]!.buildings[CampusBuilding.engineering]![1]!
          .statusAt(now),
      ClassroomSlotStatus.stale,
    );
  });

  test(
    'network failures and invalid responses keep the latest validated week',
    () async {
      var count = 0;
      final scope = _scope((request) async {
        expect(request.url.host, publicDataRoot.host);
        expect(request.followRedirects, isFalse);
        return switch (++count) {
          1 => _json(),
          2 => throw const SocketException('offline'),
          3 => http.Response('', 404),
          4 => http.Response('', 503),
          5 => http.Response('{', 200),
          _ => http.Response(
            '',
            302,
            headers: {
              'location': 'https://jwxt.neuq.edu.cn/eams/homeExt.action',
            },
          ),
        };
      });
      final controller = scope.read(classroomsProvider.notifier);
      await controller.refresh();
      final saved = scope.read(classroomsProvider).snapshot;
      for (var i = 0; i < 5; i++) {
        await controller.refresh(force: true);
        expect(scope.read(classroomsProvider).refreshFailed, isTrue);
        expect(scope.read(classroomsProvider).snapshot, same(saved));
      }
      expect(count, 6);
    },
  );

  test(
    'automatic refresh uses the thirty-minute interval and early slot expiry',
    () async {
      var now = classroomNow;
      var calls = 0;
      final scope = _scope((_) async {
        calls++;
        return _json(headers: {'cache-control': 'public, max-age=60'});
      }, clock: () => now);
      final controller = scope.read(classroomsProvider.notifier);
      await controller.refresh();
      now = now.add(const Duration(minutes: 29));
      await controller.refresh();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 1));
      await controller.refresh();
      expect(calls, 2);
      now = now.add(const Duration(minutes: 29));
      await controller.refresh();
      expect(calls, 3);
      await controller.refresh();
      expect(calls, 3);
    },
  );

  test('failed first request has no empty-room result', () async {
    final scope = _scope((_) async => http.Response('', 503));
    await scope.read(classroomsProvider.notifier).refresh();
    expect(scope.read(classroomsProvider).snapshot, isNull);
    expect(scope.read(classroomsProvider).refreshFailed, isTrue);
  });

  test(
    'Beijing midnight revalidates once and cached days match exactly',
    () async {
      var now = DateTime.utc(2026, 11, 25, 15, 59);
      var count = 0;
      final scope = _scope(
        (_) async => ++count == 1 ? _json() : http.Response('', 503),
        clock: () => now,
      );
      final controller = scope.read(classroomsProvider.notifier);
      await controller.refresh();
      final first = scope.read(classroomsProvider).snapshot!;
      expect(campusDateAt(now), classroomToday);
      now = now.add(const Duration(minutes: 1));
      final tomorrow = campusDateAt(now);
      expect(tomorrow, DateTime.utc(2026, 11, 26));
      await controller.refresh();
      final next = scope.read(classroomsProvider).snapshot!;
      expect(next, same(first));
      expect(
        next.days[tomorrow]!.buildings[CampusBuilding.engineering]![1]!.rooms,
        {'301'},
      );
      expect(next.days[DateTime.utc(2026, 12, 2)], isNull);
      await controller.refresh();
      expect(count, 2);
    },
  );
}

http.Response _json({Map<String, String>? headers}) => http.Response.bytes(
  utf8.encode(classroomWeekBody()),
  200,
  headers: headers ?? const {},
);

ProviderContainer _scope(
  Future<http.Response> Function(http.Request) handler, {
  DateTime Function()? clock,
  ClassroomCache? cache,
}) {
  final db = cache ?? ClassroomCache(NativeDatabase.memory());
  if (cache == null) addTearDown(db.close);
  final client = MockClient(handler);
  addTearDown(client.close);
  return ProviderContainer.test(
    overrides: [
      classroomCacheProvider.overrideWithValue(db),
      classroomsClockProvider.overrideWithValue(clock ?? () => classroomNow),
      publicDataClientProvider.overrideWithValue(PublicDataClient(client)),
      schoolSessionProvider.overrideWith(
        () => throw StateError('unexpected session access'),
      ),
      schoolDataSourceProvider.overrideWith(
        (_) => throw StateError('unexpected school lookup'),
      ),
      neuqClientProvider.overrideWith(
        (_) => throw StateError('unexpected school client'),
      ),
    ],
  );
}
