import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/public_data_client.dart';

final appUpdatesProvider = Provider<AppUpdatesRepository>(
  (ref) => AppUpdatesRepository(ref.watch(publicDataClientProvider)),
);

final installedAppVersionProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(appUpdatesProvider).installedVersion(),
  retry: (_, _) => null,
);

sealed class AppUpdateResult {
  const AppUpdateResult();
}

class NoPublishedAppRelease extends AppUpdateResult {
  const NoPublishedAppRelease();
}

class AppUpToDate extends AppUpdateResult {
  const AppUpToDate();
}

class AppUpdateAvailable extends AppUpdateResult {
  const AppUpdateAvailable({
    required this.currentVersion,
    required this.latestVersion,
    required this.url,
  });

  final String currentVersion;
  final String latestVersion;
  final String url;
}

class AppUpdatesRepository {
  const AppUpdatesRepository(this._client);

  static const _channel = MethodChannel('org.neuqone.neuq_one/app_version');
  static final _versionPattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );
  final PublicDataClient _client;

  Future<String> installedVersion() async {
    final version = await _channel.invokeMethod<String>('getVersion');
    if (version == null || !_versionPattern.hasMatch(version)) {
      throw const FormatException('无法识别当前 App 版本');
    }
    return version;
  }

  Future<AppUpdateResult> checkForUpdate() async {
    final response = await _client.getJson(
      '/assets/app/latest.json',
      source: PublicDataSource.assets,
      revalidate: true,
      maxBytes: 16 * 1024,
    );
    final body = response.body;
    if (body == null) throw const FormatException('缺少 App 版本信息');
    final json = jsonDecode(body);
    if (json case {'schemaVersion': 1, 'release': null}) {
      return const NoPublishedAppRelease();
    }
    if (json
        case {
          'schemaVersion': 1,
          'release': {'version': final String version, 'url': final String url},
        }
        when _versionPattern.hasMatch(version) &&
            url ==
                'https://github.com/LTCpond/neuq-one/releases/tag/v$version') {
      final installed = await installedVersion();
      final latestParts = version.split('.');
      final installedParts = installed.split('.');
      for (var i = 0; i < latestParts.length; i++) {
        final order = BigInt.parse(latestParts[i])
            .compareTo(BigInt.parse(installedParts[i]));
        if (order > 0) {
          return AppUpdateAvailable(
            currentVersion: installed,
            latestVersion: version,
            url: url,
          );
        }
        if (order < 0) break;
      }
      return const AppUpToDate();
    }
    throw const FormatException('App 版本信息格式错误');
  }
}
