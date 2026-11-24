import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/database/neuq_school_data_source.dart';
import 'package:neuq_one/core/network/neuq_web_client.dart';
import 'package:neuq_one/core/time/campus_clock.dart';
import 'package:neuq_one/core/time/neuq_periods.dart';
import 'package:neuq_one/features/grades/data/neuq_grades.dart';
import 'package:neuq_one/features/services/data/neuq_classrooms.dart';
import 'package:neuq_one/features/services/domain/classrooms.dart';
import 'package:neuq_one/features/timetable/data/neuq_timetable.dart';

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

String _grid(List<NeuqRoom> rooms, {int? count}) {
  return '<div><table class="gridtable"><thead>'
      '<tr><th>序号</th><th>名称</th><th>教学楼</th><th>容量</th>'
      '<th>教室设备配置</th><th>校区</th></tr></thead>'
      '<tbody id="grid4321_data">'
      '${rooms.map((room) => '<tr><td>1</td><td>${room.name}</td>'
          '<td>${room.building}</td><td>${room.capacity}</td>'
          '<td>${room.equipment}</td><td>校本部</td></tr>').join()}'
      '</tbody></table>共 ${count ?? rooms.length} 条</div>';
}

NeuqRoom _science(
  String name, {
  String equipment = '普通教室',
  String capacity = '60',
}) => (
  name: '科技楼$name',
  building: '科技楼',
  equipment: equipment,
  capacity: capacity,
);

NeuqRoom _engineering(String name) =>
    (name: '工学馆$name', building: '工学馆', equipment: '普通教室', capacity: '60');

NeuqRoom _humanities(String name) =>
    (name: '人文楼$name', building: '人文楼', equipment: '普通教室', capacity: '60');

NeuqRoom _comprehensive(String name) =>
    (name: '综合楼$name', building: '综合实验楼', equipment: '普通教室', capacity: '60');

