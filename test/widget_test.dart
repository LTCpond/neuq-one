import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/app/app.dart';
import 'package:neuq_one/app/login_page.dart';
import 'package:neuq_one/app/router.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/grades/data/local_grades.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/mail/data/campus_mail.dart';
import 'package:neuq_one/features/mail/presentation/campus_mail_page.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/services/data/campus_card_balance.dart';
import 'package:neuq_one/features/services/data/campus_map.dart';
import 'package:neuq_one/features/services/data/classroom_cache.dart';
import 'package:neuq_one/features/services/data/employment_feed.dart';
import 'package:neuq_one/features/services/data/public_classrooms.dart';
import 'package:neuq_one/features/services/data/school_policies.dart';
import 'package:neuq_one/features/services/domain/school_policy.dart';
import 'package:neuq_one/features/services/presentation/campus_map_page.dart';
import 'package:neuq_one/features/services/presentation/classrooms_page.dart';
import 'package:neuq_one/features/services/presentation/employment_page.dart';
import 'package:neuq_one/features/timetable/data/local_timetable.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_date.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_page.dart';
import 'package:neuq_one/features/timetable/presentation/week_timetable.dart';

import 'fixtures/classroom_week.dart';

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
          reminderSyncProvider.overrideWith(
            (ref) async => const ReminderStatus(ReminderCondition.off),
          ),
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
    expect(find.byType(ClassroomsPage), findsNothing);
  });

  final loginAuth = _RememberingTestAuth(restore: false);
  _appTest('logout waits for saved credentials to be deleted', (tester) async {
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.enterText(find.byType(TextFormField).at(0), '00001234');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('统一身份认证登录'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      _router(tester).routeInformationProvider.value.uri.path,
      '/timetable',
    );
    expect(find.byType(TimetablePage), findsOneWidget);
    expect(loginAuth.remembered, isTrue);
    await _tab(tester, '我的');
    await tester.ensureVisible(find.byTooltip('退出统一身份认证'));
    final pending = loginAuth.pendingLogout = Completer<void>();
    await tester.tap(find.byTooltip('退出统一身份认证'));
    await tester.pump();
    expect(find.text('学校身份已验证'), findsOneWidget);
    expect(find.text('统一身份认证登录'), findsNothing);
    expect(loginAuth.remembered, isTrue);

    pending.complete();
    await tester.pumpAndSettle();
    expect(loginAuth.remembered, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('统一身份认证登录'), findsOneWidget);
  }, auth: loginAuth);

  final profileAuth = _RememberingTestAuth(remembered: true);
  _appTest(
    'profile shows identity status, credential removal and the privacy notice',
    (tester) async {
      await _tab(tester, '我的');
      final status = find.text('学校身份已验证');
      final statusTile = find.ancestor(
        of: status,
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(statusTile).onTap, isNull);
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(
        _router(tester).routeInformationProvider.value.uri.path,
        '/profile',
      );

      final credentials = find.text('删除本地保存的学号与密码');
      await tester.ensureVisible(credentials);
      expect(
        tester.getTopLeft(credentials).dy,
        greaterThan(tester.getTopLeft(find.text('数据管理')).dy),
      );
      expect(
        tester.getTopLeft(credentials).dy,
        lessThan(tester.getTopLeft(find.text('关于')).dy),
      );
      await tester.tap(credentials);
      await tester.pumpAndSettle();
      expect(profileAuth.remembered, isFalse);
      expect(credentials, findsNothing);
      expect(
        _router(tester).routeInformationProvider.value.uri.path,
        '/profile',
      );

      final privacy = find.text('隐私说明');
      await tester.ensureVisible(privacy);
      await tester.tap(privacy);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'NEUQ One 尊重并保护用户隐私。用户相关信息均在本地设备处理和存储，仅在使用相关功能时与学校系统或对应服务提供方进行必要的数据交互。\n\n'
          '本应用不会向项目维护者的服务器上传用户个人数据，不包含广告、行为追踪或用户数据统计功能，源代码公开可查。诊断信息只保存在本次运行的内存中，由用户手动复制。',
        ),
        findsOneWidget,
      );
    },
    auth: profileAuth,
  );

  for (final restoreSavedSession in [true, false]) {
    late Completer<SchoolSession?> restoration;
    _appTest(
      restoreSavedSession
          ? 'cold start goes directly to the timetable after session restoration'
          : 'cold start shows login only after confirming there is no session',
      (tester) async {
        expect(
          find.byType(TimetablePage),
          restoreSavedSession ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(LoginPage),
          restoreSavedSession ? findsNothing : findsOneWidget,
        );
      },
      auth: _TestAuth(
        restoration: () {
          restoration = Completer<SchoolSession?>();
          return restoration.future;
        },
      ),
      beforeSettle: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(LoginPage), findsNothing);
        expect(find.byType(TimetablePage), findsNothing);
        restoration.complete(restoreSavedSession ? _TestAuth._session : null);
        await tester.pump();
        if (restoreSavedSession) {
          expect(find.byType(LoginPage), findsNothing);
        }
      },
    );
  }

  _appTest(
    'a restored session opens the timetable and redirects the old root',
    (tester) async {
      final router = _router(tester);
      expect(router.routeInformationProvider.value.uri.path, '/timetable');
      expect(find.byType(TimetablePage), findsOneWidget);
      final destinations = tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      );
      expect(destinations.map((destination) => destination.label), [
        '课表',
        '成绩',
        '服务',
        '我的',
      ]);
      expect(find.text('下一节课'), findsNothing);
      expect(find.text('今日课程'), findsNothing);
      expect(find.text('最近考试'), findsNothing);
      await _tab(tester, '成绩');
      expect(find.text('考试安排'), findsNothing);
      expect(find.byTooltip('GPA 计算器'), findsNothing);
      expect(find.byTooltip('查看演示成绩'), findsNothing);
      router.go('/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/timetable');
      expect(find.byType(TimetablePage), findsOneWidget);
    },
  );

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
      expect(
        tester.widget<WeekTimetable>(find.byType(WeekTimetable)).week,
        sampleTerm.weekFor(campusNow()),
      );
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
      final termMenuSize = tester.getSize(termMenu);
      expect(
        tester.getCenter(weekMenu).dx,
        lessThan(tester.getCenter(termMenu).dx),
      );
      expect(
        find.descendant(of: header, matching: find.text(sampleTerm.name)),
        findsOneWidget,
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
      expect(find.text(sampleTerm.name), findsOneWidget);
      final gradeSemester = find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('选择学期'),
      );
      final gradeRefresh = find.byTooltip('刷新教务成绩');
      expect(gradeSemester, findsOneWidget);
      expect(tester.getSize(gradeSemester), termMenuSize);
      expect(
        tester.getCenter(gradeSemester).dx,
        lessThan(tester.getCenter(gradeRefresh).dx),
      );
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await _tab(tester, '服务');
      expect(find.text('校园服务'), findsOneWidget);
      expect(find.text('校园网'), findsOneWidget);
      expect(find.text('图书馆'), findsNothing);
      expect(find.text('校园卡'), findsOneWidget);
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.byType(ClassroomsPage), findsOneWidget);
      expect(find.byTooltip('刷新空教室'), findsOneWidget);
      expect(find.text('工学馆'), findsOneWidget);
      expect(find.text('科技楼'), findsOneWidget);
      expect(find.text('人文楼'), findsOneWidget);
      expect(find.text('开始节次'), findsNothing);
      expect(find.text('结束节次'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

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
    'services display the saved campus card balance and open the card route',
    (tester) async {
      await _tab(tester, '服务');
      expect(find.text('¥12.34'), findsOneWidget);
      await tester.tap(find.text('校园卡'));
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
        find.byKey(const ValueKey('course-details-sheet')),
        findsOneWidget,
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
      final doubleBlock = find.byKey(const ValueKey('timetable-course-double'));
      expect(tester.getSize(doubleBlock).height, closeTo(120.8, .01));
      Finder inBlock(String label) =>
          find.descendant(of: doubleBlock, matching: find.text(label));
      final title = inBlock('连上两节');
      final wrappedRoom = inBlock('科技楼综合教学区316');
      final teacher = inBlock('测试教师');
      expect(tester.widget<Text>(wrappedRoom).softWrap, isTrue);
      expect(tester.widget<Text>(wrappedRoom).maxLines, greaterThan(1));
      expect(tester.getSize(wrappedRoom).height, greaterThan(12));
      for (final field in [title, wrappedRoom, teacher]) {
        expect(tester.widget<Text>(field).textAlign, TextAlign.start);
        expect(
          tester.getTopLeft(field).dx,
          tester.getTopLeft(doubleBlock).dx + 4,
        );
      }
      expect(
        tester.getTopLeft(teacher).dy,
        tester.getBottomLeft(wrappedRoom).dy,
      );
      await tester.tap(doubleBlock);
      await tester.pumpAndSettle();
      expect(find.text('科技楼综合教学区316（学校本部）'), findsOneWidget);
      _router(tester).pop();
      await tester.pumpAndSettle();
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
    expect(find.text('线性代数'), findsOneWidget);
  });

  _appTest('the services menu opens mail and employment within its branch', (
    tester,
  ) async {
    await _tab(tester, '服务');
    final router = _router(tester);
    final mail = find.text('校园邮箱');
    await tester.scrollUntilVisible(mail, 250);
    await tester.tap(mail);
    await tester.pumpAndSettle();
    expect(find.byType(CampusMailPage), findsOneWidget);
    await _tab(tester, '课表');
    await _tab(tester, '服务');
    expect(find.byType(CampusMailPage), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    final employment = find.text('宣讲会与招聘会');
    await tester.scrollUntilVisible(employment, 250);
    await tester.tap(employment);
    await tester.pumpAndSettle();
    expect(find.byType(EmploymentPage), findsOneWidget);
  });

  testWidgets(
    'employment cards separate title, time and location on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 660);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const title = '校园招聘专场宣讲会及毕业生就业咨询';
      const time = '11月27日 · 14:00–16:00';
      const location = '科技楼综合教学区 316';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            employmentCacheProvider.overrideWith((ref) async => null),
            employmentRefreshProvider.overrideWith(
              (ref, force) async => (
                syncedAt: classroomNow,
                events: [
                  EmploymentEvent(
                    EmploymentKind.talk,
                    title,
                    time,
                    location,
                    EmploymentKind.talk.uri,
                  ),
                  EmploymentEvent(
                    EmploymentKind.talk,
                    '第二场宣讲',
                    time,
                    '',
                    EmploymentKind.talk.uri,
                  ),
                  EmploymentEvent(
                    EmploymentKind.fair,
                    '校园综合招聘',
                    time,
                    location,
                    EmploymentKind.fair.uri,
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(home: EmploymentPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text(title)).dy,
        lessThan(tester.getTopLeft(find.text(time).first).dy),
      );
      expect(
        tester.getBottomLeft(find.text(time).first).dy,
        lessThan(tester.getTopLeft(find.text(location)).dy),
      );
      expect(
        tester.getBottomLeft(find.byType(Card).first).dy,
        lessThan(tester.getTopLeft(find.byType(Card).last).dy),
      );
      expect(find.text('校园综合招聘'), findsNothing);
      await tester.tap(find.text('招聘会'));
      await tester.pumpAndSettle();
      expect(find.text('校园综合招聘'), findsOneWidget);
      expect(find.text(title), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _appTest('campus map opens in the app and returns to services', (
    tester,
  ) async {
    await _tab(tester, '服务');
    final entry = find.text('校园地图');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final map = find.byType(CampusMapPage);
    expect(map, findsOneWidget);
    expect(
      GoRouterState.of(tester.element(map)).matchedLocation,
      '/services/campus-map',
    );
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('校园服务'), findsOneWidget);
  });

  final policyBytes = utf8.encode('%PDF-1.7\n%%EOF');
  var policyReads = 0;
  _appTest(
    'school policies list documents directly and support retry and download',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('io.scer.pdf_renderer'),
        (_) async => throw PlatformException(code: 'preview-unavailable'),
      );
      await _tab(tester, '服务');
      final entry = find.text('学校政策');
      await tester.scrollUntilVisible(entry, 120);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('本科生学分绩点实施办法'), findsOneWidget);
      expect(find.text('本研贯通培养实施办法'), findsOneWidget);

      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('本科生学分绩点实施办法'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法读取政策文件'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.download_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法预览，可下载 PDF 后打开。'), findsOneWidget);
      await tester.tap(find.byTooltip('下载 PDF'));
      await tester.pumpAndSettle();
      expect(find.text('政策 PDF 已保存'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('本科生学分绩点实施办法'), findsOneWidget);
      expect(find.text('本研贯通培养实施办法'), findsOneWidget);
    },
    schoolPolicyPdf: (policy) async {
      if (policyReads++ == 0) throw const FormatException();
      return policyBytes;
    },
    schoolPolicySaver: (policy, bytes) async {
      expect(policy.id, 'grade-point');
      expect(bytes, policyBytes);
      return true;
    },
    schoolPolicies: const [
      SchoolPolicy(
        id: 'grade-point',
        title: '东北大学秦皇岛分校本科生学分绩点实施办法',
        category: '学业成绩',
        sha256: 'fixture',
      ),
      SchoolPolicy(
        id: 'integrated-study',
        title: '东北大学秦皇岛分校本研贯通培养实施办法',
        category: '推免升学',
        sha256: 'fixture',
      ),
    ],
  );

  var classroomReads = 0;
  _appTest(
    'public classrooms switches seven dates and three buildings using one snapshot',
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
      expect(find.text('数据更新于 16:19'), findsOneWidget);
      expect(find.text('1–2 节'), findsOneWidget);
      expect(find.text('全天空闲'), findsOneWidget);
      expect(find.text('下一时段占用'), findsOneWidget);
      final booked = find.text('101');
      final ordinary = find.text('102').first;
      final upperFloor = find.text('207');
      expect(
        tester.widget<Text>(booked).style?.color,
        isNot(tester.widget<Text>(ordinary).style?.color),
      );
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
      await tester.tap(find.text('工学馆'));
      await tester.pumpAndSettle();
      final selector = find.byType(DropdownButton<DateTime>);
      expect(
        tester.widget<DropdownButton<DateTime>>(selector).items,
        hasLength(7),
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12月1日 · 周二').last);
      await tester.pumpAndSettle();
      expect(find.text('301'), findsWidgets);
      expect(find.text('101'), findsNothing);
      await tester.tap(find.text('科技楼'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('表格视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.text('教室空闲表'), findsOneWidget);
      expect(find.text('12月1日 · 星期二'), findsOneWidget);
      expect(find.text('6077'), findsWidgets);
      expect(classroomReads, 1);
    },
    classroomResponse: () {
      classroomReads++;
      return http.Response.bytes(utf8.encode(classroomWeekBody()), 200);
    },
  );

  var classroomTime = DateTime.utc(2026, 11, 25, 15, 59, 59);
  _appTest(
    'classroom table distinguishes free, occupied, and expired slots',
    (tester) async {
      await _tab(tester, '服务');
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.text('分时段查询'), findsOneWidget);
      await tester.tap(find.byTooltip('表格视图'));
      await tester.pumpAndSettle();

      expect(find.text('教室空闲表'), findsOneWidget);
      final blankLegend = find.text('空白 · 非空闲');
      expect(
        tester.getBottomLeft(blankLegend).dy,
        lessThan(tester.getTopLeft(find.byType(Table).first).dy),
      );
      expect(find.textContaining('暂无有效数据'), findsNothing);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        final free = find.bySemanticsLabel('101，第 1 节开始，空闲');
        final occupied = find.bySemanticsLabel('101，第 3 节开始，非空闲');
        final expired = find.bySemanticsLabel('101，第 5 节开始，暂无有效数据');
        Finder fill(Finder cell, Color color) => find.descendant(
          of: cell,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color == color,
          ),
        );
        expect(fill(free, const Color(0xFF2459E0)), findsOneWidget);
        expect(occupied, findsOneWidget);
        expect(fill(occupied, const Color(0xFF2459E0)), findsNothing);
        expect(fill(expired, const Color(0xFFDCE1E9)), findsOneWidget);
      } finally {
        semantics.dispose();
      }
      expect(find.text('?'), findsWidgets);
      expect(find.byIcon(Icons.check), findsNothing);

      await tester.tap(find.byTooltip('时间轴视图'));
      await tester.pumpAndSettle();
      expect(find.text('分时段查询'), findsOneWidget);
      final stale = find.textContaining('数据已过期，仅供参考');
      await tester.scrollUntilVisible(stale, 150);
      expect(stale, findsOneWidget);
    },
    classroomResponse: () {
      final week = classroomWeekFixture();
      fixturePeriods(week)['5-6'] = classroomSlotFixture([
        '101',
      ], expiresAt: '2026-11-25T16:19:30+08:00');
      return http.Response.bytes(utf8.encode(jsonEncode(week)), 200);
    },
  );

  var midnightReads = 0;
  _appTest(
    'Beijing midnight uses only matching cached dates when the public API fails',
    (tester) async {
      await _tab(tester, '服务');
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(find.text('101'), findsOneWidget);
      expect(find.textContaining('数据已过期，仅供参考'), findsWidgets);
      expect(find.textContaining('已有记录均已过期'), findsOneWidget);

      classroomTime = classroomTime.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('11月26日 · 星期四'), findsOneWidget);
      expect(find.text('101'), findsNothing);
      expect(find.text('301'), findsWidgets);
      expect(find.text('更新失败，正在显示离线缓存'), findsOneWidget);
      expect(midnightReads, 2);

      await tester.tap(find.byType(DropdownButton<DateTime>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12月2日 · 周三').last);
      await tester.pumpAndSettle();
      expect(find.text('空教室数据暂不可用'), findsOneWidget);
      expect(find.text('301'), findsNothing);
      expect(midnightReads, 2);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(midnightReads, 3);
    },
    classroomResponse: () {
      if (++midnightReads > 1) return http.Response('', 503);
      final week = classroomWeekFixture();
      fixtureDay(week, 1)['buildings']['工学馆']['1-2']['expiresAt'] =
          '2026-11-26T00:30:00+08:00';
      return http.Response.bytes(utf8.encode(jsonEncode(week)), 200);
    },
    classroomClock: () => classroomTime,
  );

  var expiryTime = DateTime.utc(2026, 11, 25, 9, 18, 59);
  var expiryReads = 0;
  _appTest(
    'an open classroom page revalidates at expiry and preserves historical data',
    (tester) async {
      await _tab(tester, '服务');
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      final room = find.text('101');
      final freshColor = tester.widget<Text>(room).style?.color;
      expect(find.textContaining('数据已过期，仅供参考'), findsNothing);
      expiryTime = expiryTime.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(room).style?.color, isNot(freshColor));
      expect(find.textContaining('数据已过期，仅供参考'), findsWidgets);
      final historicalEmpty = find.text('上次采集时未发现空教室');
      await tester.scrollUntilVisible(
        historicalEmpty,
        180,
        scrollable: find.descendant(
          of: find.byType(ClassroomsPage),
          matching: find.byType(Scrollable),
        ),
      );
      expect(historicalEmpty, findsWidgets);
      expect(expiryReads, 2);
    },
    classroomResponse: () {
      expiryReads++;
      return http.Response.bytes(utf8.encode(classroomWeekBody()), 200);
    },
    classroomClock: () => expiryTime,
  );

  final cardRepository = _TestCampusCardRepository();

  var periodicTime = classroomNow;
  var periodicReads = 0;
  _appTest(
    'classroom timer refreshes only while foreground and stops when leaving',
    (tester) async {
      await _tab(tester, '服务');
      await tester.tap(find.text('空教室'));
      await tester.pumpAndSettle();
      expect(periodicReads, 1);
      periodicTime = periodicTime.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(periodicReads, 2);
      final lifecycle = tester.binding;
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      periodicTime = periodicTime.add(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 10));
      expect(periodicReads, 2);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(periodicReads, 3);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ClassroomsPage), findsNothing);
      periodicTime = periodicTime.add(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 10));
      expect(periodicReads, 3);
    },
    classroomResponse: () {
      periodicReads++;
      return http.Response.bytes(utf8.encode(classroomWeekBody()), 200);
    },
    classroomClock: () => periodicTime,
  );

  _appTest(
    'campus card refresh runs only when the services menu becomes visible',
    (tester) async {
      expect(cardRepository.refreshes, 0);
      await _tab(tester, '服务');
      expect(cardRepository.refreshes, 1);
      expect(find.text('¥0.00'), findsNothing);
      await _tab(tester, '服务');
      expect(cardRepository.refreshes, 1);
      await _tab(tester, '课表');
      _resume(tester);
      await tester.pumpAndSettle();
      expect(cardRepository.refreshes, 1);

      cardRepository.nextBalance = (cents: 5678, readAt: DateTime.utc(2026));
      final router = _router(tester);
      router.go('/services/classrooms');
      await tester.pumpAndSettle();
      expect(cardRepository.refreshes, 1);
      router.pop();
      await tester.pumpAndSettle();
      expect(cardRepository.refreshes, 2);
      expect(find.text('¥56.78'), findsOneWidget);

      cardRepository.nextBalance = null;
      await _tab(tester, '课表');
      await _tab(tester, '服务');
      expect(cardRepository.refreshes, 3);
      expect(find.text('¥56.78'), findsOneWidget);
    },
    campusCardRepository: cardRepository,
  );

  final sunday = DateTime.utc(2026, 11, 29, 23, 59, 58);
  final datedTimetable = Timetable([
    Semester(id: 'dated', name: '跨日测试学期', start: mondayOf(sunday), weeks: 18),
  ], []);
  var now = sunday;
  var reminderSyncs = 0;
  var timetableRefreshes = 0;
  _appTest(
    'midnight updates the week and resume syncs while another tab is open',
    (tester) async {
      final window = find.byType(WeekTimetable);
      WeekTimetable visibleWeek() => tester.widget<WeekTimetable>(window);
      expect(visibleWeek().week, 1);
      expect(visibleWeek().today, calendarDate(sunday));
      now = DateTime.utc(2026, 11, 30);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(visibleWeek().week, 2);
      expect(visibleWeek().today, now);

      await _tab(tester, '服务');
      final priorReminderSyncs = reminderSyncs;
      final priorRefreshes = timetableRefreshes;
      now = DateTime.utc(2026, 12, 7);
      _resume(tester);
      await tester.pumpAndSettle();
      expect(reminderSyncs, priorReminderSyncs + 1);
      expect(timetableRefreshes, priorRefreshes + 1);
      await _tab(tester, '课表');
      expect(visibleWeek().week, 3);
      expect(visibleWeek().today, now);

      final container = ProviderScope.containerOf(tester.element(window));
      await container.read(schoolSessionProvider.notifier).disconnect();
      await tester.pumpAndSettle();
      final afterLogoutSyncs = reminderSyncs;
      final afterLogoutRefreshes = timetableRefreshes;
      _resume(tester);
      await tester.pumpAndSettle();
      expect(reminderSyncs, afterLogoutSyncs);
      expect(timetableRefreshes, afterLogoutRefreshes);
    },
    timetableClock: () => now,
    initialTimetable: datedTimetable,
    onReminderSync: () => reminderSyncs++,
    onRefresh: (section) {
      if (section == SchoolDataSet.timetable) timetableRefreshes++;
    },
  );
}

