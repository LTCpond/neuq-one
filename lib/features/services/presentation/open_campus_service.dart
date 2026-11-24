import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/official_browser.dart';
import '../domain/services.dart';

void openCampusService(BuildContext context, CampusService service) {
  if (service.route case final String route) {
    context.push<void>(route);
  } else if (service.url case final String url) {
    openOfficialPage(context, url);
  }
}
