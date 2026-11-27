import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../../core/auth/neuq_login_protocol.dart';
import '../../../core/network/neuq_client.dart';
import '../domain/plan_completion.dart';

PlanCompletion readNeuqPlanCompletion(String source, String expectedSubject) {
  final page = html.parse(source);
  Map<String, String>? summary;
  final groups = <PlanGroup>[];
  final extraCourses = <PlanCourse>[];
  var foundExtraCourses = false;

  for (final table in page.querySelectorAll('table')) {
    final rows = table
        .querySelectorAll('tr')
        .where((row) => row.parent == table || row.parent?.parent == table)
        .map(_cells)
        .where((row) => row.isNotEmpty)
        .toList();
    final labels = <String, String>{
      for (final row in rows)
        for (var i = 0; i + 1 < row.length; i++)
          if (row[i].classes.contains('title') &&
              row[i + 1].classes.contains('content'))
            _text(row[i]).replaceFirst(RegExp(r'[:：]$'), ''): _text(row[i + 1]),
    };
    if (labels.containsKey('学号') && labels.containsKey('必修课门数')) {
      if (summary != null) throw _invalidReport;
      summary = labels;
      continue;
    }

    final headings = rows.map((row) => row.map(_text).toList()).toList();
    final header = headings.indexWhere(
      (row) => _courseColumns.every(row.contains),
    );
    if (header < 0) continue;
    final columns = headings[header];
    if (columns.toSet().length != columns.length) throw _invalidReport;
    final data = rows.skip(header + 1);
    if (headings.take(header).any((row) => row.contains('计划外课程'))) {
      if (foundExtraCourses) throw _invalidReport;
      foundExtraCourses = true;
      extraCourses.addAll(_courseRows(data, columns));
    } else if (columns.contains('计划学期')) {
      if (groups.isNotEmpty) throw _invalidReport;
      groups.addAll(_readGroups(data, columns));
    }
  }

  final subject = schoolSubjectForStudentCode(summary?['学号'] ?? '');
  if (summary == null || subject == null || groups.isEmpty) {
    throw _invalidReport;
  }
  if (subject != expectedSubject) throw SchoolRequestFailure.differentAccount;
  final internalGpa = _optional(summary['校内专用绩点'] ?? '');
  return PlanCompletion(
    credits: _summaryProgress(summary['学分']),
    compulsoryCredits: _summaryProgress(summary['必修课学分']),
    compulsoryCourses: _summaryProgress(summary['必修课门数']),
    internalGpa: internalGpa == null ? null : _amount(internalGpa),
    groups: groups,
    extraCourses: extraCourses,
  );
}

const _invalidReport = FormatException('无法读取完整的培养方案完成情况');
const _courseColumns = {
  '课程代码',
  '课程名称',
  '是否必修',
  '计划学分',
  '完成学分',
  '成绩',
  '通过否',
  '备注',
};

List<PlanGroup> _readGroups(
  Iterable<List<Element>> rows,
  List<String> columns,
) {
  final groups = <PlanGroup>[];
  for (final row in rows) {
    if (_emptyRow(row)) continue;
    if (row.first.attributes['colspan'] == '4') {
      final values = _courseValues(row, columns);
      final heading = _text(row.first).split('缺少选修课学分').first.trim();
      final isSubgroup = _subgroup.hasMatch(heading);
      final name = heading
          .replaceFirst(isSubgroup ? _subgroup : _groupNumber, '')
          .trim();
      if (name.isEmpty || name == heading) throw _invalidReport;
      groups.add(
        PlanGroup(
          name: name,
          isSubgroup: isSubgroup,
          credits: _credits(values),
          result: values['通过否']!,
          courses: [],
        ),
      );
    } else {
      if (groups.isEmpty) throw _invalidReport;
      groups.last.courses.add(_readCourse(row, columns));
    }
  }
  return groups;
}

final _subgroup = RegExp(r'^[(（][一二三四五六七八九十]+[)）]\s*');
final _groupNumber = RegExp(r'^[一二三四五六七八九十]+[、\s]+');
final _emptyCourses = RegExp(r'^(?:暂无|没有|无)(?:课程|记录|数据)[。.]?$');

bool _emptyRow(List<Element> row) =>
    row.length == 1 && _emptyCourses.hasMatch(_text(row.single));

Iterable<PlanCourse> _courseRows(
  Iterable<List<Element>> rows,
  List<String> columns,
) => rows
    .where((row) => !_emptyRow(row))
    .map((row) => _readCourse(row, columns));

PlanCourse _readCourse(List<Element> row, List<String> columns) {
  if (row.length != columns.length) throw _invalidReport;
  final values = _courseValues(row, columns);
  final name = values['课程名称']!;
  final code = values['课程代码']!;
  final compulsory = _yesNo(values['是否必修']!);
  if (name.isEmpty || code.isEmpty || compulsory == null) throw _invalidReport;
  return PlanCourse(
    code: code,
    name: name,
    compulsory: compulsory,
    credits: _credits(values),
    passed: _yesNo(values['通过否']!),
    semester: _optional(values['计划学期'] ?? ''),
    score: _optional(values['成绩']!),
    remark: _optional(values['备注']!),
  );
}

Map<String, String> _courseValues(List<Element> row, List<String> columns) {
  final values = <String>[];
  for (final cell in row) {
    final span = int.tryParse(cell.attributes['colspan'] ?? '1');
    if (span == null || span < 1 || values.length + span > columns.length) {
      throw _invalidReport;
    }
    values.addAll(List.filled(span, _text(cell)));
  }
  if (values.length != columns.length) throw _invalidReport;
  return Map.fromIterables(columns, values);
}

PlanProgress _credits(Map<String, String> cells) => PlanProgress(
  required: _amount(cells['计划学分']!),
  completed: _amount(cells['完成学分']!),
);

final _requiredCompleted = RegExp(
  r'^要求\s*([0-9]+(?:\.[0-9]+)?)\s*(?:门|学分)?\s*[/／]\s*'
  r'完成\s*([0-9]+(?:\.[0-9]+)?)\s*(?:门|学分)?$',
);

PlanProgress _summaryProgress(String? text) {
  final match = _requiredCompleted.firstMatch(text ?? '');
  if (match == null) throw _invalidReport;
  return PlanProgress(
    required: _amount(match[1]!),
    completed: _amount(match[2]!),
  );
}

double _amount(String text) {
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0) throw _invalidReport;
  return value;
}

bool? _yesNo(String text) => switch (text) {
  '是' => true,
  '否' => false,
  '' || '--' || '—' => null,
  _ => throw _invalidReport,
};

String? _optional(String text) =>
    const {'', '-', '--', '—'}.contains(text) ? null : text;

List<Element> _cells(Element row) => [
  for (final cell in row.children)
    if (cell.localName == 'td' || cell.localName == 'th') cell,
];

final _whitespace = RegExp(r'[\s\u00a0]+');
String _text(Element cell) => cell.text.replaceAll(_whitespace, ' ').trim();
