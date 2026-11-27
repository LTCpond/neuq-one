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
  final _routes =
      <CampusResourceId, ({CampusAccessRoute route, DateTime until})>{};
  String? _signature;
  int _networkGeneration = 0;
  Future<void>? _checkingNetwork;
  CampusCancellation? _foreground = CampusCancellation();

  CampusAccessUse openUse() =>
      CampusAccessUse._(this, _webVpn.identity, _webVpn.generation);

  void setForeground(bool foreground) {
    if (foreground) {
      _foreground ??= CampusCancellation();
      refreshNetwork().ignore();
    } else if (_foreground case final previous?) {
      _foreground = null;
      previous.cancel();
      networkChanged();
    }
  }

  void networkChanged() {
    _networkGeneration++;
    _signature = null;
    _directReachableUntil.clear();
    _routes.clear();
    _checkingNetwork = null;
  }

  Future<void> refreshNetwork() {
    final signature = _networkSignature;
    if (signature == null) return Future.value();
    return _checkingNetwork ??= _refreshNetwork(signature);
  }

  Future<void> _refreshNetwork(Future<String?> Function() read) async {
    final generation = _networkGeneration;
    String? current;
    try {
      current = await Future<String?>.microtask(read);
    } catch (_) {
      // With no reliable network identifier, discard observations.
    }
    if (generation != _networkGeneration) return;
    _checkingNetwork = null;
    if (current == null || current != _signature) {
      networkChanged();
      _signature = current;
    }
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

  Uri? webVpnBrowserEntry(CampusResourceId id) {
    final resource = _resources[id];
    if (resource == null ||
        !resource.allowsWebVpn ||
        resource.policy == CampusResourcePolicy.directOnly ||
        _preference() == CampusAccessPreference.directOnly) {
      return null;
    }
    final endpoint = resource.webVpnBrowser;
    if (endpoint == null) return Uri.parse(officialWebVpnUrl);
    return endpoint.scope.host == officialWebVpnHost &&
            endpoint.scope.allows(endpoint.entry)
        ? endpoint.entry
        : null;
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
    final foreground = _foreground;
    if (foreground == null) throw CampusAccessFailure.cancelled;
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
    final unbindForeground = foreground.listen(call.cancel);
    try {
      call.check();
      final choice = _preference();
      final vpnAllowed =
          resource.allowsWebVpn &&
          resource.policy != CampusResourcePolicy.directOnly &&
          choice != CampusAccessPreference.directOnly;
      final vpnReady =
          vpnAllowed && resource.webVpn != null && _webVpn.protocolAvailable;
      final automatic =
          choice == CampusAccessPreference.automatic &&
          resource.policy == CampusResourcePolicy.preferDirect &&
          vpnReady;
      if (vpnReady && resource.policy == CampusResourcePolicy.preferDirect) {
        await call.untilCancelled(refreshNetwork());
      }
      final network = _networkGeneration;
      final canCache =
          automatic && (_networkSignature == null || _signature != null);
      final cached = canCache ? _routes[id] : null;
      final cachedRoute = cached != null && cached.until.isAfter(_now())
          ? cached.route
          : null;

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
        if (_preference() == CampusAccessPreference.directOnly) {
          throw CampusAccessFailure.preferenceBlocked;
        }
        return _webVpnTransport.read(
          resource,
          call,
          acquire: () {
            final previous = active._lease;
            return previous != null && !previous.isReleased
                ? previous
                : active._lease = _webVpn.acquire(active._vpnGeneration);
          },
          onHeaders: onHeaders,
        );
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
            (choice == CampusAccessPreference.preferVpn && vpnReady) ||
            cachedRoute == CampusAccessRoute.webVpn;
        final first = preferVpn
            ? CampusAccessRoute.webVpn
            : CampusAccessRoute.direct;
        try {
          (route, response) = await _readWithFallback(
            id,
            first,
            preferVpn ? vpn : direct,
            preferVpn
                ? direct
                : vpnAllowed
                ? vpn
                : null,
          );
        } on CampusAccessFailure catch (failure) {
          if (failure != CampusAccessFailure.cancelled &&
              cached != null &&
              network == _networkGeneration &&
              _routes[id] == cached) {
            _routes.remove(id);
          }
          rethrow;
        }
      }
      call.check();
      void ensureCurrent() {
        foreground.check();
        active._identity.check();
        use?._cancellation.check();
        cancellation?.check();
        if (route == CampusAccessRoute.webVpn &&
            active._vpnGeneration != _webVpn.generation) {
          throw CampusAccessFailure.cancelled;
        }
      }

      ensureCurrent();
      if (canCache && network == _networkGeneration) {
        _routes[id] = (
          route: route,
          // A hit on the VPN path must not postpone the next direct probe.
          until: route == CampusAccessRoute.webVpn && cachedRoute == route
              ? cached!.until
              : _now().add(CampusAccessLimits.reachability),
        );
      }
      return CampusAccessResult(response, route, ensureCurrent);
    } finally {
      unbindUse();
      unbindCall?.call();
      unbindForeground();
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
    final network = _networkGeneration;
    final canCache = probe && (_networkSignature == null || _signature != null);
    final reachable = _directReachableUntil[id]?.isAfter(_now()) == true;
    try {
      return await _direct.read(
        resource,
        cancellation,
        probe: probe && !reachable,
        onHeaders: (status) {
          if (canCache && _networkGeneration == network) {
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
