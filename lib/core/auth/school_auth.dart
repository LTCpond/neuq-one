import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../network/neuq_client.dart';
import 'neuq_login_protocol.dart';

export '../network/neuq_client.dart' show NeuqCredentials, SchoolRequestFailure;

enum SchoolConnection { unavailable, disconnected, connected }

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

class _SchoolLoginStore {
  const _SchoolLoginStore(this._storage);

  static const _legacyIdentityKey = 'verifiedNeuqStudent';
  static const _accountKey = 'neuqSchoolLogin';
  final FlutterSecureStorage _storage;

  Future<Map<String, dynamic>?> _record() async {
    final raw = await _storage.read(key: _accountKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
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

  Future<NeuqCredentials?> credentialsFor(String subject) async {
    final value = await _record();
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
      _storage.write(
        key: _accountKey,
        value: jsonEncode({
          'subject': subject,
          if (credentials != null) ...{
            'username': credentials.username,
            'password': credentials.password,
          },
        }),
      );

  Future<void> forget(String subject) async {
    if (await credentialsFor(subject) != null) await save(subject, null);
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _legacyIdentityKey);
    } finally {
      await _storage.delete(key: _accountKey);
    }
  }
}

final _schoolLoginStoreProvider = Provider(
  (ref) => _SchoolLoginStore(ref.watch(schoolTicketStorageProvider)),
);

final neuqHttpClientFactoryProvider = Provider<http.Client Function()>(
  (_) => http.Client.new,
);

final neuqClientProvider = Provider<NeuqClient>((ref) {
  final store = ref.watch(_schoolLoginStoreProvider);
  final client = NeuqClient(
    readRemembered: (subject) => defaultTargetPlatform == TargetPlatform.android
        ? store.credentialsFor(subject)
        : Future.value(),
    forgetRemembered: store.forget,
    createClient: ref.watch(neuqHttpClientFactoryProvider),
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

class SchoolSessionController extends AsyncNotifier<SchoolSession?> {
  @override
  Future<SchoolSession?> build() {
    final repository = ref.watch(schoolAuthRepositoryProvider);
    return repository.available ? repository.restoreSession() : Future.value();
  }

  Future<void> signIn(
    NeuqCredentials credentials, {
    required bool rememberPassword,
  }) async {
    if (state.isLoading) return;
    final repository = ref.read(schoolAuthRepositoryProvider);
    if (!repository.available) return;
    final previous = state.asData?.value;
    state = const AsyncLoading();
    try {
      final session = await repository.signIn(
        credentials,
        rememberPassword: rememberPassword,
      );
      if (ref.mounted) state = AsyncData(session);
    } catch (_) {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final repository = ref.read(schoolAuthRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repository.disconnect();
    } finally {
      state = const AsyncData(null);
    }
  }
}

final schoolConnectionProvider = FutureProvider<SchoolConnection>((ref) async {
  if (!ref.watch(schoolAuthRepositoryProvider).available) {
    return SchoolConnection.unavailable;
  }
  final session = await ref.watch(schoolSessionProvider.future);
  return session == null
      ? SchoolConnection.disconnected
      : SchoolConnection.connected;
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
