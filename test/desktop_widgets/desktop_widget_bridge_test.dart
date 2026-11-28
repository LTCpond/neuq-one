import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/desktop_widgets/data/desktop_widget_bridge.dart';
import 'package:neuq_one/features/desktop_widgets/presentation/desktop_widgets_page.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/timetable/domain/course_period_span.dart';
import 'package:neuq_one/features/timetable/domain/schedule.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_palette.dart';

void main() {
  final semester = Semester(
    id: 'term',
    name: '测试学期',
    start: DateTime.utc(2026, 9, 2),
    weeks: 18,
  );

  Course course({int start = 840, int end = 1060, int day = 7}) => Course(
    id: 'course',
    semesterId: semester.id,
    name: '测试课程',
    teacher: '仅在 App 显示',
    room: '测试地点',
    weekday: day,
    startMinute: start,
    endMinute: end,
    weeks: parseWeeks('1–18', semester.weeks, WeekParity.even),
    colorIndex: 3,
  );

  test('项目现有节次和跨节次坐标用于桌面快照', () {
    expect(neuqPeriods, hasLength(12));
    expect(neuqPeriods.last.start, 1275);
    expect(coursePeriodSpan(course()), (start: 4, end: 8));
    expect(coursePeriodSpan(course(start: 470, end: 480)), (start: 0, end: 1));
    expect(coursePeriodSpan(course(start: 1320, end: 1380)), (
      start: 11,
      end: 12,
    ));
  });

  test('课表快照保留单双周、周日及浅深色，省略教师和学期名称', () {
    final table = Timetable([semester], [course()]);
    final encoded = widgetTimetableData(table);
    final term = (encoded['terms']! as List).single as Map;
    final item = (term['courses']! as List).single as Map;
    expect(term['start'], '2026-09-02');
    expect(term.containsKey('name'), isFalse);
    expect(item['day'], 7);
    expect(item['weeks'], [2, 4, 6, 8, 10, 12, 14, 16, 18]);
    expect(item.containsKey('teacher'), isFalse);
    expect(item['colors'], [
      for (final theme in [Brightness.light, Brightness.dark])
        for (final color in coursePaletteColors(theme, 3)) color.toARGB32(),
    ]);
    expect(table.on(semester, 1, 7), isEmpty);
    expect(table.on(semester, 2, 7), hasLength(1));
    expect(semester.weekFor(campusDateAt(DateTime.utc(2026, 9, 1, 16))), 1);
    expect(
      semester.weekFor(campusDateAt(DateTime.utc(2026, 9, 1, 15))),
      isNull,
    );
  });

  test('考试快照保留原始时间点，组件可以按北京时间计算', () {
    final start = DateTime.parse('2026-12-03T09:00:00+08:00');
    final end = start.add(const Duration(hours: 2));
    final encoded = widgetExamData([
      Exam(id: 'exam', name: '考试', at: start, endsAt: end),
    ]);
    final exam = (encoded['items']! as List).single as Map;
    expect(exam['start'], DateTime.utc(2026, 12, 3, 1).millisecondsSinceEpoch);
    expect(exam['end'], DateTime.utc(2026, 12, 3, 3).millisecondsSinceEpoch);
  });

  test('快照传递考试冲突、覆盖后的课程块和补充时段入口', () {
    final date = semester.dateFor(2, DateTime.sunday);
    final table = Timetable([semester], [course()]);
    final exams = [
      Exam(
        id: 'lunch',
        name: '午休考试',
        at: campusInstant(date, 725),
        endsAt: campusInstant(date, 790),
      ),
      Exam(
        id: 'overlap',
        name: '冲突考试',
        at: campusInstant(date, 860),
        endsAt: campusInstant(date, 925),
      ),
    ];
    final schedule = ScheduleEvents(CourseSchedule(table), exams);
    final conflicts = ScheduleConflicts(schedule);
    final term =
        (widgetTimetableData(
                      table,
                      ready: true,
                      schedule: schedule,
                      conflicts: conflicts,
                    )['terms']
                    as List)
                .single
            as Map;
    final entries = term['examDays'] as Map;
    final day = entries.values.single as Map;
    expect(day['supplement'], isTrue);
    final items = (day['items'] as List).cast<Map>();
    expect(items.where((entry) => entry['id'] == 'course'), hasLength(2));
    final exam = items.singleWhere((entry) => entry['id'] == 'overlap');
    expect(exam['examCount'], 1);
    expect(exam['conflicts'], 1);
    expect(exam['gridFrom'], closeTo(4 + 20 / 45, .0001));
    expect(exam['gridTo'], closeTo(5 + 35 / 45, .0001));
    final roster = widgetExamData(
      exams,
      showOnTimetable: false,
      conflicts: conflicts,
    );
    expect(roster['showOnTimetable'], isFalse);
    expect((roster['items'] as List).cast<Map>().last['conflicts'], 1);
  });

  test('组件导航仅接受已知目标且编码课程 ID', () {
    expect(
      desktopWidgetLocation({'target': 'exams'}, 2)?.toString(),
      '/grades?section=exams&widget=2',
    );
    expect(desktopWidgetLocation({'target': 'card'}, 2), isNull);
    final course = desktopWidgetLocation({
      'target': 'course',
      'course': 'id&x=1',
    }, 1);
    expect(course?.queryParameters, {'course': 'id&x=1', 'widget': '1'});
    expect(desktopWidgetLocation({'target': 'course'}, 1), isNull);
    expect(desktopWidgetLocation({'target': '/profile'}, 1), isNull);
    expect(
      desktopWidgetLocation({
        'target': 'exam',
        'exam': 'e',
      }, 3)?.queryParameters,
      containsPair('exam', 'e'),
    );
    expect(
      desktopWidgetLocation({'target': 'day', 'date': '2026-11-30'}, 4)?.path,
      '/timetable',
    );
  });

  testWidgets('桌面小组件页仅请求七种尺寸的预览', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(desktopWidgetChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(desktopWidgetChannel, null),
    );

    await tester.pumpWidget(const MaterialApp(home: DesktopWidgetsPage()));
    await tester.pumpAndSettle();

    expect(calls, hasLength(7));
    expect(calls.map((call) => call.method).toSet(), {'preview'});
    expect(calls.map((call) => call.arguments['kind']).toSet(), {
      'today',
      'week',
      'exams',
    });
    expect(find.text('添加到桌面'), findsNothing);
    expect(find.text('校园卡余额'), findsNothing);
  });
}
