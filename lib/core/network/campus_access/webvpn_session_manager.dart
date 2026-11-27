import 'dart:async';

import 'package:http/http.dart' as http;

import '../../auth/school_auth.dart' show NeuqCredentials;
import '../../diagnostics/diagnostics.dart';
import 'campus_resource.dart';
import 'campus_transport.dart';

enum WebVpnPhase {
  disconnected('未连接'),
  connecting('正在连接'),
  connected('已连接'),
  idle('空闲'),
  disconnecting('正在释放会话'),
  expired('会话已过期'),
  verificationRequired('需要在官方门户验证'),
  error('连接异常');

  const WebVpnPhase(this.label);
  final String label;
}

typedef WebVpnState = ({
  WebVpnPhase phase,
  DateTime? idleUntil,
  CampusAccessFailure? failure,
});

abstract interface class WebVpnProtocol {
  /// Complete a school-supported flow and verify the authenticated subject.
  /// The adapter must check cancellation before sending any credentials.
  Future<WebVpnSession> authenticate(WebVpnAuthentication attempt);
}

class WebVpnAuthentication {
  WebVpnAuthentication(this.subject, this.cancellation, this._remembered);

  final String subject;
  final CampusCancellation cancellation;
  final Future<NeuqCredentials?> Function(String) _remembered;
  bool _readCredentials = false;

  /// Use only after a verified CAS flow establishes that a password is needed.
  Future<NeuqCredentials?> readRemembered() async {
    cancellation.check();
    if (_readCredentials) return null;
    _readCredentials = true;
    final credentials = await cancellation.untilCancelled(_remembered(subject));
    cancellation.check();
    return credentials;
  }
}

class WebVpnSession {
  WebVpnSession({required this.subject, required this.httpClient, this.logout});

  final String subject;

  /// A dedicated HTTP client and in-memory cookie jar owned by this session.
  final http.Client httpClient;

  /// Only provide this for a verified logout scoped to this specific session.
  final Future<void> Function(CampusCancellation)? logout;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    httpClient.close();
  }
}

class WebVpnLease {
  WebVpnLease._(this._owner);
  final WebVpnSessionManager _owner;
  bool _released = false;
  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(this);
  }
}

