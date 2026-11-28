import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/timetable/domain/schedule.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_palette.dart';
import 'package:neuq_one/features/timetable/presentation/week_timetable.dart';

final _monday = DateTime.utc(2026, 11, 30);
final _term = Semester(id: 'term', name: '测试学期', start: _monday, weeks: 2);

DateTime _date(int dayOffset) => _monday.add(Duration(days: dayOffset));

Finder _marker(int dayOffset) =>
    find.byKey(ValueKey('timetable-exam-marker-${_date(dayOffset)}'));

Finder _markerSlot(int dayOffset) =>
    find.byKey(ValueKey('timetable-exam-marker-slot-${_date(dayOffset)}'));

Finder _dateBadge(int dayOffset) =>
    find.byKey(ValueKey('timetable-date-badge-${_date(dayOffset)}'));

Exam _exam(String id, int start, int end) => Exam(
  id: id,
  name: '考试 $id',
  at: campusInstant(_monday, start),
  endsAt: campusInstant(_monday, end),
);

ScheduleEvents _schedule(List<Exam> exams) =>
    ScheduleEvents(CourseSchedule(Timetable([_term], const [])), exams);

Widget _app({
  required ScheduleEvents? schedule,
  DateTime? today,
  DateTime? now,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: appTheme(brightness),
  home: Scaffold(
    body: WeekTimetable(
      semester: _term,
      week: 1,
      today: today ?? _date(30),
      timetable: Timetable([_term], const []),
      onWeekChanged: (_) {},
      onCourse: (_) {},
      onDate: (_) {},
      schedule: schedule,
      now: now ?? _monday.add(const Duration(minutes: 600)),
      onExam: (_, _) {},
    ),
  ),
);

Color _markerColor(WidgetTester tester, int dayOffset) {
  final marker = tester.widget<Container>(_marker(dayOffset));
  return (marker.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('dates without exams keep the marker slot and stay aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(schedule: _schedule(const [])));
    await tester.pumpAndSettle();

    for (var offset = 0; offset < 7; offset++) {
      expect(_markerSlot(offset), findsOneWidget);
      expect(_marker(offset), findsNothing);
      expect(tester.getSize(_markerSlot(offset)).height, 9);
    }
    expect(
      tester.getTopLeft(_dateBadge(0)).dy,
      tester.getTopLeft(_dateBadge(6)).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the date header fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _app(
        schedule: _schedule([_exam('narrow', 480, 525)]),
        today: _monday,
        now: _monday.add(const Duration(minutes: 500)),
      ),
    );
    await tester.pumpAndSettle();

    expect(_marker(0), findsOneWidget);
    for (var offset = 0; offset < 7; offset++) {
      expect(tester.getSize(_markerSlot(offset)).height, 9);
      expect(
        tester.getTopLeft(_dateBadge(offset)).dy,
        tester.getTopLeft(_dateBadge(0)).dy,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one marker is shown per exam day and its color follows the end',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final schedule = _schedule([
        _exam('first', 600, 660),
        _exam('second', 700, 720),
      ]);
      await tester.pumpWidget(_app(schedule: schedule));
      await tester.pumpAndSettle();

      expect(_marker(0), findsOneWidget);
      expect(_marker(1), findsNothing);
      expect(_markerColor(tester, 0), examPalette(Brightness.light).border);
      final marker = tester.getSize(_marker(0));
      expect(marker.width, 21);
      expect(marker.height, 3);
      final decoration =
          tester.widget<Container>(_marker(0)).decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(2));

      final context = tester.element(find.byType(WeekTimetable));
      final outline = Theme.of(context).colorScheme.outline;
      await tester.pumpWidget(
        _app(
          schedule: schedule,
          now: _monday.add(const Duration(minutes: 800)),
        ),
      );
      await tester.pumpAndSettle();
      expect(_markerColor(tester, 0), outline);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the today background and the exam marker coexist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        schedule: _schedule([_exam('today', 600, 660)]),
        today: _monday,
        now: _monday.add(const Duration(minutes: 610)),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<Container>(_dateBadge(0));
    expect((badge.decoration! as BoxDecoration).color, campusBlue);
    expect(_marker(0), findsOneWidget);
    expect(
      tester.getTopLeft(_marker(0)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(_dateBadge(0)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding exams removes markers and supplemental exam periods', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(schedule: _schedule([_exam('lunch', 420, 470)])),
    );
    await tester.pumpAndSettle();
    expect(_marker(0), findsOneWidget);
    expect(find.text('补充考试时段'), findsOneWidget);

    await tester.pumpWidget(_app(schedule: null));
    await tester.pumpAndSettle();
    expect(_marker(0), findsNothing);
    expect(find.text('补充考试时段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the marker adapts to dark mode', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        schedule: _schedule([_exam('dark', 600, 660)]),
        brightness: Brightness.dark,
        now: _monday.add(const Duration(minutes: 610)),
      ),
    );
    await tester.pumpAndSettle();

    expect(_markerColor(tester, 0), examPalette(Brightness.dark).border);
    expect(tester.takeException(), isNull);
  });
}
