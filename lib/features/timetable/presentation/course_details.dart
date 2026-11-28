import 'package:material_ui/material_ui.dart';

import '../../../core/database/school_data.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../domain/timetable.dart';
import 'timetable_editors.dart';
import 'timetable_palette.dart';

class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.course, required this.onTap});
  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      course.time,
      course.room,
      course.teacher,
    ].where((value) => value.isNotEmpty);
    return Card(
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        leading: Container(
          width: 5,
          height: 38,
          decoration: BoxDecoration(
            color: courseBlockColors(context, course.colorIndex).$2,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          course.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(details.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

Future<void> showCourseDetails(
  BuildContext context,
  TimetableRepository repository,
  Semester semester,
  Course course,
) async {
  final (background, foreground) = courseBlockColors(
    context,
    course.colorIndex,
  );
  final local = !isSchoolRecord(course.id);
  final action = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: const Color(0x55111B2F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      final details = [
        (
          Icons.schedule_outlined,
          '上课时间',
          '${weekdayLabel(course.weekday).replaceFirst('周', '星期')} ${course.time}',
        ),
        (Icons.location_on_outlined, '上课地点', course.room),
        (Icons.person_outline, '授课教师', course.teacher),
        (Icons.calendar_month_outlined, '教学周', _courseWeeks(course.weeks)),
      ];
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
          child: Column(
            key: const ValueKey('course-details-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  CampusIconBadge(
                    size: 52,
                    background: background,
                    foreground: foreground,
                    child: const Icon(Icons.school_outlined),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          semester.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              const Divider(height: 1),
              const SizedBox(height: 13),
              for (final (icon, label, value) in details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Row(
                    children: [
                      CampusIconBadge(
                        size: 38,
                        background: colors.surfaceContainerLow,
                        foreground: colors.primary,
                        child: Icon(icon, size: 20),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              value.isEmpty ? '未填写' : value,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (local)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      child: const Text('删除课程'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      child: const Text('编辑课程'),
                    ),
                  ],
                )
              else ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            '教务课表 · 由学校更新',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await editCourse(
      context,
      repository,
      semester,
      course: course,
      defaultDay: course.weekday,
    );
  } else if (action == 'delete' &&
      await confirmAction(context, '删除课程？', '会移除「${course.name}」的全部教学周安排。')) {
    try {
      await repository.deleteCourse(course.id);
      if (context.mounted) showMessage(context, '课程已删除');
    } catch (_) {
      if (context.mounted) showMessage(context, '删除失败，请重试');
    }
  }
}

String _courseWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toSet().toList()..sort();
  final ranges = <String>[];
  var start = sorted.first;
  var end = start;
  for (final week in sorted.skip(1)) {
    if (week != end + 1) {
      ranges.add(start == end ? '$start' : '$start–$end');
      start = week;
    }
    end = week;
  }
  ranges.add(start == end ? '$start' : '$start–$end');
  return '第 ${ranges.join('、')} 周';
}
