import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/screen.dart';

Future<void> openOfficialPage(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('需要有效的 HTTPS 地址');
    }
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // The same actionable message also covers an unavailable browser handler.
  }
  if (context.mounted) showMessage(context, '无法打开浏览器，请检查设备设置后重试');
}
