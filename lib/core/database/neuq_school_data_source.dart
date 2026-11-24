import '../../features/grades/data/neuq_grades.dart';
import '../../features/grades/domain/grades.dart';
import '../../features/services/data/neuq_classrooms.dart';
import '../../features/services/domain/classrooms.dart';
import '../../features/timetable/data/neuq_timetable.dart';
import '../../features/timetable/domain/timetable.dart';
import '../network/neuq_web_client.dart';
import '../time/campus_clock.dart';
import '../time/neuq_periods.dart';
import 'school_data_source.dart';

class NeuqSchoolDataSource implements SchoolDataSource {
  NeuqSchoolDataSource(this._web);

  final NeuqWebClient _web;
  (NeuqTimetableEntry, Map<String, Semester>)? _knownCalendar;
  DateTime? _calendarReadAt;

  Future<(NeuqTimetableEntry, Map<String, Semester>)> _calendar() async {
    final previous = _knownCalendar;
    final timestamp = _calendarReadAt;
    if (previous != null &&
        timestamp != null &&
        DateTime.now().difference(timestamp) < const Duration(minutes: 30)) {
      return previous;
    }
    final entry = readNeuqTimetableEntry(
      await _web.request(NeuqPage.timetable),
    );
    final terms = readNeuqSemesters(
      await _web.request(
        NeuqPage.calendar,
        form: {'tagId': entry.calendarTag, 'dataType': 'semesterCalendar'},
      ),
    );
    _calendarReadAt = DateTime.now();
    return _knownCalendar = (entry, terms);
  }

  @override
  Future<Timetable> fetchTimetable() => _web.read(() async {
    final (entry, terms) = await _calendar();
    final today = calendarDate(campusNow());
    final ordered = terms.entries.toList()
      ..sort((a, b) => b.value.start.compareTo(a.value.start));
    final active =
        ordered
            .where((term) => term.value.weekFor(today) != null)
            .firstOrNull ??
        ordered.where((term) => !term.value.start.isAfter(today)).firstOrNull;
    if (active == null) throw const FormatException('教务学期列表缺少当前学期');
    final response = await _web.request(
      NeuqPage.schedule,
      form: {
        'ignoreHead': '1',
        'setting.kind': 'std',
        'startWeek': '',
        'semester.id': active.key,
        // EAMS supplies this internal ID on the verified student's own page.
        'ids': entry.student,
      },
    );
    return Timetable([active.value], readNeuqCourses(response, active.value));
  });

  @override
  Future<SchoolGradeBook> fetchGrades() => _web.read(() async {
    final response = await _web.request(
      NeuqPage.grades,
      query: const {'projectType': 'MAJOR'},
    );
    Iterable<Semester> catalog = const [];
    try {
      final (_, known) = await _calendar();
      catalog = known.values;
    } on FormatException {
      // The grade reader also accepts terms in the published NEUQ calendars.
    } on SchoolWebFailure catch (error) {
      if (error == SchoolWebFailure.expired ||
          error == SchoolWebFailure.differentAccount) {
        rethrow;
      }
    }
    return readNeuqGrades(response, catalog);
  });

