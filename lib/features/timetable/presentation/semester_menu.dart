import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/campus_components.dart';
import '../domain/timetable.dart';

class SemesterMenu extends StatelessWidget {
  const SemesterMenu({
    super.key,
    required this.semesters,
    required this.selected,
    required this.onChanged,
  });

  final List<Semester> semesters;
  final Semester selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (year, name) = _semesterLabel(selected.name);
    return PopupMenuButton<String>(
      tooltip: '选择学期',
      initialValue: selected.id,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(12),
      itemBuilder: (context) => [
        for (final semester in semesters)
          CheckedPopupMenuItem<String>(
            value: semester.id,
            checked: semester.id == selected.id,
            child: Text(semester.name),
          ),
      ],
      child: Ink(
        width: 96,
        height: campusToolbarControlSize,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Semantics(
          value: selected.name,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.35,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (year != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        year,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

(String?, String) _semesterLabel(String name) {
  final match = RegExp(r'^(\d{4})\s*[-–—至]\s*(\d{4})\s*(?:学年)?\s*[·・]?\s*(.*)$')
      .firstMatch(name);
  if (match == null || match[3]!.isEmpty) return (null, name);
  return ('${match[1]}–${match[2]} 学年', match[3]!);
}
