import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CampusScreen extends StatelessWidget {
  const CampusScreen({
    super.key,
    required this.title,
    this.eyebrow,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final String? eyebrow;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: eyebrow == null ? 60 : 76,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null)
              Text(
                eyebrow!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            Text(title, style: theme.textTheme.headlineSmall),
          ],
        ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class StatePanel extends StatelessWidget {
  const StatePanel(
    this.title,
    this.description, {
    super.key,
    required this.icon,
    this.action,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(description, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class DataPanel<T> extends StatelessWidget {
  const DataPanel({
    super.key,
    required this.value,
    required this.builder,
    required this.retry,
  });

  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Card(child: SizedBox(height: 65, width: double.infinity)),
            ),
        ],
      ),
      error: (error, stack) => StatePanel(
        '暂时无法读取数据',
        '请重试。本地已有数据会保留。',
        icon: Icons.error_outline,
        action: OutlinedButton(onPressed: retry, child: const Text('重试')),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.label, {super.key, this.action});
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
