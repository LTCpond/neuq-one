import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings.dart';
import '../core/theme/app_theme.dart';
import '../features/profile/data/course_reminders.dart';
import 'router.dart';

class NeuqOneApp extends ConsumerWidget {
  const NeuqOneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    ref.listen(reminderSyncProvider, (_, _) {});
    return MaterialApp.router(
      title: 'NEUQ One',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: settings?.theme ?? ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
