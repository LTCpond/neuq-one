import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/public_data_client.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/cache_files.dart';
import '../../../core/storage/picker_cache.dart';
import '../domain/school_policy.dart';

final schoolPolicyRepositoryProvider = Provider<SchoolPolicyRepository>(
  (ref) => SchoolPolicyRepository(
    ref.watch(publicDataClientProvider),
    getApplicationSupportDirectory,
  ),
);

final schoolPoliciesProvider = StreamProvider.autoDispose<SchoolPolicyCatalog>(
  (ref) => ref.watch(schoolPolicyRepositoryProvider).loadCatalog(),
  retry: (_, _) => null,
);

final schoolPolicyPdfProvider = FutureProvider.autoDispose
    .family<Uint8List, SchoolPolicy>(
      (ref, policy) =>
          ref.watch(schoolPolicyRepositoryProvider).loadPdf(policy),
      retry: (_, _) => null,
    );

final saveSchoolPolicyProvider = Provider<SchoolPolicySaver>(
  (ref) => (policy, bytes) async {
    final filename = policy.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    return await pickerCache.run(
          () => FilePicker.saveFile(
            dialogTitle: '保存学校政策',
            fileName: '$filename.pdf',
            mimeType: 'application/pdf',
            bytes: bytes,
          ),
        ) !=
        null;
  },
);

typedef SchoolPolicySaver = Future<bool> Function(
  SchoolPolicy policy,
  Uint8List bytes,
);

class SchoolPolicyCatalog {
  const SchoolPolicyCatalog(
    this.policies, {
    this.updatedAt,
    this.isOffline = false,
  });

  final List<SchoolPolicy> policies;
  final DateTime? updatedAt;
  final bool isOffline;
}

typedef _CatalogCache = ({
  Uint8List bytes,
  SchoolPolicyCatalog catalog,
  PublicDataValidators? validators,
});

class SchoolPolicyRepository {
  SchoolPolicyRepository(this._client, this._directory);

  static const _root = '/assets/policies';
  static const _index = 'index.json';
  static const _catalogCache = 'index.cache';
  static const _maxIndexBytes = 128 * 1024;
  static const _maxHeaderBytes = 8 * 1024;
  static const _maxPdfBytes = 25 * 1024 * 1024;
  static final _idPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static final _digestPattern = RegExp(r'^[a-f0-9]{64}$');

  final PublicDataClient _client;
  final Future<Directory> Function() _directory;
  final _writes = CacheWrites();
  Future<SchoolPolicyCatalog>? _inFlightCatalog;

  Future<int> cacheBytes() async => cacheFileBytes(await _cacheDirectory());

  Future<void> clearCache() {
    _inFlightCatalog = null;
    return _writes.clear(() async {
      await deleteCacheEntity(await _cacheDirectory());
    });
  }

  Stream<SchoolPolicyCatalog> loadCatalog() async* {
    final version = _writes.version;
    final cached =
        await _readCatalog(_catalogCache) ?? await _readCatalog(_index);
    if (!_writes.current(version)) return;
    final catalog = cached?.catalog;
    if (catalog != null) yield catalog;

    try {
      if (!_writes.current(version)) return;
      final pending = _inFlightCatalog ??= _refreshCatalog(cached, version)
          .whenComplete(() {
            if (_writes.current(version)) _inFlightCatalog = null;
          });
      final updated = await pending;
      if (_writes.current(version) && !identical(updated, catalog)) {
        yield updated;
      }
    } on PublicDataException {
      if (catalog == null) rethrow;
      if (_writes.current(version)) {
        yield SchoolPolicyCatalog(
          catalog.policies,
          updatedAt: catalog.updatedAt,
          isOffline: true,
        );
      }
    }
  }

  Future<SchoolPolicyCatalog> _refreshCatalog(
    _CatalogCache? cached,
    int? version,
  ) async {
    final response = await _client.getBytes(
      '$_root/$_index',
      source: PublicDataSource.assets,
      accept: 'application/json',
      revalidate: true,
      validators: cached?.validators,
      maxBytes: _maxIndexBytes,
      decode: (bytes) => (bytes, _parseCatalog(bytes)),
    );
    final (bytes, policies) =
        response.body ?? (cached!.bytes, cached.catalog.policies);
    final catalog = cached != null && listEquals(bytes, cached.bytes)
        ? cached.catalog
        : SchoolPolicyCatalog(policies, updatedAt: DateTime.now().toUtc());
    final previous = cached?.validators;
    final validators = response.validators(previous: previous);
    if (!identical(catalog, cached?.catalog) ||
        validators.resource != previous?.resource ||
        validators.etag != previous?.etag ||
        validators.lastModified != previous?.lastModified) {
      final metadata = {
        'resource': validators.resource.toString(),
        'etag': validators.etag,
        'lastModified': validators.lastModified,
        'updatedAt': catalog.updatedAt?.toUtc().toIso8601String(),
      };
      final header = utf8.encode('${jsonEncode(metadata)}\n');
      if (header.length <= _maxHeaderBytes) {
        await _writes.write(
          version,
          () =>
              _store(_catalogCache, Uint8List.fromList([...header, ...bytes])),
        );
      }
    }
    return catalog;
  }

