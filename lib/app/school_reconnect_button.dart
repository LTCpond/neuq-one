import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/auth/school_auth.dart';
import '../core/database/school_data.dart';
import 'school_web_login_page.dart';

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
    final web = ref.read(schoolWebClientProvider);
    if (_open || subject == null || web == null) return;
    setState(() => _open = true);
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      final session = await web.reconnect(
        () => navigator.push<SchoolSession>(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondary) =>
                SchoolWebLoginPage(expectedSubject: subject),
          ),
        ),
      );
      if (mounted && session?.subject == subject) widget.onConnected();
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
