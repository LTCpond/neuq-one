import 'campus_resource.dart';
import 'campus_transport.dart';
import 'webvpn_session_manager.dart';

class WebVpnTransport {
  const WebVpnTransport(this._manager);

  final WebVpnSessionManager _manager;

  Future<CampusResponse> read(
    CampusResource resource,
    CampusCancellation cancellation, {
    required WebVpnLease Function() acquire,
    required void Function(int) onHeaders,
  }) async {
    final endpoint = resource.webVpn;
    if (!resource.allowsWebVpn ||
        endpoint == null ||
        !_manager.protocolAvailable) {
      throw CampusAccessFailure.unsupported;
    }
    if (endpoint.scope.host != officialWebVpnHost ||
        !endpoint.scope.allows(endpoint.entry)) {
      throw CampusAccessFailure.unsafeEndpoint;
    }
    return _manager.use(
      acquire(),
      cancellation,
      (session, cancellation) => readCampusEndpoint(
        session.httpClient,
        endpoint,
        cancellation,
        timeout: resource.timeout,
        authenticatedResource: resource.requiresAuthentication,
        viaWebVpn: true,
        onHeaders: onHeaders,
      ),
      allowRecovery: resource.allowVpnRecovery,
    );
  }
}
