import 'dart:convert';

import '../../../core/time/campus_clock.dart';
import '../domain/classrooms.dart';

ClassroomWeek readClassroomWeek(String body) {
  final root = _object(jsonDecode(body), const {
    'schemaVersion',
    'timezone',
    'source',
    'generatedAt',
    'days',
  });
  if (root['schemaVersion'] is! int ||
      root['schemaVersion'] != 1 ||
      root['timezone'] != 'Asia/Shanghai' ||
      root['source'] != 'NEUQ 教务系统') {
    throw const FormatException('不支持的空教室快照版本或来源');
  }
  final generatedAt = _timestamp(root['generatedAt']);
  final rawDays = root['days'];
  if (rawDays is! List || rawDays.isEmpty || rawDays.length > 14) {
    throw const FormatException('空教室快照日期范围无效');
  }
  final days = <DateTime, ClassroomDay>{};
  Set<String>? buildingNames;
  final first = campusDateAt(generatedAt);
  for (final (index, value) in rawDays.indexed) {
    final raw = _object(value, const {
      'date',
      'updatedAt',
      'complete',
      'buildings',
    });
    final date = first.add(Duration(days: index));
    if (raw['date'] != date.toIso8601String().split('T').first) {
      throw const FormatException('空教室快照日期不连续');
    }
    final rawBuildings = _object(raw['buildings']);
    buildingNames ??= rawBuildings.keys.toSet();
    if (rawBuildings.isEmpty ||
        rawBuildings.length > 20 ||
        rawBuildings.length != buildingNames.length ||
        !rawBuildings.keys.every(
          (name) =>
              buildingNames!.contains(name) && _buildingName.hasMatch(name),
        )) {
      throw const FormatException('空教室快照楼栋范围无效');
    }

    final buildings = <CampusBuilding, Map<int, ClassroomSlot>>{};
    var complete = true;
    DateTime? latest;
    for (final entry in rawBuildings.entries) {
      final rawPeriods = _object(entry.value, classroomPeriods.values.toSet());
      final slots = {
        for (final period in classroomPeriods.entries)
          period.key: _readSlot(rawPeriods[period.value], generatedAt, date),
      };
      for (final slot in slots.values) {
        complete = complete && slot.status == ClassroomSlotStatus.success;
        final collected = slot.collectedAt;
        if (collected != null &&
            (latest == null || collected.isAfter(latest))) {
          latest = collected;
        }
      }
      final building = CampusBuilding.values
          .where((building) => building.label == entry.key)
          .firstOrNull;
      if (building != null) buildings[building] = Map.unmodifiable(slots);
    }
    final updatedAt = raw['updatedAt'] == null
        ? null
        : _timestamp(raw['updatedAt']);
    if (raw['complete'] != complete || updatedAt != latest) {
      throw const FormatException('空教室日期汇总与时段不一致');
    }
    days[date] = (
      updatedAt: updatedAt,
      complete: complete,
      buildings: Map.unmodifiable(buildings),
    );
  }
  return ClassroomWeek(generatedAt, Map.unmodifiable(days));
}

ClassroomSlot _readSlot(Object? value, DateTime generatedAt, DateTime date) {
  final raw = _object(value, const {
    'status',
    'rooms',
    'roomDetails',
    'collectedAt',
    'expiresAt',
  });
  final status = switch (raw['status']) {
    'success' => ClassroomSlotStatus.success,
    'stale' => ClassroomSlotStatus.stale,
    'unavailable' => ClassroomSlotStatus.unavailable,
    _ => throw const FormatException('未知的空教室时段状态'),
  };
  if (status == ClassroomSlotStatus.unavailable) {
    if (raw.entries.any(
      (entry) => entry.key != 'status' && entry.value != null,
    )) {
      throw const FormatException('不可用时段包含教室数据');
    }
    return const ClassroomSlot(status: ClassroomSlotStatus.unavailable);
  }

  final collectedAt = _timestamp(raw['collectedAt']);
  final expiresAt = _timestamp(raw['expiresAt']);
  if (collectedAt.isAfter(generatedAt) ||
      campusDateAt(collectedAt).isAfter(date) ||
      !expiresAt.isAfter(collectedAt) ||
      expiresAt.difference(collectedAt) > const Duration(hours: 72) ||
      (status == ClassroomSlotStatus.success &&
          !generatedAt.isBefore(expiresAt))) {
    throw const FormatException('空教室时段采集时间或有效期无效');
  }

  final rawRooms = raw['rooms'];
  final rawDetails = _object(raw['roomDetails']);
  if (rawRooms is! List || rawRooms.length != rawDetails.length) {
    throw const FormatException('空教室列表与详情不一致');
  }
  final details = <String, ClassroomRoomDetail>{};
  String? previous;
  for (final name in rawRooms) {
    if (name is! String ||
        !_roomName.hasMatch(name) ||
        (previous != null && previous.compareTo(name) >= 0)) {
      throw const FormatException('空教室编号无效或重复');
    }
    previous = name;
    final detail = _object(rawDetails[name], const {'capacity', 'equipment'});
    final capacity = detail['capacity'];
    final equipment = detail['equipment'];
    if ((capacity != null &&
            (capacity is! int || capacity < 1 || capacity > 3000)) ||
        (equipment != null && !_equipment.contains(equipment))) {
      throw const FormatException('空教室容量或配置无效');
    }
    details[name] = (
      capacity: capacity as int?,
      equipment: equipment as String?,
    );
  }
  return ClassroomSlot(
    status: status,
    rooms: Set.unmodifiable(details.keys),
    roomDetails: Map.unmodifiable(details),
    collectedAt: collectedAt,
    expiresAt: expiresAt,
  );
}

Map<String, dynamic> _object(Object? value, [Set<String>? keys]) {
  if (value is! Map<String, dynamic> ||
      (keys != null &&
          (value.length != keys.length || !keys.every(value.containsKey)))) {
    throw const FormatException('空教室快照字段不完整或未知');
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String || !_beijingTimestamp.hasMatch(value)) {
    throw const FormatException('空教室快照时间必须采用北京时间');
  }
  final time = DateTime.tryParse(value);
  // DateTime normalizes out-of-range calendar fields, such as February 30.
  if (time == null ||
      !time
          .add(campusOffset)
          .toIso8601String()
          .startsWith(value.substring(0, 19))) {
    throw const FormatException('空教室快照时间无效');
  }
  return time;
}

final _beijingTimestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?\+08:00$',
);
final _buildingName = RegExp(r'^\p{Script=Han}{2,16}$', unicode: true);
final _roomName = RegExp(
  r'^[A-Z]?[0-9]{2,5}[A-Z]?(?:-[A-Z0-9]{1,4}){0,2}(?:自习室[A-Z])?$',
);
const _equipment = {
  '普通教室',
  '标准教室',
  '多媒体教室',
  '多媒体大教室',
  '多媒体中教室',
  '多媒体小教室',
  '录播教室',
  '普通多媒体教室',
  '阶梯教室',
};
