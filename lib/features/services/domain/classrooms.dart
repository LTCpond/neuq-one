enum CampusBuilding {
  engineering('工学馆'),
  science('科技楼'),
  humanities('人文楼');

  const CampusBuilding(this.label);
  final String label;
}

enum ClassroomAvailability { allDay, nextBooked, partial }

typedef FreeClassroom = ({String name, ClassroomAvailability availability});

const classroomPeriods = {
  1: '1-2',
  3: '3-4',
  5: '5-6',
  7: '7-8',
  9: '9-10',
  11: '11-12',
};

enum ClassroomSlotStatus { success, stale, unavailable }

enum ClassroomBuildingStatus { fresh, partial, historical, unavailable }

({DateTime? updatedAt, ClassroomBuildingStatus status}) classroomBuildingAt(
  Map<int, ClassroomSlot>? slots,
  DateTime now,
) {
  DateTime? updatedAt;
  var fresh = 0;
  var historical = 0;
  for (final period in classroomPeriods.keys) {
    final slot = slots?[period];
    switch (slot?.statusAt(now)) {
      case ClassroomSlotStatus.success:
        fresh++;
      case ClassroomSlotStatus.stale:
        historical++;
      case ClassroomSlotStatus.unavailable || null:
        continue;
    }
    final collected = slot?.collectedAt;
    if (collected != null &&
        (updatedAt == null || collected.isAfter(updatedAt))) {
      updatedAt = collected;
    }
  }
  return (
    updatedAt: updatedAt,
    status: switch ((fresh, historical)) {
      (0, 0) => ClassroomBuildingStatus.unavailable,
      (0, _) => ClassroomBuildingStatus.historical,
      (final count, _) when count == classroomPeriods.length =>
        ClassroomBuildingStatus.fresh,
      _ => ClassroomBuildingStatus.partial,
    },
  );
}

typedef ClassroomRoomDetail = ({int? capacity, String? equipment});

class ClassroomSlot {
  const ClassroomSlot({
    required this.status,
    this.rooms,
    this.roomDetails,
    this.collectedAt,
    this.expiresAt,
  });

  final ClassroomSlotStatus status;
  final Set<String>? rooms;
  final Map<String, ClassroomRoomDetail>? roomDetails;
  final DateTime? collectedAt;
  final DateTime? expiresAt;

  ClassroomSlotStatus statusAt(DateTime now) =>
      status == ClassroomSlotStatus.success && !now.isBefore(expiresAt!)
      ? ClassroomSlotStatus.stale
      : status;

  bool isFreshAt(DateTime now) => statusAt(now) == ClassroomSlotStatus.success;
}

typedef ClassroomDay = ({
  DateTime? updatedAt,
  bool complete,
  Map<CampusBuilding, Map<int, ClassroomSlot>> buildings,
});

class ClassroomWeek {
  const ClassroomWeek(this.generatedAt, this.days);

  final DateTime generatedAt;
  final Map<DateTime, ClassroomDay> days;
}

ClassroomSchedule classroomScheduleAt(
  Map<int, ClassroomSlot> slots,
  DateTime now,
) => ClassroomSchedule(
  {
    for (final entry in slots.entries)
      if (entry.value.isFreshAt(now)) entry.key: entry.value.rooms!,
  },
  periodCount: 12,
  periodsPerGroup: 2,
);

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

int? engineeringRoomFloor(String name) => int.tryParse(
  _engineeringRoomNumber.firstMatch(name.trim())?.group(1) ?? '',
);

final _engineeringRoomNumber = RegExp(
  r'^(?:工学馆\s*)?(?:[Gg]\s*)?([1-9])\d{2}(?!\d)',
);
