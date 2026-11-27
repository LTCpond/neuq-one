import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/school_auth.dart';
import '../core/network/official_browser.dart';
import 'login_brand.dart';
import 'login_geometry_background.dart';
import 'login_motion.dart';
import 'school_login_form.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: loginEntranceDuration,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loginMotionDisabled(context)) {
      if (!_entrance.isCompleted) _entrance.value = 1;
    } else if (!_entranceStarted) {
      _entrance.forward();
    }
    _entranceStarted = true;
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(schoolSessionProvider);
    final repository = ref.watch(schoolAuthRepositoryProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? theme.scaffoldBackgroundColor : Colors.white;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final form = LoginReveal(
      progress: loginPhase(_entrance, 250, 700),
      child: Material(
        color: background,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (repository.available) ...[
                Semantics(
                  header: true,
                  child: Text(
                    '统一身份认证',
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 18),
                SchoolLoginForm(
                  standalone: true,
                  canRememberPassword: repository.canRememberPassword,
                  canSubmit: !session.isLoading,
                  onSubmit: (credentials, rememberPassword) => ref
                      .read(schoolSessionProvider.notifier)
                      .signIn(credentials, rememberPassword: rememberPassword),
                ),
                if (session.hasError) ...[
                  const SizedBox(height: 12),
                  const Text('暂时无法恢复上次登录，请重新登录。'),
                ],
              ] else ...[
                Text('此平台暂不支持应用内登录', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '可在系统浏览器使用学校门户。',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () =>
                      openOfficialPage(context, 'https://eone.neuq.edu.cn/'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开学校门户'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarBrightness: theme.brightness,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: background,
        systemNavigationBarDividerColor: background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final gutter = (width * .08).clamp(20.0, 32.0);
              final contentWidth = (width - gutter * 2).clamp(0.0, 400.0);
              final compact = height < 540;
              final footer = keyboardVisible
                  ? 0.0
                  : ((height - 360) * .19).clamp(0.0, 92.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!keyboardVisible)
                    LoginGeometryBackground(
                      entrance: _entrance,
                      footerHeight: footer,
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, footer),
                    child: CustomScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.manual,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: contentWidth,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: compact ? 14 : 26,
                                  bottom: compact ? 16 : 22,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: contentWidth * .60,
                                    child: LoginBrand(
                                      entrance: _entrance,
                                      size: (contentWidth * .17).clamp(
                                        40.0,
                                        compact ? 46.0 : 60.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverLayoutBuilder(
                          builder: (context, scroll) => SliverToBoxAdapter(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    (scroll.viewportMainAxisExtent -
                                            scroll.precedingScrollExtent)
                                        .clamp(0.0, height),
                              ),
                              child: Align(
                                alignment: const Alignment(0, -.36),
                                child: SizedBox(
                                  width: contentWidth,
                                  child: form,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
