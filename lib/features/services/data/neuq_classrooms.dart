import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../domain/classrooms.dart';

class NeuqClassroomForm {
  const NeuqClassroomForm(this.day);

  final DateTime day;

  Map<String, String> forPeriods(
    int start,
    int end, {
    int page = 1,
    String? buildingId,
  }) {
    final date = day.toIso8601String().substring(0, 10);
    return {
      'classroom.type.id': '',
      'classroom.campus.id': '',
      'classroom.building.id': buildingId ?? '',
      'seats': '',
      'classroom.name': '',
      'cycleTime.cycleCount': '1',
      'cycleTime.cycleType': '1',
      'cycleTime.dateBegin': date,
      'cycleTime.dateEnd': date,
      'roomApplyTimeType': '0',
      'timeBegin': '$start',
      'timeEnd': '$end',
      if (buildingId == null) 'pageSize': '1000',
      if (page > 1) 'pageNo': '$page',
    };
  }
}

typedef NeuqRoom = ({
  String name,
  String building,
  String equipment,
  String capacity,
});
typedef NeuqRoomPage = ({
  List<NeuqRoom> rooms,
  int rowCount,
  int pages,
  int? total,
});

const _nameHeaders = {'名称', '教室', '教室名称', '场地名称', '教室名', '教室编号'};
const _buildingHeaders = {'教学楼', '楼栋', '楼宇', '所在楼栋'};
const _equipmentHeader = '教室设备配置';
const _capacityHeader = '容量';

