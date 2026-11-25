import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final publicDataRoot = Uri.https('neuq-one-data.pages.dev');

final publicDataClientProvider = Provider<PublicDataClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return PublicDataClient(client);
});

typedef PublicDataResponse = ({String? body, Map<String, String> headers});
typedef PublicDataBytes = ({Uint8List? body, Map<String, String> headers});

class PublicDataClient {
  const PublicDataClient(this._client);

  final http.Client _client;
  static const _timeout = Duration(seconds: 12);
  static const _maxBytes = 8 * 1024 * 1024;

  Future<PublicDataResponse> getJson(
    String path, {
    String? etag,
    String? lastModified,
    bool revalidate = false,
  }) async {
    final (body: body, headers: headers) = await getBytes(
      path,
      accept: 'application/json',
      etag: etag,
      lastModified: lastModified,
      revalidate: revalidate,
    );
    return (body: body == null ? null : utf8.decode(body), headers: headers);
  }

  Future<PublicDataBytes> getBytes(
    String path, {
    required String accept,
    String? etag,
    String? lastModified,
    bool revalidate = false,
    Duration timeout = _timeout,
    int maxBytes = _maxBytes,
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      publicDataRoot.replace(path: path),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll({
      'Accept': accept,
      'If-None-Match': ?etag,
      'If-Modified-Since': ?lastModified,
      if (revalidate) 'Cache-Control': 'no-cache',
    });
    try {
      return await _read(request, maxBytes).timeout(timeout);
    } finally {
      abort.complete();
    }
  }

  Future<PublicDataBytes> _read(http.BaseRequest request, int maxBytes) async {
    final response = await _client.send(request);
    if (response.statusCode == 304) {
      await response.stream.drain<void>();
      return (body: null, headers: response.headers);
    }
    if (response.statusCode != 200) {
      throw http.ClientException('公共数据请求失败（HTTP ${response.statusCode}）');
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('公共数据响应过大');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('公共数据响应过大');
      }
      bytes.add(chunk);
    }
    return (body: bytes.takeBytes(), headers: response.headers);
  }
}
