import '../../diagnostics/diagnostics.dart';
import 'campus_resource.dart';
import 'campus_transport.dart';
import 'webvpn_session_manager.dart';
import 'webvpn_transport.dart';

class CampusAccessUse {
  CampusAccessUse._(this._owner, this._identity, this._vpnGeneration) {
    _unbind = _identity.listen(close);
  }

  final CampusAccessClient _owner;
  final CampusCancellation _identity;
  final int _vpnGeneration;
  final _cancellation = CampusCancellation();
  void Function()? _unbind;
  WebVpnLease? _lease;

  /// Call on route visibility loss, operation cancellation or disposal.
  void close() {
    _cancellation.cancel();
    _lease?.release();
    _unbind?.call();
  }
}

class CampusAccessResult {
  const CampusAccessResult(this.response, this.route, this.ensureCurrent);

  final CampusResponse response;
  final CampusAccessRoute route;

  /// Recheck inside the account-scoped cache transaction before writing.
  final void Function() ensureCurrent;
}

class CampusAccessClient {
  CampusAccessClient({
    required Map<CampusResourceId, CampusResource> resources,
    required this._direct,
    required WebVpnSessionManager webVpn,
    required this._preference,
    this._networkSignature,
    DateTime Function()? clock,
  }) : _resources = Map.unmodifiable(resources),
       _webVpn = webVpn,
       _webVpnTransport = WebVpnTransport(webVpn),
       _now = clock ?? DateTime.now;

  final Map<CampusResourceId, CampusResource> _resources;
  final DirectTransport _direct;
  final WebVpnSessionManager _webVpn;
  final WebVpnTransport _webVpnTransport;
  final CampusAccessPreference Function() _preference;
  final Future<String?> Function()? _networkSignature;
  final DateTime Function() _now;
  final _directReachableUntil = <CampusResourceId, DateTime>{};
  String? _signature;
  int _networkGeneration = 0;

  CampusAccessUse openUse() =>
      CampusAccessUse._(this, _webVpn.identity, _webVpn.generation);

  void networkChanged() {
    _networkGeneration++;
    _signature = null;
    _directReachableUntil.clear();
  }

  /// Returns a scoped official browser entry for a registered direct resource.
  Uri directEntry(CampusResourceId id) {
    final resource = _resources[id];
    if (resource == null || resource.policy == CampusResourcePolicy.vpnOnly) {
      throw CampusAccessFailure.unsupported;
    }
    final endpoint = resource.direct;
    if (!endpoint.scope.allows(endpoint.entry)) {
      throw CampusAccessFailure.unsafeEndpoint;
    }
    return endpoint.entry;
  }

  /// CampusAccess only accepts fixed, read-only registrations. Write
  /// operations such as payments or reservations belong to their own clients.
  Future<CampusAccessResult> read(
    CampusResourceId id, {
    CampusAccessUse? use,
    CampusCancellation? cancellation,
  }) async {
    final resource = _resources[id];
    if (resource == null) throw CampusAccessFailure.unsupported;
    if (resource.requiresAuthentication && _webVpn.subject == null) {
      throw CampusAccessFailure.credentialsRequired;
    }
    if (use != null && !identical(use._owner, this)) {
      throw CampusAccessFailure.cancelled;
    }
    final active = use ?? openUse();
    final call = CampusCancellation();
    final unbindUse = active._cancellation.listen(call.cancel);
    final unbindCall = cancellation?.listen(call.cancel);
    try {
      call.check();
      final choice = _preference();
      final vpnAllowed =
          resource.allowsWebVpn &&
          resource.policy != CampusResourcePolicy.directOnly &&
          choice != CampusAccessPreference.directOnly;
      final vpnReady =
          vpnAllowed && resource.webVpn != null && _webVpn.protocolAvailable;

      Future<CampusResponse> direct(void Function(int) onHeaders) =>
          _readDirect(
            id,
            resource,
            call,
            probe: vpnReady,
            onHeaders: onHeaders,
          );

      Future<CampusResponse> vpn(void Function(int) onHeaders) async {
        call.check();
        if (active._vpnGeneration != _webVpn.generation) {
          throw CampusAccessFailure.cancelled;
        }
        WebVpnLease? acquired;
        try {
          return await _webVpnTransport.read(
            resource,
            call,
            acquire: () {
              final previous = active._lease;
              return acquired = previous != null && !previous.isReleased
                  ? previous
                  : active._lease = _webVpn.acquire(active._vpnGeneration);
            },
            onHeaders: onHeaders,
          );
        } catch (_) {
          acquired?.release();
          rethrow;
        }
      }

      final CampusAccessRoute route;
      final CampusResponse response;
      if (resource.policy == CampusResourcePolicy.vpnOnly) {
        if (choice == CampusAccessPreference.directOnly) {
          throw CampusAccessFailure.preferenceBlocked;
        }
        route = CampusAccessRoute.webVpn;
        response = await _readRoute(id, route, vpn);
      } else {
        final preferVpn =
            choice == CampusAccessPreference.preferVpn && vpnReady;
        final first = preferVpn
            ? CampusAccessRoute.webVpn
            : CampusAccessRoute.direct;
        final (selected, data) = await _readWithFallback(
          id,
          first,
          preferVpn ? vpn : direct,
          preferVpn
              ? direct
              : vpnAllowed
              ? vpn
              : null,
        );
        route = selected;
        response = data;
      }
      call.check();
      void ensureCurrent() {
        active._identity.check();
        use?._cancellation.check();
        cancellation?.check();
        if (route == CampusAccessRoute.webVpn &&
            active._vpnGeneration != _webVpn.generation) {
          throw CampusAccessFailure.cancelled;
        }
      }

      ensureCurrent();
      return CampusAccessResult(response, route, ensureCurrent);
    } finally {
      unbindUse();
      unbindCall?.call();
      if (use == null) active.close();
    }
  }

