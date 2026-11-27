import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/network/public_data_client.dart';
import '../../../core/storage/settings.dart';

enum AppUpdateChannel { stable, beta }

const _channelName = String.fromEnvironment(
  'NEUQ_ONE_UPDATE_CHANNEL',
  defaultValue: 'beta',
);
const _buildChannel = _channelName == 'beta'
    ? AppUpdateChannel.beta
    : AppUpdateChannel.stable;

final androidDebugBuildProvider = Provider<bool>(
  (_) =>
      kDebugMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final appUpdatesProvider = Provider<AppUpdatesRepository>(
  (ref) => AppUpdatesRepository(
    ref.watch(publicDataClientProvider),
    developmentBuild: ref.watch(androidDebugBuildProvider),
  ),
);

final installedAppVersionProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(appUpdatesProvider).installedVersion(),
  retry: (_, _) => null,
);

final appUpdateCoordinatorProvider = Provider((ref) {
  SharedPreferencesAsync? preferences;
  try {
    preferences = ref.read(preferencesProvider);
  } catch (error) {
    _updateLog(
      DiagnosticStage.read,
      error: error,
      code: DiagnosticCode.storage,
    );
  }
  final coordinator = AppUpdateCoordinator(
    ref.read(appUpdatesProvider),
    preferences,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final availableAppUpdateProvider = StreamProvider<AppUpdateAvailable?>((ref) {
  final coordinator = ref.watch(appUpdateCoordinatorProvider);
  unawaited(coordinator.restore());
  return coordinator.updates;
}, retry: (_, _) => null);

class AppUpdateCoordinator {
  AppUpdateCoordinator(
    this._repository,
    this._prefs, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _stateKey = 'appUpdates.state.v1';
  static const _promptKey = 'appUpdates.lastPromptedVersion';
  static const _legacySuccess = 'appUpdates.lastSuccessfulCheck';
  static const _legacyAttempt = 'appUpdates.lastAttempt';
  static const _legacyIgnored = 'appUpdates.ignoredVersion';
  static const _successInterval = Duration(hours: 24);
  static const _maxFailures = 4;

  final AppUpdatesRepository _repository;
  final SharedPreferencesAsync? _prefs;
  final DateTime Function() _clock;
  final _available = ValueNotifier<AppUpdateAvailable?>(null);
  Future<void>? _restore;
  Future<AppUpdateResult?>? _startup;
  Future<AppUpdateResult?>? _inFlight;
  Future<AppUpdateResult?>? _manual;
  int? _lastSuccess;
  int? _lastAttempt;
  int _failures = 0;
  String? _lastPrompted;
  bool _presentationOpen = false;
  bool _promptStoreReadable = false;
  bool _disposed = false;

  AppUpdateAvailable? get available => _available.value;
  Stream<AppUpdateAvailable?> get updates => Stream.multi((events) {
    void publish() => events.add(available);
    _available.addListener(publish);
    publish();
    events.onCancel = () => _available.removeListener(publish);
  });

  Future<void> restore() => _restore ??= _restoreState();

  Future<void> _restoreState() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final remembered = await prefs.getString(_promptKey);
      final ignored = await prefs.getString(_legacyIgnored);
      _lastPrompted = _higherVersion(
        _validVersion(remembered),
        _validVersion(ignored),
      );
      // Preserve a malformed reminder record for diagnosis and use the hint.
      _promptStoreReadable =
          remembered == null || _validVersion(remembered) != null;
      if (!_promptStoreReadable) {
        _updateLog(DiagnosticStage.read, code: DiagnosticCode.invalidData);
      }
    } catch (error) {
      _updateLog(
        DiagnosticStage.read,
        error: error,
        code: DiagnosticCode.storage,
      );
    }

    try {
      final now = _now;
      final raw = await prefs.getString(_stateKey);
      if (raw == null) {
        _lastSuccess = _timestamp(await prefs.getInt(_legacySuccess), now);
        _lastAttempt = _timestamp(await prefs.getInt(_legacyAttempt), now);
        _failures = _lastAttempt == _lastSuccess || _lastAttempt == null
            ? 0
            : 1;
        if (_lastSuccess != null || _lastAttempt != null) await _saveState();
        return;
      }
      if (raw.length > AppUpdatesRepository.maxManifestBytes) {
        throw const FormatException('本地版本记录过大');
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('本地版本记录无效');
      }
      // A build switching channels needs a fresh manifest and matching offer.
      if (json['channel'] != _repository.channel.name) return;
      _lastSuccess = _timestamp(json['lastSuccess'], now);
      _lastAttempt = _timestamp(json['lastAttempt'], now);
      final failures = json['failures'];
      if (failures is int) _failures = failures.clamp(0, _maxFailures);
      if (json['lastSuccess'] != _lastSuccess ||
          json['lastAttempt'] != _lastAttempt) {
        await _saveState(cachedRelease: json['available']);
      }
      final saved = json['available'];
      if (saved == null || _repository.developmentBuild) return;
      final installed = await _repository.installedVersion();
      final offer = _AppRelease.read(saved);
      if ((_repository.channel == AppUpdateChannel.stable &&
              offer.prerelease) ||
          _compareVersions(offer.version, installed) <= 0) {
        await _saveState();
        return;
      }
      if (!_disposed) _available.value = offer.forInstalled(installed);
    } catch (error) {
      _updateLog(DiagnosticStage.read, error: error);
    }
  }

  int get _now => _clock().millisecondsSinceEpoch;

  static int? _timestamp(Object? time, int now) =>
      time is int && time >= 0 ? (time > now ? now : time) : null;

  Future<AppUpdateResult?> checkAtStartup() =>
      _startup ??= check(automatic: true);

  Future<AppUpdateResult?> check({required bool automatic}) {
    if (automatic && _repository.developmentBuild) return Future.value();
    _updateLog(
      DiagnosticStage.check,
      code: automatic
          ? DiagnosticCode.automaticCheck
          : DiagnosticCode.manualCheck,
      level: DiagnosticSeverity.debug,
    );
    if (automatic) return _request(automatic: true);
    return _manual ??= _checkManual().whenComplete(() => _manual = null);
  }

  Future<AppUpdateResult?> _request({required bool automatic}) =>
      _inFlight ??= _run(automatic: automatic)
          .whenComplete(() => _inFlight = null);

  Future<AppUpdateResult?> _checkManual() async {
    final running = _inFlight;
    if (running != null) {
      final result = await running;
      if (result != null) return result;
    }
    // A concurrent startup check may have stopped before starting a GET.
    return _request(automatic: false);
  }

  Future<AppUpdateResult?> _run({required bool automatic}) async {
    await restore();
    if (_disposed || (automatic && _prefs == null)) return null;
    final now = _now;
    _lastSuccess = _timestamp(_lastSuccess, now);
    _lastAttempt = _timestamp(_lastAttempt, now);
    if (automatic && _recent(_lastSuccess, now, _successInterval)) {
      _updateLog(
        DiagnosticStage.check,
        code: DiagnosticCode.checkInterval,
        level: DiagnosticSeverity.debug,
      );
      return null;
    }
    if (automatic &&
        _failures > 0 &&
        _recent(_lastAttempt, now, Duration(hours: 1 << (_failures - 1)))) {
      _updateLog(
        DiagnosticStage.check,
        code: DiagnosticCode.retryBackoff,
        level: DiagnosticSeverity.debug,
      );
      return null;
    }

    _lastAttempt = now;
    // Also back off if the app is closed while this request is still running.
    _failures = (_failures + 1).clamp(1, _maxFailures);
    final savedAttempt = await _saveState();
    if (automatic && !savedAttempt) return null;
    try {
      final result = await _repository.checkForUpdate();
      if (_disposed) return result;
      _lastSuccess = _now;
      _failures = 0;
      _available.value = result is AppUpdateAvailable ? result : null;
      await _saveState();
      return result;
    } catch (error) {
      final requestCode = error is PublicDataException ? error.code : null;
      _updateLog(
        error is FormatException || requestCode == DiagnosticCode.invalidData
            ? DiagnosticStage.decode
            : DiagnosticStage.request,
        code: requestCode,
        error: error,
      );
      rethrow;
    }
  }

  static bool _recent(int? last, int now, Duration interval) =>
      last != null && now - last < interval.inMilliseconds;

  Future<bool> _saveState({Object? cachedRelease}) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    try {
      await prefs.setString(
        _stateKey,
        jsonEncode({
          'channel': _repository.channel.name,
          'lastSuccess': _lastSuccess,
          'lastAttempt': _lastAttempt,
          'failures': _failures,
          'available': cachedRelease ?? available?._release.toJson(),
        }),
      );
      return true;
    } catch (error) {
      _updateLog(
        DiagnosticStage.write,
        error: error,
        code: DiagnosticCode.storage,
      );
      return false;
    }
  }

  bool beginPresentation() {
    if (_presentationOpen || _disposed) return false;
    _presentationOpen = true;
    return true;
  }

  void endPresentation() => _presentationOpen = false;

  Future<void> noteManualPresentation(String version) async {
    _updateLog(
      DiagnosticStage.show,
      code: DiagnosticCode.promptShown,
      level: DiagnosticSeverity.info,
    );
    if (_alreadyPrompted(version)) return;
    _lastPrompted = version;
    await _savePrompt(version);
  }

  bool _alreadyPrompted(String version) {
    final last = _lastPrompted;
    return last != null && _compareVersions(version, last) <= 0;
  }

  Future<void> presentAutomatically({
    required bool Function() canShow,
    required Future<void> Function(AppUpdateAvailable, VoidCallback) show,
  }) async {
    final offer = available;
    if (offer == null || !_recent(_lastSuccess, _now, _successInterval)) return;
    if (_alreadyPrompted(offer.latestVersion)) {
      _updateLog(
        DiagnosticStage.show,
        code: DiagnosticCode.promptAlreadyShown,
        level: DiagnosticSeverity.debug,
      );
      return;
    }
    if (!canShow()) {
      _updateLog(
        DiagnosticStage.show,
        code: DiagnosticCode.promptDeferred,
        level: DiagnosticSeverity.debug,
      );
      return;
    }
    if (!_promptStoreReadable || !beginPresentation()) return;

    final previous = _lastPrompted;
    var shown = false;
    try {
      // Claim durably before opening. If the view changes during this write,
      // restore the previous record and leave the offer in the profile.
      if (!await _savePrompt(offer.latestVersion)) return;
      try {
        if (_disposed || !identical(available, offer) || !canShow()) return;
        await show(offer, () {
          shown = true;
          _lastPrompted = offer.latestVersion;
          _updateLog(
            DiagnosticStage.show,
            code: DiagnosticCode.promptShown,
            level: DiagnosticSeverity.info,
          );
        });
      } finally {
        if (!shown && !await _savePrompt(previous)) {
          // A failed rollback leaves an uncertain durable claim. Keep the
          // profile hint and avoid retrying an automatic dialog this run.
          _promptStoreReadable = false;
        }
      }
    } finally {
      endPresentation();
    }
  }

  Future<bool> _savePrompt(String? version) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    try {
      if (version == null) {
        await prefs.remove(_promptKey);
      } else {
        await prefs.setString(_promptKey, version);
      }
      return true;
    } catch (error) {
      _updateLog(
        DiagnosticStage.write,
        error: error,
        code: DiagnosticCode.storage,
      );
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _available.dispose();
  }
}

sealed class AppUpdateResult {
  const AppUpdateResult();
}

class NoPublishedAppRelease extends AppUpdateResult {
  const NoPublishedAppRelease();
}

class AppUpToDate extends AppUpdateResult {
  const AppUpToDate();
}

class PublishedAppVersion extends AppUpdateResult {
  const PublishedAppVersion(this.version, {required this.prerelease});

  final String version;
  final bool prerelease;
}

class AppUpdateAvailable extends AppUpdateResult {
  const AppUpdateAvailable._(this.currentVersion, this._release);

  final String currentVersion;
  final _AppRelease _release;
  String get latestVersion => _release.version;
  String get url => _release.url;
  bool get prerelease => _release.prerelease;
  List<String> get changelog => _release.changelog;
}

class _AppRelease {
  const _AppRelease(this.version, this.url, this.prerelease, this.changelog);

  final String version;
  final String url;
  final bool prerelease;
  final List<String> changelog;

  factory _AppRelease.read(Object? value, {bool? expectedPrerelease}) {
    if (value case {'version': final String version, 'url': final String url}
        when _validVersion(version) != null &&
            url ==
                'https://github.com/LTCpond/neuq-one/releases/tag/v$version') {
      final object = value as Map;
      final flag = object.containsKey('prerelease')
          ? object['prerelease']
          : false;
      if (flag is bool &&
          (expectedPrerelease == null || expectedPrerelease == flag)) {
        final change = object['changelog'];
        return _AppRelease(
          version,
          url,
          flag,
          List.unmodifiable(
            change is List
                ? change
                      .whereType<String>()
                      .map(_plainText)
                      .where((line) => line.isNotEmpty)
                      .take(5)
                : const <String>[],
          ),
        );
      }
    }
    throw const FormatException('App 版本信息格式错误');
  }

  static final _controls = RegExp(
    r'[\x00-\x20\x7f-\x9f\u2028-\u202e\u2066-\u2069]+',
  );

  static String _plainText(String value) => String.fromCharCodes(
    value.replaceAll(_controls, ' ').trim().runes.take(160),
  ).trimRight();

  Map<String, Object> toJson() => {
    'version': version,
    'url': url,
    'prerelease': prerelease,
    'changelog': changelog,
  };

  AppUpdateAvailable forInstalled(String installed) =>
      AppUpdateAvailable._(installed, this);
}

final _versionPattern = RegExp(
  r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
);

String? _validVersion(Object? value) =>
    value is String &&
        value.length <= 128 &&
        _versionPattern.stringMatch(value) == value
    ? value
    : null;

String? _higherVersion(String? first, String? second) => first == null
    ? second
    : second == null || _compareVersions(first, second) >= 0
    ? first
    : second;

int _compareVersions(String first, String second) {
  final a = first.split('.');
  final b = second.split('.');
  for (var i = 0; i < a.length; i++) {
    final order = BigInt.parse(a[i]).compareTo(BigInt.parse(b[i]));
    if (order != 0) return order;
  }
  return 0;
}

class AppUpdatesRepository {
  const AppUpdatesRepository(
    this._client, {
    this.channel = _buildChannel,
    this.developmentBuild = false,
  });

  static const _channel = MethodChannel('org.neuqone.neuq_one/app_version');
  static const maxManifestBytes = 16 * 1024;
  final PublicDataClient _client;
  final AppUpdateChannel channel;
  final bool developmentBuild;

  Future<String> installedVersion() async {
    final version = await _channel.invokeMethod<String>('getVersion');
    if (version == null) throw const FormatException('无法识别当前 App 版本');
    final baseVersion = developmentBuild && version.endsWith('-dev')
        ? version.substring(0, version.length - '-dev'.length)
        : version;
    if (_validVersion(baseVersion) == null) {
      throw const FormatException('无法识别当前 App 版本');
    }
    return version;
  }

  Future<AppUpdateResult> checkForUpdate() async {
    final response = await _client.getJson(
      '/assets/app/latest.json',
      source: PublicDataSource.assets,
      revalidate: true,
      maxBytes: maxManifestBytes,
      decode: _readManifest,
    );
    _updateLog(
      DiagnosticStage.check,
      level: DiagnosticSeverity.debug,
      code: channel == AppUpdateChannel.beta
          ? DiagnosticCode.betaChannel
          : DiagnosticCode.stableChannel,
    );
    final latest = response.body;
    if (latest == null) {
      _updateLog(
        DiagnosticStage.check,
        code: DiagnosticCode.noPublishedRelease,
        level: DiagnosticSeverity.info,
      );
      return const NoPublishedAppRelease();
    }
    if (developmentBuild) {
      return PublishedAppVersion(latest.version, prerelease: latest.prerelease);
    }
    final installed = await installedVersion();
    final newer = _compareVersions(latest.version, installed) > 0;
    _updateLog(
      DiagnosticStage.check,
      code: newer ? DiagnosticCode.updateAvailable : DiagnosticCode.upToDate,
      level: DiagnosticSeverity.info,
    );
    return newer ? latest.forInstalled(installed) : const AppUpToDate();
  }

  _AppRelease? _readManifest(String body) {
    final json = jsonDecode(body);
    if (json case {'schemaVersion': 1, 'release': final stable}) {
      var latest = stable == null
          ? null
          : _AppRelease.read(stable, expectedPrerelease: false);
      final beta = json['prerelease'];
      if (channel == AppUpdateChannel.beta && beta != null) {
        final candidate = _AppRelease.read(beta, expectedPrerelease: true);
        // A stable release wins ties at the same version.
        if (latest == null ||
            _compareVersions(candidate.version, latest.version) > 0) {
          latest = candidate;
        }
      }
      return latest;
    }
    throw const FormatException('App 版本信息格式错误');
  }
}

void _updateLog(
  DiagnosticStage stage, {
  DiagnosticSeverity level = DiagnosticSeverity.warn,
  DiagnosticCode? code,
  Object? error,
}) => diagnostics.record(
  DiagnosticModule.updates,
  stage,
  level: level,
  code: code,
  error: error,
);
