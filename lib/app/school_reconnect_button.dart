import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/school_auth.dart';
import 'school_login_form.dart';

class SchoolReconnectButton extends ConsumerStatefulWidget {
  const SchoolReconnectButton({super.key, required this.onConnected});

  final VoidCallback onConnected;

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
      final navigator = Navigator.of(context, rootNavigator: true);
      final connected = await navigator.push<bool>(
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
                      canRememberPassword: repository.canRememberPassword,
                      onSubmit: (credentials, rememberPassword) async {
                        await repository.signIn(
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
      if (mounted && connected == true) {
        ref.invalidate(rememberedSchoolPasswordProvider);
        widget.onConnected();
      }
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: _open ? null : _reconnect,
    child: const Text('重新连接教务'),
  );
}
