import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/app/app.dart';
import 'package:neuq_one/app/router.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/grades/data/local_grades.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/services/data/campus_card_balance.dart';
import 'package:neuq_one/features/services/domain/classrooms.dart';
import 'package:neuq_one/features/timetable/data/local_timetable.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/week_timetable.dart';

void main() {
  final sampleTerm = Semester(
    id: 'fixture',
    name: '测试学期',
    start: mondayOf(campusNow()).subtract(const Duration(days: 7)),
    weeks: 18,
  );
  testWidgets('unconfigured SSO keeps the main pages behind the login gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolAuthRepositoryProvider.overrideWithValue(
            const UnavailableSchoolAuthRepository(),
          ),
          settingsProvider.overrideWith(_TestSettings.new),
          reminderSyncProvider.overrideWith((ref) async {}),
        ],
        child: const NeuqOneApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('此平台暂不支持应用内登录'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.text('NEUQ One')),
    );
    container.read(routerProvider).go('/services/classrooms');
    await tester.pumpAndSettle();
    expect(find.text('此平台暂不支持应用内登录'), findsOneWidget);
    expect(find.text('当日空教室'), findsNothing);
  });

  _appTest('a verified session unlocks the app and logout clears access', (
    tester,
  ) async {
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('统一身份认证登录'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await _tab(tester, '我的');
    await tester.ensureVisible(find.byTooltip('退出统一身份认证'));
    await tester.tap(find.byTooltip('退出统一身份认证'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('统一身份认证登录'), findsOneWidget);
  }, auth: const _TestAuth(restore: false));

  _appTest('home and grades omit the removed features', (tester) async {
    expect(find.text('下一节课'), findsNothing);
    expect(find.text('今日课程'), findsOneWidget);
    expect(find.text('最近考试'), findsNothing);
    await _tab(tester, '成绩');
    expect(find.text('考试安排'), findsNothing);
    expect(find.byTooltip('GPA 计算器'), findsNothing);
    expect(find.byTooltip('查看演示成绩'), findsNothing);
  });

  _appTest(
    'school grades display the GPA returned by the school',
    (tester) async {
      await _tab(tester, '成绩');
      expect(find.text('学期 GPA'), findsOneWidget);
      expect(find.text('累计 GPA'), findsOneWidget);
      expect(find.text('3.6721'), findsOneWidget);
      expect(find.text('3.6502'), findsOneWidget);
      expect(find.text('4.0000'), findsNothing);
    },
    schoolGrades: SchoolGradeBook(
      [
        Semester(
          id: 'school:term',
          name: '教务学期',
          start: DateTime.utc(2026, 9, 7),
          weeks: 18,
        ),
      ],
      [
        const Grade(
          id: 'school:grade',
          semesterId: 'school:term',
          name: '测试课程',
          credit: 3,
          score: 90,
          kind: GradeKind.required,
        ),
      ],
      semesterGpa: const {'school:term': 3.6721},
      cumulativeGpa: 3.6502,
    ),
  );

  _appTest(
    'missing semester GPA is calculated and fractional credits display cleanly',
    (tester) async {
      await _tab(tester, '成绩');
      expect(find.text('学期 GPA'), findsOneWidget);
      expect(find.text('2.8750'), findsOneWidget);
      expect(find.text('1.5 学分'), findsOneWidget);
      expect(find.text('2.5 学分'), findsOneWidget);
      expect(find.textContaining(r'$1'), findsNothing);
      expect(find.textContaining('绩点趋势'), findsNothing);
      expect(find.textContaining('其他'), findsNothing);
    },
    schoolGrades: SchoolGradeBook(
      [
        Semester(
          id: 'school:term',
          name: '测试学期',
          start: DateTime.utc(2026, 9, 7),
          weeks: 18,
        ),
      ],
      const [
        Grade(
          id: 'school:a',
          semesterId: 'school:term',
          name: '课程甲',
          credit: 1.5,
          score: 60,
          kind: GradeKind.other,
        ),
        Grade(
          id: 'school:b',
          semesterId: 'school:term',
          name: '课程乙',
          credit: 2.5,
          score: 90,
          kind: GradeKind.required,
        ),
        Grade(
          id: 'school:c',
          semesterId: 'school:term',
          name: '课程丙',
          credit: 1,
          score: 80,
          kind: GradeKind.general,
        ),
      ],
    ),
  );

  final refreshed = <SchoolDataSet>[];
  _appTest(
    'navigation keeps timetable state and refreshes on every tab tap',
    (tester) async {
      expect(find.text('NEUQ One'), findsOneWidget);

      await _tab(tester, '课表');
      expect(find.text('课程表'), findsNothing);
      expect(find.byTooltip('同步教务课表'), findsNothing);
      expect(find.byTooltip('新增课程'), findsNothing);
      final header = find.byType(AppBar);
      final weekMenu = find.descendant(
        of: header,
        matching: find.byTooltip('选择教学周'),
      );
      final termMenu = find.descendant(
        of: header,
        matching: find.byTooltip('选择学期'),
      );
      expect(
        tester.getCenter(weekMenu).dx,
        lessThan(tester.getCenter(termMenu).dx),
      );
      expect(
        find.descendant(of: header, matching: find.text(sampleTerm.name)),
        findsNothing,
      );
      await tester.tap(termMenu);
      await tester.pumpAndSettle();
      final selectedTerm = find.widgetWithText(
        CheckedPopupMenuItem<String>,
        sampleTerm.name,
      );
      expect(
        tester.widget<CheckedPopupMenuItem<String>>(selectedTerm).checked,
        isTrue,
      );
      await tester.tap(selectedTerm);
      await tester.pumpAndSettle();
      final initialWeek = tester
          .widget<WeekTimetable>(find.byType(WeekTimetable))
          .week;
      await tester.tap(weekMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 ${initialWeek + 1} 周'));
      await tester.pumpAndSettle();
      final week = tester
          .widget<WeekTimetable>(find.byType(WeekTimetable))
          .week;
      expect(week, initialWeek + 1);

      await _tab(tester, '成绩');
      expect(find.text('成绩中心'), findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text(sampleTerm.name)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('选择学期'),
        ),
        findsOneWidget,
      );
      await _tab(tester, '服务');
      expect(find.text('校园服务'), findsOneWidget);
      expect(find.text('校园网'), findsOneWidget);
      expect(find.text('图书馆'), findsNothing);
      expect(find.text('校园卡'), findsOneWidget);
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.text('当日空教室'), findsOneWidget);
      expect(find.byTooltip('打开学校空教室查询'), findsNothing);
      expect(find.byTooltip('刷新空教室'), findsOneWidget);
      expect(find.text('工学馆'), findsOneWidget);
      expect(find.text('科技楼'), findsOneWidget);
      expect(find.text('人文楼'), findsOneWidget);
      expect(find.text('开始节次'), findsNothing);
      expect(find.text('结束节次'), findsNothing);

      await _tab(tester, '我的');
      expect(find.text('学校身份已验证'), findsOneWidget);
      await tester.tap(find.byTooltip('切换主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('我的').first)).brightness,
        Brightness.dark,
      );

      await _tab(tester, '课表');
      expect(
        tester.widget<WeekTimetable>(find.byType(WeekTimetable)).week,
        week,
      );
      expect(find.text('日视图'), findsNothing);
      await _tab(tester, '课表');
      expect(refreshed, [
        SchoolDataSet.timetable,
        SchoolDataSet.grades,
        SchoolDataSet.timetable,
        SchoolDataSet.timetable,
      ]);
    },
    initialTimetable: Timetable([sampleTerm], []),
    onRefresh: refreshed.add,
  );

  _appTest(
    'the home card displays the saved balance and opens the school card route',
    (tester) async {
      final tile = find.byKey(const ValueKey('home-shortcut-campus-card'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: tile, matching: find.text('¥12.34')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.textContaining('上次读取')),
        findsNothing,
      );
      expect(
        find.descendant(of: tile, matching: find.text('校园卡余额')),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('打开学校校园卡'), findsOneWidget);
      expect(find.text('在浏览器打开'), findsOneWidget);
    },
    campusCardBalance: (cents: 1234, readAt: DateTime.utc(2026, 1, 1)),
  );

  _appTest(
    'an existing local course can be edited and deleted through its details',
    (tester) async {
      await _tab(tester, '课表');
      final course = find.text('高等数学');
      await tester.ensureVisible(course);
      await tester.pumpAndSettle();
      expect(course, findsOneWidget);
      await tester.tap(course);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).alignment,
        Alignment.center,
      );
      await tester.tap(find.text('编辑课程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '线性代数');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('线性代数'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('线性代数'), findsNothing);
    },
    initialTimetable: Timetable(
      [sampleTerm],
      [_sampleCourse('editable', '高等数学', sampleTerm, 1, 1, 2)],
    ),
  );

  _appTest(
    'week grid aligns one, two and four periods with the rail',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _tab(tester, '课表');
      final wrappedRoom = find.text('科技楼综合教学区316（学校本部）');
      expect(tester.widget<Text>(wrappedRoom).softWrap, isTrue);
      expect(tester.widget<Text>(wrappedRoom).maxLines, greaterThan(1));
      expect(tester.getSize(wrappedRoom).height, greaterThan(12));
      for (final (id, first, last) in [
        ('single', 4, 4),
        ('double', 1, 2),
        ('four', 5, 8),
        ('evening', 11, 12),
      ]) {
        final firstRow = find.byKey(ValueKey('timetable-period-$first'));
        final lastRow = find.byKey(ValueKey('timetable-period-$last'));
        final block = find.byKey(ValueKey('timetable-course-$id'));
        await tester.ensureVisible(lastRow);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(block).dy,
          closeTo(tester.getTopLeft(firstRow).dy + 2, .01),
        );
        expect(
          tester.getBottomLeft(block).dy,
          closeTo(tester.getBottomLeft(lastRow).dy - 2, .01),
        );
      }
      for (final time in ['20:25', '21:10', '21:15', '22:00']) {
        expect(find.text(time), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    initialTimetable: Timetable(
      [sampleTerm],
      [
        _sampleCourse('single', '一节课程', sampleTerm, 1, 4, 4),
        _sampleCourse(
          'double',
          '连上两节',
          sampleTerm,
          2,
          1,
          2,
          room: '科技楼综合教学区316（学校本部）',
        ),
        _sampleCourse('four', '连上四节', sampleTerm, 4, 5, 8),
        _sampleCourse('evening', '晚间课程', sampleTerm, 5, 11, 12),
      ],
    ),
  );

  _appTest('manual grade contributes to GPA', (tester) async {
    await _tab(tester, '成绩');
    await _createSemester(tester);
    await tester.tap(find.text('录入成绩'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '线性代数');
    await tester.enterText(fields.at(1), '3');
    await tester.enterText(fields.at(2), '88');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('3.8000'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '线性代数'), findsOneWidget);
  });

  _appTest('quick links can be reordered and saved', (tester) async {
    final reorder = find.text('调整快捷入口');
    await tester.ensureVisible(reorder);
    await tester.pumpAndSettle();
    await tester.tap(reorder);
    await tester.pumpAndSettle();
    final academic = find.byKey(const ValueKey('academic'));
    final handle = find.descendant(
      of: academic,
      matching: find.byType(ReorderableDragStartListener),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('一网通办')).dx,
      lessThan(tester.getTopLeft(find.text('教务系统')).dx),
    );
  });

  _appTest('home shortcut selection supports the complete service catalog', (
    tester,
  ) async {
    await tester.tap(find.text('调整快捷入口'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    for (final id in ['campus-card', 'classrooms', 'vpn']) {
      final row = find.descendant(
        of: dialog,
        matching: find.byKey(ValueKey(id)),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('校园卡余额'), findsNothing);
    expect(find.text('WebVPN'), findsOneWidget);
    await tester.tap(find.text('空教室'));
    await tester.pumpAndSettle();
    expect(find.text('当日空教室'), findsOneWidget);
  });

  var classroomReads = 0;
  _appTest(
    'empty classrooms switches buildings using one school day query',
    (tester) async {
      await _tab(tester, '服务');
      expect(find.text('学校官方服务'), findsNothing);
      expect(find.text('学校网站与办事入口'), findsNothing);
      expect(find.textContaining('登录由校方处理'), findsNothing);
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(tile.subtitle, isNull);
      }
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.textContaining('学校教务 · 查询于'), findsOneWidget);
      expect(find.text('第 1–2 节'), findsOneWidget);
      expect(find.text('红色 · 下节有课'), findsOneWidget);
      expect(
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)),
        hasLength(3),
      );
      final booked = find.text('101');
      final ordinary = find.text('102').first;
      final upperFloor = find.text('207');
      final colors = Theme.of(tester.element(booked)).colorScheme;
      expect(tester.widget<Text>(booked).style?.color, colors.error);
      expect(tester.widget<Text>(ordinary).style?.color, colors.onSurface);
      expect(find.text('2层'), findsOneWidget);
      expect(
        tester.getTopLeft(upperFloor).dy,
        greaterThan(tester.getTopLeft(booked).dy),
      );
      await tester.tap(find.text('科技楼'));
      await tester.pumpAndSettle();
      expect(find.text('101'), findsNothing);
      expect(find.text('6077'), findsWidgets);
      expect(find.text('6层'), findsNothing);
      await tester.tap(find.text('人文楼'));
      await tester.pumpAndSettle();
      expect(find.text('210'), findsOneWidget);
      expect(find.text('2层'), findsNothing);
      expect(classroomReads, 1);
    },
    classrooms: (day) {
      classroomReads++;
      return (
        syncedAt: day,
        buildings: {
          for (final building in CampusBuilding.values)
            building: ClassroomSchedule(
              {
                1: {
                  switch (building) {
                    CampusBuilding.engineering => '101',
                    CampusBuilding.science => '6077',
                    CampusBuilding.humanities => '210',
                  },
                  if (building == CampusBuilding.engineering) ...{'102', '207'},
                },
                if (building == CampusBuilding.engineering) 3: {'102'},
              },
              periodCount: 12,
              periodsPerGroup: 2,
            ),
        },
      );
    },
  );

  var balanceReads = 0;
  _appTest(
    'home entry and selecting the home tab automatically refresh the campus balance',
    (tester) async {
      expect(balanceReads, 1);
      await _tab(tester, '服务');
      expect(balanceReads, 1);
      await _tab(tester, '首页');
      expect(balanceReads, 2);
    },
    onCampusCardRefresh: () => balanceReads++,
  );
}

