import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/neuq_login_protocol.dart';
import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import '../core/network/official_browser.dart';
import '../core/widgets/screen.dart';
import 'school_login_form.dart';

class SchoolReconnectButton extends ConsumerStatefulWidget {
  const SchoolReconnectButton({super.key});

  @override
  ConsumerState<SchoolReconnectButton> createState() =>
      _SchoolReconnectButtonState();
}

class _SchoolReconnectButtonState extends ConsumerState<SchoolReconnectButton> {
  bool _open = false;

  Future<void> _reconnect() async {
    final subject = ref.read(schoolSessionProvider).asData?.value?.subject;
    final repository = ref.read(schoolAuthRepositoryProvider);
    if (_open || subject == null || !repository.available) return;
    setState(() => _open = true);
    try {
      final recovered = await ref
          .read(schoolSessionProvider.notifier)
          .recoverSession(trigger: SchoolRecoveryTrigger.manual);
      if (mounted && recovered) ref.read(refreshSchoolDataProvider)();
    } on SchoolRequestFailure catch (error) {
      if (!mounted ||
          ref.read(schoolSessionProvider).asData?.value?.subject != subject) {
        return;
      }
      if (error.requiresCredentials) {
        await _openLogin(subject, repository.canRememberPassword, error);
      } else if (error.requiresOfficialLogin) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            action: SnackBarAction(
              label: '打开官方教务',
              onPressed: () =>
                  openOfficialPage(context, schoolWebEntry.toString()),
            ),
          ),
        );
      } else if (error != SchoolRequestFailure.cancelled) {
        showMessage(context, error.message);
      }
    } catch (_) {
      if (mounted) showMessage(context, '暂时无法恢复教务连接，请检查网络或稍后重试。');
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  Future<void> _openLogin(
    String subject,
    bool canRememberPassword,
    SchoolRequestFailure failure,
  ) async {
    final controller = ref.read(schoolSessionProvider.notifier);
    final connected = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('重新连接教务')),
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SchoolLoginForm(
                        canRememberPassword: canRememberPassword,
                        initialFailure: failure == SchoolRequestFailure.expired
                            ? null
                            : failure,
                        onSubmit: (credentials, rememberPassword) async {
                          await controller.signIn(
                            credentials,
                            rememberPassword: rememberPassword,
                            expectedSubject: subject,
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    if (mounted && connected == true) ref.read(refreshSchoolDataProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final subject = ref.watch(
      schoolSessionProvider.select((session) => session.asData?.value?.subject),
    );
    final restoring = ref.watch(
      schoolSessionStatusProvider.select(
        (status) =>
            status.subject == subject &&
            status.health == SchoolSessionHealth.restoring,
      ),
    );
    return OutlinedButton(
      onPressed: _open || restoring ? null : _reconnect,
      child: _open
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '正在恢复教务连接',
              ),
            )
          : const Text('重新连接教务'),
    );
  }
}
