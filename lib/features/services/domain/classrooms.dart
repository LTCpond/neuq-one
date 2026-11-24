enum CampusBuilding {
  engineering('工学馆'),
  science('科技楼'),
  humanities('人文楼');

  const CampusBuilding(this.label);
  final String label;
}

class ClassroomDay {
  const ClassroomDay({required this.name, required this.occupiedPeriods});

  final String name;
  final Set<int> occupiedPeriods;
}

enum ClassroomAvailability { allDay, nextBooked, partial }

ClassroomAvailability? classroomAvailability(
  ClassroomDay room,
  int start,
  int end,
) {
  if (room.occupiedPeriods.isEmpty) return ClassroomAvailability.allDay;
  if (room.occupiedPeriods.any((period) => period >= start && period <= end)) {
    return null;
  }
  if (room.occupiedPeriods.contains(end + 1)) {
    return ClassroomAvailability.nextBooked;
  }
  return ClassroomAvailability.partial;
}

typedef FreeClassroom = ({String name, ClassroomAvailability availability});

typedef ClassroomSchedules = ({
  DateTime syncedAt,
  Map<CampusBuilding, ClassroomSchedule> buildings,
});

class ClassroomSchedule {
  ClassroomSchedule(
    Map<int, Set<String>> periods, {
    required this.periodCount,
    this.periodsPerGroup = 1,
  }) : assert(periodCount > 0),
       assert(periodsPerGroup > 0),
       freeByPeriod = Map.unmodifiable(
         periods.map(
           (period, rooms) => MapEntry(period, Set<String>.unmodifiable(rooms)),
         ),
       );

  final Map<int, Set<String>> freeByPeriod;
  final int periodCount;
  final int periodsPerGroup;

  Iterable<int> get groupStarts sync* {
    for (var period = 1; period <= periodCount; period += periodsPerGroup) {
      yield period;
    }
  }

  bool get complete => groupStarts.every(freeByPeriod.containsKey);

  late final Set<String> allDay = complete
      ? groupStarts
            .map((period) => freeByPeriod[period]!)
            .reduce((a, b) => a.intersection(b))
      : const {};

  List<FreeClassroom>? forPeriod(int period) {
    final current = freeByPeriod[period];
    if (current == null) return null;
    final next = freeByPeriod[period + periodsPerGroup];
    return [
      for (final name in current.toList()..sort())
        (
          name: name,
          availability: allDay.contains(name)
              ? ClassroomAvailability.allDay
              : next != null && !next.contains(name)
              ? ClassroomAvailability.nextBooked
              : ClassroomAvailability.partial,
        ),
    ];
  }
}

abstract interface class SchoolClassroomsDataSource {
  Future<ClassroomSchedules> fetchClassrooms(DateTime day);
}

/// 用房间编号简写已知格式的教室名称，保留教务返回的其他名称。
String cleanRoomName(String building, String name) {
  switch (building) {
    case '工学馆':
    case '人文楼':
      return _extractNumber(name, building);
    case '科技楼':
      return _cleanKeji(name) ?? name;
    default:
      return name;
  }
}

int? engineeringRoomFloor(String name) => int.tryParse(
  _engineeringRoomNumber.firstMatch(name.trim())?.group(1) ?? '',
);

final _engineeringRoomNumber = RegExp(
  r'^(?:工学馆\s*)?(?:[Gg]\s*)?([1-9])\d{2}(?!\d)',
);
final _numberPattern = RegExp(r'^\d+[A-Z]?$|^\d+[A-Z]?-[A-Z\d-]+$');
final _zizhuPattern = RegExp(r'^自主学习室([A-Z])科技楼(.+)$');

String _extractNumber(String name, String prefix) {
  if (name.startsWith(prefix)) {
    final rest = name.substring(prefix.length);
    if (_numberPattern.hasMatch(rest)) return rest;
  }
  return name;
}

String? _cleanKeji(String name) {
  if (name.startsWith('科技楼')) {
    final rest = name.substring('科技楼'.length);
    if (_numberPattern.hasMatch(rest)) return rest;
  }
  final match = _zizhuPattern.firstMatch(name);
  if (match != null) return '${match.group(2)}自习室${match.group(1)}';
  return null;
}
