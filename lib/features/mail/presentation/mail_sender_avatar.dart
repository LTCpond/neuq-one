import 'package:material_ui/material_ui.dart';

class MailSenderAvatar extends StatelessWidget {
  const MailSenderAvatar(this.sender, {super.key});

  final String sender;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = sender.trim().characters.firstOrNull;
    final (background, foreground) = switch ((initial?.runes.first ?? 0) % 3) {
      1 => (colors.secondaryContainer, colors.onSecondaryContainer),
      2 => (colors.tertiaryContainer, colors.onTertiaryContainer),
      _ => (colors.primaryContainer, colors.onPrimaryContainer),
    };
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 20,
        backgroundColor: background,
        foregroundColor: foreground,
        child: initial == null
            ? const Icon(Icons.person_outline_rounded, size: 20)
            : Text(initial.toUpperCase(), maxLines: 1),
      ),
    );
  }
}
