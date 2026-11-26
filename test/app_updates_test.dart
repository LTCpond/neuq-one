import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/features/profile/data/app_updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.neuqone.neuq_one/app_version');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getVersion');
      return '0.9.1';
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  AppUpdatesRepository repository(Object? release) {
    final client = MockClient((request) async {
      expect(request.url, publicAssetsRoot.resolve('/assets/app/latest.json'));
      expect(request.headers['cache-control'], 'no-cache');
      return http.Response(
        jsonEncode({'schemaVersion': 1, 'release': release}),
        200,
      );
    });
    addTearDown(client.close);
    return AppUpdatesRepository(PublicDataClient(client));
  }

  AppRelease release(String version) => (
    version: version,
    url: 'https://github.com/LTCpond/neuq-one/releases/tag/v$version',
  );

  test('compares stable release versions numerically', () async {
    final latest = release('0.10.0');
    expect(
      await repository({'version': latest.version, 'url': latest.url})
          .checkForUpdate(),
      latest,
    );
    for (final version in ['0.9.1', '0.8.9']) {
      expect(
        await repository({'version': version, 'url': release(version).url})
            .checkForUpdate(),
        isNull,
      );
    }
    expect(await repository(null).checkForUpdate(), isNull);
  });

  test('rejects an update link outside the official release', () async {
    await expectLater(
      repository({'version': '1.0.0', 'url': 'https://example.test/update.apk'})
          .checkForUpdate(),
      throwsFormatException,
    );
  });
}
