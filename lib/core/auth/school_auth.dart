import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../network/neuq_client.dart';
import '../diagnostics/diagnostics.dart';
import 'neuq_login_protocol.dart';

export '../network/neuq_client.dart'
    show
        NeuqCredentials,
        SchoolRecoveryTrigger,
        SchoolRequestFailure,
        SchoolSessionHealth;

enum SchoolConnection {
  unavailable,
  disconnected,
  connected,
  restoring,
  expired,
  offline,
  unknown,
}

class SchoolSession {
  const SchoolSession({required this.subject, this.admissionYear});

  /// Stable pseudonymous identifier for a verified student account.
  final String subject;

  /// Applicable cohort from the school's enrollment record, including reclassification.
  final int? admissionYear;
}

abstract interface class SchoolAuthRepository {
  bool get available;
  bool get canRememberPassword;

  /// Restores the device identity established by a previous school login.
  Future<SchoolSession?> restoreSession();

  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  });

  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  });

  Future<bool> hasRememberedPassword(String subject);
  Future<void> forgetPassword(String subject);

  /// Clears the local identity, remembered credentials and active session.
  Future<void> disconnect();
}

class UnavailableSchoolAuthRepository implements SchoolAuthRepository {
  const UnavailableSchoolAuthRepository();

  @override
  bool get available => false;
  @override
  bool get canRememberPassword => false;
  @override
  Future<SchoolSession?> restoreSession() async => null;
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
  }) async => throw SchoolRequestFailure.unavailable;
  @override
  Future<bool> hasRememberedPassword(String subject) async => false;
  @override
  Future<void> forgetPassword(String subject) async {}
  @override
  Future<void> disconnect() async {}
}

class _NeuqAuthRepository implements SchoolAuthRepository {
  _NeuqAuthRepository(this._loginStore, this._client);

  final _SchoolLoginStore _loginStore;
  final NeuqClient _client;

  @override
  bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get canRememberPassword =>
      available && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<SchoolSession?> restoreSession() async {
    final subject = await _loginStore.restoreSubject();
    return subject == null ? null : SchoolSession(subject: subject);
  }

  @override
  Future<bool> recoverSession(
    String subject, {
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) => _client.recoverSession(
    subject,
    trigger: trigger,
    isForeground: isForeground,
  );

  @override
  Future<SchoolSession> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async {
    if (!available) throw SchoolRequestFailure.unavailable;
    final subject = await _client.signIn(
      credentials,
      expectedSubject: expectedSubject,
      onVerified: (subject) => _loginStore.save(
        subject,
        rememberPassword && canRememberPassword ? credentials : null,
      ),
    );
    return SchoolSession(subject: subject);
  }

  @override
  Future<bool> hasRememberedPassword(String subject) async =>
      canRememberPassword && await _loginStore.credentialsFor(subject) != null;

  @override
  Future<void> forgetPassword(String subject) =>
      _client.forgetPassword(subject);

  @override
  Future<void> disconnect() => _client.disconnect(() async {
    try {
      await _loginStore.clear();
    } finally {
      // The independent campus card page still uses the platform cookie store.
      if (available) await WebViewCookieManager().clearCookies();
    }
  });
}

class SchoolPasswordConsentRequired implements Exception {
  const SchoolPasswordConsentRequired();
}

class _SchoolLoginStore {
  _SchoolLoginStore(this._storage);

  static const _legacyIdentityKey = 'verifiedNeuqStudent';
  static const _accountKey = 'neuqSchoolLogin';
  final FlutterSecureStorage _storage;
  Future<void> _writes = Future.value();

  Future<Map<String, dynamic>?> _record() async {
    final raw = await _storage.read(key: _accountKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        DiagnosticStage.decode,
        error: error,
      );
      return const {};
    }
  }

  Future<String?> restoreSubject() async {
    final value = await _record();
    final subject = value == null
        ? await _storage.read(key: _legacyIdentityKey)
        : value['subject'];
    return subject is String && isStoredSchoolSubject(subject) ? subject : null;
  }

  Future<NeuqCredentials?> credentialsFor(
    String subject, {
    bool forWebVpn = false,
  }) async {
    final value = await _record();
    final credentials = _credentials(value, subject);
    if (forWebVpn && credentials != null && value?['allowWebVpn'] != true) {
      throw const SchoolPasswordConsentRequired();
    }
    return credentials;
  }

  NeuqCredentials? _credentials(Map<String, dynamic>? value, String subject) {
    if (value == null || value['subject'] != subject) return null;
    final username = value['username'];
    final password = value['password'];
    return username is String &&
            password is String &&
            password.isNotEmpty &&
            schoolSubjectForStudentCode(username) == subject
        ? NeuqCredentials(username, password)
        : null;
  }

