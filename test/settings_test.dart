import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/features/services/data/classroom_view_preferences.dart';
import 'package:neuq_one/features/services/domain/classrooms.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'settings updates preserve preferences from older installations',
    () async {
      final preferences = _ExistingPreferences();
      final original = Map.of(preferences.values);
      final container = ProviderContainer(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      final settings = await container.read(settingsProvider.future);
      expect(settings.theme, ThemeMode.dark);
      expect(settings.reminderMinutes, 10);
      expect(settings.admissionYear, 2024);

      await container.read(settingsProvider.notifier).setTheme(ThemeMode.light);
      expect(preferences.values, {...original, 'theme': 'light'});
    },
  );

  test('classroom view preferences survive a new provider scope', () async {
    final preferences = _ExistingPreferences();
    final overrides = [preferencesProvider.overrideWithValue(preferences)];
    final first = ProviderContainer(overrides: overrides);
    addTearDown(first.dispose);
    final initial = first.read(classroomViewProvider);
    expect(initial, (
      building: CampusBuilding.engineering,
      date: null,
      table: false,
    ));

    final date = DateTime.utc(2026, 11, 27);
    final controller = first.read(classroomViewProvider.notifier);
    controller.selectBuilding(CampusBuilding.science);
    controller.selectDate(date);
    controller.selectTable(true);
    await Future<void>.delayed(Duration.zero);

    final second = ProviderContainer(overrides: overrides);
    addTearDown(second.dispose);
    second.read(classroomViewProvider);
    await Future<void>.delayed(Duration.zero);
    expect(second.read(classroomViewProvider), (
      building: CampusBuilding.science,
      date: date,
      table: true,
    ));
  });
}

class _ExistingPreferences implements SharedPreferencesAsync {
  final values = <String, Object>{
    'theme': 'dark',
    'reminderMinutes': 10,
    'admissionYear': 2024,
    'dashboardServiceShortcuts': ['campus-card'],
    'quickLinks': ['mail'],
  };

  @override
  Future<int?> getInt(String key) async => values[key] as int?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key] as List<String>?;

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
