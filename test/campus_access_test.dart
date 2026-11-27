import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/core/auth/school_auth.dart';
import 'package:neuq_one/core/diagnostics/diagnostics.dart';
import 'package:neuq_one/core/network/campus_access/campus_access_client.dart';
import 'package:neuq_one/core/network/campus_access/campus_access_providers.dart';
import 'package:neuq_one/core/network/campus_access/campus_resource.dart';
import 'package:neuq_one/core/network/campus_access/campus_transport.dart';
import 'package:neuq_one/core/network/campus_access/webvpn_session_manager.dart';
import 'package:neuq_one/core/storage/settings.dart';
import 'package:neuq_one/features/profile/presentation/webvpn_settings_page.dart';
import 'package:neuq_one/features/services/presentation/campus_resource_panel.dart';

const _academic = CampusResourceId.academic;
const _guide = CampusResourceId.webVpnGuide;
const _subject = 'synthetic-subject';
const _directHost = 'academic.neuq.edu.cn';
const _vpnPath = '/fixture/academic';
const _directScope = CampusUrlScope(_directHost, '/academic', subtree: true);
const _vpnScope = CampusUrlScope(officialWebVpnHost, _vpnPath, subtree: true);

CampusResource _resource({
  CampusResourcePolicy policy = CampusResourcePolicy.preferDirect,
  bool allowsWebVpn = true,
  bool configured = true,
  bool allowRecovery = true,
  CampusEndpoint? vpn,
}) => CampusResource(
  direct: CampusEndpoint(
    entry: Uri.https(_directHost, '/academic/data'),
    scope: _directScope,
    businessLogin: const CampusUrlScope('ids.neuq.edu.cn', '/authserver/login'),
  ),
  policy: policy,
  requiresAuthentication: true,
  allowsWebVpn: allowsWebVpn,
  webVpn: configured
      ? vpn ??
            CampusEndpoint(
              entry: Uri.https(officialWebVpnHost, '$_vpnPath/data'),
              scope: _vpnScope,
              vpnLogin: const CampusUrlScope(
                officialWebVpnHost,
                '/fixture/auth-required',
              ),
              classify: (response) => switch (utf8.decode(response.bytes)) {
                'synthetic-displaced' => CampusAccessFailure.vpnDisplaced,
                'synthetic-verification' =>
                  CampusAccessFailure.verificationRequired,
                'synthetic-invalid' => CampusAccessFailure.invalidResponse,
                _ => null,
              },
            )
      : null,
  allowVpnRecovery: allowRecovery,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'direct success and direct-only public requests do not authenticate',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final access = fixture.access;
      expect((await access.read(_academic)).route, CampusAccessRoute.direct);
      final public = access.read(_guide);
      expect((await public).route, CampusAccessRoute.direct);
      expect(fixture.protocol.attempts, 0);
      expect(fixture.manager.state.phase, WebVpnPhase.disconnected);
    },
  );

  test(
    'registered resource falls back only on a reachability failure',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.direct = (_) async =>
          throw const SocketException('Failed host lookup');
      final result = await fixture.access.read(_academic);
      expect(result.route, CampusAccessRoute.webVpn);
      expect(utf8.decode(result.response.bytes), 'vpn response');
      expect(fixture.protocol.attempts, 1);
      expect(fixture.directRequests, 1);
      expect(fixture.vpnRequests, 1);
      expect(fixture.manager.state.phase, WebVpnPhase.idle);
    },
  );

  test('a changed network invalidates cached direct reachability', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    var network = 'fixture-network-one';
    final access = fixture.client(
      _resource(),
      networkSignature: () async => network,
    );
    expect((await access.read(_academic)).route, CampusAccessRoute.direct);

    final sameNetwork = Completer<http.Response>();
    final started = Completer<void>();
    fixture.direct = (_) {
      started.complete();
      return sameNetwork.future;
    };
    final slowerRead = access.read(_academic);
    await started.future;
    await Future<void>.delayed(
      CampusAccessLimits.directProbe + const Duration(milliseconds: 50),
    );
    expect(fixture.protocol.attempts, 0);
    sameNetwork.complete(http.Response('direct', 200));
    expect((await slowerRead).route, CampusAccessRoute.direct);

    network = 'fixture-network-two';
    final otherNetwork = Completer<http.Response>();
    fixture.direct = (_) => otherNetwork.future;
    final switched = access.read(_academic);
    expect((await switched).route, CampusAccessRoute.webVpn);
    otherNetwork.complete(http.Response('too late', 200));
  });

  test(
    'automatic VPN path is per resource and expires despite cache hits',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final access = fixture.client(_resource(), second: _resource());
      fixture.direct = (_) async => throw const SocketException('no route');
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      fixture.direct = (_) async => http.Response('direct', 200);
      expect((await access.read(_guide)).route, CampusAccessRoute.direct);

      fixture.advance(const Duration(minutes: 4));
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      expect(fixture.directRequests, 2);
      expect(fixture.protocol.attempts, 1);
      fixture.advance(const Duration(minutes: 1));
      expect((await access.read(_academic)).route, CampusAccessRoute.direct);
      expect(fixture.directRequests, 3);
    },
  );

  test(
    'network changes, user preference and VPN failure reassess the cached path',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      String? network = 'wifi';
      final access = fixture.client(
        _resource(),
        networkSignature: () async => network,
      );
      fixture.direct = (_) async => throw const SocketException('no route');
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);

      fixture.preference = CampusAccessPreference.directOnly;
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.unreachable),
      );
      expect(fixture.vpnRequests, 1);
      fixture.preference = CampusAccessPreference.automatic;
      fixture.direct = (_) async => http.Response('direct', 200);
      fixture.vpn = (_) async => throw const SocketException('no route');
      expect((await access.read(_academic)).route, CampusAccessRoute.direct);
      expect(fixture.vpnRequests, 2);

      fixture.vpn = (_) async => http.Response('vpn', 200);
      fixture.direct = (_) async => throw const SocketException('no route');
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      network = 'mobile';
      fixture.direct = (_) async => http.Response('direct', 200);
      expect((await access.read(_academic)).route, CampusAccessRoute.direct);

      network = null;
      fixture.direct = (_) async => throw const SocketException('no route');
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      fixture.direct = (_) async => http.Response('direct', 200);
      expect((await access.read(_academic)).route, CampusAccessRoute.direct);
    },
  );

  test('a failed preferred read discards the cached path without replaying a denial', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final access = fixture.access;
    fixture.direct = (_) async => throw const SocketException('no route');
    await access.read(_academic);
    fixture.vpn = (_) async => http.Response('denied', 403);
    fixture.direct = (_) async => http.Response('direct', 200);
    await expectLater(
      access.read(_academic),
      throwsA(CampusAccessFailure.unauthorized),
    );
    expect(fixture.directRequests, 1);
    expect((await access.read(_academic)).route, CampusAccessRoute.direct);
  });

  test('background cancels direct work and foreground checks the network without VPN authentication', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    var checks = 0;
    final access = fixture.client(
      _resource(),
      networkSignature: () async => 'network-${++checks}',
    );
    final started = Completer<void>();
    final response = Completer<http.Response>();
    fixture.direct = (_) {
      started.complete();
      return response.future;
    };
    final pending = access.read(_academic);
    await started.future;
    access.setForeground(true);
    await access.refreshNetwork();
    final cancelled = expectLater(
      pending,
      throwsA(CampusAccessFailure.cancelled),
    );
    access.setForeground(false);
    await cancelled;
    await expectLater(
      access.read(_academic),
      throwsA(CampusAccessFailure.cancelled),
    );
    response.complete(http.Response('late', 200));
    access.setForeground(true);
    await access.refreshNetwork();
    expect(checks, 3);
    expect(fixture.protocol.attempts, 0);
  });

  test(
    'an identity change invalidates direct results and cancels in-flight reads',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final access = fixture.access;
      final previous = await access.read(_academic);
      final started = Completer<void>();
      final finish = Completer<http.Response>();
      fixture.direct = (_) {
        started.complete();
        return finish.future;
      };
      final pending = access.read(_academic);
      await started.future;
      final cancelled = expectLater(
        pending,
        throwsA(CampusAccessFailure.cancelled),
      );
      fixture.manager.setAccount('new-synthetic-subject');
      expect(previous.ensureCurrent, throwsA(CampusAccessFailure.cancelled));
      await cancelled;
      finish.complete(http.Response('stale response', 200));
      expect(fixture.protocol.attempts, 0);
    },
  );

  test(
    'business login, denial and server errors never trigger VPN fallback',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final access = fixture.access;
      for (final (response, failure) in [
        (
          http.Response(
            '',
            302,
            headers: {'location': 'https://ids.neuq.edu.cn/authserver/login'},
          ),
          CampusAccessFailure.businessSessionExpired,
        ),
        (http.Response('', 401), CampusAccessFailure.businessSessionExpired),
        (http.Response('', 403), CampusAccessFailure.unauthorized),
        (http.Response('', 429), CampusAccessFailure.rateLimited),
        (http.Response('', 503), CampusAccessFailure.server),
      ]) {
        fixture.direct = (_) async => response;
        await expectLater(access.read(_academic), throwsA(failure));
      }
      expect(fixture.directRequests, 5);
      expect(fixture.protocol.attempts, 0);
    },
  );

  test(
    'response body interruption after headers never triggers VPN fallback',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final direct = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream<List<int>>.error(
            const SocketException('fixture body interrupted'),
          ),
          200,
        ),
      );
      addTearDown(direct.close);
      final access = CampusAccessClient(
        resources: {_academic: _resource()},
        direct: DirectTransport(direct),
        webVpn: fixture.manager,
        preference: () => CampusAccessPreference.automatic,
      );
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.responseInterrupted),
      );
      expect(fixture.protocol.attempts, 0);
    },
  );

  test(
    'access preferences respect resource rules and missing authorization',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.direct = (_) async => throw const SocketException('offline');
      await expectLater(
        fixture.client(_resource(allowsWebVpn: false)).read(_academic),
        throwsA(CampusAccessFailure.unreachable),
      );
      await expectLater(
        fixture.client(_resource(configured: false)).read(_academic),
        throwsA(CampusAccessFailure.unsupported),
      );
      fixture.preference = CampusAccessPreference.directOnly;
      await expectLater(
        fixture
            .client(_resource(policy: CampusResourcePolicy.vpnOnly))
            .read(_academic),
        throwsA(CampusAccessFailure.preferenceBlocked),
      );
      expect(fixture.protocol.attempts, 0);

      fixture.preference = CampusAccessPreference.preferVpn;
      final directBefore = fixture.directRequests;
      expect(
        (await fixture.access.read(_academic)).route,
        CampusAccessRoute.webVpn,
      );
      expect(fixture.directRequests, directBefore);
    },
  );

  test(
    'VPN fallback without a verified native protocol fails closed',
    () async {
      final fixture = _Fixture(protocolAvailable: false);
      addTearDown(fixture.dispose);
      fixture.direct = (_) async => throw const SocketException('offline');
      await expectLater(
        fixture.access.read(_academic),
        throwsA(CampusAccessFailure.unsupported),
      );
      expect(fixture.protocol.attempts, 0);
      expect(fixture.manager.state.phase, WebVpnPhase.disconnected);
    },
  );

  test(
    'parallel requests for different resources share one authentication',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final started = Completer<void>();
      final resume = Completer<void>();
      fixture.protocol.before = (_) async {
        started.complete();
        await resume.future;
      };
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
        second: CampusResource(
          direct: _resource().direct,
          webVpn: CampusEndpoint(
            entry: Uri.https(officialWebVpnHost, '/fixture/library/index'),
            scope: const CampusUrlScope(
              officialWebVpnHost,
              '/fixture/library',
              subtree: true,
            ),
          ),
          policy: CampusResourcePolicy.vpnOnly,
          allowsWebVpn: true,
        ),
      );
      final first = access.openUse();
      final second = access.openUse();
      final reads = [
        access.read(_academic, use: first),
        access.read(_guide, use: second),
      ];
      await started.future;
      expect(fixture.manager.state.phase, WebVpnPhase.connecting);
      expect(fixture.protocol.attempts, 1);
      resume.complete();
      await Future.wait(reads);
      expect(fixture.vpnRequests, 2);
      first.close();
      first.close();
      expect(fixture.manager.state.phase, WebVpnPhase.connected);
      second.close();
      expect(fixture.manager.state.phase, WebVpnPhase.idle);
    },
  );

  testWidgets('idle starts after the last lease and last request finish', (
    tester,
  ) async {
    final fixture = _Fixture();
    final manager = fixture.manager;
    try {
      final first = manager.acquire(manager.generation);
      final second = manager.acquire(manager.generation);
      final started = Completer<void>();
      final finish = Completer<void>();
      final pending = manager.use(first, CampusCancellation(), (_, _) async {
        started.complete();
        await finish.future;
      }, allowRecovery: true);
      await started.future;
      first.release();
      second.release();
      second.release();
      expect(manager.state.phase, WebVpnPhase.connected);
      fixture.advance(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 6));
      expect(fixture.protocol.closed, 0);

      finish.complete();
      await pending;
      expect(
        manager.state.idleUntil,
        fixture.now.add(const Duration(minutes: 5)),
      );
      fixture.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      final again = manager.acquire(manager.generation);
      await manager.use(
        again,
        CampusCancellation(),
        (_, _) async {},
        allowRecovery: true,
      );
      expect(fixture.protocol.attempts, 1);
      again.release();
      fixture.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      expect(manager.state.phase, WebVpnPhase.disconnected);
      expect(fixture.protocol.closed, 1);
    } finally {
      fixture.dispose();
    }
  });

  testWidgets(
    'background pauses consumers and resume clears elapsed idle time without login',
    (tester) async {
      final fixture = _Fixture();
      final manager = fixture.manager;
      try {
        final lease = manager.acquire(manager.generation);
        await manager.use(
          lease,
          CampusCancellation(),
          (_, _) async {},
          allowRecovery: true,
        );
        manager.setForeground(false);
        expect(lease.isReleased, isTrue);
        expect(manager.state.phase, WebVpnPhase.idle);
        expect(
          () => manager.acquire(manager.generation),
          throwsA(CampusAccessFailure.cancelled),
        );
        fixture.advance(const Duration(minutes: 7));
        await tester.pump(const Duration(minutes: 7));
        expect(fixture.protocol.closed, 0);
        expect(fixture.protocol.attempts, 1);
        manager.setForeground(true);
        expect(manager.state.phase, WebVpnPhase.disconnected);
        expect(fixture.protocol.closed, 1);
        expect(fixture.protocol.attempts, 1);
      } finally {
        fixture.dispose();
      }
    },
  );

  test(
    'a rejected replay expires the VPN and stops automatic authentication',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.vpn = (_) async => http.Response(
        '',
        302,
        headers: {'location': '/fixture/auth-required'},
      );
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.vpnSessionExpired),
      );
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.vpnSessionExpired),
      );
      expect(fixture.vpnRequests, 2);
      expect(fixture.protocol.attempts, 2);
      expect(fixture.manager.state.phase, WebVpnPhase.expired);
    },
  );

  test(
    'per-resource opt-out disables recovery and displacement always stops',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.vpn = (_) async => http.Response(
        '',
        302,
        headers: {'location': '/fixture/auth-required'},
      );
      await expectLater(
        fixture
            .client(
              _resource(
                policy: CampusResourcePolicy.vpnOnly,
                allowRecovery: false,
              ),
            )
            .read(_academic),
        throwsA(CampusAccessFailure.vpnSessionExpired),
      );
      expect(fixture.protocol.attempts, 1);
      fixture.manager.allowReconnect();
      fixture.vpn = (_) async => http.Response('synthetic-displaced', 200);
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          access.read(_academic),
          throwsA(CampusAccessFailure.vpnDisplaced),
        );
      }
      expect(fixture.protocol.attempts, 2);
      fixture.manager.allowReconnect(
        expectedFailure: CampusAccessFailure.timeout,
      );
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.vpnDisplaced),
      );
      fixture.manager.allowReconnect(
        expectedFailure: CampusAccessFailure.vpnDisplaced,
      );
      fixture.vpn = (_) async => http.Response('vpn', 200);
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      expect(fixture.protocol.attempts, 3);
    },
  );

  test(
    'extra verification stops authentication and does not read a password',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.protocol.before = (_) async =>
          throw CampusAccessFailure.verificationRequired;
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          access.read(_academic),
          throwsA(CampusAccessFailure.verificationRequired),
        );
      }
      expect(fixture.manager.state.phase, WebVpnPhase.verificationRequired);
      expect(fixture.protocol.attempts, 1);
      expect(fixture.credentialReads, 0);
    },
  );

  test('password storage is accessed once only if the verified adapter requests it', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.protocol.before = (attempt) async {
      expect(await attempt.readRemembered(), isNull);
      expect(await attempt.readRemembered(), isNull);
    };
    final access = fixture.client(
      _resource(policy: CampusResourcePolicy.vpnOnly),
    );
    expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
    expect(fixture.credentialReads, 1);
  });

  test(
    'password rejection backs off without blocking a different account',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      fixture.protocol.before = (_) async =>
          throw CampusAccessFailure.invalidCredentials;
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.invalidCredentials),
      );
      fixture.protocol.before = null;
      fixture.manager.allowReconnect(
        expectedFailure: CampusAccessFailure.invalidCredentials,
      );
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.invalidCredentials),
      );
      expect(fixture.protocol.attempts, 1);
      fixture.manager.setAccount('second-synthetic-subject');
      expect((await access.read(_academic)).route, CampusAccessRoute.webVpn);
      expect(fixture.protocol.attempts, 2);
    },
  );

  test('new authentication cannot inherit an unverified account', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.protocol.returnSubject = 'other-synthetic-subject';
    final access = fixture.client(
      _resource(policy: CampusResourcePolicy.vpnOnly),
    );
    await expectLater(
      access.read(_academic),
      throwsA(CampusAccessFailure.accountMismatch),
    );
    expect(fixture.protocol.closed, 1);
    expect(fixture.manager.state.failure, CampusAccessFailure.accountMismatch);
    expect(fixture.vpnRequests, 0);
  });

  test(
    'manual disconnect cancels a pending read and invalidates existing uses',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final entered = Completer<void>();
      final finish = Completer<http.Response>();
      fixture.vpn = (_) {
        entered.complete();
        return finish.future;
      };
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      final use = access.openUse();
      addTearDown(use.close);
      final pending = access.read(_academic, use: use);
      await entered.future;
      final failed = expectLater(
        pending,
        throwsA(CampusAccessFailure.cancelled),
      );
      await fixture.manager.disconnect();
      finish.complete(
        http.Response('', 302, headers: {'location': '/fixture/auth-required'}),
      );
      await failed;
      await expectLater(
        access.read(_academic, use: use),
        throwsA(CampusAccessFailure.cancelled),
      );
      expect(fixture.protocol.attempts, 1);
      expect(fixture.manager.state.phase, WebVpnPhase.disconnected);
    },
  );

  test(
    'logout failure closes only the isolated client before a new session opens',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final logoutStarted = Completer<void>();
      final logout = Completer<void>();
      fixture.protocol.logout = (_) {
        logoutStarted.complete();
        return logout.future;
      };
      final access = fixture.client(
        _resource(policy: CampusResourcePolicy.vpnOnly),
      );
      await access.read(_academic);
      final disconnect = fixture.manager.disconnect();
      await logoutStarted.future;
      expect(fixture.manager.state.phase, WebVpnPhase.disconnecting);
      fixture.protocol.logout = null;
      final nextRead = access.read(_academic);
      expect((await access.read(_guide)).route, CampusAccessRoute.direct);
      expect(fixture.protocol.attempts, 1);
      logout.completeError(StateError('synthetic logout failure'));
      await disconnect;
      await nextRead;
      expect(fixture.protocol.closed, 1);
      expect(fixture.protocol.attempts, 2);
    },
  );

  test(
    'scope checks reject unsafe initial entries and every unsafe redirect',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final fallback = _resource(
        policy: CampusResourcePolicy.vpnOnly,
        vpn: CampusEndpoint(
          entry: Uri.parse('https://outside.example/fixture/academic'),
          scope: const CampusUrlScope('outside.example', _vpnPath),
        ),
      );
      await expectLater(
        fixture.client(fallback).read(_academic),
        throwsA(CampusAccessFailure.unsafeEndpoint),
      );
      expect(fixture.protocol.attempts, 0);
      final access = fixture.access;
      for (final target in [
        'https://outside.example/academic/data',
        'http://$_directHost/academic/data',
        'https://name@$_directHost/academic/data',
        'https://$_directHost:444/academic/data',
        '/academic-unsafe',
        '/academic/%252fhidden',
      ]) {
        final before = fixture.directRequests;
        fixture.direct = (_) async =>
            http.Response('', 302, headers: {'location': target});
        await expectLater(
          access.read(_academic),
          throwsA(CampusAccessFailure.unsafeEndpoint),
        );
        expect(fixture.directRequests, before + 1);
      }
      expect(fixture.protocol.attempts, 0);
      fixture.vpn = (_) async => http.Response(
        '',
        302,
        headers: {'location': 'https://outside.example/fixture/academic'},
      );
      await expectLater(
        fixture
            .client(_resource(policy: CampusResourcePolicy.vpnOnly))
            .read(_academic),
        throwsA(CampusAccessFailure.unsafeEndpoint),
      );
      expect(fixture.vpnRequests, 1);
    },
  );

  test(
    'request metrics exclude headers, credentials, response and full URLs',
    () async {
      diagnostics.clear();
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.direct = (_) async =>
          throw const SocketException('Failed host lookup SecretFixture');
      fixture.vpn = (_) async => http.Response(
        'SecretFixture body',
        200,
        headers: {'set-cookie': 'SecretFixture=cookie'},
      );
      final response = await fixture.access.read(_academic);
      expect(response.response.headers.containsKey('set-cookie'), isFalse);
      expect(diagnostics.entries.toString(), isNot(contains('SecretFixture')));
      expect(
        diagnostics.entries.toString(),
        isNot(contains(officialWebVpnHost)),
      );
      expect(
        diagnostics.entries.any(
          (entry) =>
              entry.resource == _academic &&
              entry.route == CampusAccessRoute.webVpn &&
              entry.httpStatus == 200,
        ),
        isTrue,
      );
    },
  );

  test(
    'Riverpod invalidates the old account before secure logout finishes',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final auth = _SchoolAuth();
      final scope = ProviderContainer.test(
        overrides: [
          schoolAuthRepositoryProvider.overrideWithValue(auth),
          campusAccessSettingsProvider.overrideWith(_TestSettings.new),
          webVpnProtocolProvider.overrideWithValue(fixture.protocol),
          campusResourcesProvider.overrideWithValue({
            _academic: _resource(policy: CampusResourcePolicy.vpnOnly),
          }),
        ],
      );
      await scope.read(schoolSessionProvider.future);
      final manager = scope.read(webVpnSessionManagerProvider);
      final access = scope.read(campusAccessClientProvider);
      final first = await access.read(_academic);
      scope.read(schoolSessionStatusProvider.notifier).update((
        subject: _subject,
        health: SchoolSessionHealth.connected,
      ));
      await manager.disconnect();
      expect(scope.read(schoolSessionProvider).value?.subject, _subject);
      expect(
        scope.read(schoolSessionStatusProvider).health,
        SchoolSessionHealth.connected,
      );

      final entered = Completer<void>();
      final lateResult = Completer<void>();
      fixture.protocol.before = (_) async {
        entered.complete();
        await lateResult.future;
      };
      final read = access.read(_academic);
      await entered.future;
      final cancelled = expectLater(
        read,
        throwsA(CampusAccessFailure.cancelled),
      );
      final controller = scope.read(schoolSessionProvider.notifier);
      final logout = controller.disconnect();
      expect(manager.subject, isNull);
      expect(first.ensureCurrent, throwsA(CampusAccessFailure.cancelled));
      await cancelled;
      auth.logout.complete();
      await logout;
      auth.subject = 'second-synthetic-subject';
      await controller.signIn(
        const NeuqCredentials('00001234', 'synthetic-password'),
        rememberPassword: false,
      );
      fixture.protocol.before = null;
      await access.read(_academic);
      lateResult.complete();
      await Future<void>.delayed(Duration.zero);
      expect(manager.subject, auth.subject);
      expect(manager.state.phase, WebVpnPhase.idle);
      expect(fixture.protocol.closed, 2);
    },
  );

  testWidgets(
    'settings show the native limitation and allow local preferences',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolAuthRepositoryProvider.overrideWithValue(
              const UnavailableSchoolAuthRepository(),
            ),
            campusAccessSettingsProvider.overrideWith(_TestSettings.new),
          ],
          child: const MaterialApp(home: WebVpnSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text('打开官方门户'), findsOneWidget);
      expect(find.text('应用内访问待学校协议确认，可使用官方门户。'), findsOneWidget);
      await tester.tap(find.text('5 分钟'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即释放').last);
      await tester.pumpAndSettle();
      expect(find.text('立即释放'), findsOneWidget);
    },
  );

  test('Android legacy passwords require fresh WebVPN consent and deletion erases it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const username = '00000001';
    final subject = schoolSubjectForStudentCode(username)!;
    FlutterSecureStorage.setMockInitialValues({
      'neuqSchoolLogin': jsonEncode({
        'subject': subject,
        'username': username,
        'password': 'synthetic-password',
      }),
    });
    final scope = ProviderContainer.test();
    expect((await scope.read(schoolSessionProvider.future))?.subject, subject);
    final read = scope.read(schoolRememberedCredentialsProvider);
    expect((await read(subject))?.username, username);
    await expectLater(
      read(subject, forWebVpn: true),
      throwsA(isA<SchoolPasswordConsentRequired>()),
    );
    final controller = scope.read(schoolSessionProvider.notifier);
    expect(await controller.allowRememberedPasswordForWebVpn('other'), isFalse);
    expect(await controller.allowRememberedPasswordForWebVpn(subject), isTrue);
    expect((await read(subject, forWebVpn: true))?.username, username);
    expect(await controller.forgetPassword(), isTrue);
    expect(await read(subject, forWebVpn: true), isNull);
    expect(await controller.allowRememberedPasswordForWebVpn(subject), isFalse);
    expect(scope.read(schoolSessionProvider).value?.subject, subject);
  });

  test(
    'password removal cancels an in-flight credential-dependent VPN login',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final auth = _SchoolAuth();
      final lookupStarted = Completer<void>();
      final lookup = Completer<NeuqCredentials?>();
      var lookups = 0;
      final scope = ProviderContainer.test(
        overrides: [
          schoolAuthRepositoryProvider.overrideWithValue(auth),
          campusAccessSettingsProvider.overrideWith(_TestSettings.new),
          schoolRememberedCredentialsProvider.overrideWithValue((
            _, {
            forWebVpn = false,
          }) {
            expect(forWebVpn, isTrue);
            if (++lookups == 1) lookupStarted.complete();
            return auth.deleted ? Future.value() : lookup.future;
          }),
          webVpnProtocolProvider.overrideWithValue(fixture.protocol),
          campusResourcesProvider.overrideWithValue({
            _academic: _resource(policy: CampusResourcePolicy.vpnOnly),
          }),
        ],
      );
      await scope.read(schoolSessionProvider.future);
      final access = scope.read(campusAccessClientProvider);
      fixture.protocol.before = (attempt) async {
        if (await attempt.readRemembered() == null) {
          throw CampusAccessFailure.credentialsRequired;
        }
        fail('a deleted credential reached the adapter');
      };
      final pending = access.read(_academic);
      await lookupStarted.future;
      final cancelled = expectLater(
        pending,
        throwsA(CampusAccessFailure.cancelled),
      );
      expect(
        await scope.read(schoolSessionProvider.notifier).forgetPassword(),
        isTrue,
      );
      lookup.complete(const NeuqCredentials('00000001', 'synthetic-password'));
      await cancelled;
      await expectLater(
        access.read(_academic),
        throwsA(CampusAccessFailure.credentialsRequired),
      );
      expect(lookups, 2);
      expect(fixture.vpnRequests, 0);
      expect(scope.read(schoolSessionProvider).value?.subject, _subject);
    },
  );

  testWidgets(
    'verification is deduplicated and browser return keeps native state unchanged',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.protocol.before = (_) async =>
          throw CampusAccessFailure.credentialsRequired;
      final browser = <String>[];
      final target = Uri.https(officialWebVpnHost, '$_vpnPath/browser');
      final resource = CampusResource(
        direct: _resource().direct,
        policy: CampusResourcePolicy.vpnOnly,
        allowsWebVpn: true,
        webVpn: _resource().webVpn,
        webVpnBrowser: CampusEndpoint(entry: target, scope: _vpnScope),
      );
      final scope = ProviderContainer.test(
        overrides: [
          schoolAuthRepositoryProvider.overrideWithValue(_SchoolAuth()),
          campusAccessSettingsProvider.overrideWith(_TestSettings.new),
          webVpnProtocolProvider.overrideWithValue(fixture.protocol),
          campusResourcesProvider.overrideWithValue({
            _academic: resource,
            _guide: resource,
          }),
          campusVerificationBrowserProvider.overrideWithValue(
            (_, url) async => browser.add(url),
          ),
        ],
      );
      scope.read(schoolSessionProvider.future).ignore();
      await tester.pump();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  CampusResourcePanel(
                    id: _academic,
                    builder: (_) => const Text('数据'),
                  ),
                  CampusResourcePanel(
                    id: _guide,
                    builder: (_) => const Text('数据'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要学校身份验证'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('需要学校身份验证'), findsNothing);
      expect(browser, isEmpty);
      await tester.tap(find.text('前往验证').first);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('前往验证')),
      );
      await tester.pumpAndSettle();
      expect(browser, [target.toString()]);
      final manager = scope.read(webVpnSessionManagerProvider);
      manager.setForeground(false);
      manager.setForeground(true);
      await tester.pumpAndSettle();
      expect(manager.state.phase, WebVpnPhase.verificationRequired);
      expect(fixture.protocol.attempts, 1);
    },
  );
}

