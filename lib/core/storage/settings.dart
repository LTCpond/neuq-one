import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/campus_access/campus_resource.dart';

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

class CampusAccessSettings {
  const CampusAccessSettings({
    this.preference = CampusAccessPreference.automatic,
    this.idleMinutes = CampusAccessLimits.idleMinutes,
  });

  final CampusAccessPreference preference;
  final int idleMinutes;
}

final campusAccessSettingsProvider =
    AsyncNotifierProvider<CampusAccessSettingsController, CampusAccessSettings>(
      CampusAccessSettingsController.new,
      retry: (_, _) => null,
    );

class CampusAccessSettingsController
    extends AsyncNotifier<CampusAccessSettings> {
  static const _preferenceKey = 'campusAccessPreference';
  static const _idleKey = 'webVpnIdleMinutes';

  @override
  Future<CampusAccessSettings> build() async {
    final prefs = ref.watch(preferencesProvider);
    final preference = await prefs.getString(_preferenceKey);
    final idle = await prefs.getInt(_idleKey);
    return CampusAccessSettings(
      preference: CampusAccessPreference.values.firstWhere(
        (value) => value.name == preference,
        orElse: () => CampusAccessPreference.automatic,
      ),
      idleMinutes: CampusAccessLimits.idleChoices.contains(idle)
          ? idle!
          : CampusAccessLimits.idleMinutes,
    );
  }

  Future<void> setPreference(CampusAccessPreference value) async {
    await ref.read(preferencesProvider).setString(_preferenceKey, value.name);
    if (ref.mounted) ref.invalidateSelf();
  }

  Future<void> setIdleMinutes(int value) async {
    if (!CampusAccessLimits.idleChoices.contains(value)) {
      throw ArgumentError.value(value);
    }
    await ref.read(preferencesProvider).setInt(_idleKey, value);
    if (ref.mounted) ref.invalidateSelf();
  }
}
