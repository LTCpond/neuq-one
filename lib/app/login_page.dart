import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/school_auth.dart';
import '../core/network/official_browser.dart';
import 'school_web_login_page.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(schoolSessionProvider);
    final enabled = ref.watch(schoolAuthRepositoryProvider).available;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.school_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('NEUQ One', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('请使用东北大学秦皇岛分校统一身份认证登录。'),
                  const SizedBox(height: 24),
                  if (session.isLoading)
                    const LinearProgressIndicator()
                  else if (enabled)
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(schoolSessionProvider.notifier)
                          .signIn(
                            openLogin: () async {
                              if (!context.mounted) return null;
                              return Navigator.of(context).push<SchoolSession>(
                                PageRouteBuilder<SchoolSession>(
                                  transitionDuration: Duration.zero,
                                  reverseTransitionDuration: Duration.zero,
                                  pageBuilder: (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                  ) => const SchoolWebLoginPage(),
                                ),
                              );
                            },
                          ),
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(session.hasError ? '重试统一身份认证' : '统一身份认证登录'),
                    )
                  else ...[
                    Text('此平台暂不支持应用内登录', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('可在系统浏览器使用学校门户。'),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => openOfficialPage(
                        context,
                        'https://eone.neuq.edu.cn/',
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('打开学校门户'),
                    ),
                  ],
                  if (session.hasError && enabled) ...[
                    const SizedBox(height: 12),
                    const Text('登录暂未完成，请重新打开学校认证页。'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