void _appTest(
  String description,
  Future<void> Function(WidgetTester) scenario, {
  _TestAuth auth = const _TestAuth(),
  Future<void> Function(WidgetTester)? beforeSettle,
  SchoolGradeBook? schoolGrades,
  Timetable? initialTimetable,
  CampusCardBalance? campusCardBalance,
  CampusCardRepository? campusCardRepository,
  http.Response Function()? classroomResponse,
  DateTime Function()? classroomClock,
  DateTime Function()? timetableClock,
  List<SchoolPolicy>? schoolPolicies,
  Future<Uint8List> Function(SchoolPolicy)? schoolPolicyPdf,
  SchoolPolicySaver? schoolPolicySaver,
  void Function()? onReminderSync,
  void Function(SchoolDataSet)? onRefresh,
}) {
  testWidgets(description, (tester) async {
    final timetable = _TestTimetable();
    final grades = _TestGrades();
    final classroomCache = _WidgetClassroomCache();
    final classroomClient = MockClient(
      (_) async => classroomResponse?.call() ?? http.Response('', 503),
    );
    addTearDown(classroomCache.close);
    addTearDown(classroomClient.close);
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
            classroomCacheProvider.overrideWithValue(classroomCache),
            classroomsClockProvider.overrideWithValue(
              classroomClock ?? () => classroomNow,
            ),
            publicDataClientProvider.overrideWithValue(
              PublicDataClient(
                classroomClient,
                dataBackupOrigin: publicDataRoot,
                cooldown: Duration.zero,
              ),
            ),
            campusMapProvider.overrideWith(
              (ref) => Stream.error(const FormatException()),
            ),
            if (schoolPolicies != null)
              schoolPoliciesProvider.overrideWith(
                (ref) => Stream.value(SchoolPolicyCatalog(schoolPolicies)),
              ),
            if (schoolPolicyPdf != null)
              schoolPolicyPdfProvider.overrideWith(
                (ref, policy) => schoolPolicyPdf(policy),
              ),
            if (schoolPolicySaver != null)
              saveSchoolPolicyProvider.overrideWithValue(schoolPolicySaver),
            if (campusCardRepository != null)
              campusCardRepositoryProvider.overrideWithValue(
                campusCardRepository,
              ),
            if (timetableClock != null)
              timetableClockProvider.overrideWithValue(timetableClock),
            campusMailProvider.overrideWithValue(null),
            employmentCacheProvider.overrideWith((ref) async => null),
            employmentRefreshProvider.overrideWith(
              (ref, force) async => throw const FormatException(),
            ),
            timetableRepositoryProvider.overrideWithValue(timetable),
            gradesRepositoryProvider.overrideWithValue(grades),
            settingsProvider.overrideWith(_TestSettings.new),
            reminderSyncProvider.overrideWith((ref) async {
              onReminderSync?.call();
              return const ReminderStatus(ReminderCondition.off);
            }),
          ],
          child: const NeuqOneApp(),
        ),
      );
      await beforeSettle?.call(tester);
      await tester.pumpAndSettle();
      await scenario(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(timetable.changes.close());
      unawaited(grades.changes.close());
    }
  });
}