void _appTest(
  String description,
  Future<void> Function(WidgetTester) scenario, {
  _TestAuth auth = const _TestAuth(),
  SchoolGradeBook? schoolGrades,
  Timetable? initialTimetable,
  CampusCardBalance? campusCardBalance,
  ClassroomSchedules Function(DateTime)? classrooms,
  void Function()? onCampusCardRefresh,
  void Function(SchoolDataSet)? onRefresh,
}) {
  testWidgets(description, (tester) async {
    final timetable = _TestTimetable();
    final grades = _TestGrades();
    if (initialTimetable != null) {
      for (final semester in initialTimetable.semesters) {
        await timetable.saveSemester(semester);
      }
      for (final course in initialTimetable.courses) {
        await timetable.saveCourse(course);
      }
    }
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolAuthRepositoryProvider.overrideWithValue(auth),
            if (onRefresh != null)
              schoolRefreshProvider.overrideWith(
                (ref, section) async => onRefresh(section),
              ),
            if (schoolGrades != null)
              schoolGradesCacheProvider.overrideWith(
                (ref) =>
                    Stream.value(SchoolCache(schoolGrades, DateTime.utc(2026))),
              ),
            if (campusCardBalance != null)
              campusCardBalanceProvider.overrideWith(
                (ref) async => campusCardBalance,
              ),
            if (classrooms != null)
              classroomsProvider.overrideWith(
                (ref, day) async => classrooms(day),
              ),
            if (onCampusCardRefresh != null)
              campusCardRefreshProvider.overrideWith((ref) async {
                onCampusCardRefresh();
                return CampusCardRefreshStatus.updated;
              }),
            timetableRepositoryProvider.overrideWithValue(timetable),
            gradesRepositoryProvider.overrideWithValue(grades),
            settingsProvider.overrideWith(_TestSettings.new),
            reminderSyncProvider.overrideWith((ref) async {}),
          ],
          child: const NeuqOneApp(),
        ),
      );
      await tester.pumpAndSettle();
      await scenario(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(timetable.changes.close());
      unawaited(grades.changes.close());
    }
  });
}

