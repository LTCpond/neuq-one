import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final preferencesProvider = Provider((ref) => SharedPreferencesAsync());

class AppSettings {
  const AppSettings({
    this.theme = ThemeMode.system,
    this.reminderMinutes = 0,
    this.allowInexactReminders = false,
    this.admissionYear = 2025,
  });

  final ThemeMode theme;
  final int reminderMinutes;
  final bool allowInexactReminders;
  final int admissionYear;
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  SharedPreferencesAsync get _prefs => ref.read(preferencesProvider);

  @override
  Future<AppSettings> build() async {
    final prefs = ref.watch(preferencesProvider);
    final theme = await prefs.getString('theme');
    return AppSettings(
      theme: ThemeMode.values.firstWhere(
        (item) => item.name == theme,
        orElse: () => ThemeMode.system,
      ),
      reminderMinutes: await prefs.getInt('reminderMinutes') ?? 0,
      allowInexactReminders:
          await prefs.getBool('allowInexactReminders') ?? false,
      admissionYear: await prefs.getInt('admissionYear') ?? 2025,
    );
  }

  Future<void> setTheme(ThemeMode value) =>
      _update(() => _prefs.setString('theme', value.name));
  Future<void> setReminder(int value) =>
      _update(() => _prefs.setInt('reminderMinutes', value));
  Future<void> setInexactReminders(bool value) =>
      _update(() => _prefs.setBool('allowInexactReminders', value));
  Future<void> _update(Future<void> Function() write) async {
    await write();
    ref.invalidateSelf();
    await future;
  }
}