class WebVpnSessionManager {
  WebVpnSessionManager({
    this._protocol,
    required this._readRemembered,
    required this._onState,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final WebVpnProtocol? _protocol;
  final Future<NeuqCredentials?> Function(String) _readRemembered;
  final void Function(WebVpnState) _onState;
  final DateTime Function() _now;
  final _leases = <WebVpnLease>{};
  final _requests = <CampusCancellation>{};

  WebVpnState _state = (
    phase: WebVpnPhase.disconnected,
    idleUntil: null,
    failure: null,
  );
  WebVpnState get state => _state;
  bool get protocolAvailable => _protocol != null;

  String? _subject;
  String? get subject => _subject;
  CampusCancellation _identity = CampusCancellation();
  CampusCancellation get identity => _identity;
  int _generation = 0;
  int get generation => _generation;
  bool _foreground = true;
  bool _disposed = false;

  WebVpnSession? _session;
  ({CampusCancellation cancellation, Future<WebVpnSession> result})?
  _connecting;
  Future<void>? _closing;
  CampusCancellation? _logoutCancellation;
  CampusAccessFailure? _blocked;
  DateTime? _rateLimitedUntil;
  bool _automaticRecoveryUsed = false;

  Duration _idleTimeout = const Duration(
    minutes: CampusAccessLimits.idleMinutes,
  );
  DateTime? _idleSince;
  Timer? _idleTimer;

  void setAccount(String? subject) {
    if (_disposed || _subject == subject) return;
    _subject = subject;
    _identity.cancel();
    _identity = CampusCancellation();
    disconnect();
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) _suspendConsumers();
    _updateIdle();
  }

  void setIdleTimeout(Duration duration) {
    if (_idleTimeout == duration) return;
    _idleTimeout = duration;
    _updateIdle();
  }

  /// Clears a recoverable stop only after an explicit user action.
  /// The next authorized business read decides whether to connect.
  void allowReconnect() {
    if (_disposed || !_foreground || _blocked == null) return;
    if (_rateLimitedUntil?.isAfter(_now()) == true) return;
    _blocked = null;
    _automaticRecoveryUsed = false;
    _publish(WebVpnPhase.disconnected);
  }

  WebVpnLease acquire(int generation) {
    if (_disposed || !_foreground || generation != _generation) {
      throw CampusAccessFailure.cancelled;
    }
    if (_protocol == null) throw CampusAccessFailure.unsupported;
    if (_subject == null) throw CampusAccessFailure.credentialsRequired;
    _updateIdle();
    final lease = WebVpnLease._(this);
    _leases.add(lease);
    _updateIdle();
    return lease;
  }

  void _release(WebVpnLease lease) {
    _leases.remove(lease);
    _updateIdle();
  }

  Future<T> use<T>(
    WebVpnLease lease,
    CampusCancellation cancellation,
    Future<T> Function(WebVpnSession, CampusCancellation) operation, {
    required bool allowRecovery,
  }) async {
    cancellation.check();
    if (!_leases.contains(lease)) throw CampusAccessFailure.cancelled;
    final call = CampusCancellation();
    final unlisten = cancellation.listen(call.cancel);
    _requests.add(call);
    _updateIdle();
    try {
      var session = await call.untilCancelled(_connect());
      try {
        call.check();
        final result = await call.untilCancelled(operation(session, call));
        call.check();
        return result;
      } on CampusAccessFailure catch (failure) {
        call.check();
        if (failure != CampusAccessFailure.vpnSessionExpired) {
          _handleResourceFailure(session, failure);
          rethrow;
        }
        session = await call.untilCancelled(_recover(session, allowRecovery));
        try {
          call.check();
          final result = await call.untilCancelled(operation(session, call));
          call.check();
          return result;
        } on CampusAccessFailure catch (retryFailure) {
          call.check();
          _handleResourceFailure(session, retryFailure);
          rethrow;
        }
      }
    } finally {
      unlisten();
      _requests.remove(call);
      if (_requests.isEmpty && _leases.isEmpty) {
        _connecting?.cancellation.cancel();
      }
      _updateIdle();
    }
  }

  Future<WebVpnSession> _connect() async {
    if (_disposed || !_foreground) throw CampusAccessFailure.cancelled;
    if (_rateLimitedUntil?.isAfter(_now()) == true) {
      throw CampusAccessFailure.rateLimited;
    }
    if (_blocked case final failure?) throw failure;
    if (_session case final session?) return session;
    if (_connecting case final connecting?) return connecting.result;

    final generation = _generation;
    final subject = _subject;
    final protocol = _protocol;
    if (subject == null) throw CampusAccessFailure.credentialsRequired;
    if (protocol == null) throw CampusAccessFailure.unsupported;

    final cancellation = CampusCancellation();
    final result = Future.microtask(
      () => _authenticate(protocol, subject, cancellation, generation),
    );
    _connecting = (cancellation: cancellation, result: result);
    try {
      return await result;
    } finally {
      if (identical(_connecting?.result, result)) _connecting = null;
    }
  }

  Future<WebVpnSession> _authenticate(
    WebVpnProtocol protocol,
    String subject,
    CampusCancellation cancellation,
    int generation,
  ) async {
    try {
      // Wait for an older isolated logout even if a new user has arrived.
      if (_closing case final closing?) {
        await cancellation.untilCancelled(closing);
      }
      cancellation.check();
      _publish(WebVpnPhase.connecting);
      final pending = protocol.authenticate(
        WebVpnAuthentication(subject, cancellation, _readRemembered),
      );
      final checked = pending.then((candidate) {
        try {
          cancellation.check();
          if (_generation != generation || !_foreground || _disposed) {
            throw CampusAccessFailure.cancelled;
          }
          if (candidate.subject != subject) {
            throw CampusAccessFailure.accountMismatch;
          }
          return candidate;
        } catch (_) {
          candidate.close();
          rethrow;
        }
      });
      final session = await cancellation
          .untilCancelled(checked)
          .timeout(
            CampusAccessLimits.authentication,
            onTimeout: () {
              // Mark this attempt before a late adapter result can be accepted.
              cancellation.cancel();
              throw CampusAccessFailure.timeout;
            },
          );
      try {
        cancellation.check();
        _session = session;
      } catch (_) {
        session.close();
        rethrow;
      }
      _publish(WebVpnPhase.connected);
      diagnostics.record(
        DiagnosticModule.webVpn,
        DiagnosticStage.signIn,
        level: DiagnosticSeverity.info,
      );
      return session;
    } catch (error) {
      final failure = classifyCampusError(error);
      if (generation == _generation && !_disposed) {
        if (failure == CampusAccessFailure.cancelled) {
          if (_state.phase == WebVpnPhase.connecting) {
            _publish(WebVpnPhase.disconnected);
          }
        } else {
          _stop(failure);
          diagnostics.record(
            DiagnosticModule.webVpn,
            DiagnosticStage.signIn,
            code: campusFailureCode(failure),
          );
        }
      }
      throw failure;
    }
  }

  Future<WebVpnSession> _recover(WebVpnSession rejected, bool allowed) async {
    if (!identical(_session, rejected)) {
      if (!allowed) throw CampusAccessFailure.vpnSessionExpired;
      return _connect();
    }
    _session = null;
    rejected.close();
    if (!allowed || _automaticRecoveryUsed) {
      _stop(CampusAccessFailure.vpnSessionExpired);
      throw CampusAccessFailure.vpnSessionExpired;
    }
    _automaticRecoveryUsed = true;
    return _connect();
  }

  void _handleResourceFailure(
    WebVpnSession session,
    CampusAccessFailure failure,
  ) {
    if (!identical(_session, session)) return;
    switch (failure) {
      case CampusAccessFailure.vpnSessionExpired ||
          CampusAccessFailure.vpnDisplaced ||
          CampusAccessFailure.accountMismatch ||
          CampusAccessFailure.authenticationRejected ||
          CampusAccessFailure.verificationRequired:
        _session = null;
        session.close();
        _stop(failure);
      default:
        break;
    }
  }

  void _stop(CampusAccessFailure failure) {
    _blocked = failure;
    if (failure == CampusAccessFailure.rateLimited) {
      _rateLimitedUntil = _now().add(CampusAccessLimits.reachability);
    }
    _publish(switch (failure) {
      CampusAccessFailure.verificationRequired =>
        WebVpnPhase.verificationRequired,
      CampusAccessFailure.vpnSessionExpired ||
      CampusAccessFailure.vpnDisplaced => WebVpnPhase.expired,
      _ => WebVpnPhase.error,
    }, failure: failure);
  }

  /// A credentials deletion only cancels authentication already in progress.
  void cancelAuthentication() => _connecting?.cancellation.cancel();

  void _suspendConsumers() {
    _connecting?.cancellation.cancel();
    for (final call in _requests) {
      call.cancel();
    }
    for (final lease in _leases.toList()) {
      lease.release();
    }
  }

  void _updateIdle() {
    _idleTimer?.cancel();
    if (_session == null || _disposed) return;
    if (_requests.isNotEmpty || _leases.isNotEmpty) {
      _idleSince = null;
      if (_state.phase == WebVpnPhase.idle) _publish(WebVpnPhase.connected);
      return;
    }
    final now = _now();
    final deadline = (_idleSince ??= now).add(_idleTimeout);
    if (!now.isBefore(deadline)) {
      diagnostics.record(
        DiagnosticModule.webVpn,
        DiagnosticStage.clear,
        level: DiagnosticSeverity.info,
        code: DiagnosticCode.idleRelease,
      );
      _retire();
      return;
    }
    _publish(WebVpnPhase.idle, idleUntil: deadline);
    if (_foreground) _idleTimer = Timer(deadline.difference(now), _updateIdle);
  }

  Future<void> disconnect() {
    if (_disposed) return Future.value();
    _generation++;
    _blocked = null;
    _automaticRecoveryUsed = false;
    _suspendConsumers();
    _connecting = null;
    return _retire();
  }

  Future<void> _retire() {
    final session = _session;
    _session = null;
    _idleSince = null;
    _idleTimer?.cancel();
    if (session == null) {
      if (_closing case final closing?) return closing;
      _publish(WebVpnPhase.disconnected);
      return Future.value();
    }
    _automaticRecoveryUsed = false;
    if (session.logout == null || !_foreground) {
      session.close();
      _publish(WebVpnPhase.disconnected);
      return Future.value();
    }

    final result = Future<void>.microtask(() => _logout(session));
    _closing = result;
    _publish(WebVpnPhase.disconnecting);
    return result.whenComplete(() {
      if (!identical(_closing, result)) return;
      _closing = null;
      if (_state.phase == WebVpnPhase.disconnecting) {
        _publish(WebVpnPhase.disconnected);
      }
    });
  }

  Future<void> _logout(WebVpnSession session) async {
    if (_disposed) {
      session.close();
      return;
    }
    final cancellation = CampusCancellation();
    _logoutCancellation = cancellation;
    try {
      await cancellation
          .untilCancelled(session.logout!(cancellation))
          .timeout(CampusAccessLimits.logout);
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.webVpn,
        DiagnosticStage.clear,
        code: campusFailureCode(classifyCampusError(error)),
      );
    } finally {
      cancellation.cancel();
      session.close();
      if (identical(_logoutCancellation, cancellation)) {
        _logoutCancellation = null;
      }
    }
  }

