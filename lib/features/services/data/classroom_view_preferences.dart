import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/settings.dart';
import '../../../core/time/campus_clock.dart';
import '../domain/classrooms.dart';

typedef ClassroomView = ({CampusBuilding building, DateTime? date, bool table});

final classroomViewProvider =
    NotifierProvider<ClassroomViewController, ClassroomView>(
      ClassroomViewController.new,
    );

class ClassroomViewController extends Notifier<ClassroomView> {
  static const _key = 'classroomView';
  SharedPreferencesAsync? _preferences;
  bool _changed = false;
  Future<void> _pendingWrite = Future.value();

  @override
  ClassroomView build() {
    unawaited(_restore());
    return (building: CampusBuilding.engineering, date: null, table: false);
  }

  Future<void> _restore() async {
    try {
      final prefs = ref.read(preferencesProvider);
      _preferences = prefs;
      final stored = await prefs.getStringList(_key);
      if (!ref.mounted || _changed || stored == null || stored.length != 3) {
        return;
      }
      final date = DateTime.tryParse(stored[1]);
      state = (
        building: CampusBuilding.values.firstWhere(
          (building) => building.name == stored[0],
          orElse: () => CampusBuilding.engineering,
        ),
        date: date == null ? null : calendarDate(date),
        table: stored[2] == 'table',
      );
    } catch (_) {
      // The default selection is usable even if preferences cannot be read.
    }
  }

  void selectBuilding(CampusBuilding building) =>
      _select((building: building, date: state.date, table: state.table));

  void selectDate(DateTime? date) =>
      _select((building: state.building, date: date, table: state.table));

  void selectTable(bool table) =>
      _select((building: state.building, date: state.date, table: table));

  void _select(ClassroomView selection) {
    if (selection == state) return;
    _changed = true;
    state = selection;
    final prefs = _preferences;
    if (prefs == null) return;
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await prefs.setStringList(_key, [
          selection.building.name,
          selection.date?.toIso8601String() ?? '',
          selection.table ? 'table' : 'timeline',
        ]);
      } catch (_) {
        // Keep the current selection in memory if preferences cannot be saved.
      }
    });
  }
}
