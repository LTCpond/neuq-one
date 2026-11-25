import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/services/data/public_classrooms.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _Startup()));
}

class _Startup extends ConsumerStatefulWidget {
  const _Startup();

  @override
  ConsumerState<_Startup> createState() => _StartupState();
}

class _StartupState extends ConsumerState<_Startup> {
  @override
  void initState() {
    super.initState();
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      unawaited(
        scheduler.scheduleTask<void>(() {
          if (mounted) {
            unawaited(ref.read(classroomsProvider.notifier).refresh());
          }
        }, Priority.idle),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const NeuqOneApp();
}
