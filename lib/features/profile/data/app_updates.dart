import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/public_data_client.dart';

final appUpdatesProvider = Provider<AppUpdatesRepository>(
  (ref) => AppUpdatesRepository(ref.watch(publicDataClientProvider)),
);

typedef AppRelease = ({String version, String url});

class AppUpdatesRepository {
  const AppUpdatesRepository(this._client);

  static const _channel = MethodChannel('org.neuqone.neuq_one/app_version');
  static final _versionPattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );
  final PublicDataClient _client;

  Future<AppRelease?> checkForUpdate() async {
    final response = await _client.getJson(
      '/assets/app/latest.json',
      source: PublicDataSource.assets,
      revalidate: true,
      maxBytes: 16 * 1024,
    );
    final body = response.body;
    if (body == null) throw const FormatException('缺少 App 版本信息');
    final json = jsonDecode(body);
    if (json case {'schemaVersion': 1, 'release': null}) return null;
    if (json
        case {
          'schemaVersion': 1,
          'release': {'version': final String version, 'url': final String url},
        }
        when _versionPattern.hasMatch(version) &&
            url ==
                'https://github.com/LTCpond/neuq-one/releases/tag/v$version') {
      final installed = await _channel.invokeMethod<String>('getVersion');
      if (installed == null || !_versionPattern.hasMatch(installed)) {
        throw const FormatException('无法识别当前 App 版本');
      }
      final latestParts = version.split('.');
      final installedParts = installed.split('.');
      for (var i = 0; i < latestParts.length; i++) {
        final order = BigInt.parse(latestParts[i])
            .compareTo(BigInt.parse(installedParts[i]));
        if (order > 0) return (version: version, url: url);
        if (order < 0) return null;
      }
      return null;
    }
    throw const FormatException('App 版本信息格式错误');
  }
}
