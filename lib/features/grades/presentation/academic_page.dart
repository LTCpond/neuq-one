import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/school_data.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/campus_segmented_picker.dart';
import '../../exams/presentation/exams_section.dart';
import '../data/local_grades.dart';
import 'grades_section.dart';
import 'grades_view.dart';
import 'plan_completion_section.dart';

enum AcademicSection {
  grades('成绩'),
  planCompletion('培养方案'),
  exams('考试安排');

  const AcademicSection(this.label);
  final String label;
}

/// The academic center keeps grades, the study plan and exams in one page.
/// Sections load lazily, stay alive after their first visit and own their own
/// data, filters and scroll position.
class AcademicPage extends ConsumerStatefulWidget {
  const AcademicPage({super.key});

  @override
  ConsumerState<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends ConsumerState<AcademicPage> {
  var _selection = AcademicSection.grades;
  final _visited = {AcademicSection.grades};

  void _select(AcademicSection section) {
    if (section == _selection) return;
    setState(() {
      _selection = section;
      _visited.add(section);
    });
  }

  @override
  Widget build(BuildContext context) {
    final semesters = ref.watch(gradeSemestersProvider);
    final semesterSelection = ref.watch(gradesSemesterSelectionProvider);
    final term = selectedGradeSemester(semesters, semesterSelection);
    final showGradeEntry =
        _selection == AcademicSection.grades &&
        term != null &&
        !isSchoolRecord(term.id);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight:
            72 + (MediaQuery.textScalerOf(context).scale(30) - 30).clamp(0, 36),
        actionsPadding: const EdgeInsets.only(right: 12),
        title: const FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: CampusPageTitle('学业中心', eyebrow: 'NEUQ · ACADEMIC'),
        ),
        actions: [
          switch (_selection) {
            AcademicSection.grades => const GradesActions(),
            AcademicSection.planCompletion => const PlanCompletionActions(),
            AcademicSection.exams => const ExamActions(),
          },
        ],
      ),
      floatingActionButton: showGradeEntry
          ? FloatingActionButton.extended(
              onPressed: () => showGradeEditor(
                context,
                ref.read(gradesRepositoryProvider),
                term,
              ),
              icon: const Icon(Icons.add),
              label: const Text('录入成绩'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: CampusSegmentedPicker<AcademicSection>(
              values: AcademicSection.values,
              selected: _selection,
              labelOf: (section) => section.label,
              onChanged: _select,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selection.index,
              children: [
                for (final section in AcademicSection.values)
                  if (_visited.contains(section))
                    switch (section) {
                      AcademicSection.grades => const GradesSection(),
                      AcademicSection.planCompletion =>
                        const PlanCompletionSection(),
                      AcademicSection.exams => const ExamSection(),
                    }
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