class _TestCampusCardRepository extends CampusCardRepository {
  _TestCampusCardRepository() : super(const FlutterSecureStorage(), 'test');

  int refreshes = 0;
  CampusCardBalance? nextBalance;
  CampusCardBalance? _cached;

  @override
  Future<CampusCardBalance?> load() async => _cached;

  @override
  Future<CampusCardBalance> refresh() async {
    refreshes++;
    final balance = nextBalance;
    if (balance == null) throw StateError('Balance unavailable');
    _cached = balance;
    return balance;
  }
}

class _WidgetClassroomCache extends ClassroomCache {
  _WidgetClassroomCache() : super(NativeDatabase.memory());

  @override
  Future<ClassroomCacheEntry?> readWeek() async => null;

  @override
  Future<void> writeWeek(ClassroomCacheEntry entry) async {}
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

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NavigationBar)))
        .read(routerProvider);

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<void> _createSemester(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, '新增学期'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '新增学期'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, '测试学期');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
  expect(find.text('测试学期'), findsOneWidget);
  await tester.tap(find.byTooltip('选择学期'));
  await tester.pumpAndSettle();
  final term = find.widgetWithText(CheckedPopupMenuItem<String>, '测试学期');
  expect(tester.widget<CheckedPopupMenuItem<String>>(term).checked, isTrue);
  await tester.tap(term);
  await tester.pumpAndSettle();
}

