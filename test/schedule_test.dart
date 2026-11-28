import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/database/app_database.dart';
import 'package:neuq_one/core/database/school_data.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/features/exams/data/exam_conflict_reminders.dart';
import 'package:neuq_one/features/exams/domain/exam.dart';
import 'package:neuq_one/features/timetable/domain/course_colors.dart';
import 'package:neuq_one/features/timetable/domain/schedule.dart';
import 'package:neuq_one/features/timetable/domain/schedule_grid.dart';
import 'package:neuq_one/features/timetable/domain/timetable.dart';
import 'package:neuq_one/features/timetable/presentation/timetable_palette.dart';

final _monday = DateTime.utc(2026, 11, 30);
final _term = Semester(
  id: 'school:term',
  name: '测试学期',
  start: _monday,
  weeks: 4,
);

Course _course(
  String name, {
  int day = 1,
  int start = 480,
  int end = 575,
  List<int> weeks = const [1, 3],
  String? id,
}) => Course(
  id: 'school:${id ?? name}',
  semesterId: _term.id,
  name: name,
  teacher: '测试老师',
  room: '测试教室',
  weekday: day,
  startMinute: start,
  endMinute: end,
  weeks: weeks,
  colorIndex: 0,
);

Exam _exam(String id, int start, int end, {DateTime? date}) => Exam(
  id: id,
  name: '考试 $id',
  at: campusInstant(date ?? _monday, start),
  endsAt: campusInstant(date ?? _monday, end),
);

ScheduleEvents _schedule(List<Course> courses, List<Exam> exams) =>
    ScheduleEvents(CourseSchedule(Timetable([_term], courses)), exams);

