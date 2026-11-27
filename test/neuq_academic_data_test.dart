import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/network/neuq_client.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/grades/data/neuq_grades.dart';
import 'package:neuq_one/features/grades/data/neuq_plan_completion.dart';
import 'package:neuq_one/features/timetable/data/neuq_timetable.dart';

import 'fixtures/plan_completion.dart';

const _entry = '''
<select id="semesterBar7Semester"></select>
<script>bg.form.addInput(form,"ids","1000");</script>
''';

const _calendar = '''
({semesters: {'2026-2027': [
 {id:7,schoolYear:'2026-2027',name:'1',beginOn:'2026-08-31',endOn:'2027-01-16',},
 {id:8,schoolYear:'2026-2027',name:'春季'},
]}})
''';

const _schedule = '''
<script>
var actTeachers = [{name:"样例甲"}, {name:"样例乙"}];
var courseName = '应用数据（测试）';
activity = new TaskActivity(0, actTeachers.join(","), 1, courseName + "(1.01)", 2, "样例楼 A101", "01010");
index = 0 * unitCount + 0;
index = 0 * unitCount + 1;
index = 0 * unitCount + 3;
index = 2 * unitCount + 6;
var taskId = 2;
activity = new TaskActivity(0, "任课教师", 2, "工程数学(2.02)", 3, "工学馆 201", "0010");
index = 4 * unitCount + 2;
</script>
''';

const _results = '''
<p>累计平均学分绩点：3.7654</p>
<table>
<thead><tr><th>学年学期</th><th>课程代码</th><th>课程名称</th><th>学分</th>
<th>课程性质</th><th>成绩</th><th>考试类型</th></tr></thead>
<tbody>
<tr><td colspan="7">2026-2027 秋季学期 · 学期平均学分绩点 3.81</td></tr>
<tr><td>2026-2027 1</td><td>X01</td><td>数学</td><td>4</td><td>必修</td><td>58</td><td>正常</td></tr>
<tr><td>2026-2027 1</td><td>X01</td><td>数学</td><td>4</td><td>必修</td><td>89</td><td>补考</td></tr>
<tr><td>2026-2027 1</td><td>X02</td><td>实践</td><td>0</td><td>其他</td><td>合格</td><td>正常</td></tr>
</tbody>
</table>
''';

void main() {
  test('NEUQ semester and course format preserves sparse weeks and slots', () {
    final terms = readNeuqSemesters(_calendar);
    final entry = readNeuqTimetableEntry(_entry);
    expect(entry.calendarTag, 'semesterBar7Semester');
    expect(entry.student, '1000');
    expect(terms['7']!.start, DateTime.utc(2026, 8, 31));
    expect(terms['7']!.weeks, 20);
    expect(terms['8']!.start, DateTime.utc(2027, 3, 1));
    final classes = readNeuqCourses(_schedule, terms['7']!);
    expect(classes, hasLength(4));
    expect(classes.first.weeks, [1, 3]);
    expect(classes.first.teacher, '样例甲、样例乙');
    expect(classes.first.endMinute, neuqPeriods[1].end);
    expect(classes[1].startMinute, neuqPeriods[3].start);
    expect(classes[2].weekday, 3);
    expect(classes.last.name, '工程数学');
    expect(
      () => readNeuqSemesters('new Function("return {}")()'),
      throwsFormatException,
    );
    expect(
      () => readNeuqCourses('<title>另一页面</title>', terms['7']!),
      throwsFormatException,
    );
  });

  test(
    'course blocks merge adjacent slots only within the same teaching week',
    () {
      const source = '''
<script>
var taskId = 3;
activity = new TaskActivity(0, "教师", 1, "课程(1.01)", 2, "A101", "0110");
index = 0 * unitCount + 4;
index = 0 * unitCount + 5;
activity = new TaskActivity(0, "教师", 1, "课程(1.01)", 2, "A101", "0010");
index = 0 * unitCount + 6;
index = 0 * unitCount + 7;
var taskId = 4;
index = 0 * unitCount + 8;
activity = new TaskActivity(0, "教师", 1, "课程(1.01)", 2, "A101", "0010");
index = 0 * unitCount + 9;
</script>
''';
      final term = readNeuqSemesters(_calendar)['7']!;
      final courses = readNeuqCourses(source, term);
      expect(courses.map((course) => [course.time, course.weeks]), [
        [
          '14:00–15:35',
          [1],
        ],
        [
          '14:00–17:40',
          [2],
        ],
        [
          '19:30–20:15',
          [2],
        ],
      ]);
    },
  );

  test('grade reader keeps each attempt and school-reported GPA', () {
    final grades = readNeuqGrades(
      _results,
      readNeuqSemesters(_calendar).values,
    );
    expect(grades.grades.map((grade) => grade.scoreLabel), ['58', '89', '合格']);
    expect(grades.grades.map((grade) => grade.id).toSet(), hasLength(3));
    expect(grades.cumulativeGpa, 3.7654);
    expect(grades.semesterGpa['school:7'], 3.81);
    expect(
      () => readNeuqGrades('<title>系统提示</title>', []),
      throwsFormatException,
    );
  });

  test('academic requests retain their AJAX query', () {
    expect(NeuqPage.schedule.requestUri().queryParameters, {
      'sf_request_type': 'ajax',
    });
  });

  test(
    'plan report keeps official totals, group audit and outside courses',
    () {
      final subject = schoolSubjectForStudentCode(planFixtureStudent)!;
      final report = readNeuqPlanCompletion(planCompletionHtml, subject);
      expect(report.credits.toJson(), {'required': 12.5, 'completed': 8.5});
      expect(report.compulsoryCourses.completed, 2);
      expect(report.internalGpa, 3.8125);
      expect(report.groups.map((group) => group.name), ['通识类课程', '科学基础']);
      final group = report.groups.last;
      expect(group.isSubgroup, isTrue);
      expect(group.result, '缺1.5分 缺1门');
      expect(group.courses.first.remark, '替代课程：示例基础');
      expect(group.courses[1].score, isNull);
      expect(group.courses[1].passed, isTrue);
      expect(group.courses.last.passed, isFalse);
      expect(report.extraCourses.single.semester, isNull);
      expect(report.extraCourses.single.score, '合格');
    },
  );

  test('plan report rejects an unrelated page and another school account', () {
    final subject = schoolSubjectForStudentCode(planFixtureStudent)!;
    expect(
      () => readNeuqPlanCompletion('<p>系统提示</p>', subject),
      throwsFormatException,
    );
    expect(
      () => readNeuqPlanCompletion(
        planCompletionHtml.replaceFirst(planFixtureStudent, '00005678'),
        subject,
      ),
      throwsA(SchoolRequestFailure.differentAccount),
    );
  });
}
