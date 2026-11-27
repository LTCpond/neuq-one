import '../../features/grades/data/neuq_grades.dart';
import '../../features/grades/data/neuq_plan_completion.dart';
import '../../features/grades/domain/grades.dart';
import '../../features/grades/domain/plan_completion.dart';
import '../../features/timetable/data/neuq_timetable.dart';
import '../../features/timetable/domain/timetable.dart';
import '../network/neuq_client.dart';
import '../time/campus_clock.dart';
import 'school_data_source.dart';

class NeuqSchoolDataSource implements SchoolDataSource {
  NeuqSchoolDataSource(this._client, this._subject);

  final NeuqClient _client;
  final String _subject;
  ({
    NeuqSession session,
    DateTime readAt,
    (NeuqTimetableEntry, Map<String, Semester>) data,
  })?
  _knownCalendar;

  Future<(NeuqTimetableEntry, Map<String, Semester>)> _calendar(
    NeuqSession session,
  ) async {
    final previous = _knownCalendar;
    if (previous != null &&
        identical(previous.session, session) &&
        DateTime.now().difference(previous.readAt) <
            const Duration(minutes: 30)) {
      return previous.data;
    }
    final entry = readNeuqTimetableEntry(
      await session.request(NeuqPage.timetable),
    );
    final terms = readNeuqSemesters(
      await session.request(
        NeuqPage.calendar,
        form: {'tagId': entry.calendarTag, 'dataType': 'semesterCalendar'},
      ),
    );
    final data = (entry, terms);
    _knownCalendar = (session: session, readAt: DateTime.now(), data: data);
    return data;
  }

  @override
  Future<Timetable> fetchTimetable() => _client.read(_subject, (session) async {
    final (entry, terms) = await _calendar(session);
    final today = calendarDate(campusNow());
    final ordered = terms.entries.toList()
      ..sort((a, b) => b.value.start.compareTo(a.value.start));
    final active =
        ordered
            .where((term) => term.value.weekFor(today) != null)
            .firstOrNull ??
        ordered.where((term) => !term.value.start.isAfter(today)).firstOrNull;
    if (active == null) throw const FormatException('教务学期列表缺少当前学期');
    final response = await session.request(
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
  Future<SchoolGradeBook> fetchGrades() => _client.read(_subject, (
    session,
  ) async {
    final response = await session.request(
      NeuqPage.grades,
      query: const {'projectType': 'MAJOR'},
    );
    Iterable<Semester> catalog = const [];
    try {
      final (_, known) = await _calendar(session);
      catalog = known.values;
    } on FormatException {
      // The grade reader also accepts terms in the published NEUQ calendars.
    } on SchoolRequestFailure catch (error) {
      if (error == SchoolRequestFailure.expired ||
          error == SchoolRequestFailure.differentAccount) {
        rethrow;
      }
    }
    return readNeuqGrades(response, catalog);
  });

  @override
  Future<PlanCompletion> fetchPlanCompletion() =>
      _client.read(_subject, (session) async {
        final response = await session.request(NeuqPage.planCompletion);
        return readNeuqPlanCompletion(response, _subject);
      });
}