void main() {
  test('12 门课颜色唯一，重排、跨周和增删保留颜色', () {
    final courses = [for (var i = 0; i < 12; i++) _course('课程$i')];
    final table = Timetable([_term], courses);
    final initial = assignCourseColors(table);
    expect(initial[_term.id]!.values.toSet(), hasLength(12));
    expect(
      assignCourseColors(Timetable([_term], courses.reversed.toList())),
      initial,
    );

    final moved = _course('课程1', id: 'new-activity', day: 2, weeks: [2]);
    final updated = Timetable(
      [_term],
      [...courses.skip(1), moved, _course('新课')],
    );
    final after = assignCourseColors(updated, initial);
    for (final course in courses.skip(1)) {
      final key = courseSubjectKey(course);
      expect(after[_term.id]![key], initial[_term.id]![key]);
    }
    final projected = withCourseColors(updated, after);
    expect(
      projected.courses
          .where((row) => row.name == '课程1')
          .map((row) => row.colorIndex)
          .toSet(),
      hasLength(1),
    );
    expect(
      assignCourseColors(table, after)[_term.id]!['课程0'],
      initial[_term.id]!['课程0'],
    );
  });

  test('超过十二门课优先复用实际日期不交叉的颜色', () {
    final courses = [
      for (var i = 0; i < 12; i++)
        _course('A${i.toString().padLeft(2, '0')}', day: i == 0 ? 2 : 1),
      _course('Z'),
    ];
    final colors = assignCourseColors(Timetable([_term], courses))[_term.id]!;
    expect(colors.values.toSet(), hasLength(12));
    expect(colors['z'], colors['a00']);
  });

  test('课程色板保留指定浅色值，深色与考试色板达到正文对比度', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return x >= y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final brightness in Brightness.values) {
      final backgrounds = <Color>{};
      for (var index = 0; index < courseColorCount; index++) {
        final colors = coursePaletteColors(brightness, index);
        // These three exact light pairs are specified by the palette.
        final specified = {
          4: (0xFFF5BCCA, 0xFF963F58),
          5: (0xFFBAE4EF, 0xFF236C84),
          10: (0xFFDCC5E2, 0xFF774681),
        }[index];
        if (brightness == Brightness.light && specified != null) {
          expect(colors.map((color) => color.toARGB32()), [
            specified.$1,
            specified.$2,
          ]);
        } else {
          expect(
            contrast(colors.first, colors.last),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness $index',
          );
        }
        backgrounds.add(colors.first);
      }
      expect(backgrounds, hasLength(12));
      expect(
        coursePaletteColors(brightness, 15),
        coursePaletteColors(brightness, 3),
      );
      for (final finished in [false, true]) {
        final exam = examPalette(brightness, finished: finished);
        expect(backgrounds, isNot(contains(exam.background)));
        expect(contrast(exam.background, exam.text), greaterThanOrEqualTo(4.5));
        expect(contrast(exam.background, exam.border), greaterThanOrEqualTo(3));
      }
    }
    expect(
      coursePaletteColors(Brightness.light, 6).first.toARGB32(),
      0xFFE8EDB5,
    );
    expect(examPalette(Brightness.light).background.toARGB32(), 0xFFFBE2DF);
  });

  test('实际左闭右开区间、日期与单双周决定冲突', () {
    final course = _course('课程', weeks: [1, 3]);
    final schedule = _schedule(
      [course],
      [
        _exam('相接', 575, 670),
        _exam('无冲突', 600, 720),
        _exam('部分覆盖', 540, 660),
        _exam('内部', 510, 540),
        _exam('完全覆盖', 450, 590),
        _exam('不同日期', 480, 570, date: _monday.add(const Duration(days: 1))),
        _exam('双周', 480, 570, date: _monday.add(const Duration(days: 7))),
        _exam('单周', 480, 570, date: _monday.add(const Duration(days: 14))),
      ],
    );
    final pairs = ScheduleConflicts(schedule).pairs
        .where((pair) => pair.other.course != null);
    expect(pairs.map((pair) => pair.exam.exam!.id).toSet(), {
      '部分覆盖',
      '内部',
      '完全覆盖',
      '单周',
    });
    expect(
      pairs.firstWhere((pair) => pair.exam.exam!.id == '单周').other.time.start,
      DateTime.utc(2026, 12, 14),
    );
  });

  test('考试冲突详情包含相连的多场考试、所有课程，并排除编辑中的考试自身', () {
    final first = _exam('甲', 490, 525);
    final second = _exam('乙', 510, 550);
    final third = _exam('丙', 540, 565);
    final schedule = _schedule(
      [_course('数学'), _course('物理', start: 530)],
      [third, second, first],
    );
    final conflicts = ScheduleConflicts(schedule);
    expect(conflicts.forExam(second.id), hasLength(4));
    expect(
      conflicts
          .relatedTo([ScheduleEvent.exam(first)])
          .map((entry) => entry.name)
          .toSet(),
      {'考试 甲', '考试 乙', '考试 丙', '数学', '物理'},
    );
    expect(
      schedule
          .conflictsForDraft(
            ScheduleInterval(second.at, second.endsAt),
            excludeExamId: second.id,
          )
          .map((entry) => entry.exam?.id)
          .whereType<String>(),
      ['甲', '丙'],
    );
    expect(groupExamsOn(_monday, schedule.exams).single.events, hasLength(3));
  });

  test('考试优先，课程仅让出真实重叠部分并保留原时间与详情', () {
    final course = _course('编译原理');
    final event = ScheduleEvent.course(course, _term, _monday);
    final internal = groupExamsOn(_monday, [
      ScheduleEvent.exam(_exam('部分', 500, 550)),
    ]);
    final visible = visibleCourseSpans(_monday, event, internal);
    expect(visible, hasLength(2));
    expect(visible.first.start, 0);
    expect(visible.first.end, closeTo(20 / 45, .0001));
    expect(visible.last.start, closeTo(1 + 20 / 45, .0001));
    expect(visible.last.end, 2);
    expect(event.course, same(course));
    final all = groupExamsOn(_monday, [
      ScheduleEvent.exam(_exam('覆盖', 450, 580)),
    ]);
    expect(visibleCourseSpans(_monday, event, all), isEmpty);
  });

  test('午休、课间、首节前、晚间、最后一节后与教学周外', () {
    for (final (start, end) in [
      (420, 470),
      (525, 530),
      (720, 790),
      (1325, 1350),
    ]) {
      final group = groupExamsOn(_monday, [
        ScheduleEvent.exam(_exam('补充', start, end)),
      ]).single;
      final span = examGridSpan(_monday, group.time);
      expect(span.start, span.end);
      expect(examNeedsSupplement(_monday, group), isTrue);
    }
    final evening = groupExamsOn(_monday, [
      ScheduleEvent.exam(_exam('晚间', 1130, 1210)),
    ]).single;
    final grid = examGridSpan(_monday, evening.time);
    expect(grid.start, closeTo(8 + 10 / 45, .0001));
    expect(grid.end, closeTo(9 + 40 / 45, .0001));
    final out = _exam(
      '教学周外',
      580,
      605,
      date: _monday.add(const Duration(days: 45)),
    );
    final schedule = _schedule([], [out]);
    expect(_term.weekFor(out.campusDate), isNull);
    expect(schedule.on(out.campusDate).single.exam, same(out));
    expect(out.campusTimeRange, '09:40–10:05');
    expect(out.isFinishedAt(out.campusEnd), isTrue);
    final fromOtherZone = DateTime.parse('2026-11-30T01:00:00-05:00');
    expect(campusMinuteAt(fromOtherZone), 14 * 60);
  });

  test('考试开始和结束必须同日且结束严格晚于开始', () {
    expect(
      examTimeValidation(
        campusInstant(_monday, 540),
        campusInstant(_monday, 600),
      ),
      isNull,
    );
    for (final end in [
      campusInstant(_monday, 540),
      campusInstant(_monday, 480),
    ]) {
      expect(
        examTimeValidation(campusInstant(_monday, 540), end),
        examTimeError,
      );
    }
    expect(
      examTimeValidation(
        campusInstant(_monday, 1380),
        campusInstant(_monday.add(const Duration(days: 1)), 60),
      ),
      examTimeError,
    );
  });

  test('旧课表缓存首次分色，刷新和重开复用分配，失败保留课表', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final courses = [_course('甲'), _course('乙')];
    await db
        .into(db.schoolCacheRows)
        .insert(
          SchoolCacheRow(
            id: 'timetable',
            payload: jsonEncode({
              'semesters': [_term.toJson()],
              'courses': courses.map((course) => course.toJson()).toList(),
            }),
            syncedAt: _monday,
          ),
        );
    final repository = SchoolDataRepository(db);
    final before = (await repository.watchTimetable().first)!.data;
    expect(
      before.courses.map((course) => course.colorIndex).toSet(),
      hasLength(2),
    );
    final exam = _exam('考试', 540, 550);
    final shifted = Timetable(
      [_term],
      [_course('乙', start: 605, end: 650), _course('甲'), _course('丙', day: 3)],
    );
    await repository.refresh(SchoolDataSet.timetable, _Source(shifted));
    final after = (await SchoolDataRepository(db).watchTimetable().first)!.data;
    expect(
      after.courses.firstWhere((course) => course.name == '乙').colorIndex,
      before.courses.firstWhere((course) => course.name == '乙').colorIndex,
    );
    expect(
      ScheduleConflicts(ScheduleEvents(CourseSchedule(after), [exam])).pairs,
      hasLength(1),
    );
    await expectLater(
      repository.refresh(SchoolDataSet.timetable, const _Source(null)),
      throwsFormatException,
    );
    final retained = (await repository.watchTimetable().first)!.data;
    expect(
      ScheduleConflicts(ScheduleEvents(CourseSchedule(retained), [exam])).pairs,
      hasLength(1),
    );
  });

  test('通知只记录有效更新引入的冲突，支持重启、解除、拒绝权限和关闭设置', () {
    final exam = _exam('已知', 540, 560);
    final course = _course('冲突课程');
    final event = ScheduleEvent.exam(exam);
    final pair = ScheduleConflicts(_schedule([course], [exam])).pairs.single;
    final key = ExamConflictLedger.conflictKey(pair);
    final conflict = {key: pair};

    ExamConflictLedger next(
      ExamConflictLedger? previous,
      String revision, {
      Map<String, ScheduleConflict> active = const {},
      List<ScheduleEvent>? exams,
      bool enabled = true,
    }) => ExamConflictLedger.reconcile(
      previous: previous,
      revision: revision,
      exams: exams ?? [event],
      active: active,
      enabled: enabled,
    );
    final baseline = next(null, 'old');
    final found = next(baseline, 'new', active: conflict);
    expect(found.pending, {key});
    final denied = next(
      ExamConflictLedger.decode(found.encode()),
      'new',
      active: conflict,
    );
    expect(denied.pending, {key});
    final restart = ExamConflictLedger.decode(found.delivered().encode());
    expect(next(restart, 'new', active: conflict).pending, isEmpty);
    expect(
      next(restart, 'same-data-refresh', active: conflict).pending,
      isEmpty,
    );
    final cleared = next(restart, 'cleared');
    expect(next(cleared, 'again', active: conflict).pending, {key});
    final manualSave = next(baseline, 'old', active: conflict);
    expect(next(manualSave, 'sync', active: conflict).pending, isEmpty);
    final noExamBefore = next(null, 'old', exams: []);
    expect(next(noExamBefore, 'new', active: conflict).pending, isEmpty);
    final off = next(baseline, 'new', active: conflict, enabled: false);
    expect(off.pending, isEmpty);
    expect(next(off, 'resumed', active: conflict).pending, isEmpty);
  });
}

class _Source implements SchoolDataSource {
  const _Source(this.timetable);

  final Timetable? timetable;

  @override
  Future<Timetable> fetchTimetable() async =>
      timetable ?? (throw const FormatException('测试读取失败'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
