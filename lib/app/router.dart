import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import '../core/theme/app_theme.dart';
import '../features/grades/presentation/academic_page.dart';
import '../features/mail/presentation/campus_mail_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/profile/presentation/update_prompt.dart';
import '../features/services/presentation/campus_card_page.dart';
import '../features/services/presentation/campus_map_page.dart';
import '../features/services/presentation/classrooms_page.dart';
import '../features/services/presentation/employment_page.dart';
import '../features/services/presentation/school_policies_page.dart';
import '../features/services/presentation/services_page.dart';
import '../features/timetable/presentation/timetable_date.dart';
import '../features/timetable/presentation/timetable_page.dart';
import 'login_motion.dart';
import 'login_page.dart';

const _timetablePath = '/timetable';
// The academic center keeps the existing branch path so saved tab state and
// deep links to the former grades tab remain valid.
const _gradesPath = '/grades';
const _servicesPath = '/services';

const _tabs = [
  (path: _timetablePath, label: '课表', icon: 'timetable', page: TimetablePage()),
  (path: _gradesPath, label: '学业', icon: 'academic', page: AcademicPage()),
  (path: _servicesPath, label: '服务', icon: 'services', page: ServicesPage()),
  (path: '/profile', label: '我的', icon: 'profile', page: ProfilePage()),
];

final routerProvider = Provider<GoRouter>((ref) {
  final sessionSubject = schoolSessionProvider.select(
    (value) => value.asData?.value?.subject,
  );
  final rootNavigator = GlobalKey<NavigatorState>();
  final rootUpdates = AppUpdateRouteObserver();
  final branchUpdates = [for (final _ in _tabs) AppUpdateRouteObserver()];
  final router = GoRouter(
    navigatorKey: rootNavigator,
    observers: [rootUpdates],
    initialLocation: _timetablePath,
    redirect: (context, state) {
      final subject = ref.read(sessionSubject);
      final onLogin = state.matchedLocation == '/login';
      if (subject == null || subject.trim().isEmpty) {
        return onLogin ? null : '/login';
      }
      return onLogin ? _timetablePath : null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _EntryPage(state, const LoginPage(), isLogin: true),
      ),
      GoRoute(path: '/', redirect: (context, state) => _timetablePath),
      StatefulShellRoute.indexedStack(
        notifyRootObserver: false,
        pageBuilder: (context, state, shell) => _EntryPage(
          state,
          AppUpdatePromptHost(
            root: rootUpdates,
            branch: branchUpdates[shell.currentIndex],
            child: _Navigation(shell),
          ),
        ),
        branches: [
          for (final (index, tab) in _tabs.indexed)
            StatefulShellBranch(
              observers: [branchUpdates[index]],
              routes: [
                GoRoute(
                  path: tab.path,
                  builder: (context, state) => tab.page,
                  routes: [
                    if (tab.path == _gradesPath)
                      GoRoute(
                        path: 'plan-completion',
                        redirect: (context, state) => _gradesPath,
                      ),
                    if (tab.path == _servicesPath) ...[
                      GoRoute(
                        path: 'classrooms',
                        parentNavigatorKey: rootNavigator,
                        builder: (context, state) => const ClassroomsPage(),
                      ),
                      GoRoute(
                        path: 'campus-card',
                        builder: (context, state) => const CampusCardPage(),
                      ),
                      GoRoute(
                        path: 'campus-map',
                        parentNavigatorKey: rootNavigator,
                        builder: (context, state) => const CampusMapPage(),
                      ),
                      GoRoute(
                        path: 'employment',
                        builder: (context, state) => const EmploymentPage(),
                      ),
                      GoRoute(
                        path: 'policies',
                        parentNavigatorKey: rootNavigator,
                        builder: (context, state) => const SchoolPoliciesPage(),
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
  ref.listen(sessionSubject, (previous, next) {
    if (previous != null && previous.trim().isNotEmpty) {
      // Release all authenticated navigation stacks on logout or account change.
      ref.invalidateSelf();
    } else {
      router.refresh();
    }
  });
  ref.onDispose(() {
    router.dispose();
    rootUpdates.dispose();
    for (final branch in branchUpdates) {
      branch.dispose();
    }
  });
  return router;
});

class _EntryPage extends MaterialPage<void> {
  _EntryPage(GoRouterState state, Widget child, {this.isLogin = false})
    : super(
        key: state.pageKey,
        name: state.name ?? state.path,
        arguments: {...state.pathParameters, ...state.uri.queryParameters},
        restorationId: state.pageKey.value,
        child: _EntryTransition(child: child),
      );

  final bool isLogin;

  // Reuse the route during sign-in so the login can fade over the new shell.
  @override
  bool canUpdate(Page<dynamic> other) =>
      super.canUpdate(other) ||
      (!isLogin && other is _EntryPage && other.isLogin);
}

class _EntryTransition extends StatefulWidget {
  const _EntryTransition({required this.child});

  final Widget child;

  @override
  State<_EntryTransition> createState() => _EntryTransitionState();
}

class _EntryTransitionState extends State<_EntryTransition>
    with SingleTickerProviderStateMixin {
  late final _exit =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status.isDismissed) setState(() => _outgoingLogin = null);
      });
  late final _opacity = _exit.drive(CurveTween(curve: Curves.easeInOut));
  LoginPage? _outgoingLogin;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = loginMotionDisabled(context);
    if (_reduceMotion && _outgoingLogin != null) {
      _exit.stop();
      _outgoingLogin = null;
    }
  }

  @override
  void didUpdateWidget(covariant _EntryTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child case final LoginPage login
        when !_reduceMotion && widget.child is! LoginPage) {
      _outgoingLogin = login;
      _exit.reverse(from: 1);
    }
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Widget _loginSurface(LoginPage login, {required bool exiting}) =>
      FadeTransition(
        key: const ValueKey('login surface'),
        opacity: exiting ? _opacity : const AlwaysStoppedAnimation(1),
        child: ExcludeFocus(
          excluding: exiting,
          child: ExcludeSemantics(
            excluding: exiting,
            child: IgnorePointer(ignoring: exiting, child: login),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (child is LoginPage) _loginSurface(child, exiting: false) else child,
        if (_outgoingLogin case final login?)
          _loginSurface(login, exiting: true),
      ],
    );
  }
}

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
    final colors = Theme.of(context).colorScheme;
    // Keep foreground sync active even when the timetable branch is offstage.
    ref.listen(schoolRefreshProvider(SchoolDataSet.timetable), (_, _) {});
    return Scaffold(
      body: TickerMode(
        enabled: ModalRoute.isCurrentOf(context) ?? true,
        child: shell,
      ),
      bottomNavigationBar: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) {
            final section = switch (_tabs[index].path) {
              _gradesPath => SchoolDataSet.grades,
              _timetablePath => SchoolDataSet.timetable,
              _ => null,
            };
            if (section != null) ref.invalidate(schoolRefreshProvider(section));
            shell.goBranch(index);
          },
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(
                icon: _TabIcon(tab.icon),
                selectedIcon: _TabIcon(tab.icon, selected: true),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon(this.name, {this.selected = false});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFE0E8FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Image.asset(
      'assets/ui/nav-$name.png',
      width: 24,
      height: 24,
      color: selected
          ? campusBlue
          : Theme.of(context).colorScheme.onSurfaceVariant,
      excludeFromSemantics: true,
    ),
  );
}
