import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/network/public_data_client.dart';

void main() {
  test('reads each origin from its own dart-define', () {
    expect(
      publicDataRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_DATA_ORIGIN',
        defaultValue: 'https://neuq-one-data.pages.dev',
      ),
    );
    expect(
      publicAssetsRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_ASSETS_ORIGIN',
        defaultValue: 'https://neuq-one-assets.pages.dev',
      ),
    );
  });

  test(
    'isolates requests and preserves conditional GET on both origins',
    () async {
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        return http.Response('', 304, headers: {'etag': '"unchanged"'});
      });
      addTearDown(httpClient.close);
      final client = PublicDataClient(
        httpClient,
        dataOrigin: Uri.https('data.example.test'),
        assetsOrigin: Uri.https('assets.example.test'),
      );
      final week = await client.getJson(
        '/api/v1/classrooms/week.json',
        source: PublicDataSource.data,
        etag: '"classrooms"',
      );
      final map = await client.getBytes(
        '/assets/maps/campus-map.png',
        source: PublicDataSource.assets,
        accept: 'image/png',
        etag: '"map"',
        revalidate: true,
      );

      expect(week.body, isNull);
      expect(map.headers['etag'], '"unchanged"');
      expect(requests.map((request) => request.url.toString()), [
        'https://data.example.test/api/v1/classrooms/week.json',
        'https://assets.example.test/assets/maps/campus-map.png',
      ]);
      expect(requests.map((request) => request.headers['if-none-match']), [
        '"classrooms"',
        '"map"',
      ]);
      expect(requests.last.headers['cache-control'], 'no-cache');
      expect(requests.every((request) => !request.followRedirects), isTrue);
    },
  );
}