class _TestAuth implements SchoolAuthRepository {
  const _TestAuth({this.restore = true, this.restoration});
  final bool restore;
  final Future<SchoolSession?> Function()? restoration;

  @override
  bool get available => true;
  @override
  bool get canRememberPassword => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> hasRememberedPassword(String subject) async => false;
  @override
  Future<void> forgetPassword(String subject) async {}
  @override
  Future<SchoolSession?> restoreSession() =>
      restoration?.call() ?? Future.value(restore ? _session : null);
  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async => _session;

  static const _session = SchoolSession(
    subject: 'test-owner',
    admissionYear: 2025,
  );
}

class _RememberingTestAuth extends _TestAuth {
  _RememberingTestAuth({super.restore, this.remembered = false});

  bool remembered;
  Completer<void>? pendingLogout;

  @override
  Future<bool> hasRememberedPassword(String subject) async => remembered;

  @override
  Future<void> forgetPassword(String subject) async {
    expect(subject, _TestAuth._session.subject);
    remembered = false;
  }

  @override
  Future<void> disconnect() async {
    await pendingLogout?.future;
    remembered = false;
  }

  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async {
    remembered = rememberPassword;
    return _TestAuth._session;
  }
}

class _TestSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> setTheme(ThemeMode value) async =>
      state = AsyncData(AppSettings(theme: value));
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
