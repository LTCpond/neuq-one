import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/screen.dart';
import '../domain/services.dart';
import 'campus_card_tile.dart';
import 'open_campus_service.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CampusScreen(
      title: '校园服务',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: Icon(classroomsService.icon),
              title: Text(classroomsService.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openCampusService(context, classroomsService),
            ),
          ),
          const SizedBox(height: 7),
          const CampusCardTile(),
          for (final group in campusServiceGroups.entries) ...[
            SectionTitle(group.key),
            for (final entry in group.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      child: Icon(entry.icon, size: 21),
                    ),
                    title: Text(entry.name),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => openCampusService(context, entry),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
