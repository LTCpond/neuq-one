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
import 'package:neuq_one/app/login_motion.dart';
import 'package:neuq_one/app/login_page.dart';
import 'package:neuq_one/app/router.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/network/campus_access/campus_access_providers.dart';
import 'package:neuq_one/core/network/campus_access/webvpn_session_manager.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/exams/data/local_exams.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/exams/presentation/exams_section.dart';
import 'package:neuq_one/features/grades/data/local_grades.dart';
import 'package:neuq_one/features/grades/data/neuq_plan_completion.dart';
import 'package:neuq_one/features/grades/domain/grades.dart';
import 'package:neuq_one/features/grades/domain/plan_completion.dart';
import 'package:neuq_one/features/grades/presentation/academic_page.dart';
import 'package:neuq_one/features/grades/presentation/plan_completion_section.dart';
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
import 'package:neuq_one/features/services/presentation/services_page.dart';
import 'package:neuq_one/features/timetable/data/local_timetable.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_date.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_page.dart';
import 'package:neuq_one/features/timetable/presentation/week_timetable.dart';

import 'fixtures/classroom_week.dart';
import 'fixtures/plan_completion.dart';

void main() {
  final unusedVpn = _UnusedWebVpn();
  _appTest(
    'startup, public classroom data and foreground resume leave WebVPN untouched',
    (tester) async {
      expect(unusedVpn.attempts, 0);
      await _tab(tester, '服务');
      final services = find.descendant(
        of: find.byType(ServicesPage),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('WebVPN'),
        240,
        scrollable: services,
      );
      expect(find.text('WebVPN'), findsOneWidget);
      _router(tester).push<void>('/services/classrooms');
      await tester.pumpAndSettle();
      expect(find.byType(ClassroomsPage), findsOneWidget);
      _resume(tester);
      await tester.pumpAndSettle();
      expect(unusedVpn.attempts, 0);
    },
    vpnProtocol: unusedVpn,
    classroomResponse: () =>
        http.Response.bytes(utf8.encode(classroomWeekBody()), 200),
  );

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
    expect(find.text('打开学校门户'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginPage)),
    );
    container.read(routerProvider).go('/services/classrooms');
    await tester.pumpAndSettle();
    expect(find.text('此平台暂不支持应用内登录'), findsOneWidget);
    expect(find.byType(ClassroomsPage), findsNothing);
  });

  testWidgets('login layout follows the theme and skips reduced motion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolAuthRepositoryProvider.overrideWithValue(
            const _TestAuth(restore: false),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          home: const LoginPage(),
        ),
      ),
    );
    for (final reveal in tester.widgetList<LoginReveal>(
      find.byType(LoginReveal),
    )) {
      expect(reveal.progress.value, 1);
    }
    await tester.pumpAndSettle();
    expect(find.text('校园一站式服务平台'), findsNothing);
    final title = find.text('统一身份认证');
    final brand = find.text('NEUQ');
    final button = find.widgetWithText(FilledButton, '统一身份认证登录');
    final input = find.byType(TextFormField).first;
    expect(tester.getTopLeft(brand).dx, tester.getTopLeft(title).dx);
    expect(tester.getTopLeft(input).dx, tester.getTopLeft(title).dx);
    expect(tester.getSize(input).height, inInclusiveRange(54, 56));
    expect(tester.getSize(button).width, tester.getSize(input).width);
    final formCenter =
        (tester.getTopLeft(title).dy + tester.getBottomLeft(button).dy) / 2;
    expect(formCenter, closeTo(422, 32));
    final lightRect = tester.getRect(input);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );
    expect(tester.widget<Text>(brand).style?.color, campusBlue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    final dark = appTheme(Brightness.dark);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      dark.scaffoldBackgroundColor,
    );
    expect(tester.widget<Text>(brand).style?.color, dark.colorScheme.primary);
    expect(tester.getRect(input), lightRect);

    tester.view.physicalSize = const Size(1080, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(input).width, 400);
  });

  _appTest(
    'the compact login keeps controls reachable with the keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 520);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final inputs = find.byType(EditableText);
      await tester.enterText(inputs.first, '00001234');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(inputs.last).focusNode.hasFocus,
        isTrue,
      );
      final button = find.widgetWithText(FilledButton, '统一身份认证登录');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(260));
      expect(tester.takeException(), isNull);
    },
    auth: const _TestAuth(restore: false),
  );

  late Completer<SchoolSession> pendingLogin;
  var loginAttempts = 0;
  _appTest(
    'login toggles password visibility, loads in place, and exposes the official fallback',
    (tester) async {
      pendingLogin = Completer<SchoolSession>();
      final inputs = find.byType(EditableText);
      final button = find.widgetWithText(FilledButton, '统一身份认证登录');
      final size = tester.getSize(button);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.widget<EditableText>(inputs.last).obscureText, isTrue);
      await tester.enterText(inputs.first, '00001234');
      await tester.enterText(inputs.last, 'test-password');
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(inputs.last).obscureText, isFalse);
      await tester.tap(find.byTooltip('隐藏密码'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(inputs.last).obscureText, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.getSize(button), size);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(button);
      expect(loginAttempts, 1);
      pendingLogin.completeError(SchoolRequestFailure.verificationRequired);
      await tester.pumpAndSettle();
      expect(
        find.text(SchoolRequestFailure.verificationRequired.message),
        findsOneWidget,
      );
      expect(find.text('在系统浏览器打开教务'), findsOneWidget);
      expect(
        tester.widget<EditableText>(inputs.first).controller.text,
        '00001234',
      );
      expect(tester.widget<EditableText>(inputs.last).controller.text, isEmpty);
    },
    auth: _TestAuth(
      restore: false,
      canRememberPassword: false,
      onSignIn: () {
        loginAttempts++;
        return pendingLogin.future;
      },
    ),
  );

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(TextFormField).hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
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
      expect(find.text('偏好设置'), findsOneWidget);
      expect(find.text('WebVPN'), findsNothing);
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
      await tester.pumpAndSettle();
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
        '学业',
        '服务',
        '我的',
      ]);
      expect(find.text('下一节课'), findsNothing);
      expect(find.text('今日课程'), findsNothing);
      expect(find.text('最近考试'), findsNothing);
      await _tab(tester, '学业');
      expect(find.byType(ExamSection), findsNothing);
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
      await _tab(tester, '学业');
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
      await _tab(tester, '学业');
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

  _appTest(
    'all semesters combines cached and local grades under their own semesters',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      await _tab(tester, '学业');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NavigationBar)),
      );
      await container
          .read(gradesRepositoryProvider)
          .save(
            const Grade(
              id: 'local:grade',
              semesterId: 'local:term',
              name: '本地课程',
              credit: 2,
              score: 70,
              kind: GradeKind.required,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('本地课程'), findsNothing);

      final menu = find.byTooltip('选择学期');
      final all = find.widgetWithText(CheckedPopupMenuItem<String>, '全部学期');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();

      expect(find.text('全部学期'), findsOneWidget);
      expect(find.text('教务累计 GPA'), findsOneWidget);
      expect(find.text('3.6502'), findsOneWidget);
      expect(find.text('80.0'), findsOneWidget);
      expect(find.text('5 / 5'), findsOneWidget);
      final average = tester.getTopLeft(find.text('平均分'));
      final gpa = tester.getTopLeft(find.text('教务累计 GPA'));
      final credits = tester.getTopLeft(find.text('通过 / 登记学分'));
      final trend = tester.getTopLeft(find.text('各学期 GPA 趋势'));
      expect(gpa.dx, greaterThan(average.dx));
      expect(credits.dx, closeTo(gpa.dx, 2));
      expect(credits.dy, greaterThan(gpa.dy));
      expect(trend.dx, lessThan(credits.dx));
      expect(trend.dy, greaterThan(credits.dy));
      final localPoint = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '本地学期 · GPA 2.0000',
      );
      final schoolPoint = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '教务学期 · GPA 3.7123',
      );
      expect(
        tester.getCenter(localPoint).dx,
        lessThan(tester.getCenter(schoolPoint).dx),
      );
      expect(find.text('教务课程'), findsOneWidget);
      expect(find.text('录入成绩'), findsNothing);
      final localCourse = find.text('本地课程');
      await tester.ensureVisible(localCourse);
      await tester.pumpAndSettle();
      await tester.tap(localCourse);
      await tester.pumpAndSettle();
      expect(find.textContaining('本地学期\n'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '编辑'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();

      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckedPopupMenuItem<String>>(all).checked, isTrue);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '本地学期'),
      );
      await tester.pumpAndSettle();
      expect(find.text('教务课程'), findsNothing);
      expect(find.text('本地课程'), findsOneWidget);
      expect(find.text('录入成绩'), findsOneWidget);
      expect(find.text('各学期 GPA 趋势'), findsNothing);
    },
    initialTimetable: Timetable([
      Semester(
        id: 'local:term',
        name: '本地学期',
        start: DateTime.utc(2024, 9, 2),
        weeks: 18,
      ),
    ], const []),
    schoolGrades: SchoolGradeBook(
      [
        Semester(
          id: 'school:term',
          name: '教务学期',
          start: DateTime.utc(2025, 9, 1),
          weeks: 18,
        ),
      ],
      const [
        Grade(
          id: 'school:grade',
          semesterId: 'school:term',
          name: '教务课程',
          credit: 3,
          score: 90,
          kind: GradeKind.required,
        ),
      ],
      semesterGpa: const {'school:term': 3.7123},
      cumulativeGpa: 3.6502,
    ),
  );

  final planRefreshes = <SchoolDataSet>[];
  _appTest(
    'academic center opens the plan audit and expands courses from the last snapshot',
    (tester) async {
      await _tab(tester, '学业');
      expect(find.byType(AcademicPage), findsOneWidget);
      expect(planRefreshes, isNot(contains(SchoolDataSet.planCompletion)));
      await tester.tap(find.text('培养方案'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanCompletionSection), findsOneWidget);
      expect(find.text('培养方案'), findsOneWidget);
      expect(
        planRefreshes.where(
          (section) => section == SchoolDataSet.planCompletion,
        ),
        hasLength(1),
      );
      expect(find.text('距离计划要求还差 4 学分'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('示例数学'), findsNothing);
      await tester.ensureVisible(find.text('通识类课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通识类课程'));
      await tester.pumpAndSettle();
      expect(find.text('科学基础'), findsOneWidget);
      await tester.ensureVisible(find.text('科学基础'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('科学基础'));
      await tester.pumpAndSettle();
      expect(find.text('示例数学'), findsOneWidget);
      expect(find.text('大一上 · 必修 · 4 学分'), findsOneWidget);
      // The only '已通过' text left is the filter chip; course status is
      // conveyed by the semantic status icon.
      expect(find.text('已通过'), findsOneWidget);
      final planList = find.descendant(
        of: find.byType(PlanCompletionSection),
        matching: find.byType(Scrollable),
      );
      final pending = find.byIcon(Icons.schedule_rounded);
      await tester.scrollUntilVisible(pending, 100, scrollable: planList);
      expect(pending, findsOneWidget);
    },
    planCompletion: readNeuqPlanCompletion(
      planCompletionHtml,
      schoolSubjectForStudentCode(planFixtureStudent)!,
    ),
    onRefresh: (section) {
      planRefreshes.add(section);
      if (section == SchoolDataSet.planCompletion) {
        throw SchoolRequestFailure.unavailable;
      }
    },
  );

  final sectionRefreshes = <SchoolDataSet>[];
  _appTest(
    'academic sections keep their actions, filters and data when switching',
    (tester) async {
      await _tab(tester, '学业');
      expect(find.byType(AcademicPage), findsOneWidget);
      _router(tester).go('/grades/plan-completion');
      await tester.pumpAndSettle();
      expect(
        _router(tester).routeInformationProvider.value.uri.path,
        '/grades',
      );
      expect(find.text('学业中心'), findsOneWidget);
      expect(find.text('成绩'), findsOneWidget);
      expect(find.text('培养方案'), findsOneWidget);
      expect(find.text('考试安排'), findsOneWidget);
      expect(find.byTooltip('选择学期'), findsOneWidget);
      expect(find.byTooltip('刷新教务成绩'), findsOneWidget);
      expect(find.byTooltip('刷新培养方案'), findsNothing);
      expect(find.byTooltip('添加考试'), findsNothing);

      await tester.tap(find.byTooltip('选择学期'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '全部学期'),
      );
      await tester.pumpAndSettle();
      expect(find.text('教务累计 GPA'), findsOneWidget);
      final gradesLoads = sectionRefreshes
          .where((section) => section == SchoolDataSet.grades)
          .length;
      expect(gradesLoads, 1);

      await tester.tap(find.text('培养方案'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新培养方案'), findsOneWidget);
      expect(find.byTooltip('选择学期'), findsNothing);
      expect(find.byTooltip('刷新教务成绩'), findsNothing);
      expect(find.byTooltip('添加考试'), findsNothing);
      await tester.ensureVisible(find.text('通识类课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通识类课程'));
      await tester.pumpAndSettle();
      expect(find.text('科学基础'), findsOneWidget);
      final planScroll = find
          .descendant(
            of: find.byType(PlanCompletionSection),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(planScroll, const Offset(0, -160));
      await tester.pumpAndSettle();
      final planOffset = tester
          .state<ScrollableState>(planScroll)
          .position
          .pixels;
      expect(planOffset, greaterThan(0));
      final planLoads = sectionRefreshes
          .where((section) => section == SchoolDataSet.planCompletion)
          .length;

      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('添加考试'), findsOneWidget);
      expect(find.byTooltip('选择学期'), findsNothing);
      expect(find.byTooltip('刷新培养方案'), findsNothing);
      expect(find.text('该板块不从教务处同步数据，考试安排由学生手动添加。'), findsOneWidget);
      expect(find.text('暂无考试安排'), findsOneWidget);

      await tester.tap(find.text('培养方案'));
      await tester.pumpAndSettle();
      expect(find.text('科学基础'), findsOneWidget);
      final restoredPlanScroll = find
          .descendant(
            of: find.byType(PlanCompletionSection),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(restoredPlanScroll).position.pixels,
        planOffset,
      );
      expect(
        sectionRefreshes
            .where((section) => section == SchoolDataSet.planCompletion)
            .length,
        planLoads,
      );

      await tester.tap(find.text('成绩'));
      await tester.pumpAndSettle();
      expect(find.text('教务累计 GPA'), findsOneWidget);
      expect(
        sectionRefreshes
            .where((section) => section == SchoolDataSet.grades)
            .length,
        gradesLoads,
      );
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
    planCompletion: readNeuqPlanCompletion(
      planCompletionHtml,
      schoolSubjectForStudentCode(planFixtureStudent)!,
    ),
    onRefresh: sectionRefreshes.add,
  );

  final today = calendarDate(campusNow());
  final currentTerm = Semester(
    id: 'local:term',
    name: '当前学期',
    start: mondayOf(today),
    weeks: 18,
  );
  _appTest(
    'exam subjects deduplicate and only custom entries show an input',
    (tester) async {
      await _tab(tester, '学业');
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(find.text('暂无考试安排'), findsOneWidget);

      await tester.tap(find.byTooltip('添加考试'));
      await tester.pumpAndSettle();
      final nameField = find.byKey(const ValueKey('exam-subject-name'));
      final textField = tester.widget<TextField>(
        find.descendant(of: nameField, matching: find.byType(TextField)),
      );
      expect(textField.decoration?.filled, isTrue);
      final border = textField.decoration?.border;
      expect(border, isA<OutlineInputBorder>());
      expect((border! as OutlineInputBorder).borderSide, BorderSide.none);
      final start = find.byKey(const ValueKey('exam-start-time'));
      final end = find.byKey(const ValueKey('exam-end-time'));
      expect(tester.getTopLeft(start).dy, tester.getTopLeft(end).dy);
      expect(tester.getTopRight(start).dx, lessThan(tester.getTopLeft(end).dx));

      await tester.tap(find.text('自定义科目'));
      await tester.pumpAndSettle();
      expect(find.text('线性代数'), findsOneWidget);
      await tester.tap(find.text('线性代数'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-subject-name')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('exam-room')),
        '工学馆 101',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('线性代数'), findsOneWidget);
      expect(find.text('09:00–11:00'), findsOneWidget);
      expect(find.text('工学馆 101'), findsOneWidget);
      expect(find.text('暂无考试安排'), findsNothing);

      await tester.tap(find.text('线性代数'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-subject-name')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exam-subject-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义科目'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-subject-name')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('exam-subject-name')),
        '高等数学 A',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('高等数学 A'), findsOneWidget);

      await tester.tap(find.text('成绩'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(find.text('高等数学 A'), findsOneWidget);

      await tester.tap(find.byTooltip('考试选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('暂无考试安排'), findsOneWidget);
    },
    initialTimetable: Timetable(
      [currentTerm],
      [
        _sampleCourse('course-a', '线性代数', currentTerm, DateTime.monday, 1, 2),
        _sampleCourse('course-b', '线性代数', currentTerm, DateTime.tuesday, 3, 4),
      ],
    ),
  );

  _appTest(
    'exam cards group by date under independent headings',
    (tester) async {
      await _tab(tester, '学业');
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));
      String heading(DateTime date) =>
          '${shortDate(date)} ${weekdayLabel(date.weekday)}';
      expect(find.text('今天 · ${heading(today)}'), findsOneWidget);
      expect(find.text('明天 · ${heading(tomorrow)}'), findsOneWidget);
      expect(find.text(heading(yesterday)), findsOneWidget);
      expect(find.text('今日考试甲'), findsOneWidget);
      expect(find.text('今日考试乙'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(heading(yesterday))).dy,
        lessThan(tester.getTopLeft(find.text('今天 · ${heading(today)}')).dy),
      );
      expect(
        tester.getTopLeft(find.text('今天 · ${heading(today)}')).dy,
        lessThan(tester.getTopLeft(find.text('明天 · ${heading(tomorrow)}')).dy),
      );
      final past = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('昨日考试'), matching: find.byType(Opacity))
            .first,
      );
      final upcoming = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('明日考试'), matching: find.byType(Opacity))
            .first,
      );
      expect(past.opacity, lessThan(1));
      expect(upcoming.opacity, 1);
    },
    initialExams: [
      _testExam('yesterday', '昨日考试', today.subtract(const Duration(days: 1))),
      _testExam('today-a', '今日考试甲', today),
      _testExam('today-b', '今日考试乙', today, start: 14),
      _testExam('tomorrow', '明日考试', today.add(const Duration(days: 1))),
    ],
  );

  _appTest(
    'academic center fits a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await _tab(tester, '学业');
      expect(find.text('学业中心'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('培养方案'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('该板块不从教务处同步数据，考试安排由学生手动添加。'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      await tester.tap(find.byTooltip('添加考试'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
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
    initialExams: [_testExam('narrow', '高等数学', today)],
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

      await _tab(tester, '学业');
      expect(find.text('学业中心'), findsOneWidget);
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
      await tester.scrollUntilVisible(find.text('校园网').hitTestable(), 160);
      expect(find.text('校园网'), findsOneWidget);
      expect(find.text('图书馆'), findsNothing);
      await tester.scrollUntilVisible(find.text('空教室').hitTestable(), -160);
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

  final pagingTerm = Semester(
    id: 'paging',
    name: '分页学期',
    start: DateTime.utc(2026, 8, 24),
    weeks: 6,
  );
  final shortTerm = Semester(
    id: 'short',
    name: '较短学期',
    start: DateTime.utc(2026, 4, 6),
    weeks: 2,
  );
  final pagingTimetable = Timetable(
    [pagingTerm, shortTerm],
    [_sampleCourse('paging', '分页测试课程', pagingTerm, DateTime.monday, 1, 2)],
  );
  final pagingRefreshes = <SchoolDataSet>[];

  _appTest(
    'timetable pages follow a slow drag, settle, and handle quick swipes and edges',
    (tester) async {
      final pager = find.byType(PageView);
      final controller = tester.widget<PageView>(pager).controller!;
      final viewport = tester.getRect(pager);
      final rail = find.byKey(const ValueKey('timetable-period-1'));
      final railBounds = tester.getRect(rail);
      final card = find.descendant(
        of: find.byType(WeekTimetable),
        matching: find.byType(Card),
      );
      final cardBounds = tester.getRect(card);
      final headerBounds = tester.getRect(find.byType(AppBar));
      final navBounds = tester.getRect(find.byType(NavigationBar));
      final currentDate = find.byKey(ValueKey(DateTime.utc(2026, 9, 1)));
      final initialDateX = tester.getTopLeft(currentDate).dx;
      final course = find.byKey(const ValueKey('timetable-course-paging'));
      final initialCourseX = tester.getTopLeft(course).dx;
      final nextMonday = find.byKey(ValueKey(DateTime.utc(2026, 9, 7)));
      final initialRefreshes = pagingRefreshes.length;
      expect(controller.page, 1);
      expect(find.text('8月31日 – 9月6日'), findsOneWidget);
      expect(find.text('8月'), findsOneWidget);
      expect(nextMonday, findsNothing);

      final drag = await tester.startGesture(
        viewport.centerRight - const Offset(12, 0),
      );
      for (var step = 1; step <= 8; step++) {
        final time = Duration(milliseconds: 200 * step);
        await drag.moveBy(Offset(-viewport.width * .09, 0), timeStamp: time);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(controller.page, inExclusiveRange(1.5, 1.8));
      final displacement = (controller.page! - 1) * viewport.width;
      expect(
        tester.getTopLeft(currentDate).dx,
        closeTo(initialDateX - displacement, 1),
      );
      expect(
        tester.getTopLeft(course).dx,
        closeTo(initialCourseX - displacement, 1),
      );
      expect(
        tester.getTopLeft(nextMonday).dx,
        inExclusiveRange(viewport.left, viewport.right),
      );
      expect(tester.getRect(rail), railBounds);
      expect(tester.getRect(card), cardBounds);
      expect(tester.getRect(find.byType(AppBar)), headerBounds);
      expect(tester.getRect(find.byType(NavigationBar)), navBounds);
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('8月'), findsOneWidget);

      await drag.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      expect(find.text('第 3 周'), findsOneWidget);
      expect(find.text('9月7日 – 9月13日'), findsOneWidget);
      expect(find.text('9月'), findsOneWidget);
      expect(tester.getRect(card), cardBounds);
      expect(tester.getRect(rail), railBounds);
      expect(find.text('本周暂无课程'), findsOneWidget);
      for (var day = 0; day < DateTime.daysPerWeek; day++) {
        expect(
          find.byKey(ValueKey(DateTime.utc(2026, 9, 7 + day))),
          findsOneWidget,
        );
      }
      await tester.tap(nextMonday);
      await tester.pumpAndSettle();
      expect(find.text('当天没有课程'), findsOneWidget);
      _router(tester).pop();
      await tester.pumpAndSettle();

      await tester.timedDragFrom(
        viewport.center,
        Offset(viewport.width * .22, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      expect(find.text('第 3 周'), findsOneWidget);

      Future<void> fling(int direction, {double distance = .28}) =>
          tester.flingFrom(
            viewport.center,
            Offset(viewport.width * distance * direction, 0),
            2000,
          );
      await fling(1);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(find.text('第 2 周'), findsOneWidget);
      expect(course, findsOneWidget);

      await fling(-1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 185));
      expect(controller.page, inExclusiveRange(1.75, 2));
      expect(find.text('第 2 周'), findsOneWidget);
      await fling(-1, distance: .43);
      await tester.pumpAndSettle();
      expect(controller.page, 3);
      expect(find.text('第 4 周'), findsOneWidget);

      for (var week = 5; week <= 7; week++) {
        await fling(-1);
        await tester.pumpAndSettle();
        expect(controller.page, (week - 1).clamp(0, 5));
      }
      expect(find.text('第 6 周'), findsOneWidget);
      await _selectTimetableWeek(tester, 1);
      await tester.pumpAndSettle();
      await fling(1);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(pagingRefreshes, hasLength(initialRefreshes));

      await tester.dragFrom(viewport.center, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(rail).dy, lessThan(railBounds.top));
      expect(controller.page, 0);
      expect(tester.takeException(), isNull);
    },
    initialTimetable: pagingTimetable,
    timetableClock: () => DateTime.utc(2026, 9, 1),
    onRefresh: pagingRefreshes.add,
  );

  _appTest(
    'week menu animates adjacent weeks, jumps distant weeks, and resets for a new semester',
    (tester) async {
      PageController controller() =>
          tester.widget<PageView>(find.byType(PageView)).controller!;
      final initialController = controller();
      await _selectTimetableWeek(tester, 3);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller().page, inExclusiveRange(1, 2));
      await tester.pumpAndSettle();
      expect(controller().page, 2);

      await _selectTimetableWeek(tester, 6);
      await tester.pump();
      expect(controller().page, 5);
      await tester.pumpAndSettle();
      expect(find.text('第 6 周'), findsOneWidget);

      await tester.tap(find.byTooltip('选择学期'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, shortTerm.name),
      );
      await tester.pumpAndSettle();
      expect(controller(), isNot(same(initialController)));
      expect(controller().page, 0);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text('4月6日 – 4月12日'), findsOneWidget);
      await tester.tap(find.byTooltip('选择教学周'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<int>), findsNWidgets(shortTerm.weeks));
      await tester.tap(find.widgetWithText(PopupMenuItem<int>, '第 2 周'));
      await tester.pumpAndSettle();
      expect(controller().page, 1);

      await tester.tap(find.byTooltip('课表选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回到本周'));
      await tester.pumpAndSettle();
      expect(controller().page, 1);
      expect(find.text('8月31日 – 9月6日'), findsOneWidget);
      expect(find.text('分页测试课程'), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await _selectTimetableWeek(tester, 3);
      await tester.pump();
      expect(controller().page, 2);
      await tester.pumpAndSettle();
      expect(find.text('第 3 周'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    initialTimetable: pagingTimetable,
    timetableClock: () => DateTime.utc(2026, 9, 1),
  );

  _appTest('manual grade contributes to GPA', (tester) async {
    await _tab(tester, '学业');
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

    await tester.tap(find.byTooltip('选择学期'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '全部学期'));
    await tester.pumpAndSettle();
    expect(find.text('累计 GPA'), findsOneWidget);
    expect(find.text('3.8000'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '测试学期 · GPA 3.8000',
      ),
      findsOneWidget,
    );
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
      final entry = find.text('学校政策').hitTestable();
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

  final fusionDate = DateTime.utc(2026, 12, 7);
  final fusionTerm = Semester(
    id: 'school:fusion-test',
    name: '融合测试学期',
    start: fusionDate.subtract(const Duration(days: 7)),
    weeks: 3,
  );
  final fusionCourse = Course(
    id: 'school:fusion-course',
    semesterId: fusionTerm.id,
    name: '融合课程',
    teacher: '任课教师',
    room: '融合教室',
    weekday: DateTime.monday,
    startMinute: 480,
    endMinute: 575,
    weeks: const [2],
    colorIndex: 7,
  );
  final fusionExam = Exam(
    id: 'fusion-exam',
    name: '融合考试',
    at: campusInstant(fusionDate, 500),
    endsAt: campusInstant(fusionDate, 550),
    room: '融合考场',
  );
  _appTest(
    '课表考试融合保留原课程信息、响应考试删除和显示开关，保持所选教学周',
    (tester) async {
      final week = find.byType(WeekTimetable);
      final course = find.byKey(
        const ValueKey('timetable-course-school:fusion-course'),
      );
      final exam = find.byKey(
        ValueKey('timetable-exam-fusion-exam-$fusionDate'),
      );
      await tester.tap(find.byTooltip('选择教学周'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 2 周').last);
      await tester.pumpAndSettle();
      expect(course, findsNWidgets(2));
      expect(exam, findsOneWidget);
      await tester.tap(exam);
      await tester.pumpAndSettle();
      expect(find.text('时间冲突'), findsOneWidget);
      expect(find.textContaining('08:00–09:35'), findsOneWidget);
      expect(find.textContaining('任课教师'), findsOneWidget);
      expect(find.textContaining('融合考场\n查看考试详情'), findsOneWidget);
      Navigator.of(tester.element(find.text('时间冲突'))).pop();
      await tester.pumpAndSettle();

      final scope = ProviderScope.containerOf(tester.element(week));
      final exams = scope.read(examRepositoryProvider);
      await exams.delete(fusionExam.id);
      await tester.pumpAndSettle();
      expect(tester.widget<WeekTimetable>(week).week, 2);
      expect(course, findsOneWidget);
      expect(exam, findsNothing);

      await exams.save(fusionExam);
      await tester.pumpAndSettle();
      await _tab(tester, '学业');
      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle();
      expect(find.text('时间冲突 · 融合课程'), findsOneWidget);
      _router(tester).go(
        '/grades?section=exams&widget=90&exam=fusion-exam&date=2026-12-07&conflict=1',
      );
      await tester.pumpAndSettle();
      expect(find.text('时间冲突'), findsOneWidget);
      Navigator.of(tester.element(find.text('时间冲突'))).pop();
      await tester.pumpAndSettle();
      await exams.delete(fusionExam.id);
      await tester.pumpAndSettle();
      expect(find.text('时间冲突 · 融合课程'), findsNothing);
      _router(tester).go(
        '/grades?section=exams&widget=91&exam=fusion-exam&date=2026-12-07&conflict=1',
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无考试安排'), findsOneWidget);
      await exams.save(fusionExam);
      await scope
          .read(settingsProvider.notifier)
          .setShowExamsInTimetable(false);
      await tester.pumpAndSettle();
      expect(find.text('时间冲突 · 融合课程'), findsOneWidget);
      await _tab(tester, '课表');
      expect(tester.widget<WeekTimetable>(week).week, 2);
      expect(course, findsOneWidget);
      expect(exam, findsNothing);
    },
    initialTimetable: Timetable([fusionTerm], [fusionCourse]),
    initialExams: [fusionExam],
    timetableClock: () => fusionDate.subtract(const Duration(days: 7)),
  );

  var examClock = fusionExam.campusEnd.subtract(const Duration(seconds: 1));
  _appTest(
    '考试在结束时自动切换历史配色，教学周之外通过对应日期查看',
    (tester) async {
      final exam = find.byKey(
        ValueKey('timetable-exam-fusion-exam-$fusionDate'),
      );
      final before = tester.widget<Material>(exam).color;
      examClock = fusionExam.campusEnd;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(exam).color, isNot(before));
      final outside = find.text('教学周外单独考试');
      await tester.scrollUntilVisible(
        outside,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(outside);
      await tester.pumpAndSettle();
      expect(find.text('当日日程'), findsOneWidget);
      expect(find.textContaining('12月28日'), findsWidgets);
    },
    initialTimetable: Timetable([fusionTerm], [fusionCourse]),
    initialExams: [
      fusionExam,
      Exam(
        id: 'outside',
        name: '教学周外单独考试',
        at: campusInstant(fusionDate, 21 * 1440 + 720),
        endsAt: campusInstant(fusionDate, 21 * 1440 + 780),
      ),
    ],
    timetableClock: () => examClock,
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

  var schoolNow = DateTime.utc(2026, 11, 27);
  final recoveryTriggers = <SchoolRecoveryTrigger>[];
  late Completer<bool> finishRecovery;
  var resumedRefreshes = 0;
  _appTest(
    'long backgrounding checks school health without blocking cached pages',
    (tester) async {
      finishRecovery = Completer<bool>();
      await _tab(tester, '我的');
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(NavigationBar)),
      );
      final status = scope.read(schoolSessionStatusProvider.notifier);
      void setHealth(SchoolSessionHealth health) =>
          status.update((subject: _TestAuth._session.subject, health: health));
      setHealth(SchoolSessionHealth.connected);
      await tester.pumpAndSettle();

      _resume(tester);
      await tester.pumpAndSettle();
      expect(recoveryTriggers, isEmpty);

      final priorRefreshes = resumedRefreshes;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      schoolNow = schoolNow.add(const Duration(minutes: 6));
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(recoveryTriggers, [SchoolRecoveryTrigger.foreground]);
      expect(resumedRefreshes, priorRefreshes);
      setHealth(SchoolSessionHealth.restoring);
      await tester.pumpAndSettle();
      expect(find.text('正在自动恢复教务连接'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('学校身份已验证'), findsOneWidget);

      setHealth(SchoolSessionHealth.connected);
      finishRecovery.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('教务会话正常'), findsOneWidget);
      expect(resumedRefreshes, priorRefreshes + 1);
    },
    auth: _TestAuth(
      onRecovery: (trigger) {
        recoveryTriggers.add(trigger);
        return finishRecovery.future;
      },
    ),
    schoolSessionClock: () => schoolNow,
    onRefresh: (section) {
      if (section == SchoolDataSet.timetable) resumedRefreshes++;
    },
  );
}

void _appTest(
  String description,
  Future<void> Function(WidgetTester) scenario, {
  _TestAuth auth = const _TestAuth(),
  Future<void> Function(WidgetTester)? beforeSettle,
  SchoolGradeBook? schoolGrades,
  PlanCompletion? planCompletion,
  Timetable? initialTimetable,
  List<Exam>? initialExams,
  CampusCardBalance? campusCardBalance,
  CampusCardRepository? campusCardRepository,
  http.Response Function()? classroomResponse,
  DateTime Function()? classroomClock,
  DateTime Function()? timetableClock,
  DateTime Function()? schoolSessionClock,
  WebVpnProtocol? vpnProtocol,
  List<SchoolPolicy>? schoolPolicies,
  Future<Uint8List> Function(SchoolPolicy)? schoolPolicyPdf,
  SchoolPolicySaver? schoolPolicySaver,
  void Function()? onReminderSync,
  void Function(SchoolDataSet)? onRefresh,
}) {
  testWidgets(description, (tester) async {
    final timetable = _TestTimetable();
    final grades = _TestGrades();
    final exams = _TestExams();
    final classroomCache = _WidgetClassroomCache();
    final classroomClient = MockClient(
      (_) async => classroomResponse?.call() ?? http.Response('', 503),
    );
    addTearDown(classroomCache.close);
    addTearDown(classroomClient.close);
    addTearDown(exams.close);
    if (initialTimetable != null) {
      for (final semester in initialTimetable.semesters) {
        await timetable.saveSemester(semester);
      }
      for (final course in initialTimetable.courses) {
        await timetable.saveCourse(course);
      }
    }
    if (initialExams != null) {
      for (final exam in initialExams) {
        await exams.save(exam);
      }
    }
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolAuthRepositoryProvider.overrideWithValue(auth),
            if (vpnProtocol != null) ...[
              webVpnProtocolProvider.overrideWithValue(vpnProtocol),
              campusAccessSettingsProvider.overrideWith(
                _WidgetCampusSettings.new,
              ),
            ],
            if (schoolSessionClock != null)
              schoolSessionClockProvider.overrideWithValue(schoolSessionClock),
            if (onRefresh != null)
              schoolRefreshProvider.overrideWith(
                (ref, section) async => onRefresh(section),
              ),
            schoolGradesCacheProvider.overrideWith(
              (ref) => Stream<SchoolCache<SchoolGradeBook>?>.value(
                schoolGrades == null
                    ? null
                    : SchoolCache(schoolGrades, DateTime.utc(2026)),
              ),
            ),
            if (planCompletion != null)
              schoolPlanCompletionCacheProvider.overrideWith(
                (ref) => Stream.value(
                  SchoolCache(planCompletion, DateTime.utc(2026)),
                ),
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
            examRepositoryProvider.overrideWithValue(exams),
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

class _UnusedWebVpn implements WebVpnProtocol {
  int attempts = 0;

  @override
  Future<WebVpnSession> authenticate(WebVpnAuthentication attempt) async {
    attempts++;
    throw StateError('An unrelated app action attempted VPN authentication');
  }
}

class _WidgetCampusSettings extends CampusAccessSettingsController {
  @override
  Future<CampusAccessSettings> build() async => const CampusAccessSettings();
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

Exam _testExam(String id, String name, DateTime date, {int start = 9}) => Exam(
  id: id,
  name: name,
  at: campusInstant(date, start * 60),
  endsAt: campusInstant(date, start * 60 + 120),
  room: '测试楼',
);

Future<void> _tab(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(title)),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTimetableWeek(WidgetTester tester, int week) async {
  await tester.tap(find.byTooltip('选择教学周'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<int>, '第 $week 周'));
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
  const _TestAuth({
    this.restore = true,
    this.restoration,
    this.onRecovery,
    this.canRememberPassword = true,
    this.onSignIn,
  });
  final bool restore;
  final Future<SchoolSession?> Function()? restoration;
  final Future<bool> Function(SchoolRecoveryTrigger)? onRecovery;
  final Future<SchoolSession> Function()? onSignIn;

  @override
  bool get available => true;
  @override
  final bool canRememberPassword;
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
  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) async {
    if (isForeground?.call() == false) return false;
    return await onRecovery?.call(trigger) ?? true;
  }

  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async => await onSignIn?.call() ?? _session;

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
  Future<void> setShowExamsInTimetable(bool value) async {
    state = AsyncData(AppSettings(showExamsInTimetable: value));
  }

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

class _TestExams implements ExamRepository {
  final changes = StreamController<List<Exam>>.broadcast();
  final _exams = <String, Exam>{};

  List<Exam> get _sorted =>
      _exams.values.toList()..sort((a, b) => a.at.compareTo(b.at));

  void close() => changes.close();

  @override
  Stream<List<Exam>> watch() => Stream.multi((controller) {
    controller.add(_sorted);
    controller.onCancel = changes.stream.listen(controller.add).cancel;
  });

  @override
  Future<void> save(Exam exam) async {
    _exams[exam.id] = exam;
    changes.add(_sorted);
  }

  @override
  Future<void> delete(String id) async {
    _exams.remove(id);
    changes.add(_sorted);
  }
}
