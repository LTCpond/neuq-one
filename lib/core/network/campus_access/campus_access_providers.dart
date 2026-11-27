import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../auth/school_auth.dart';
import '../../storage/settings.dart';
import 'campus_access_client.dart';
import 'campus_resource.dart';
import 'campus_transport.dart';
import 'webvpn_session_manager.dart';

/// Native access is disabled until an authorized school flow and resource have
/// been verified. The browser portal does not use this provider.
final webVpnProtocolProvider = Provider<WebVpnProtocol?>((_) => null);
final campusAccessHttpFactoryProvider = Provider<http.Client Function()>(
  (_) => http.Client.new,
);
final campusAccessClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final campusResourcesProvider = Provider<Map<CampusResourceId, CampusResource>>(
  (_) => {
    CampusResourceId.webVpnGuide: CampusResource(
      direct: CampusEndpoint(
        entry: Uri.parse(officialWebVpnGuide),
        scope: const CampusUrlScope('xxhb.neuq.edu.cn', '/info/1018/1434.htm'),
        classify: (response) {
          if (response.status == 200 &&
              response.headers['content-type']?.startsWith('text/html') ==
                  true &&
              utf8.decode(response.bytes).contains('校外远程资源访问系统（WebVPN）使用说明')) {
            return null;
          }
          return CampusAccessFailure.invalidResponse;
        },
      ),
      policy: CampusResourcePolicy.directOnly,
    ),
  },
);

final webVpnStateProvider =
    NotifierProvider<WebVpnStateController, WebVpnState>(
      WebVpnStateController.new,
    );

class WebVpnStateController extends Notifier<WebVpnState> {
  @override
  WebVpnState build() =>
      (phase: WebVpnPhase.disconnected, idleUntil: null, failure: null);

  void update(WebVpnState next) => state = next;
}

final webVpnSessionManagerProvider = Provider<WebVpnSessionManager>((ref) {
  final readRemembered = ref.watch(schoolRememberedCredentialsProvider);
  final subjectProvider = schoolSessionProvider.select(
    (session) => session.asData?.value?.subject,
  );
  final manager = WebVpnSessionManager(
    protocol: ref.watch(webVpnProtocolProvider),
    clock: ref.watch(campusAccessClockProvider),
    readRemembered: (subject) async {
      final boundary = ref.read(schoolNetworkBoundaryProvider);
      if (boundary.signingOut ||
          boundary.deletingPassword ||
          ref.read(subjectProvider) != subject) {
        return null;
      }
      try {
        return await readRemembered(subject, forWebVpn: true);
      } on SchoolPasswordConsentRequired {
        throw CampusAccessFailure.credentialConsentRequired;
      }
    },
    onState: (state) {
      if (ref.mounted) ref.read(webVpnStateProvider.notifier).update(state);
    },
  );

  void updateAccount() {
    manager.setAccount(
      ref.read(schoolNetworkBoundaryProvider).signingOut
          ? null
          : ref.read(subjectProvider),
    );
  }

  ref.listen(subjectProvider, (_, _) => updateAccount());
  ref.listen(schoolNetworkBoundaryProvider, (previous, next) {
    if (next.deletingPassword && previous?.deletingPassword != true) {
      manager.cancelAuthentication();
    }
    updateAccount();
  });
  if (manager.protocolAvailable) {
    ref.listen(campusAccessSettingsProvider, (_, settings) {
      manager.setIdleTimeout(
        Duration(
          minutes:
              settings.value?.idleMinutes ?? CampusAccessLimits.idleMinutes,
        ),
      );
    }, fireImmediately: true);
  }
  updateAccount();
  ref.onDispose(manager.dispose);
  return manager;
});

final campusAccessClientProvider = Provider<CampusAccessClient>((ref) {
  final http = ref.watch(campusAccessHttpFactoryProvider)();
  final webVpn = ref.watch(webVpnSessionManagerProvider);
  final resources = ref.watch(campusResourcesProvider);
  final canSwitchRoutes =
      webVpn.protocolAvailable &&
      resources.values.any(
        (resource) =>
            resource.policy == CampusResourcePolicy.preferDirect &&
            resource.allowsWebVpn &&
            resource.webVpn != null,
      );
  ref.onDispose(http.close);
  return CampusAccessClient(
    resources: resources,
    direct: DirectTransport(http),
    webVpn: webVpn,
    clock: ref.watch(campusAccessClockProvider),
    preference: () =>
        ref.read(campusAccessSettingsProvider).value?.preference ??
        CampusAccessPreference.automatic,
    networkSignature: canSwitchRoutes ? _networkSignature : null,
  );
});

Future<String?> _networkSignature() async {
  try {
    if (Platform.isAndroid) {
      return await const MethodChannel('org.neuqone.neuq_one/campus_network')
          .invokeMethod<String>('activeNetwork')
          .timeout(const Duration(milliseconds: 250));
    }
    final interfaces = await NetworkInterface.list().timeout(
      const Duration(milliseconds: 250),
    );
    final addresses = [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          '${interface.index}:${address.address}',
    ]..sort();
    // Only used in memory to invalidate observations, never to select a route.
    return addresses.isEmpty ? null : addresses.join('|');
  } catch (_) {
    return null;
  }
}