  Future<_CatalogCache?> _readCatalog(String filename) async {
    final hasMetadata = filename == _catalogCache;
    final entry = await _read(
      filename,
      _maxIndexBytes + (hasMetadata ? _maxHeaderBytes : 0),
    );
    if (entry == null) return null;
    try {
      final separator = hasMetadata ? entry.indexOf(0x0a) : -1;
      if (hasMetadata && (separator < 0 || separator >= _maxHeaderBytes)) {
        throw const FormatException('政策目录缓存头无效');
      }
      final header = separator < 0
          ? const <String, dynamic>{}
          : jsonDecode(utf8.decode(entry.sublist(0, separator)))
                as Map<String, dynamic>;
      final bytes = Uint8List.sublistView(entry, separator + 1);
      if (bytes.length > _maxIndexBytes) return null;
      final resource = Uri.tryParse(header['resource'] as String? ?? '');
      final validators = resource != null && resource.hasAuthority
          ? PublicDataValidators(
              resource,
              etag: header['etag'] as String?,
              lastModified: header['lastModified'] as String?,
            )
          : null;
      final policies = _parseCatalog(bytes);
      final updatedAt =
          DateTime.tryParse(header['updatedAt'] as String? ?? '') ??
          await File.fromUri((await _cacheDirectory()).uri.resolve(filename))
              .lastModified();
      return (
        bytes: bytes,
        catalog: SchoolPolicyCatalog(policies, updatedAt: updatedAt),
        validators: validators,
      );
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.decode,
        error: error,
      );
      return null;
    }
  }

  Future<Uint8List> loadPdf(SchoolPolicy policy) async {
    final version = _writes.version;
    if (version == null) throw const FormatException('正在清理学校政策缓存');
    if (!_idPattern.hasMatch(policy.id) ||
        policy.id.length > 64 ||
        !_digestPattern.hasMatch(policy.sha256)) {
      throw const FormatException('学校政策文件标识无效');
    }
    final name = '${policy.id}-${policy.sha256}.pdf';
    final legacyName = '${policy.id}.pdf';
    for (final filename in [name, legacyName]) {
      final cached = await _read(filename, _maxPdfBytes);
      if (cached != null && _validPdf(cached, policy.sha256)) return cached;
    }

    final response = await _client.getBytes(
      '$_root/$legacyName',
      source: PublicDataSource.assets,
      accept: 'application/pdf',
      revalidate: true,
      maxBytes: _maxPdfBytes,
      timeout: const Duration(seconds: 30),
      decode: (bytes) {
        if (!_validPdf(bytes, policy.sha256)) {
          throw const FormatException('学校政策文件校验失败');
        }
        return bytes;
      },
    );
    final bytes = response.body!;
    await _writes.write(version, () => _store(name, bytes));
    return bytes;
  }

  static bool _validPdf(Uint8List bytes, String digest) =>
      bytes.length >= 5 &&
      String.fromCharCodes(bytes, 0, 5) == '%PDF-' &&
      sha256.convert(bytes).toString() == digest;

  static List<SchoolPolicy> _parseCatalog(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes));
    if (json case {'version': 1, 'policies': final List<dynamic> rows}) {
      final policies = <SchoolPolicy>[];
      final ids = <String>{};
      for (final row in rows) {
        if (row
            case {
              'id': final String id,
              'title': final String title,
              'category': final String category,
              'sha256': final String digest,
            }
            when _idPattern.hasMatch(id) &&
                id.length <= 64 &&
                title.trim().isNotEmpty &&
                category.trim().isNotEmpty &&
                _digestPattern.hasMatch(digest) &&
                ids.add(id)) {
          policies.add(
            SchoolPolicy(
              id: id,
              title: title,
              category: category,
              sha256: digest,
            ),
          );
        } else {
          throw const FormatException('学校政策条目格式错误');
        }
      }
      return List.unmodifiable(policies);
    }
    throw const FormatException('学校政策目录格式错误');
  }

  Future<Directory> _cacheDirectory() async =>
      Directory.fromUri((await _directory()).uri.resolve('school-policies/'));

  Future<Uint8List?> _read(String name, int maxBytes) async {
    try {
      final file = File.fromUri((await _cacheDirectory()).uri.resolve(name));
      if (!await file.exists()) return null;
      if (await file.length() <= maxBytes) return await file.readAsBytes();
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.read,
        error: error,
      );
    }
    return null;
  }

  Future<void> _store(String name, Uint8List bytes) async {
    try {
      final directory = await (await _cacheDirectory()).create(recursive: true);
      final staging = await directory.createTemp('policy-');
      final temporary = File.fromUri(staging.uri.resolve(name));
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(File.fromUri(directory.uri.resolve(name)).path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
        await staging.delete();
      }
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.write,
        error: error,
      );
    }
  }
}