  Future<void> save(String subject, NeuqCredentials? credentials) =>
      _write(() => _save(subject, credentials));

  Future<void> _save(String subject, NeuqCredentials? credentials) =>
      _storage.write(
        key: _accountKey,
        value: jsonEncode({
          'subject': subject,
          if (credentials != null) ...{
            'username': credentials.username,
            'password': credentials.password,
            'allowWebVpn': true,
          },
        }),
      );

  Future<bool> allowWebVpn(String subject) async {
    var granted = false;
    await _write(() async {
      final credentials = _credentials(await _record(), subject);
      if (credentials == null) return;
      await _save(subject, credentials);
      granted = true;
    });
    return granted;
  }

  Future<void> forget(String subject) => _write(() async {
    final value = await _record();
    if (value == null || value['subject'] != subject) return;
    if (value.containsKey('username') || value.containsKey('password')) {
      await _save(subject, null);
    }
  });

  Future<void> clear() => _write(() async {
    try {
      await _storage.delete(key: _legacyIdentityKey);
    } finally {
      await _storage.delete(key: _accountKey);
    }
  });

  Future<void> _write(Future<void> Function() write) {
    final result = _writes.then((_) => write());
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

final _schoolLoginStoreProvider = Provider(
  (ref) => _SchoolLoginStore(ref.watch(schoolTicketStorageProvider)),
);

final schoolRememberedCredentialsProvider =
    Provider<Future<NeuqCredentials?> Function(String, {bool forWebVpn})>((
      ref,
    ) {
      final store = ref.watch(_schoolLoginStoreProvider);
      return (subject, {forWebVpn = false}) =>
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? store.credentialsFor(subject, forWebVpn: forWebVpn)
          : Future.value();
    });

final neuqHttpClientFactoryProvider = Provider<http.Client Function()>(
  (_) => http.Client.new,
);

final schoolSessionClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final schoolSessionStatusProvider =
    NotifierProvider<SchoolSessionStatusController, SchoolSessionStatus>(
      SchoolSessionStatusController.new,
    );

class SchoolSessionStatusController extends Notifier<SchoolSessionStatus> {
  @override
  SchoolSessionStatus build() =>
      (subject: null, health: SchoolSessionHealth.unknown);

  void update(SchoolSessionStatus next) {
    if (state != next) state = next;
  }
}

final Provider<NeuqClient> neuqClientProvider = Provider((ref) {
  final store = ref.watch(_schoolLoginStoreProvider);
  final client = NeuqClient(
    readRemembered: ref.watch(schoolRememberedCredentialsProvider),
    forgetRemembered: (subject) async {
      if (!ref.mounted) return;
      final boundary = ref.read(schoolNetworkBoundaryProvider.notifier);
      final ownsDeletion = !ref
          .read(schoolNetworkBoundaryProvider)
          .deletingPassword;
      if (ownsDeletion) boundary.deletingPassword(true);
      try {
        await store.forget(subject);
        if (ref.mounted) ref.invalidate(rememberedSchoolPasswordProvider);
      } finally {
        if (ref.mounted && ownsDeletion) boundary.deletingPassword(false);
      }
    },
    createClient: ref.watch(neuqHttpClientFactoryProvider),
    clock: ref.watch(schoolSessionClockProvider),
    onSessionStatus: (status) {
      if (ref.mounted) {
        ref.read(schoolSessionStatusProvider.notifier).update(status);
      }
    },
  );
  ref.onDispose(client.dispose);
  return client;
});

final schoolAuthRepositoryProvider = Provider<SchoolAuthRepository>(
  (ref) => _NeuqAuthRepository(
    ref.watch(_schoolLoginStoreProvider),
    ref.watch(neuqClientProvider),
  ),
);

final schoolSessionProvider =
    AsyncNotifierProvider<SchoolSessionController, SchoolSession?>(
      SchoolSessionController.new,
      retry: (_, _) => null,
    );

final schoolNetworkBoundaryProvider =
    NotifierProvider<
      SchoolNetworkBoundary,
      ({bool signingOut, bool deletingPassword})
    >(SchoolNetworkBoundary.new);

class SchoolNetworkBoundary
    extends Notifier<({bool signingOut, bool deletingPassword})> {
  @override
  ({bool signingOut, bool deletingPassword}) build() =>
      (signingOut: false, deletingPassword: false);

  void signingOut(bool value) =>
      state = (signingOut: value, deletingPassword: state.deletingPassword);

  void deletingPassword(bool value) =>
      state = (signingOut: state.signingOut, deletingPassword: value);
}

class SchoolSessionController extends AsyncNotifier<SchoolSession?> {
  int _revision = 0;
  bool _disconnecting = false;
  bool _signingIn = false;

  @override
  Future<SchoolSession?> build() async {
    final repository = ref.watch(schoolAuthRepositoryProvider);
    try {
      return repository.available ? await repository.restoreSession() : null;
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.schoolAuth,
        DiagnosticStage.restore,
        error: error,
      );
      rethrow;
    }
  }

  Future<bool> recoverSession({
    required SchoolRecoveryTrigger trigger,
    bool Function()? isForeground,
  }) async {
    final session = state.asData?.value;
    if (_disconnecting || _signingIn || session == null) return false;
    final revision = _revision;
    final recovered = await ref
        .read(schoolAuthRepositoryProvider)
        .recoverSession(
          session.subject,
          trigger: trigger,
          isForeground: isForeground,
        );
    return recovered && ref.mounted && revision == _revision;
  }

  Future<void> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
    String? expectedSubject,
  }) async {
    if (state.isLoading || _disconnecting || _signingIn) {
      throw SchoolRequestFailure.cancelled;
    }
    final repository = ref.read(schoolAuthRepositoryProvider);
    if (!repository.available) throw SchoolRequestFailure.unavailable;
    final previous = state.asData?.value;
    if (expectedSubject != null && previous?.subject != expectedSubject) {
      throw SchoolRequestFailure.cancelled;
    }
    final revision = ++_revision;
    _signingIn = true;
    if (expectedSubject == null) state = const AsyncLoading();
    try {
      final session = await repository.signIn(
        credentials,
        rememberPassword: rememberPassword,
        expectedSubject: expectedSubject,
      );
      if (!ref.mounted || revision != _revision) {
        throw SchoolRequestFailure.cancelled;
      }
      if (expectedSubject == null) state = AsyncData(session);
      ref.invalidate(rememberedSchoolPasswordProvider);
    } catch (_) {
      if (ref.mounted && revision == _revision && expectedSubject == null) {
        state = AsyncData(previous);
      }
      rethrow;
    } finally {
      _signingIn = false;
    }
  }

  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    _revision++;
    final boundary = ref.read(schoolNetworkBoundaryProvider.notifier);
    boundary.signingOut(true);
    try {
      await ref.read(schoolAuthRepositoryProvider).disconnect();
    } finally {
      if (ref.mounted) {
        state = const AsyncData(null);
        boundary.signingOut(false);
      }
      _disconnecting = false;
    }
  }

  Future<bool> forgetPassword() async {
    final subject = state.asData?.value?.subject;
    if (subject == null ||
        _disconnecting ||
        ref.read(schoolNetworkBoundaryProvider).deletingPassword) {
      return false;
    }
    final boundary = ref.read(schoolNetworkBoundaryProvider.notifier);
    boundary.deletingPassword(true);
    try {
      await ref.read(schoolAuthRepositoryProvider).forgetPassword(subject);
      return true;
    } finally {
      if (ref.mounted) boundary.deletingPassword(false);
    }
  }

  Future<bool> allowRememberedPasswordForWebVpn(String subject) async {
    if (state.asData?.value?.subject != subject ||
        _disconnecting ||
        _signingIn ||
        ref.read(schoolNetworkBoundaryProvider).deletingPassword ||
        !ref.read(schoolAuthRepositoryProvider).canRememberPassword) {
      return false;
    }
    final revision = _revision;
    final granted = await ref
        .read(_schoolLoginStoreProvider)
        .allowWebVpn(subject);
    return granted &&
        ref.mounted &&
        revision == _revision &&
        !ref.read(schoolNetworkBoundaryProvider).deletingPassword;
  }
}

final schoolConnectionProvider = FutureProvider<SchoolConnection>((ref) async {
  if (!ref.watch(schoolAuthRepositoryProvider).available) {
    return SchoolConnection.unavailable;
  }
  final health = ref.watch(schoolSessionStatusProvider);
  final session = await ref.watch(schoolSessionProvider.future);
  if (session == null) return SchoolConnection.disconnected;
  if (health.subject != session.subject) return SchoolConnection.unknown;
  return switch (health.health) {
    SchoolSessionHealth.unknown => SchoolConnection.unknown,
    SchoolSessionHealth.restoring => SchoolConnection.restoring,
    SchoolSessionHealth.connected => SchoolConnection.connected,
    SchoolSessionHealth.expired => SchoolConnection.expired,
    SchoolSessionHealth.offline => SchoolConnection.offline,
  };
});

final schoolTicketStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final rememberedSchoolPasswordProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final subject = ref.watch(
    schoolSessionProvider.select((session) => session.asData?.value?.subject),
  );
  return subject != null &&
      await ref
          .watch(schoolAuthRepositoryProvider)
          .hasRememberedPassword(subject);
});
