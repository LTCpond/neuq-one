import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../diagnostics/diagnostics.dart';

final publicDataRoot = Uri.parse(
  const String.fromEnvironment(
    'NEUQ_ONE_DATA_ORIGIN',
    defaultValue: 'https://blue-flower-0e0c87f00.4.azurestaticapps.net',
  ),
);
final publicAssetsRoot = Uri.parse(
  const String.fromEnvironment(
    'NEUQ_ONE_ASSETS_ORIGIN',
    defaultValue: 'https://agreeable-wave-005580b00.4.azurestaticapps.net',
  ),
);
final publicDataBackupRoot = Uri.parse(
  const String.fromEnvironment(
    'NEUQ_ONE_DATA_BACKUP_ORIGIN',
    defaultValue: 'https://neuq-one-data.pages.dev',
  ),
);
final publicAssetsBackupRoot = Uri.parse(
  const String.fromEnvironment(
    'NEUQ_ONE_ASSETS_BACKUP_ORIGIN',
    defaultValue: 'https://neuq-one-assets.pages.dev',
  ),
);

enum PublicDataSource { data, assets }

final publicDataClientProvider = Provider<PublicDataClient>((ref) {
  final client = IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 3),
  );
  ref.onDispose(client.close);
  return PublicDataClient(client);
});

class PublicDataValidators {
  const PublicDataValidators(this.resource, {this.etag, this.lastModified});

  final Uri resource;
  final String? etag;
  final String? lastModified;
}

class PublicDataResponse<T> {
  const PublicDataResponse(
    this.body,
    this.headers,
    this.resource, {
    required this.notModified,
  });

  final T? body;
  final Map<String, String> headers;
  final Uri resource;
  final bool notModified;

  PublicDataValidators validators({PublicDataValidators? previous}) {
    final match = notModified && previous?.resource == resource
        ? previous
        : null;
    return PublicDataValidators(
      resource,
      etag: headers['etag'] ?? match?.etag,
      lastModified: headers['last-modified'] ?? match?.lastModified,
    );
  }
}

class PublicDataException implements Exception {
  const PublicDataException(this.code, {this.status});

  final DiagnosticCode code;
  final int? status;

  @override
  String toString() => '公共数据暂时无法获取';
}