Course _sampleCourse(
  String id,
  String title,
  Semester semester,
  int day,
  int start,
  int end, {
  String room = '测试楼101',
}) => Course(
  id: id,
  semesterId: semester.id,
  name: title,
  teacher: '测试教师',
  room: room,
  weekday: day,
  startMinute: neuqPeriods[start - 1].start,
  endMinute: neuqPeriods[end - 1].end,
  weeks: const [2],
  colorIndex: 0,
);

Future<void> _tab(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(title)),
  );
  await tester.pumpAndSettle();
}

Future<void> _createSemester(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, '新增学期'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '新增学期'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '测试学期');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
  expect(find.text('测试学期'), findsNothing);
  await tester.tap(find.byTooltip('选择学期'));
  await tester.pumpAndSettle();
  final term = find.widgetWithText(CheckedPopupMenuItem<String>, '测试学期');
  expect(tester.widget<CheckedPopupMenuItem<String>>(term).checked, isTrue);
  await tester.tap(term);
  await tester.pumpAndSettle();
}

class _TestAuth implements SchoolAuthRepository {
  const _TestAuth({this.restore = true});
  final bool restore;

  @override
  bool get available => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<SchoolSession?> restoreSession() =>
      restore ? signIn() : Future.value(null);
  @override
  Future<SchoolSession?> signIn({SchoolLoginPresenter? openLogin}) async =>
      const SchoolSession(subject: 'test-owner', admissionYear: 2025);
}

