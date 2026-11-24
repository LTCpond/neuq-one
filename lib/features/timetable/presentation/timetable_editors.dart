import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/time/neuq_periods.dart';
import '../../../core/widgets/editor.dart';
import '../domain/timetable.dart';

const courseColors = [
  Color(0xFF087569),
  Color(0xFF3860B8),
  Color(0xFF8A4998),
  Color(0xFFAE5530),
  Color(0xFF977000),
  Color(0xFFAC4263),
];

Future<void> editSemester(
  BuildContext context,
  TimetableRepository repository, [
  Semester? semester,
]) {
  final today = campusNow();
  var name = semester?.name ?? '';
  var weeks = semester?.weeks ?? 18;
  var start = semester?.start ?? calendarDate(today);
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => RecordEditor(
        title: semester == null ? '新增学期' : '编辑学期',
        onSave: () => repository.saveSemester(
          Semester(
            id: semester?.id ?? const Uuid().v4(),
            name: name,
            start: start,
            weeks: weeks,
          ),
        ),
        children: [
          TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '学期名称'),
            validator: requireText,
            onSaved: (value) => name = value!.trim(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('开学日期'),
            subtitle: Text('${start.year}年${shortDate(start)}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked != null && context.mounted) {
                update(() => start = calendarDate(picked));
              }
            },
          ),
          TextFormField(
            initialValue: '$weeks',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '教学周数',
              helperText: '开学所在的自然周为第 1 周',
            ),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number == null || number < 1 || number > 30
                  ? '请输入 1–30'
                  : null;
            },
            onSaved: (value) => weeks = int.parse(value!.trim()),
          ),
        ],
      ),
    ),
  );
}

Future<void> editCourse(
  BuildContext context,
  TimetableRepository repository,
  Semester semester, {
  Course? course,
  required int defaultDay,
  int? defaultWeek,
}) {
  var name = course?.name ?? '';
  var teacher = course?.teacher ?? '';
  var room = course?.room ?? '';
  var weekday = course?.weekday ?? defaultDay;
  var start = course == null ? 1 : periodAtStart(course.startMinute);
  var end = course == null ? 2 : periodAtEnd(course.endMinute);
  var weeks =
      course?.weeks.join(',') ??
      defaultWeek?.toString() ??
      '1-${semester.weeks}';
  var parity = WeekParity.all;
  var color = course?.colorIndex ?? 0;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => RecordEditor(
        title: course == null ? '新增课程' : '编辑课程',
        onSave: () {
          final first = start;
          final last = end;
          if (first == null || last == null || last < first) {
            throw const FormatException('请选择有效的东秦上课节次');
          }
          return repository.saveCourse(
            Course(
              id: course?.id ?? const Uuid().v4(),
              semesterId: semester.id,
              name: name,
              teacher: teacher,
              room: room,
              weekday: weekday,
              startMinute: neuqPeriods[first - 1].start,
              endMinute: neuqPeriods[last - 1].end,
              weeks: parseWeeks(weeks, semester.weeks, parity),
              colorIndex: color,
            ),
          );
        },
        children: [
          TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '课程名称'),
            validator: requireText,
            onSaved: (value) => name = value!.trim(),
          ),
          TextFormField(
            initialValue: teacher,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '教师（选填）'),
            onSaved: (value) => teacher = value!.trim(),
          ),
          TextFormField(
            initialValue: room,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '教室（选填）'),
            onSaved: (value) => room = value!.trim(),
          ),
          DropdownButtonFormField<int>(
            initialValue: weekday,
            decoration: const InputDecoration(labelText: '星期'),
            items: [
              for (var day = 1; day <= 7; day++)
                DropdownMenuItem(value: day, child: Text(weekdayLabel(day))),
            ],
            onChanged: (value) => update(() => weekday = value!),
          ),
          DropdownButtonFormField<int>(
            initialValue: start,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '开始节次'),
            items: [
              for (var period = 1; period <= neuqPeriods.length; period++)
                DropdownMenuItem(
                  value: period,
                  child: Text(periodLabel(period)),
                ),
            ],
            onChanged: (value) => start = value,
          ),
          DropdownButtonFormField<int>(
            initialValue: end,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '结束节次'),
            items: [
              for (var period = 1; period <= neuqPeriods.length; period++)
                DropdownMenuItem(
                  value: period,
                  child: Text(periodLabel(period)),
                ),
            ],
            onChanged: (value) => end = value,
          ),
          if (course != null &&
              (periodAtStart(course.startMinute) == null ||
                  periodAtEnd(course.endMinute) == null))
            Text('原时段 ${course.time}。保存编辑时需重新选择官方节次。'),
          TextFormField(
            initialValue: weeks,
            decoration: const InputDecoration(
              labelText: '教学周',
              hintText: '例如 1-8,10,12',
            ),
            validator: (value) {
              try {
                parseWeeks(value ?? '', semester.weeks, parity);
              } on FormatException catch (error) {
                return error.message;
              }
              return null;
            },
            onSaved: (value) => weeks = value!,
          ),
          DropdownButtonFormField<WeekParity>(
            initialValue: parity,
            decoration: const InputDecoration(labelText: '单双周筛选'),
            items: [
              for (final option in WeekParity.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (value) => update(() => parity = value!),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (var index = 0; index < courseColors.length; index++)
                ChoiceChip(
                  labelPadding: EdgeInsets.zero,
                  label: Icon(
                    Icons.circle,
                    size: 16,
                    color: courseColors[index],
                    semanticLabel: '颜色 ${index + 1}',
                  ),
                  selected: index == color,
                  showCheckmark: false,
                  onSelected: (_) => update(() => color = index),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