/// 解析教务系统「空闲教室查询」返回的 HTML。
///
/// 结果网格按列对齐：有表头时按「名称 / 教学楼 / 容量 / 教室设备配置」定位列；
/// 无表头（AJAX 只返回表格片段）时按教务网格的固定列序
/// `序号 / 名称 / 教学楼 / 校区 / 教室设备配置 / 容量` 读取。
/// 无法识别的响应会作为查询失败处理，避免把错误页显示成无空教室。
NeuqRoomPage readNeuqFreeRooms(
  String source, {
  Map<String, String>? requested,
}) {
  final trimmed = source.trimLeft();
  // AJAX 响应可能只返回表格片段（tbody 或裸 tr 行），补上外层标签统一解析。
  final page = html.parse(
    RegExp(r'^<tbody\b', caseSensitive: false).hasMatch(trimmed)
        ? '<table class="gridtable">$trimmed</table>'
        : RegExp(r'^<tr\b', caseSensitive: false).hasMatch(trimmed)
        ? '<table class="gridtable"><tbody>$trimmed</tbody></table>'
        : source,
  );

  final table = page.querySelector('table.gridtable');
  final grid = page.querySelector(r'tbody[id^="grid"][id$="_data"]');
  final tableId = table?.id.isNotEmpty == true
      ? table!.id
      : grid?.id.replaceFirst(RegExp(r'_data$'), '');
  _checkReturnedQuery(source, requested);
  final rows = table != null
      ? table.querySelectorAll('tbody tr')
      : grid != null
      ? grid.querySelectorAll('tr')
      : const <Element>[];
  if (table == null && grid == null) {
    if (_noRooms.hasMatch(_compact(page.body?.text ?? ''))) {
      return (rooms: const [], rowCount: 0, pages: 1, total: 0);
    }
    throw const FormatException('无法识别教务返回的空教室结果');
  }

  final headers =
      table
          ?.querySelectorAll('thead th, thead td')
          .map((cell) => _compact(cell.text))
          .toList() ??
      const <String>[];
  final hasHeader =
      headers.any(_nameHeaders.contains) &&
      headers.any(_buildingHeaders.contains);
  final nameIndex = hasHeader ? headers.indexWhere(_nameHeaders.contains) : 1;
  final buildingIndex = hasHeader
      ? headers.indexWhere(_buildingHeaders.contains)
      : 2;
  final equipmentIndex = hasHeader ? headers.indexOf(_equipmentHeader) : 4;
  final capacityIndex = hasHeader ? headers.indexOf(_capacityHeader) : 5;

  final rooms = <NeuqRoom>[];
  var rowCount = 0;
  for (final row in rows) {
    final cells = row.children.where((cell) => cell.localName == 'td').toList();
    if (cells.isEmpty) continue;
    if (cells.length < 2) {
      if (_noRooms.hasMatch(_compact(row.text))) continue;
      throw const FormatException('教务结果行缺少教室字段');
    }
    rowCount++;
    final name = _compact(_cellText(cells, nameIndex))
        .replaceFirst(RegExp(r'[（(]?具体安排以开课部门通知为准[）)]?$'), '');
    if (name.isEmpty) continue;
    final capacity = _compact(_cellText(cells, capacityIndex));
    final legacyCapacity = _compact(_cellText(cells, 3));
    rooms.add((
      name: name,
      building: _compact(_cellText(cells, buildingIndex)),
      equipment: _compact(_cellText(cells, equipmentIndex)),
      capacity:
          !hasHeader &&
              int.tryParse(capacity) == null &&
              int.tryParse(legacyCapacity) != null
          ? legacyCapacity
          : capacity,
    ));
  }

  final content = page.body?.text ?? '';
  final pageInfo = tableId == null
      ? null
      : RegExp(
          '\\bpage_${RegExp.escape(tableId)}\\.pageInfo\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)',
        ).firstMatch(source);
  if (pageInfo != null &&
      requested != null &&
      pageInfo[1] != (requested['pageNo'] ?? '1')) {
    throw const FormatException('教务返回了其他页的空教室结果');
  }
  final pageSize = int.tryParse(pageInfo?[2] ?? '') ?? rowCount;
  final total =
      int.tryParse(pageInfo?[3] ?? '') ??
      int.tryParse(
        RegExp(r'共\s*(\d+)\s*(?:条|项)').firstMatch(content)?.group(1) ?? '',
      );
  final hintedPages = int.tryParse(
    RegExp(r'共\s*(\d+)\s*页').firstMatch(content)?.group(1) ?? '',
  );
  final pages =
      hintedPages ??
      (total != null && pageSize > 0 ? (total / pageSize).ceil() : 1);
  return (
    rooms: rooms,
    rowCount: rowCount,
    pages: pages < 1 ? 1 : pages,
    total: total,
  );
}

void _checkReturnedQuery(String source, Map<String, String>? requested) {
  if (requested == null) return;
  final match = RegExp(r'''\bvar\s+_paramstring\s*=\s*["']([^"']+)["']''')
      .allMatches(source)
      .where((item) => item[1]!.contains('timeBegin='))
      .firstOrNull;
  if (match == null) return;
  final returned = Uri.splitQueryString(match[1]!);
  for (final field in const [
    'cycleTime.dateBegin',
    'cycleTime.dateEnd',
    'timeBegin',
    'timeEnd',
    'classroom.building.id',
  ]) {
    if (returned.containsKey(field) && returned[field] != requested[field]) {
      throw const FormatException('教务返回了其他时段或楼栋的结果');
    }
  }
}

String _cellText(List<Element> cells, int index) =>
    index >= 0 && index < cells.length ? cells[index].text : '';

CampusBuilding? neuqRoomBuilding(NeuqRoom room) {
  final label = room.building.isEmpty ? room.name : room.building;
  return CampusBuilding.values
      .where((building) => label.contains(building.label))
      .firstOrNull;
}

final _noRooms = RegExp(
  r'^(?:暂无(?:空闲|空)教室|没有(?:空闲|空)教室|无符合条件的(?:教室|记录)|'
  r'(?:没有|未)查询到(?:符合条件的)?记录|没有查询结果|暂无数据|没有记录|无记录)[。！!]?$',
);

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '').trim();
