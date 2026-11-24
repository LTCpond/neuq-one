import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/features/services/domain/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'existing shortcut order and explicit selections survive a settings reload',
    () async {
      final storage = _ShortcutPreferences();
      ProviderContainer container() {
        final instance = ProviderContainer(
          overrides: [preferencesProvider.overrideWithValue(storage)],
        );
        addTearDown(instance.dispose);
        return instance;
      }

      final initial = container();
      expect(_ids(await initial.read(settingsProvider.future)), [
        'campus-card',
        'mail',
        'academic',
        'portal',
        'map',
      ]);

      await initial.read(settingsProvider.notifier).setQuickLinks([
        'classrooms',
        'vpn',
        'classrooms',
        'removed-service',
      ]);
      final reopened = container();
      expect(_ids(await reopened.read(settingsProvider.future)), [
        'classrooms',
        'vpn',
      ]);

      await reopened.read(settingsProvider.notifier).setQuickLinks([]);
      expect(_ids(await container().read(settingsProvider.future)), isEmpty);
    },
  );
}

List<String> _ids(AppSettings settings) => shortcutsInOrder(
  settings.quickLinks,
  customized: settings.quickLinksCustomized,
).map((service) => service.id).toList();

class _ShortcutPreferences implements SharedPreferencesAsync {
  final _lists = <String, List<String>>{
    'quickLinks': ['mail'],
  };

  @override
  Future<List<String>?> getStringList(String key) async => _lists[key];

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _lists[key] = List.of(value);
  }

  @override
  Future<int?> getInt(String key) async => null;

  @override
  Future<String?> getString(String key) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
