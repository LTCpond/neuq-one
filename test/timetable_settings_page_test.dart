import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_settings_page.dart';

final _status = ReminderStatus(
  ReminderCondition.active,
  count: 12,
  firstDay: DateTime.utc(2026, 11, 20),
  lastDay: DateTime.utc(2026, 11, 26),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('timetable settings stay readable in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_page(_TestSettings(), brightness));
      await tester.pumpAndSettle();

      expect(find.text('课表设置'), findsOneWidget);
      expect(find.text('显示设置'), findsOneWidget);
      expect(find.text('通知提醒'), findsOneWidget);
      expect(find.text('通知诊断'), findsOneWidget);
      expect(find.text('在课表中显示考试'), findsOneWidget);
      expect(find.text('在周课表中展示考试安排'), findsOneWidget);
      expect(find.text('课程提醒'), findsOneWidget);
      expect(find.text('考试冲突提醒'), findsOneWidget);
      expect(find.text('正常运行'), findsOneWidget);
      expect(find.text('已排程 12 条'), findsOneWidget);
      expect(find.text('11月20日 – 11月26日'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('已允许，课程提醒与考试冲突提醒可正常送达'), findsOneWidget);
      expect(find.text('发送测试通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('timetable settings fit a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(_TestSettings(), Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text('在课表中显示考试'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('通知诊断'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('发送测试通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied notification permission offers a request entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _page(
        _TestSettings(),
        Brightness.light,
        service: _TestReminderService(allowed: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未允许，点击申请通知权限'), findsOneWidget);

    final entry = find.text('通知权限');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('通知权限未开启，请在系统设置中允许 NEUQ One 的通知。'), findsOneWidget);
    expect(find.text('未允许，点击申请通知权限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a reminder lead time updates the setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = _TestSettings();
    await tester.pumpWidget(_page(settings, Brightness.light));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('30 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    expect(settings.current.reminderMinutes, 30);
    expect(find.text('提前 30 分钟'), findsOneWidget);
    expect(settings.current.showExamsInTimetable, isTrue);
    expect(settings.current.examConflictReminders, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three timetable switches stay independent', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = _TestSettings();
    await tester.pumpWidget(_page(settings, Brightness.light));
    await tester.pumpAndSettle();

    Future<void> toggle(String label) async {
      final tile = find.widgetWithText(SwitchListTile, label);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    await toggle('在课表中显示考试');
    expect(settings.current.showExamsInTimetable, isFalse);
    expect(settings.current.examConflictReminders, isTrue);
    expect(settings.current.reminderMinutes, 10);

    await toggle('课程提醒');
    expect(settings.current.reminderMinutes, 0);
    expect(settings.current.examConflictReminders, isTrue);
    expect(settings.current.showExamsInTimetable, isFalse);

    await toggle('考试冲突提醒');
    expect(settings.current.examConflictReminders, isFalse);
    expect(settings.current.reminderMinutes, 0);
    expect(settings.current.showExamsInTimetable, isFalse);

    // 关闭课程提醒不影响重新开启考试冲突提醒。
    await toggle('考试冲突提醒');
    expect(settings.current.examConflictReminders, isTrue);
    expect(settings.current.reminderMinutes, 0);
    expect(settings.current.showExamsInTimetable, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(
  _TestSettings settings,
  Brightness brightness, {
  CourseReminderService? service,
}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(() => settings),
    reminderServiceProvider.overrideWithValue(
      service ?? _TestReminderService(),
    ),
    reminderSyncProvider.overrideWith((ref) async => _status),
  ],
  child: MaterialApp(
    theme: appTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: const TimetableSettingsPage(),
  ),
);

class _TestReminderService extends CourseReminderService {
  _TestReminderService({this.allowed = true});

  final bool allowed;

  @override
  bool get supported => true;

  @override
  bool get isAndroid => false;

  @override
  Future<bool> notificationsAllowed() async => allowed;

  @override
  Future<bool> requestPermission() async => allowed;
}

class _TestSettings extends SettingsController {
  AppSettings current = const AppSettings(reminderMinutes: 10);

  void _apply(AppSettings value) {
    current = value;
    state = AsyncData(current);
  }

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> setReminder(int value) async => _apply(
    AppSettings(
      theme: current.theme,
      reminderMinutes: value,
      allowInexactReminders: current.allowInexactReminders,
      admissionYear: current.admissionYear,
      showExamsInTimetable: current.showExamsInTimetable,
      examConflictReminders: current.examConflictReminders,
    ),
  );

  @override
  Future<void> setInexactReminders(bool value) async => _apply(
    AppSettings(
      theme: current.theme,
      reminderMinutes: current.reminderMinutes,
      allowInexactReminders: value,
      admissionYear: current.admissionYear,
      showExamsInTimetable: current.showExamsInTimetable,
      examConflictReminders: current.examConflictReminders,
    ),
  );

  @override
  Future<void> setShowExamsInTimetable(bool value) async => _apply(
    AppSettings(
      theme: current.theme,
      reminderMinutes: current.reminderMinutes,
      allowInexactReminders: current.allowInexactReminders,
      admissionYear: current.admissionYear,
      showExamsInTimetable: value,
      examConflictReminders: current.examConflictReminders,
    ),
  );

  @override
  Future<void> setExamConflictReminders(bool value) async => _apply(
    AppSettings(
      theme: current.theme,
      reminderMinutes: current.reminderMinutes,
      allowInexactReminders: current.allowInexactReminders,
      admissionYear: current.admissionYear,
      showExamsInTimetable: current.showExamsInTimetable,
      examConflictReminders: value,
    ),
  );
}
