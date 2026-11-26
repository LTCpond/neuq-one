import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/school_auth.dart';
import '../core/storage/settings.dart';
import '../core/theme/app_theme.dart';
import '../features/profile/data/course_reminders.dart';
import 'router.dart';

class NeuqOneApp extends ConsumerStatefulWidget {
  const NeuqOneApp({super.key});

  @override
  ConsumerState<NeuqOneApp> createState() => _NeuqOneAppState();
}

class _NeuqOneAppState extends ConsumerState<NeuqOneApp> {
  bool _restoringSession = true;

  @override
  Widget build(BuildContext context) {
    if (_restoringSession) {
      _restoringSession = ref.watch(
        schoolSessionProvider.select((session) => session.isLoading),
      );
    }
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
      builder: _restoringSession
          ? (context, child) => const Scaffold(
              body: Center(
                child: CircularProgressIndicator(semanticsLabel: '正在恢复登录状态'),
              ),
            )
          : null,
    );
  }
}
