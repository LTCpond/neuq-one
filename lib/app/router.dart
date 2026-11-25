import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/grades/presentation/grades_page.dart';
import '../features/mail/presentation/campus_mail_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/services/data/campus_card_balance.dart';
import '../features/services/presentation/campus_card_page.dart';
import '../features/services/presentation/employment_page.dart';
import '../features/services/presentation/services_page.dart';
import '../features/services/presentation/classrooms_page.dart';
import '../features/timetable/presentation/timetable_page.dart';
import 'login_page.dart';

const tabs = [
  (
    path: '/',
    label: '首页',
    icon: Icons.home_outlined,
    selected: Icons.home_rounded,
  ),
  (
    path: '/timetable',
    label: '课表',
    icon: Icons.calendar_month_outlined,
    selected: Icons.calendar_month_rounded,
  ),
  (
    path: '/grades',
    label: '成绩',
    icon: Icons.insights_outlined,
    selected: Icons.insights_rounded,
  ),
  (
    path: '/services',
    label: '服务',
    icon: Icons.grid_view_outlined,
    selected: Icons.grid_view_rounded,
  ),
  (
    path: '/profile',
    label: '我的',
    icon: Icons.person_outline,
    selected: Icons.person_rounded,
  ),
];

final routerProvider = Provider<GoRouter>((ref) {
  final subject = ref.watch(
    schoolSessionProvider.select((value) => value.asData?.value?.subject),
  );
  const pages = [
    DashboardPage(),
    TimetablePage(),
    GradesPage(),
    ServicesPage(),
    ProfilePage(),
  ];
  final router = GoRouter(
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      if (subject == null || subject.trim().isEmpty) {
        return onLogin ? null : '/login';
      }
      return onLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Navigation(shell),
        branches: [
          for (final (index, tab) in tabs.indexed)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: tab.path,
                  builder: (context, state) => pages[index],
                  routes: [
                    if (tab.path == '/services')
                      GoRoute(
                        path: 'classrooms',
                        builder: (context, state) => const ClassroomsPage(),
                      ),
                    if (tab.path == '/services')
                      GoRoute(
                        path: 'campus-card',
                        builder: (context, state) => const CampusCardPage(),
                      ),
                    if (tab.path == '/services')
                      GoRoute(
                        path: 'employment',
                        builder: (context, state) => const EmploymentPage(),
                      ),
                    if (tab.path == '/services')
                      GoRoute(
                        path: 'mail',
                        builder: (context, state) => const CampusMailPage(),
                      ),
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

class _Navigation extends ConsumerWidget {
  const _Navigation(this.shell);

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) {
          if (index == 0) ref.invalidate(campusCardRefreshProvider);
          final section = switch (tabs[index].path) {
            '/grades' => SchoolDataSet.grades,
            '/timetable' => SchoolDataSet.timetable,
            _ => null,
          };
          if (section != null) ref.invalidate(schoolRefreshProvider(section));
          shell.goBranch(index);
        },
        destinations: [
          for (final tab in tabs)
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
