import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/diagnostics/diagnostics.dart';
import 'package:neuq_one/core/network/public_data_client.dart';

const _week = '/api/v1/classrooms/week.json';
const _map = '/assets/maps/campus-map.png';
final _azureData = Uri.https('data-test.azurestaticapps.net');
final _azureAssets = Uri.https('assets-test.azurestaticapps.net');
final _backupData = Uri.https('data-backup.example.test');
final _backupAssets = Uri.https('assets-backup.example.test');

void main() {
  setUp(diagnostics.clear);

  test('reads all four origins from their own dart-define', () {
    expect(
      publicDataRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_DATA_ORIGIN',
        defaultValue: 'https://blue-flower-0e0c87f00.4.azurestaticapps.net',
      ),
    );
    expect(
      publicDataBackupRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_DATA_BACKUP_ORIGIN',
        defaultValue: 'https://neuq-one-data.pages.dev',
      ),
    );
    expect(
      publicAssetsRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_ASSETS_ORIGIN',
        defaultValue: 'https://agreeable-wave-005580b00.4.azurestaticapps.net',
      ),
    );
    expect(
      publicAssetsBackupRoot.toString(),
      const String.fromEnvironment(
        'NEUQ_ONE_ASSETS_BACKUP_ORIGIN',
        defaultValue: 'https://neuq-one-assets.pages.dev',
      ),
    );
  });

  test(
    'primary success uses Azure classroom path and keeps asset paths',
    () async {
      final requests = <http.Request>[];
      final client = _client(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      expect(
        (await _getWeek(client)).resource,
        _azureData.resolve('/data/v1/classrooms/week.json'),
      );
      expect(
        (await client.getBytes(
          _map,
          source: PublicDataSource.assets,
          accept: 'image/png',
          decode: (bytes) => bytes,
          revalidate: true,
        )).resource,
        _azureAssets.resolve(_map),
      );
      expect(requests.map((request) => request.url), [
        _azureData.resolve('/data/v1/classrooms/week.json'),
        _azureAssets.resolve(_map),
      ]);
      expect(requests.last.headers['cache-control'], 'no-cache');
      expect(requests.every((request) => !request.followRedirects), isTrue);
    },
  );

  final failures = <DiagnosticCode, http.Response Function()>{
    DiagnosticCode.dnsFailure: () =>
        throw const SocketException('Failed host lookup: private.example'),
    DiagnosticCode.connectionFailed: () =>
        throw const SocketException('Connection refused'),
    DiagnosticCode.connectionTimeout: () =>
        throw const SocketException('Connection timed out'),
    DiagnosticCode.rateLimited: () => http.Response('', 429),
    DiagnosticCode.serverError: () => http.Response('', 503),
    DiagnosticCode.missingResource: () => http.Response('', 404),
    DiagnosticCode.invalidData: () => http.Response('<html>', 200),
    DiagnosticCode.responseTooLarge: () => http.Response(' ' * 32, 200),
  };
  for (final MapEntry(key: code, value: failure) in failures.entries) {
    test('tries backup for ${code.name}', () async {
      final requests = <Uri>[];
      final client = _client(
        MockClient((request) async {
          requests.add(request.url);
          return request.url.host == _azureData.host
              ? failure()
              : http.Response('{"ok":true}', 200);
        }),
      );
      final received = await _getWeek(client, maxBytes: 16);
      expect(received.body, {'ok': true});
      expect(received.resource, _backupData.resolve(_week));
      expect(requests, [
        _azureData.resolve('/data/v1/classrooms/week.json'),
        received.resource,
      ]);
      expect(diagnostics.entries.map((entry) => (entry.endpoint, entry.code)), [
        (DiagnosticEndpoint.dataPrimary, code),
        (DiagnosticEndpoint.dataBackup, DiagnosticCode.sourceSwitch),
        (DiagnosticEndpoint.dataBackup, DiagnosticCode.completed),
      ]);
      expect(
        diagnostics.entries.every((entry) => entry.elapsedMs != null),
        isTrue,
      );
    });
  }

  test(
    'only sends validators to the matching URL and rejects unsolicited 304',
    () async {
      final requests = <http.Request>[];
      late http.Response primary;
      late http.Response backup;
      final client = _client(
        MockClient((request) async {
          requests.add(request);
          return request.url.host == _azureData.host ? primary : backup;
        }),
        cooldown: Duration.zero,
      );
      primary = http.Response(
        '{}',
        200,
        headers: {
          'etag': '"shared"',
          'last-modified': 'Wed, 25 Nov 2026 08:19:12 GMT',
        },
      );
      final original = await _getWeek(client);
      primary = http.Response('', 503);
      backup = http.Response('', 304);
      await expectLater(
        _getWeek(client, validators: original.validators()),
        throwsA(
          isA<PublicDataException>().having(
            (e) => e.code,
            'code',
            DiagnosticCode.invalidData,
          ),
        ),
      );
      expect(requests[1].headers['if-none-match'], '"shared"');
      expect(requests[1].headers['if-modified-since'], isNotNull);
      expect(requests[2].headers['if-none-match'], isNull);
      expect(requests[2].headers['if-modified-since'], isNull);

      backup = http.Response('{}', 200, headers: {'etag': '"backup"'});
      final mirrored = await _getWeek(client);
      primary = http.Response('', 404);
      backup = http.Response('', 304);
      expect(
        (await _getWeek(client, validators: mirrored.validators())).notModified,
        isTrue,
      );
      expect(requests[5].headers['if-none-match'], isNull);
      expect(requests[6].headers['if-none-match'], '"backup"');
    },
  );

  test(
    'cools each source independently and allows one recovery probe',
    () async {
      final requests = <String>[];
      var now = DateTime.utc(2026, 11, 26);
      final probing = Completer<void>();
      final primaryResult = Completer<http.Response>();
      final client = _client(
        MockClient((request) async {
          requests.add(request.url.host);
          if (request.url.host != _azureData.host) {
            return http.Response('{}', 200);
          }
          if (now.second < 45) return http.Response('', 503);
          probing.complete();
          return primaryResult.future;
        }),
        clock: () => now,
      );
      await _getWeek(client);
      await _getWeek(client);
      await client.getBytes(
        _map,
        source: PublicDataSource.assets,
        accept: 'image/png',
        decode: (bytes) => bytes,
      );
      expect(requests, [
        _azureData.host,
        _backupData.host,
        _backupData.host,
        _azureAssets.host,
      ]);

      now = now.add(const Duration(seconds: 45));
      final recovery = _getWeek(client);
      await probing.future;
      expect((await _getWeek(client)).resource.host, _backupData.host);
      primaryResult.complete(http.Response('{}', 200));
      expect((await recovery).resource.host, _azureData.host);
      expect(
        diagnostics.entries.where(
          (entry) => entry.code == DiagnosticCode.sourceProbe,
        ),
        hasLength(1),
      );
    },
  );

  test('both sources fail once and are skipped during cooldown', () async {
    var attempts = 0;
    final client = _client(
      MockClient((_) async {
        attempts++;
        return http.Response('', 503);
      }),
    );
    await expectLater(_getWeek(client), throwsA(isA<PublicDataException>()));
    await expectLater(
      _getWeek(client),
      throwsA(
        isA<PublicDataException>().having(
          (error) => error.code,
          'code',
          DiagnosticCode.sourceCoolingDown,
        ),
      ),
    );
    expect(attempts, 2);
  });

  test(
    'distinguishes response headers, idle reads and the shared deadline',
    () async {
      for (final mode in [
        DiagnosticCode.responseTimeout,
        DiagnosticCode.readIdleTimeout,
        DiagnosticCode.downloadDeadline,
      ]) {
        final timers = <Timer>[];
        final body = StreamController<List<int>>.broadcast();
        final never = Completer<http.StreamedResponse>();
        final client = _client(
          MockClient.streaming((request, _) async {
            if (request.url.host == _backupData.host) {
              return http.StreamedResponse(
                Stream.value(utf8.encode('{}')),
                200,
              );
            }
            if (mode == DiagnosticCode.responseTimeout) return never.future;
            if (mode == DiagnosticCode.downloadDeadline) {
              timers.add(
                Timer.periodic(const Duration(milliseconds: 5), (_) {
                  body.add([0x20]);
                }),
              );
              final abort = (request as http.AbortableRequest).abortTrigger!;
              unawaited(
                abort.then((_) {
                  timers.last.cancel();
                  return body.close();
                }),
              );
            }
            return http.StreamedResponse(body.stream, 200);
          }),
          responseTimeout: const Duration(milliseconds: 35),
          idleTimeout: mode == DiagnosticCode.downloadDeadline
              ? const Duration(seconds: 1)
              : const Duration(milliseconds: 35),
        );
        diagnostics.clear();
        try {
          final result = await _getWeek(
            client,
            timeout: const Duration(milliseconds: 240),
          );
          expect(result.resource.host, _backupData.host);
          expect(diagnostics.entries.first.code, mode);
          expect(body.hasListener, isFalse);
        } finally {
          for (final timer in timers) {
            timer.cancel();
          }
          await body.close();
        }
      }
    },
  );
}

PublicDataClient _client(
  http.Client transport, {
  DateTime Function()? clock,
  Duration cooldown = const Duration(seconds: 45),
  Duration responseTimeout = const Duration(seconds: 4),
  Duration idleTimeout = const Duration(seconds: 4),
}) {
  addTearDown(transport.close);
  return PublicDataClient(
    transport,
    dataOrigin: _azureData,
    dataBackupOrigin: _backupData,
    assetsOrigin: _azureAssets,
    assetsBackupOrigin: _backupAssets,
    clock: clock,
    cooldown: cooldown,
    responseTimeout: responseTimeout,
    idleTimeout: idleTimeout,
  );
}

Future<PublicDataResponse<Object?>> _getWeek(
  PublicDataClient client, {
  PublicDataValidators? validators,
  int maxBytes = 1024,
  Duration timeout = const Duration(seconds: 12),
}) => client.getJson(
  _week,
  source: PublicDataSource.data,
  decode: jsonDecode,
  validators: validators,
  maxBytes: maxBytes,
  timeout: timeout,
);
