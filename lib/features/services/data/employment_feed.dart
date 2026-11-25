import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html;

import '../../../core/storage/settings.dart';

enum EmploymentKind {
  talk('宣讲会', '/teachin/index', '/teachin/view/id/'),
  fair('招聘会', '/jobfair', '/jobfair/view/id/');

  const EmploymentKind(this.label, this.path, this.detailPrefix);
  final String label;
  final String path;
  final String detailPrefix;

  Uri get uri => Uri.https(_host, path);

  bool matches(Uri uri) =>
      uri.host == _host &&
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path.startsWith(detailPrefix) &&
      RegExp(r'^\d+$').hasMatch(uri.path.substring(detailPrefix.length));
}

const _host = 'job.neuq.edu.cn';
final _home = Uri.https(_host, '/');
const _cacheKey = 'employmentFeed';
const _maxBytes = 1024 * 1024;
const _ttl = Duration(minutes: 30);

class EmploymentEvent {
  const EmploymentEvent(this.kind, this.title, this.when, this.where, this.url);

  final EmploymentKind kind;
  final String title;
  final String when;
  final String where;
  final Uri url;

  Map<String, String> toJson() => {
    'kind': kind.name,
    'title': title,
    'when': when,
    'where': where,
    'url': url.toString(),
  };

  factory EmploymentEvent.fromJson(Map<String, dynamic> json) {
    final event = EmploymentEvent(
      EmploymentKind.values.byName(json['kind'] as String),
      json['title'] as String,
      json['when'] as String,
      json['where'] as String,
      Uri.parse(json['url'] as String),
    );
    if (!event.kind.matches(event.url)) throw const FormatException();
    return event;
  }
}

typedef EmploymentSnapshot = ({
  List<EmploymentEvent> events,
  DateTime syncedAt,
});

final employmentCacheProvider = FutureProvider<EmploymentSnapshot?>((
  ref,
) async {
  final stored = await ref.watch(preferencesProvider).getString(_cacheKey);
  if (stored == null) return null;
  try {
    final json = jsonDecode(stored) as Map<String, dynamic>;
    return (
      events: (json['events'] as List)
          .map((item) => EmploymentEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
      syncedAt: DateTime.parse(json['syncedAt'] as String),
    );
  } catch (_) {
    return null;
  }
});

final employmentRefreshProvider = FutureProvider.autoDispose
    .family<EmploymentSnapshot, bool>((ref, force) async {
      final prefs = ref.watch(preferencesProvider);
      final previous = await ref.read(employmentCacheProvider.future);
      if (!force &&
          previous != null &&
          DateTime.now().difference(previous.syncedAt) < _ttl) {
        return previous;
      }
      final events = readEmploymentFeed(await _readHome());
      final now = DateTime.now().toUtc();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'events': events.map((event) => event.toJson()).toList(),
          'syncedAt': now.toIso8601String(),
        }),
      );
      if (ref.mounted) ref.invalidate(employmentCacheProvider);
      return (events: events, syncedAt: now);
    }, retry: (_, _) => null);

Future<String> _readHome() async {
  final timeout = const Duration(seconds: 12);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(_home).timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > _maxBytes) {
      throw const HttpException('就业信息网暂不可用');
    }
    final bytes = await response
        .fold<List<int>>(<int>[], (bytes, chunk) {
          if (bytes.length + chunk.length > _maxBytes) {
            throw const FormatException('就业信息网返回的数据超出大小限制');
          }
          return bytes..addAll(chunk);
        })
        .timeout(timeout);
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}

List<EmploymentEvent> readEmploymentFeed(String source) {
  final page = html.parse(source);
  final events = <Uri, EmploymentEvent>{};
  for (final row in page.querySelectorAll('li .content-info')) {
    final link = row.querySelector('a.title');
    final href = link?.attributes['href'];
    if (link == null || href == null) continue;
    final uri = _home.resolve(href);
    final kind = EmploymentKind.values
        .where((kind) => kind.matches(uri))
        .firstOrNull;
    if (kind == null) continue;
    final date =
        row.parent
            ?.querySelectorAll('.new-time p')
            .map((p) => p.text.trim())
            .join() ??
        '';
    final status = link.querySelector('.status-text')?.text.trim();
    final title = link.text.trim();
    final cleanTitle =
        status != null && status.isNotEmpty && title.startsWith(status)
        ? title.substring(status.length).trim()
        : title;
    if (cleanTitle.isEmpty || date.isEmpty) continue;
    events[uri] = EmploymentEvent(
      kind,
      cleanTitle,
      [
        date,
        row.querySelector('.time')?.text.trim(),
        status ?? (row.text.contains('已举办') ? '已举办' : null),
      ].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
      row.querySelector('.address')?.text.trim() ?? '',
      uri,
    );
  }
  if (EmploymentKind.values.any(
    (kind) => !events.values.any((event) => event.kind == kind),
  )) {
    throw const FormatException('未能读取完整的学校就业活动列表');
  }
  return events.values.toList();
}
