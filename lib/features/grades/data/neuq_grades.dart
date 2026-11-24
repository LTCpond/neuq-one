import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:uuid/uuid.dart';

import '../../timetable/data/neuq_timetable.dart';
import '../../timetable/domain/timetable.dart';
import '../domain/grades.dart';

SchoolGradeBook readNeuqGrades(String source, Iterable<Semester> catalog) {
  final page = html.parse(source);
  final known = {
    ...neuqPublishedTerms,
    for (final term in catalog) term.name: term,
  };
  final grades = <Grade>[];
  final terms = <String, Semester>{};
  final gpa = <String, double>{};
  final attempts = <String, int>{};
  var foundGradeGrid = false;

  for (final table in page.querySelectorAll('table')) {
    final rows = table.querySelectorAll('tr').where((row) {
      final parent = row.parent;
      return parent == table || parent?.parent == table;
    }).toList();
    final header = rows.indexWhere((row) {
      final labels = _cells(row);
      return labels.contains('课程名称') &&
          labels.contains('学分') &&
          labels.any(_gradeHeader.contains);
    });
    if (header == -1) continue;
    foundGradeGrid = true;
    final columns = _cells(rows[header]);
    final courseCol = columns.indexOf('课程名称');
    final creditCol = columns.indexOf('学分');
    final scoreCol = columns.indexWhere(_gradeHeader.contains);
    final termCol = columns.indexWhere({'学年学期', '学期', '开课学期'}.contains);
    final yearCol = columns.indexWhere({'学年', '开课学年'}.contains);
    final kindCols = columns.indexed
        .where(
          (column) => const {
            '课程性质',
            '课程类别',
            '课程属性',
            '课程类型',
            '课程分类',
            '课程模块',
          }.contains(column.$2),
        )
        .map((column) => column.$1);
    final codeCol = columns.indexWhere({'课程代码', '课程编号', '课程序号'}.contains);
    final attemptCol = columns.indexWhere(
      {'考试性质', '考试类型', '成绩类型', '修读方式'}.contains,
    );
    Semester? groupedTerm;
    for (final row in rows.skip(header + 1)) {
      final cells = _cells(row);
      final text = cells.join(' ');
      if (cells.isEmpty || _noGrades.hasMatch(text)) continue;
      final label = _termIn(text);
      final named = label == null ? null : known[label];
      if (cells.length < columns.length ||
          row.querySelector('td[colspan]') != null) {
        if (label != null && named == null) {
          throw const FormatException('教务成绩包含未知学期');
        }
        groupedTerm = named ?? groupedTerm;
        final points = _gpaValue(text, r'(?:学期|本学期)(?:平均)?(?:学分)?绩点');
        if (points != null && groupedTerm != null) {
          gpa[groupedTerm.id] = points;
          terms[groupedTerm.id] = groupedTerm;
        }
        continue;
      }
      final scoreText = cells[scoreCol];
      if (const {'待录入', '未录入', '未公布', '', '--', '—'}.contains(scoreText)) {
        continue;
      }
      final termLabel = termCol >= 0
          ? _termIn(cells[termCol]) ??
                (yearCol >= 0
                    ? neuqTermKey(cells[yearCol], cells[termCol])
                    : null)
          : label;
      final term = termLabel == null ? groupedTerm : known[termLabel];
      final credit = double.tryParse(cells[creditCol]);
      if (term == null || credit == null || cells[courseCol].isEmpty) {
        throw const FormatException('教务成绩缺少学期、课程名称或学分');
      }
      final (format, score) = _score(scoreText);
      final signature = jsonEncode([
        term.id,
        codeCol < 0 ? cells[courseCol] : cells[codeCol],
        attemptCol < 0 ? '' : cells[attemptCol],
      ]);
      final index = attempts.update(signature, (n) => n + 1, ifAbsent: () => 1);
      final id = const Uuid().v5(Namespace.url.value, '$signature#$index');
      terms[term.id] = term;
      grades.add(
        Grade(
          id: 'school:$id',
          semesterId: term.id,
          name: cells[courseCol],
          credit: credit,
          score: score,
          format: format,
          kind: _kind(kindCols.map((index) => cells[index]).join(' ')),
        ),
      );
    }
  }

  final visibleText = page.body?.text ?? '';
  if (!foundGradeGrid || (grades.isEmpty && !_noGrades.hasMatch(visibleText))) {
    throw const FormatException('无法识别完整的教务成绩表');
  }
  return SchoolGradeBook(
    terms.values.toList(),
    grades,
    semesterGpa: gpa,
    cumulativeGpa:
        _gpaValue(visibleText, r'(?:累计|总|主修)(?:平均)?(?:学分)?绩点') ??
        _gpaValue(visibleText, r'(?:^|[\r\n])\s*平均学分绩点'),
  );
}

const _gradeHeader = {'总评成绩', '最终成绩', '成绩', '课程成绩', '总评'};
final _noGrades = RegExp(r'暂无(?:成绩|记录|数据)|没有(?:成绩|记录|数据)|无(?:成绩|记录|数据)');

List<String> _cells(Element row) => [
  for (final cell in row.children)
    if (cell.localName == 'td' || cell.localName == 'th')
      cell.text.trim().replaceAll(RegExp(r'\s+'), ' '),
];

String? _termIn(String label) {
  final match = RegExp(
    r'(\d{4}\s*[-—–－至]\s*\d{4})(?:学年)?\s*(?:第)?([12一二]|[秋春]季?|[上下])',
  ).firstMatch(label);
  return match == null ? null : neuqTermKey(match[1]!, match[2]!);
}

double? _gpaValue(String text, String label) {
  final value = RegExp('$label\\s*[：:]?\\s*([0-9]+(?:\\.[0-9]+)?)')
      .firstMatch(text)
      ?.group(1);
  return value == null ? null : double.tryParse(value);
}

(ScoreFormat, double) _score(String text) {
  final numeric = double.tryParse(text);
  if (numeric != null) return (ScoreFormat.numeric, numeric);
  return switch (text) {
    '优' || '优秀' => (ScoreFormat.fiveLevel, 95),
    '良' || '良好' => (ScoreFormat.fiveLevel, 85),
    '中' || '中等' => (ScoreFormat.fiveLevel, 75),
    '及格' => (ScoreFormat.fiveLevel, 65),
    '不及格' => (ScoreFormat.fiveLevel, 0),
    '合格' || '通过' => (ScoreFormat.binary, 60),
    '不合格' || '不通过' => (ScoreFormat.binary, 0),
    '缓考' => (ScoreFormat.deferred, 0),
    _ => throw const FormatException('教务成绩采用了未识别的计分方式'),
  };
}

GradeKind _kind(String text) {
  if (text.contains('文化素质')) return GradeKind.cultureElective;
  for (final kind in [
    GradeKind.microMajor,
    GradeKind.dualDegree,
    GradeKind.minor,
    GradeKind.extracurricular,
    GradeKind.general,
    GradeKind.required,
    GradeKind.elective,
  ]) {
    if (text.contains(kind.label)) return kind;
  }
  return GradeKind.other;
}
