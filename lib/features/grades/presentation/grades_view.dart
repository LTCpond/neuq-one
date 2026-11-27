import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/school_data.dart';
import '../../../core/time/campus_clock.dart';
import '../../timetable/data/local_timetable.dart';
import '../../timetable/domain/timetable.dart';

/// The grades section keeps its own semester scope so switching academic
/// sections never changes the plan or exam views.
class GradesSemesterSelection {
  const GradesSemesterSelection({this.semesterId, this.allSemesters = false});

  final String? semesterId;
  final bool allSemesters;
}

final gradesSemesterSelectionProvider =
    NotifierProvider<
      GradesSemesterSelectionController,
      GradesSemesterSelection
    >(GradesSemesterSelectionController.new);

class GradesSemesterSelectionController
    extends Notifier<GradesSemesterSelection> {
  @override
  GradesSemesterSelection build() => const GradesSemesterSelection();

  void selectSemester(String id) {
    if (!state.allSemesters && state.semesterId == id) return;
    state = GradesSemesterSelection(semesterId: id);
  }

  void selectAll() {
    if (state.allSemesters) return;
    state = const GradesSemesterSelection(allSemesters: true);
  }
}

/// School grade terms and local timetable terms share one sorted list, just as
/// the original grades page did. Watching the local cache avoids extra network
/// requests when the section is shown again.
final gradeSemestersProvider = Provider.autoDispose<List<Semester>>((ref) {
  final gradeBook = ref.watch(schoolGradesCacheProvider).value?.data;
  final timetable = ref.watch(timetableProvider).value;
  return [...?gradeBook?.semesters, ...?timetable?.semesters]
    ..sort((a, b) => b.start.compareTo(a.start));
});

Semester? selectedGradeSemester(
  List<Semester> semesters,
  GradesSemesterSelection selection,
) {
  if (selection.allSemesters) return null;
  return semesters
          .where((semester) => semester.id == selection.semesterId)
          .firstOrNull ??
      currentSemester(semesters, campusNow());
}