class _Fixture {
  _Fixture({bool protocolAvailable = true}) {
    protocol = _Protocol((request) {
      vpnRequests++;
      return vpn(request);
    });
    manager = WebVpnSessionManager(
      protocol: protocolAvailable ? protocol : null,
      readRemembered: (_) async {
        credentialReads++;
        return null;
      },
      clock: () => now,
      onState: (_) {},
    )..setAccount(_subject);
  }

  DateTime now = DateTime.utc(2026, 1, 1);
  void advance(Duration duration) => now = now.add(duration);
  int directRequests = 0;
  int vpnRequests = 0;
  int credentialReads = 0;
  CampusAccessPreference preference = CampusAccessPreference.automatic;
  Future<http.Response> Function(http.Request) direct = (_) async =>
      http.Response('direct response', 200);
  Future<http.Response> Function(http.Request) vpn = (_) async =>
      http.Response('vpn response', 200);
  late final _Protocol protocol;
  late final WebVpnSessionManager manager;
  late final _direct = MockClient((request) {
    directRequests++;
    expect(request.method, 'GET');
    expect(request.followRedirects, isFalse);
    return direct(request);
  });

  CampusAccessClient get access => client(_resource());

  CampusAccessClient client(
    CampusResource resource, {
    CampusResource? second,
    Future<String?> Function()? networkSignature,
  }) => CampusAccessClient(
    resources: {
      _academic: resource,
      _guide:
          second ??
          CampusResource(
            direct: resource.direct,
            policy: CampusResourcePolicy.directOnly,
          ),
    },
    direct: DirectTransport(_direct),
    webVpn: manager,
    preference: () => preference,
    clock: () => now,
    networkSignature: networkSignature,
  );

