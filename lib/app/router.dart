import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import '../features/grades/presentation/grades_page.dart';
import '../features/mail/presentation/campus_mail_page.dart';
import '../features/profile/data/course_reminders.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/services/presentation/campus_card_page.dart';
import '../features/services/presentation/classrooms_page.dart';
import '../features/services/presentation/employment_page.dart';
import '../features/services/presentation/services_page.dart';
import '../features/timetable/presentation/timetable_date.dart';
import '../features/timetable/presentation/timetable_page.dart';
import 'login_page.dart';

const _timetablePath = '/timetable';
const _servicesPath = '/services';

const _tabs = [
  (
    path: _timetablePath,
    label: '课表',
    icon: Icons.calendar_month_outlined,
    selected: Icons.calendar_month_rounded,
    page: TimetablePage(),
  ),
  (
    path: '/grades',
    label: '成绩',
    icon: Icons.insights_outlined,
    selected: Icons.insights_rounded,
    page: GradesPage(),
  ),
  (
    path: _servicesPath,
    label: '服务',
    icon: Icons.grid_view_outlined,
    selected: Icons.grid_view_rounded,
    page: ServicesPage(),
  ),
  (
    path: '/profile',
    label: '我的',
    icon: Icons.person_outline,
    selected: Icons.person_rounded,
    page: ProfilePage(),
  ),
];

final routerProvider = Provider<GoRouter>((ref) {
  final subject = ref.watch(
    schoolSessionProvider.select((value) => value.asData?.value?.subject),
  );
  final router = GoRouter(
    initialLocation: _timetablePath,
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      if (subject == null || subject.trim().isEmpty) {
        return onLogin ? null : '/login';
      }
      return onLogin ? _timetablePath : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/', redirect: (context, state) => _timetablePath),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Navigation(shell),
        branches: [
          for (final tab in _tabs)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: tab.path,
                  builder: (context, state) => tab.page,
                  routes: [
                    if (tab.path == _servicesPath) ...[
                      GoRoute(
                        path: 'classrooms',
                        builder: (context, state) => const ClassroomsPage(),
                      ),
                      GoRoute(
                        path: 'campus-card',
                        builder: (context, state) => const CampusCardPage(),
                      ),
                      GoRoute(
                        path: 'employment',
                        builder: (context, state) => const EmploymentPage(),
                      ),
                      GoRoute(
                        path: 'mail',
                        builder: (context, state) => const CampusMailPage(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _Navigation extends ConsumerStatefulWidget {
  const _Navigation(this.shell);

  final StatefulNavigationShell shell;

  @override
  ConsumerState<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends ConsumerState<_Navigation> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.invalidate(reminderSyncProvider);
        ref.invalidate(schoolRefreshProvider(SchoolDataSet.timetable));
        ref.invalidate(timetableDateProvider);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    // Keep foreground sync active even when the timetable branch is offstage.
    ref.listen(schoolRefreshProvider(SchoolDataSet.timetable), (_, _) {});
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) {
          final section = switch (_tabs[index].path) {
            '/grades' => SchoolDataSet.grades,
            _timetablePath => SchoolDataSet.timetable,
            _ => null,
          };
          if (section != null) ref.invalidate(schoolRefreshProvider(section));
          shell.goBranch(index);
        },
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selected),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