  void _publish(
    WebVpnPhase phase, {
    DateTime? idleUntil,
    CampusAccessFailure? failure,
  }) {
    if (_disposed) return;
    final next = (phase: phase, idleUntil: idleUntil, failure: failure);
    if (next == _state) return;
    _state = next;
    _onState(next);
  }

  void dispose() {
    _disposed = true;
    _identity.cancel();
    _suspendConsumers();
    _logoutCancellation?.cancel();
    _idleTimer?.cancel();
    _session?.close();
    _session = null;
  }
}

DiagnosticCode campusFailureCode(CampusAccessFailure failure) =>
    switch (failure) {
      CampusAccessFailure.unreachable => DiagnosticCode.connectionFailed,
      CampusAccessFailure.dns => DiagnosticCode.dnsFailure,
      CampusAccessFailure.timeout => DiagnosticCode.timeout,
      CampusAccessFailure.businessSessionExpired =>
        DiagnosticCode.sessionExpired,
      CampusAccessFailure.vpnSessionExpired ||
      CampusAccessFailure.vpnDisplaced => DiagnosticCode.vpnExpired,
      CampusAccessFailure.verificationRequired =>
        DiagnosticCode.verificationRequired,
      CampusAccessFailure.unauthorized => DiagnosticCode.permissionDenied,
      CampusAccessFailure.accountMismatch ||
      CampusAccessFailure.credentialsRequired ||
      CampusAccessFailure.authenticationRejected => DiagnosticCode.rejected,
      CampusAccessFailure.rateLimited => DiagnosticCode.rateLimited,
      CampusAccessFailure.server => DiagnosticCode.serverError,
      CampusAccessFailure.invalidResponse => DiagnosticCode.invalidData,
      CampusAccessFailure.unsafeEndpoint => DiagnosticCode.unsafeEndpoint,
      CampusAccessFailure.unsupported => DiagnosticCode.unsupportedProtocol,
      CampusAccessFailure.preferenceBlocked => DiagnosticCode.unavailable,
      CampusAccessFailure.cancelled => DiagnosticCode.recoveryCancelled,
    };
