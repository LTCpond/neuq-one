import 'dart:convert';

import 'package:neuq_one/features/services/domain/classrooms.dart';

final classroomNow = DateTime.utc(2026, 11, 25, 8, 20);
final classroomToday = DateTime.utc(2026, 11, 25);
const classroomCollectedAt = '2026-11-25T16:19:00+08:00';
const classroomExpiresAt = '2026-11-25T17:19:00+08:00';

Map<String, dynamic> classroomWeekFixture() => {
  'schemaVersion': 1,
  'timezone': 'Asia/Shanghai',
  'source': 'NEUQ 教务系统',
  'generatedAt': '2026-11-25T16:19:12.440823154+08:00',
  'days': [
    for (var day = 0; day < 7; day++)
      <String, dynamic>{
        'date': classroomToday
            .add(Duration(days: day))
            .toIso8601String()
            .split('T')
            .first,
        'updatedAt': classroomCollectedAt,
        'complete': true,
        'buildings': {
          for (final building in CampusBuilding.values)
            building.label: {
              for (final period in classroomPeriods.entries)
                period.value: classroomSlotFixture(switch ((
                  building,
                  day,
                  period.key,
                )) {
                  (CampusBuilding.engineering, 0, 1) => ['101', '102', '207'],
                  (CampusBuilding.engineering, 0, 3 || 7 || 9 || 11) => ['102'],
                  (CampusBuilding.engineering, 0, _) => [],
                  (CampusBuilding.engineering, _, _) => ['301'],
                  (CampusBuilding.science, _, _) => ['6077'],
                  (CampusBuilding.humanities, _, 1) => ['210'],
                  _ => [],
                }),
            },
        },
      },
  ],
};

Map<String, dynamic> classroomSlotFixture(
  List<String>? rooms, {
  String status = 'success',
  String collectedAt = classroomCollectedAt,
  String expiresAt = classroomExpiresAt,
}) => {
  'status': status,
  'rooms': rooms,
  'roomDetails': rooms == null
      ? null
      : {
          for (final name in rooms) name: {'capacity': 60, 'equipment': '普通教室'},
        },
  'collectedAt': rooms == null ? null : collectedAt,
  'expiresAt': rooms == null ? null : expiresAt,
};

String classroomWeekBody() => jsonEncode(classroomWeekFixture());

Map<String, dynamic> fixtureDay(Map<String, dynamic> week, [int index = 0]) =>
    (week['days'] as List<Map<String, dynamic>>)[index];

Map<String, Map<String, dynamic>> fixturePeriods(
  Map<String, dynamic> week, [
  CampusBuilding building = CampusBuilding.engineering,
]) =>
    fixtureDay(week)['buildings'][building.label]
        as Map<String, Map<String, dynamic>>;
