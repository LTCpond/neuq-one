import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'campus_resource.dart';

class DirectTransport {
  const DirectTransport(this._http);

  final http.Client _http;

  Future<CampusResponse> read(
    CampusResource resource,
    CampusCancellation cancellation, {
    required bool probe,
    required void Function(int) onHeaders,
  }) => readCampusEndpoint(
    _http,
    resource.direct,
    cancellation,
    timeout: resource.timeout,
    probe: probe,
    authenticatedResource: resource.requiresAuthentication,
    onHeaders: onHeaders,
  );
}

Future<CampusResponse> readCampusEndpoint(
  http.Client client,
  CampusEndpoint endpoint,
  CampusCancellation cancellation, {
  required Duration timeout,
  required bool authenticatedResource,
  required void Function(int) onHeaders,
  bool probe = false,
  bool viaWebVpn = false,
}) async {
  cancellation.check();
  final request = CampusCancellation();
  final unbind = cancellation.listen(request.cancel);
  final abort = Completer<void>();
  final unlisten = request.listen(() {
    if (!abort.isCompleted) abort.complete();
  });
  var receivedHeaders = false;
  try {
    return await request.untilCancelled(
      _read(
        client,
        endpoint,
        request,
        abort.future,
        probe: probe,
        viaWebVpn: viaWebVpn,
        authenticatedResource: authenticatedResource,
        onHeaders: (status) {
          receivedHeaders = true;
          onHeaders(status);
        },
      ).timeout(timeout),
    );
  } on CampusAccessFailure {
    rethrow;
  } catch (error) {
    cancellation.check();
    final failure = classifyCampusError(error);
    if (receivedHeaders && failure.isReachabilityFailure) {
      throw CampusAccessFailure.responseInterrupted;
    }
    throw failure;
  } finally {
    unbind();
    request.cancel();
    unlisten();
  }
}

Future<CampusResponse> _read(
  http.Client client,
  CampusEndpoint endpoint,
  CampusCancellation cancellation,
  Future<void> abort, {
  required bool probe,
  required bool viaWebVpn,
  required bool authenticatedResource,
  required void Function(int) onHeaders,
}) async {
  var target = endpoint.entry;
  for (
    var redirects = 0;
    redirects <= CampusAccessLimits.redirects;
    redirects++
  ) {
    cancellation.check();
    if (!endpoint.scope.allows(target) ||
        (viaWebVpn && target.host != officialWebVpnHost)) {
      throw CampusAccessFailure.unsafeEndpoint;
    }
    final sending = client.send(
      http.AbortableRequest('GET', target, abortTrigger: abort)
        ..followRedirects = false,
    );
    final response = await (probe && redirects == 0
        ? sending.timeout(CampusAccessLimits.directProbe)
        : sending);
    try {
      cancellation.check();
    } on CampusAccessFailure {
      response.stream.listen(null).cancel().ignore();
      rethrow;
    }
    final status = response.statusCode;
    onHeaders(status);
    if (const {301, 302, 303, 307, 308}.contains(status)) {
      response.stream.listen(null).cancel().ignore();
      final location = response.headers['location'];
      if (location == null ||
          location.trim().isEmpty ||
          location.contains(r'\')) {
        throw CampusAccessFailure.invalidResponse;
      }
      target = target.resolve(location);
      if (viaWebVpn && endpoint.vpnLogin?.allows(target) == true) {
        throw CampusAccessFailure.vpnSessionExpired;
      }
      if (endpoint.businessLogin?.allows(target) == true) {
        throw CampusAccessFailure.businessSessionExpired;
      }
      continue;
    }
    if (status == 429 || status >= 500) {
      response.stream.listen(null).cancel().ignore();
      throw status == 429
          ? CampusAccessFailure.rateLimited
          : CampusAccessFailure.server;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      cancellation.check();
      if (bytes.length + chunk.length > CampusAccessLimits.responseBytes) {
        throw CampusAccessFailure.invalidResponse;
      }
      bytes.add(chunk);
    }
    final result = CampusResponse(
      status,
      Map.unmodifiable({
        for (final name in ['content-type', 'etag', 'last-modified'])
          name: ?response.headers[name],
      }),
      bytes.takeBytes(),
    );
    final classified = endpoint.classify?.call(result);
    if (classified != null) throw classified;
    if (status == 401 && authenticatedResource) {
      throw CampusAccessFailure.businessSessionExpired;
    }
    if (status == 401 || status == 403) throw CampusAccessFailure.unauthorized;
    if (status < 200 || status >= 300) {
      throw CampusAccessFailure.invalidResponse;
    }
    cancellation.check();
    return result;
  }
  throw CampusAccessFailure.invalidResponse;
}

CampusAccessFailure classifyCampusError(Object error) {
  if (error is CampusAccessFailure) return error;
  if (error is http.RequestAbortedException) {
    return CampusAccessFailure.cancelled;
  }
  if (error is TimeoutException) return CampusAccessFailure.timeout;
  if (error is HandshakeException || error is TlsException) {
    return CampusAccessFailure.unsafeEndpoint;
  }
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    return message.contains('host lookup') ||
            message.contains('name resolution') ||
            message.contains('name or service not known')
        ? CampusAccessFailure.dns
        : CampusAccessFailure.unreachable;
  }
  if (error is http.ClientException) return CampusAccessFailure.unreachable;
  return CampusAccessFailure.invalidResponse;
}