class PublicDataClient {
  PublicDataClient(
    this._client, {
    Uri? dataOrigin,
    Uri? dataBackupOrigin,
    Uri? assetsOrigin,
    Uri? assetsBackupOrigin,
    this.responseTimeout = const Duration(seconds: 4),
    this.idleTimeout = const Duration(seconds: 4),
    this.cooldown = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _endpoints = {
         PublicDataSource.data: [
           _Endpoint(
             dataOrigin ?? publicDataRoot,
             DiagnosticEndpoint.dataPrimary,
           ),
           _Endpoint(
             dataBackupOrigin ?? publicDataBackupRoot,
             DiagnosticEndpoint.dataBackup,
           ),
         ],
         PublicDataSource.assets: [
           _Endpoint(
             assetsOrigin ?? publicAssetsRoot,
             DiagnosticEndpoint.assetsPrimary,
           ),
           _Endpoint(
             assetsBackupOrigin ?? publicAssetsBackupRoot,
             DiagnosticEndpoint.assetsBackup,
           ),
         ],
       };

  final http.Client _client;
  final Map<PublicDataSource, List<_Endpoint>> _endpoints;
  final Duration responseTimeout;
  final Duration idleTimeout;
  final Duration cooldown;
  final DateTime Function() _clock;
  static const _timeout = Duration(seconds: 12);
  static const _maxBytes = 8 * 1024 * 1024;

  Future<PublicDataResponse<T>> getJson<T>(
    String path, {
    required PublicDataSource source,
    required T Function(String) decode,
    PublicDataValidators? validators,
    bool Function()? canReuseCache,
    bool revalidate = false,
    Duration timeout = _timeout,
    int maxBytes = _maxBytes,
  }) => getBytes(
    path,
    source: source,
    accept: 'application/json',
    decode: (bytes) => decode(utf8.decode(bytes)),
    validators: validators,
    canReuseCache: canReuseCache,
    revalidate: revalidate,
    timeout: timeout,
    maxBytes: maxBytes,
  );

  Future<PublicDataResponse<T>> getBytes<T>(
    String path, {
    required PublicDataSource source,
    required String accept,
    required FutureOr<T> Function(Uint8List) decode,
    PublicDataValidators? validators,
    bool Function()? canReuseCache,
    bool revalidate = false,
    Duration timeout = _timeout,
    int maxBytes = _maxBytes,
  }) async {
    final [primary, backup] = _endpoints[source]!;
    final primaryResource = primary.resource(source, path);
    final backupResource = backup.resource(source, path);
    final candidates = {
      primaryResource: primary,
      if (backupResource != primaryResource) backupResource: backup,
    };
    final total = Stopwatch()..start();
    var failure = const PublicDataException(DiagnosticCode.sourceCoolingDown);
    for (final MapEntry(key: resource, value: endpoint) in candidates.entries) {
      if (!endpoint.isReady(_clock())) {
        _log(endpoint, DiagnosticCode.sourceCoolingDown, total.elapsed);
        continue;
      }
      var budget = timeout - total.elapsed;
      if (budget <= Duration.zero) break;
      if (endpoint == primary &&
          candidates.length == 2 &&
          backup.isReady(_clock())) {
        // Reserve a share for the backup even if the primary keeps sending bytes.
        final primaryBudget = timeout * (2 / 3);
        if (primaryBudget < budget) budget = primaryBudget;
      }
      if (endpoint == backup) {
        _log(endpoint, DiagnosticCode.sourceSwitch, total.elapsed);
      }
      final previousCooldown = endpoint.retryAt;
      if (previousCooldown != null) {
        endpoint.probing = true;
        _log(endpoint, DiagnosticCode.sourceProbe, total.elapsed);
      }
      final attempt = Stopwatch()..start();
      try {
        final result = await _attempt(
          resource,
          accept: accept,
          decode: decode,
          validators: validators?.resource == resource ? validators : null,
          canReuseCache: canReuseCache,
          revalidate: revalidate,
          budget: budget,
          maxBytes: maxBytes,
        );
        if (identical(endpoint.retryAt, previousCooldown)) {
          endpoint.retryAt = null;
        }
        _log(endpoint, DiagnosticCode.completed, attempt.elapsed);
        return result;
      } on PublicDataException catch (error) {
        failure = error;
        if (identical(endpoint.retryAt, previousCooldown)) {
          endpoint.retryAt = _coolsOrigin(error.code)
              ? _clock().add(cooldown)
              : null;
        }
        _log(
          endpoint,
          error.code,
          attempt.elapsed,
          status: error.status,
          failed: true,
        );
      } finally {
        if (previousCooldown != null) endpoint.probing = false;
      }
    }
    throw failure;
  }

  Future<PublicDataResponse<T>> _attempt<T>(
    Uri resource, {
    required String accept,
    required FutureOr<T> Function(Uint8List) decode,
    required PublicDataValidators? validators,
    required bool Function()? canReuseCache,
    required bool revalidate,
    required Duration budget,
    required int maxBytes,
  }) async {
    final abort = Completer<void>();
    final conditional = validators != null && (canReuseCache?.call() ?? true);
    final request = http.AbortableRequest(
      'GET',
      resource,
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll({
      'Accept': accept,
      if (conditional) 'If-None-Match': ?validators.etag,
      if (conditional) 'If-Modified-Since': ?validators.lastModified,
      if (revalidate) 'Cache-Control': 'no-cache',
    });
    final sentValidators =
        conditional &&
        (validators.etag != null || validators.lastModified != null);

    try {
      return await _read(
        request,
        decode,
        maxBytes,
        sentValidators,
        canReuseCache,
      ).timeout(
        budget,
        onTimeout: () =>
            throw const PublicDataException(DiagnosticCode.downloadDeadline),
      );
    } on SocketException catch (error) {
      // Dart exposes DNS and connection timeouts through SocketException.
      final message = error.message;
      final code = switch (message) {
        _ when message.startsWith('Failed host lookup') =>
          DiagnosticCode.dnsFailure,
        _ when message.startsWith('Connection timed out') =>
          DiagnosticCode.connectionTimeout,
        _ => DiagnosticCode.connectionFailed,
      };
      throw PublicDataException(code);
    } on TimeoutException {
      throw const PublicDataException(DiagnosticCode.timeout);
    } on HandshakeException {
      throw const PublicDataException(DiagnosticCode.connectionFailed);
    } on HttpException {
      throw const PublicDataException(DiagnosticCode.network);
    } on http.ClientException {
      throw const PublicDataException(DiagnosticCode.network);
    } finally {
      abort.complete();
    }
  }

  Future<PublicDataResponse<T>> _read<T>(
    http.BaseRequest request,
    FutureOr<T> Function(Uint8List) decode,
    int maxBytes,
    bool sentValidators,
    bool Function()? canReuseCache,
  ) async {
    final response = await _client
        .send(request)
        .timeout(
          responseTimeout,
          onTimeout: () =>
              throw const PublicDataException(DiagnosticCode.responseTimeout),
        );
    final status = response.statusCode;
    if (status != 200) {
      response.stream.listen(null).cancel().ignore();
      if (status == 304 && sentValidators && (canReuseCache?.call() ?? true)) {
        return PublicDataResponse(
          null,
          response.headers,
          request.url,
          notModified: true,
        );
      }
      final code = switch (status) {
        304 => DiagnosticCode.invalidData,
        404 || 410 => DiagnosticCode.missingResource,
        408 => DiagnosticCode.responseTimeout,
        429 => DiagnosticCode.rateLimited,
        >= 500 && <= 599 => DiagnosticCode.serverError,
        _ => DiagnosticCode.rejected,
      };
      throw PublicDataException(code, status: status);
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      response.stream.listen(null).cancel().ignore();
      throw const PublicDataException(DiagnosticCode.responseTooLarge);
    }
    final bytes = BytesBuilder(copy: false);
    final chunks = StreamIterator(response.stream);
    try {
      while (await chunks.moveNext().timeout(
        idleTimeout,
        onTimeout: () =>
            throw const PublicDataException(DiagnosticCode.readIdleTimeout),
      )) {
        final chunk = chunks.current;
        if (bytes.length + chunk.length > maxBytes) {
          throw const PublicDataException(DiagnosticCode.responseTooLarge);
        }
        bytes.add(chunk);
      }
    } finally {
      chunks.cancel().ignore();
    }
    try {
      final body = await decode(bytes.takeBytes());
      return PublicDataResponse(
        body,
        response.headers,
        request.url,
        notModified: false,
      );
    } on FormatException {
      throw const PublicDataException(DiagnosticCode.invalidData);
    }
  }

  static bool _coolsOrigin(DiagnosticCode code) => switch (code) {
    DiagnosticCode.network ||
    DiagnosticCode.timeout ||
    DiagnosticCode.dnsFailure ||
    DiagnosticCode.connectionFailed ||
    DiagnosticCode.connectionTimeout ||
    DiagnosticCode.responseTimeout ||
    DiagnosticCode.readIdleTimeout ||
    DiagnosticCode.downloadDeadline ||
    DiagnosticCode.rateLimited ||
    DiagnosticCode.serverError => true,
    _ => false,
  };

  static void _log(
    _Endpoint endpoint,
    DiagnosticCode code,
    Duration elapsed, {
    int? status,
    bool failed = false,
  }) => diagnostics.record(
    DiagnosticModule.publicData,
    DiagnosticStage.request,
    code: code,
    level: failed ? DiagnosticSeverity.warn : DiagnosticSeverity.debug,
    endpoint: endpoint.label,
    elapsedMs: elapsed.inMilliseconds,
    httpStatus: status,
  );
}

class _Endpoint {
  _Endpoint(this.origin, this.label) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw ArgumentError('公共数据源必须为 HTTPS 根地址');
    }
  }

  final Uri origin;
  final DiagnosticEndpoint label;
  DateTime? retryAt;
  bool probing = false;

  bool isReady(DateTime now) => !probing && !(retryAt?.isAfter(now) ?? false);

  Uri resource(PublicDataSource source, String path) => origin.replace(
    path:
        source == PublicDataSource.data &&
            origin.host.endsWith('.azurestaticapps.net') &&
            path.startsWith('/api/v1/')
        ? path.replaceFirst('/api/v1/', '/data/v1/')
        : path,
  );
}
