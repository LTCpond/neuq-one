import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/profile/data/course_reminders.dart';
import 'package:neuq_one/features/profile/presentation/reminder_settings_page.dart';

final _status = ReminderStatus(
  ReminderCondition.active,
  count: 12,
  firstDay: DateTime.utc(2026, 11, 20),
  lastDay: DateTime.utc(2026, 11, 26),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('reminder settings stay readable in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_page(_TestSettings(), brightness));
      await tester.pumpAndSettle();

      expect(find.text('课程提醒'), findsOneWidget);
      expect(find.text('正常运行'), findsOneWidget);
      expect(find.text('已排程 12 条'), findsOneWidget);
      expect(find.text('11月20日 – 11月26日'), findsOneWidget);
      expect(find.text('提醒时间'), findsOneWidget);
      expect(find.text('通知检查'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('choosing a reminder lead time updates the setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = _TestSettings();
    await tester.pumpWidget(_page(settings, Brightness.light));
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    expect(settings.current.reminderMinutes, 30);
    expect(find.text('提前 30 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(_TestSettings settings, Brightness brightness) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(() => settings),
    reminderServiceProvider.overrideWithValue(_TestReminderService()),
    reminderSyncProvider.overrideWith((ref) async => _status),
  ],
  child: MaterialApp(
    theme: appTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: const ReminderSettingsPage(),
  ),
);

class _TestReminderService extends CourseReminderService {
  @override
  bool get supported => true;

  @override
  bool get isAndroid => false;
}

class _TestSettings extends SettingsController {
  AppSettings current = const AppSettings(reminderMinutes: 10);

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> setReminder(int value) async {
    current = AppSettings(
      theme: current.theme,
      reminderMinutes: value,
      allowInexactReminders: current.allowInexactReminders,
      admissionYear: current.admissionYear,
    );
    state = AsyncData(current);
  }

  @override
  Future<void> setInexactReminders(bool value) async {
    current = AppSettings(
      theme: current.theme,
      reminderMinutes: current.reminderMinutes,
      allowInexactReminders: value,
      admissionYear: current.admissionYear,
    );
    state = AsyncData(current);
  }
}