  Future<(CampusAccessRoute, CampusResponse)> _readWithFallback(
    CampusResourceId id,
    CampusAccessRoute first,
    Future<CampusResponse> Function(void Function(int)) primary,
    Future<CampusResponse> Function(void Function(int))? fallback,
  ) async {
    try {
      return (first, await _readRoute(id, first, primary));
    } on CampusAccessFailure catch (failure) {
      if (fallback == null || !failure.isReachabilityFailure) rethrow;
      final next = first == CampusAccessRoute.direct
          ? CampusAccessRoute.webVpn
          : CampusAccessRoute.direct;
      diagnostics.record(
        DiagnosticModule.campusAccess,
        DiagnosticStage.request,
        level: DiagnosticSeverity.info,
        resource: id,
        route: next,
        code: DiagnosticCode.sourceSwitch,
      );
      return (next, await _readRoute(id, next, fallback));
    }
  }

  Future<CampusResponse> _readDirect(
    CampusResourceId id,
    CampusResource resource,
    CampusCancellation cancellation, {
    required bool probe,
    required void Function(int) onHeaders,
  }) async {
    if (probe && _networkSignature != null) {
      final signature = await cancellation.untilCancelled(_networkSignature());
      if (_signature != signature || signature == null) {
        networkChanged();
        _signature = signature;
      }
    }
    final network = _networkGeneration;
    final reachable = _directReachableUntil[id]?.isAfter(_now()) == true;
    try {
      return await _direct.read(
        resource,
        cancellation,
        probe: probe && !reachable,
        onHeaders: (status) {
          if (probe && _networkGeneration == network) {
            _directReachableUntil[id] = _now().add(
              CampusAccessLimits.reachability,
            );
          }
          onHeaders(status);
        },
      );
    } on CampusAccessFailure catch (failure) {
      if (failure.isReachabilityFailure && _networkGeneration == network) {
        _directReachableUntil.remove(id);
      }
      rethrow;
    }
  }

  Future<CampusResponse> _readRoute(
    CampusResourceId id,
    CampusAccessRoute route,
    Future<CampusResponse> Function(void Function(int)) read,
  ) async {
    final watch = Stopwatch()..start();
    int? status;
    CampusAccessFailure? failure;
    try {
      return await read((value) => status = value);
    } catch (error) {
      failure = classifyCampusError(error);
      throw failure;
    } finally {
      diagnostics.record(
        DiagnosticModule.campusAccess,
        DiagnosticStage.request,
        level: failure == null
            ? DiagnosticSeverity.debug
            : DiagnosticSeverity.warn,
        resource: id,
        route: route,
        elapsedMs: watch.elapsedMilliseconds,
        httpStatus: status,
        code: failure == null
            ? DiagnosticCode.completed
            : campusFailureCode(failure),
      );
    }
  }
}
