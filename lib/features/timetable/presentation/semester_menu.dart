import 'package:material_ui/material_ui.dart';

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
    return PopupMenuButton<String>(
      tooltip: '选择学期',
      icon: const Icon(Icons.calendar_month_outlined),
      initialValue: selected.id,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final semester in semesters)
          CheckedPopupMenuItem<String>(
            value: semester.id,
            checked: semester.id == selected.id,
            child: Text(semester.name),
          ),
      ],
    );
  }
}