  @override
  Future<ClassroomSchedules> fetchClassrooms(DateTime day) =>
      _web.read(() async {
        await _web.prepareClassroomQuery();
        final form = NeuqClassroomForm(day);
        final byBuilding = {
          for (final building in CampusBuilding.values)
            building: <int, Set<String>>{},
        };
        final unresolved = <int>[];
        Object? firstFailure;
        final count = neuqPeriods.length;
        for (var start = 1; start <= count; start += 2) {
          try {
            final rooms = await _readRoomPeriod(form, start);
            final names = {
              for (final building in byBuilding.keys)
                building: _roomNames(rooms, building),
            };
            if (names.values.every((rooms) => rooms.isEmpty)) {
              unresolved.add(start);
              continue;
            }
            for (final entry in names.entries) {
              byBuilding[entry.key]![start] = entry.value;
            }
          } on FormatException catch (error) {
            unresolved.add(start);
            firstFailure ??= error;
          } on SchoolWebFailure catch (error) {
            if (error != SchoolWebFailure.unavailable) rethrow;
            unresolved.add(start);
            firstFailure ??= error;
          }
        }
        if (unresolved.isNotEmpty) {
          try {
            await _web.prepareClassroomQuery();
            final ids = await _web.classroomBuildingIds([
              for (final building in byBuilding.keys) building.label,
            ]);
            for (final start in unresolved) {
              for (final building in byBuilding.keys) {
                // The school's 工学馆 option has the verified value 1.
                final id =
                    ids[building.label] ??
                    (building == CampusBuilding.engineering ? '1' : null);
                if (id == null) continue;
                try {
                  final rooms = await _readRoomPeriod(
                    form,
                    start,
                    buildingId: id,
                  );
                  byBuilding[building]![start] = _roomNames(
                    rooms,
                    building,
                    scoped: true,
                  );
                } on FormatException catch (error) {
                  firstFailure ??= error;
                } on SchoolWebFailure catch (error) {
                  if (error != SchoolWebFailure.unavailable) rethrow;
                  firstFailure ??= error;
                }
              }
            }
          } on SchoolWebFailure catch (error) {
            if (error != SchoolWebFailure.unavailable) rethrow;
            firstFailure ??= error;
          }
        }
        if (byBuilding.values.every((periods) => periods.isEmpty)) {
          throw firstFailure ?? SchoolWebFailure.unavailable;
        }
        return (
          syncedAt: DateTime.now().toUtc(),
          buildings: Map<CampusBuilding, ClassroomSchedule>.unmodifiable({
            for (final entry in byBuilding.entries)
              entry.key: ClassroomSchedule(
                entry.value,
                periodCount: count,
                periodsPerGroup: 2,
              ),
          }),
        );
      });

  Future<List<NeuqRoom>> _readRoomPeriod(
    NeuqClassroomForm form,
    int period, {
    String? buildingId,
  }) async {
    Future<NeuqRoomPage> request(int page) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final fields = form.forPeriods(
        period,
        period + 1,
        page: page,
        buildingId: buildingId,
      );
      final response = await _web.request(NeuqPage.roomResult, form: fields);
      return readNeuqFreeRooms(response, requested: fields);
    }

    final first = await request(1);
    if (first.pages > 4) throw const FormatException('教务教室分页数量超出当日查询范围');
    final rooms = [...first.rooms];
    var rowCount = first.rowCount;
    for (var page = 2; page <= first.pages; page++) {
      final next = await request(page);
      if (next.rowCount == 0 ||
          (next.rooms.isNotEmpty && next.rooms.every(rooms.contains))) {
        throw const FormatException('教务教室分页结果不完整');
      }
      rooms.addAll(next.rooms);
      rowCount += next.rowCount;
    }
    if (first.total != null && rowCount != first.total) {
      throw const FormatException('教务教室查询结果仍有缺页');
    }
    return rooms;
  }
}

const _forbiddenRoomConfigs = {
  '体育教学场地',
  '机房',
  '实验室',
  '活动教室',
  '研讨室',
  '多功能',
  '智慧教室',
  '不排课教室',
  '语音室',
};

/// Excludes zero-capacity rooms and equipment categories outside this view.
bool _isUsableRoom(NeuqRoom room) {
  if (room.capacity == '0') return false;
  if (_forbiddenRoomConfigs.contains(room.equipment)) return false;
  return true;
}

Set<String> _roomNames(
  List<NeuqRoom> rooms,
  CampusBuilding building, {
  bool scoped = false,
}) {
  final names = <String>{};
  for (final room in rooms) {
    final actual = neuqRoomBuilding(room);
    if (actual != building &&
        !(scoped && actual == null && room.building.isEmpty)) {
      continue;
    }
    if (!_isUsableRoom(room)) continue;
    names.add(cleanRoomName(building.label, room.name));
  }
  return names;
}
