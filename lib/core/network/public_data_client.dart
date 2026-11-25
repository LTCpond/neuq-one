import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final publicDataRoot = Uri.https('neuq-one-data.pages.dev');

final publicDataClientProvider = Provider<PublicDataClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return PublicDataClient(client);
});

typedef PublicDataResponse = ({String? body, Map<String, String> headers});

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
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      publicDataRoot.replace(path: path),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'If-None-Match': ?etag,
      'If-Modified-Since': ?lastModified,
      if (revalidate) 'Cache-Control': 'no-cache',
    });
    try {
      return await _read(request).timeout(_timeout);
    } finally {
      abort.complete();
    }
  }

  Future<PublicDataResponse> _read(http.BaseRequest request) async {
    final response = await _client.send(request);
    if (response.statusCode == 304) {
      await response.stream.drain<void>();
      return (body: null, headers: response.headers);
    }
    if (response.statusCode != 200) {
      throw http.ClientException('公共数据请求失败（HTTP ${response.statusCode}）');
    }
    if ((response.contentLength ?? 0) > _maxBytes) {
      throw const FormatException('公共数据响应过大');
    }
    final bytes = await response.stream.fold(<int>[], (bytes, chunk) {
      if (bytes.length + chunk.length > _maxBytes) {
        throw const FormatException('公共数据响应过大');
      }
      return bytes..addAll(chunk);
    });
    return (body: utf8.decode(bytes), headers: response.headers);
  }
}
