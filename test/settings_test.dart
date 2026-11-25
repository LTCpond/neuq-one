import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/storage/settings.dart';
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
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