  void dispose() {
    manager.dispose();
    _direct.close();
  }
}

class _Protocol implements WebVpnProtocol {
  _Protocol(this.read);
  final Future<http.Response> Function(http.Request) read;
  int attempts = 0;
  int closed = 0;
  Future<void> Function(WebVpnAuthentication)? before;
  Future<void> Function(CampusCancellation)? logout;
  String? returnSubject;

  @override
  Future<WebVpnSession> authenticate(WebVpnAuthentication attempt) async {
    attempts++;
    await before?.call(attempt);
    return WebVpnSession(
      subject: returnSubject ?? attempt.subject,
      httpClient: _CountedClient(read, () => closed++),
      logout: logout,
    );
  }
}

class _CountedClient extends MockClient {
  _CountedClient(super.fn, this.closed);
  final void Function() closed;

  @override
  void close() {
    closed();
    super.close();
  }
}

class _SchoolAuth implements SchoolAuthRepository {
  String subject = _subject;
  bool deleted = false;
  final logout = Completer<void>();
  @override
  bool get available => true;
  @override
  bool get canRememberPassword => false;
  @override
  Future<SchoolSession?> restoreSession() async =>
      SchoolSession(subject: subject);
  @override
  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) async => false;
  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async => SchoolSession(subject: subject);
  @override
  Future<bool> hasRememberedPassword(String subject) async => false;
  @override
  Future<void> forgetPassword(String subject) async => deleted = true;
  @override
  Future<void> disconnect() => logout.future;
}

class _TestSettings extends CampusAccessSettingsController {
  @override
  Future<CampusAccessSettings> build() async => const CampusAccessSettings();

  @override
  Future<void> setIdleMinutes(int value) async {
    state = AsyncData(CampusAccessSettings(idleMinutes: value));
  }
}
