import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/campus_access/campus_access_providers.dart';
import '../../../core/network/campus_access/campus_resource.dart';
import '../../../core/network/official_browser.dart';
import '../../../core/widgets/screen.dart';
import '../domain/services.dart';

void openCampusService(BuildContext context, CampusService service) {
  if (service.route case final String route) {
    context.push<void>(route);
  } else if (service.url case final String url) {
    openOfficialPage(context, url);
  }
}

Future<void> openRegisteredCampusWebsite(
  BuildContext context,
  WidgetRef ref,
  CampusResourceId id,
) async {
  try {
    final entry = ref.read(campusAccessClientProvider).directEntry(id);
    await openOfficialPage(context, entry.toString());
  } on CampusAccessFailure catch (failure) {
    if (context.mounted) showMessage(context, failure.message);
  }
}