const _engineeringGrid = '''
<div class="grid"><table id="grid15320024301" class="gridtable">
<thead><tr><th>序号</th><th>名称</th><th>教学楼</th><th>校区</th>
<th>教室设备配置</th><th>容量</th></tr></thead>
<tbody id="grid15320024301_data">
<tr><td>1</td><td>工学馆410</td><td>工学馆</td><td>学校本部</td><td>录播教室</td><td>30</td></tr>
<tr><td>2</td><td>工学馆803</td><td>工学馆</td><td>学校本部</td><td>多媒体小教室</td><td>50</td></tr>
<tr><td>3</td><td>具体安排以开课部门通知为准</td><td>工学馆</td><td>学校本部</td><td></td><td>1000</td></tr>
</tbody></table></div>
<script>
var _paramstring = 'classroom.building.id=1&cycleTime.dateBegin=2026-11-24&cycleTime.dateEnd=2026-11-24&timeBegin=3&timeEnd=4';
page_grid15320024301.pageInfo(1,100,3);
</script>
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

  test('classroom request matches the school form and POST URL', () {
    final form = NeuqClassroomForm(DateTime.utc(2026, 11, 24));
    expect(
      NeuqPage.roomResult.requestUri().toString(),
      'https://jwxt.neuq.edu.cn/eams/classroom/apply/free!search.action',
    );
    expect(NeuqPage.roomResult.ajax, isTrue);
    expect(NeuqPage.roomResult.followsAcademicRedirects, isTrue);
    expect(NeuqPage.schedule.followsAcademicRedirects, isFalse);
    expect(NeuqPage.schedule.requestUri().queryParameters, {
      'sf_request_type': 'ajax',
    });
    expect(
      form.forPeriods(1, 2),
      Uri.splitQueryString(
        'classroom.type.id=&classroom.campus.id=&classroom.building.id=&'
        'seats=&classroom.name=&cycleTime.cycleCount=1&cycleTime.cycleType=1&'
        'cycleTime.dateBegin=2026-11-24&cycleTime.dateEnd=2026-11-24&'
        'roomApplyTimeType=0&timeBegin=1&timeEnd=2&pageSize=1000',
      ),
    );
    expect(form.forPeriods(4, 4, page: 2)['pageNo'], '2');
  });

  test('room parser accepts grid fragments and preserves pagination', () {
    expect(readNeuqFreeRooms(_grid([_science('A101')], count: 4)).pages, 4);
    final splitGrid = readNeuqFreeRooms(
      '<tbody id="grid15320024301_data"><tr>'
      '<td>1</td><td>科技楼 B202（具体安排以开课部门通知为准）</td>'
      '<td>科技楼</td><td>60</td><td>普通教室</td><td>校本部</td>'
      '</tr></tbody>',
    );
    expect(splitGrid.rooms, [
      (name: '科技楼B202', building: '科技楼', equipment: '普通教室', capacity: '60'),
    ]);
    expect(neuqRoomBuilding(splitGrid.rooms.single), CampusBuilding.science);
    expect(readNeuqFreeRooms(_grid([_science('B202')])).rooms, [
      (name: '科技楼B202', building: '科技楼', equipment: '普通教室', capacity: '60'),
    ]);
    expect(() => readNeuqFreeRooms('<p>页面暂不可用</p>'), throwsFormatException);
    expect(readNeuqFreeRooms('<p>没有查询结果</p>').rooms, isEmpty);
  });

  test(
    'engineering floor inference accepts plain and prefixed room numbers',
    () {
      expect(engineeringRoomFloor('工学馆G410'), 4);
      expect(engineeringRoomFloor('803'), 8);
      expect(engineeringRoomFloor('报告厅'), isNull);
      expect(engineeringRoomFloor('1201'), isNull);
    },
  );

  test(
    'the live result format identifies the requested time and counts note rows',
    () {
      final form = NeuqClassroomForm(DateTime.utc(2026, 11, 24));
      final requested = form.forPeriods(3, 4, buildingId: '1');
      final result = readNeuqFreeRooms(_engineeringGrid, requested: requested);
      expect(result.rooms.map((room) => room.name), ['工学馆410', '工学馆803']);
      expect(result.rooms.first.capacity, '30');
      expect(result.rowCount, 3);
      expect(result.total, 3);
      expect(result.pages, 1);
      expect(
        () => readNeuqFreeRooms(
          _engineeringGrid,
          requested: form.forPeriods(5, 6, buildingId: '1'),
        ),
        throwsFormatException,
      );
    },
  );

  test('paired school queries keep the three selected buildings and follow pagination', () async {
    final web = _ClassroomBrowser();
    final source = NeuqSchoolDataSource(web);
    final result = await source.fetchClassrooms(calendarDate(campusNow()));
    final science = result.buildings[CampusBuilding.science]!;
    expect(web.requests, hasLength(7));
    expect(web.requests.toSet(), {
      for (var period = 1; period <= 12; period += 2) (period, 1),
      (3, 2),
    });
    expect(science.complete, isTrue);
    expect(science.allDay, {'6026'});
    expect(result.buildings[CampusBuilding.engineering]!.freeByPeriod[1], {
      '108',
    });
    expect(result.buildings[CampusBuilding.humanities]!.freeByPeriod[1], {
      '207',
    });
    expect(
      result.buildings.keys,
      unorderedEquals([
        CampusBuilding.engineering,
        CampusBuilding.science,
        CampusBuilding.humanities,
      ]),
    );
    // 机房等非教室场地在数据源层被过滤。
    expect(science.freeByPeriod[5], isNot(contains('7000')));
    expect(science.forPeriod(3), [
      (name: '6026', availability: ClassroomAvailability.allDay),
      (name: '6027', availability: ClassroomAvailability.nextBooked),
      (name: '6028', availability: ClassroomAvailability.partial),
    ]);
  });

  test(
    'missing bulk periods fall back to the original building query form',
    () async {
      final web = _ClassroomBrowser(incomplete: true);
      final result = await NeuqSchoolDataSource(web)
          .fetchClassrooms(DateTime.utc(2026, 11, 24));
      final engineering = result.buildings[CampusBuilding.engineering]!;
      expect(web.scopedRequests, [3, 5]);
      expect(engineering.freeByPeriod[1], {'108'});
      expect(engineering.freeByPeriod[3], {'410', '803'});
      expect(engineering.freeByPeriod[5], {'805'});
      expect(result.buildings[CampusBuilding.science]!.forPeriod(3), isNull);
    },
  );

  test(
    'missing periods do not appear empty or prove full-day availability',
    () {
      final schedule = ClassroomSchedule({
        1: {'A101'},
        3: {},
      }, periodCount: 3);
      expect(schedule.complete, isFalse);
      expect(schedule.allDay, isEmpty);
      expect(
        schedule.forPeriod(1)!.single.availability,
        ClassroomAvailability.partial,
      );
      expect(schedule.forPeriod(2), isNull);
      expect(schedule.forPeriod(3), isEmpty);
    },
  );
}

class _ClassroomBrowser extends NeuqWebClient {
  _ClassroomBrowser({this.incomplete = false}) : super('example');
  final bool incomplete;
  final requests = <(int, int)>[];
  final scopedRequests = <int>[];
  bool openedForm = false;

  @override
  Future<T> read<T>(Future<T> Function() operation) => operation();

  @override
  Future<void> prepareClassroomQuery() async {
    openedForm = true;
  }

  @override
  Future<String> request(
    NeuqPage page, {
    Map<String, String> query = const {},
    Map<String, String>? form,
  }) async {
    expect(page, NeuqPage.roomResult);
    expect(openedForm, isTrue);
    expect(int.parse(form!['timeEnd']!), int.parse(form['timeBegin']!) + 1);
    final start = int.parse(form['timeBegin']!);
    if (form['classroom.building.id'] == '1') {
      expect(form, isNot(contains('pageSize')));
      scopedRequests.add(start);
      return start == 3
          ? _engineeringGrid
          : '''
<tbody><tr><td>1</td><td>805</td></tr></tbody>
''';
    }
    expect(form['classroom.building.id'], isEmpty);
    expect(form['pageSize'], '1000');
    expect(form['roomApplyTimeType'], '0');
    final request = (
      int.parse(form['timeBegin']!),
      int.parse(form['pageNo'] ?? '1'),
    );
    requests.add(request);
    if (incomplete && start == 3) {
      final grid = _grid([_engineering('108')]);
      return "$grid<script>var _paramstring = 'timeBegin=1&timeEnd=2';</script>";
    }
    if (incomplete && start == 5) return '<p>页面暂不可用</p>';
    return switch (request) {
      (1, 1) => _grid([
        _science('6026'),
        _engineering('108'),
        _humanities('207'),
        _comprehensive('199'),
      ]),
      (3, 1) => _grid([_science('6026'), _science('6027')], count: 3),
      (3, 2) => _grid([_science('6028')], count: 3),
      (5, 1) => _grid([
        _science('6026'),
        _science('6028'),
        _engineering('108'),
        _science('7000', equipment: '机房'),
      ]),
      _ => _grid([_science('6026'), _engineering('108')]),
    };
  }
}
