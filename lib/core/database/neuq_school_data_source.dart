import '../../features/grades/data/neuq_grades.dart';
import '../../features/grades/domain/grades.dart';
import '../../features/timetable/data/neuq_timetable.dart';
import '../../features/timetable/domain/timetable.dart';
import '../network/neuq_web_client.dart';
import '../time/campus_clock.dart';
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
}
