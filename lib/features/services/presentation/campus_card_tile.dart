import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/campus_card_balance.dart';
import '../domain/services.dart';
import 'open_campus_service.dart';

class CampusCardTile extends ConsumerWidget {
  const CampusCardTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(campusCardBalanceProvider).value;

    return Card(
      child: ListTile(
        leading: Icon(campusCardService.icon),
        title: Text(campusCardService.name),
        trailing: balance == null
            ? const Icon(Icons.chevron_right)
            : Text(
                campusCardMoney(balance.cents),
                style: Theme.of(context).textTheme.titleMedium,
              ),
        onTap: () => openCampusService(context, campusCardService),
      ),
    );
  }
}