class _TestSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> setTheme(ThemeMode value) async =>
      state = AsyncData(AppSettings(theme: value));

  @override
  Future<void> setQuickLinks(List<String> value) async => state = AsyncData(
    AppSettings(quickLinks: value, quickLinksCustomized: true),
  );
}

class _TestTimetable implements TimetableRepository {
  final changes = StreamController<Timetable>.broadcast();
  final _semesters = <String, Semester>{};
  final _courses = <String, Course>{};

  Timetable get _data =>
      Timetable(_semesters.values.toList(), _courses.values.toList());

  @override
  Stream<Timetable> watch() => Stream.multi((controller) {
    controller.add(_data);
    controller.onCancel = changes.stream.listen(controller.add).cancel;
  });

  @override
  Future<void> saveSemester(Semester semester) async {
    _semesters[semester.id] = semester;
    changes.add(_data);
  }

  @override
  Future<void> saveCourse(Course course) async {
    _courses[course.id] = course;
    changes.add(_data);
  }

  @override
  Future<void> deleteCourse(String id) async {
    _courses.remove(id);
    changes.add(_data);
  }
}

class _TestGrades implements GradesRepository {
  final changes = StreamController<List<Grade>>.broadcast();
  final _grades = <String, Grade>{};

  @override
  Stream<List<Grade>> watch() => Stream.multi((controller) {
    controller.add(_grades.values.toList());
    controller.onCancel = changes.stream.listen(controller.add).cancel;
  });

  @override
  Future<void> save(Grade grade) async {
    _grades[grade.id] = grade;
    changes.add(_grades.values.toList());
  }

  @override
  Future<void> delete(String id) async {
    _grades.remove(id);
    changes.add(_grades.values.toList());
  }
}
