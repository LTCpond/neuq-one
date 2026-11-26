import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/public_data_client.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/cache_files.dart';

final campusMapRepositoryProvider = Provider<CampusMapRepository>(
  (ref) => CampusMapRepository(
    ref.watch(publicDataClientProvider),
    getApplicationSupportDirectory,
  ),
);

final campusMapProvider = StreamProvider.autoDispose<CampusMap>(
  (ref) => ref.watch(campusMapRepositoryProvider).load(),
  retry: (_, _) => null,
);

class CampusMap {
  const CampusMap(
    this.bytes, {
    this.validators,
    this.updatedAt,
    this.isOffline = false,
  });

  final Uint8List bytes;
  final PublicDataValidators? validators;
  final DateTime? updatedAt;
  final bool isOffline;
}

class CampusMapRepository {
  CampusMapRepository(this._client, this._directory);

  static const _path = '/assets/maps/campus-map.png';
  static const _fileName = 'neuq_one_campus_map.cache';
  static const _maxBytes = 25 * 1024 * 1024;
  static const _maxHeaderBytes = 8 * 1024;
  final PublicDataClient _client;
  final Future<Directory> Function() _directory;
  Future<CampusMap>? _inFlight;
  final _writes = CacheWrites();

  Future<List<FileSystemEntity>> _cacheFiles() async {
    final directory = await _directory();
    if (!await directory.exists()) return [];
    return directory.list(followLinks: false).where((entity) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      return name == _fileName || name.startsWith('neuq_one_campus_map-');
    }).toList();
  }

  Future<int> cacheBytes() async =>
      (await Future.wait((await _cacheFiles()).map(cacheFileBytes)))
          .fold<int>(0, (sum, bytes) => sum + bytes);

  Future<void> clearCache() {
    final clearing = _writes.clear(() async {
      await Future.wait((await _cacheFiles()).map(deleteCacheEntity));
    });
    _inFlight = null;
    return clearing;
  }

  Stream<CampusMap> load() async* {
    final version = _writes.version;
    final cached = await readCached();
    if (!_writes.current(version)) return;
    if (cached != null) yield cached;
    try {
      if (!_writes.current(version)) return;
      final updated = await refresh(cached);
      if (_writes.current(version) && !identical(updated, cached)) {
        yield updated;
      }
    } on PublicDataException {
      if (cached == null) rethrow;
      if (_writes.current(version)) {
        yield CampusMap(
          cached.bytes,
          validators: cached.validators,
          updatedAt: cached.updatedAt,
          isOffline: true,
        );
      }
    }
  }

  Future<CampusMap?> readCached() async {
    try {
      final file = File.fromUri((await _directory()).uri.resolve(_fileName));
      if (!await file.exists()) return null;
      if (await file.length() > _maxBytes + _maxHeaderBytes) return null;
      final entry = await file.readAsBytes();
      final separator = entry.indexOf(0x0a);
      if (separator < 0 || separator >= _maxHeaderBytes) return null;
      final header = jsonDecode(
        utf8.decode(entry.sublist(0, separator)),
      ) as Map<String, dynamic>;
      final bytes = Uint8List.sublistView(entry, separator + 1);
      final isPng = _isPng(bytes);
      if (!isPng && !_isLegacyWebP(bytes)) return null;
      await _validateImage(bytes);
      final legacyOrigin = Uri.tryParse(header['origin'] as String? ?? '');
      final resource = header['resource'] is String
          ? Uri.tryParse(header['resource'] as String)
          : legacyOrigin != null && legacyOrigin.hasAuthority
          ? legacyOrigin.resolve(_path)
          : null;
      return CampusMap(
        bytes,
        validators: isPng && resource != null
            ? PublicDataValidators(
                resource,
                etag: header['etag'] as String?,
                lastModified: header['lastModified'] as String?,
              )
            : null,
        updatedAt:
            DateTime.tryParse(header['updatedAt'] as String? ?? '') ??
            await file.lastModified(),
      );
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.read,
        error: error,
      );
      return null;
    }
  }

  Future<CampusMap> refresh(CampusMap? cached) {
    final version = _writes.version;
    return _inFlight ??= _refresh(cached, version).whenComplete(() {
      if (_writes.current(version)) _inFlight = null;
    });
  }

  Future<CampusMap> _refresh(CampusMap? cached, int? version) async {
    if (version == null) throw const FormatException('正在清理校园地图缓存');
    final response = await _client.getBytes(
      _path,
      source: PublicDataSource.assets,
      accept: 'image/png',
      validators: cached?.validators,
      revalidate: true,
      timeout: const Duration(seconds: 30),
      maxBytes: _maxBytes,
      decode: (bytes) async {
        if (!_isPng(bytes)) throw const FormatException('校园地图不是有效的 PNG 文件');
        try {
          await _validateImage(bytes);
        } on Exception {
          throw const FormatException('校园地图无法解码');
        }
        return bytes;
      },
    );
    final validators = response.validators(previous: cached?.validators);
    if (response.notModified &&
        cached!.validators?.etag == validators.etag &&
        cached.validators?.lastModified == validators.lastModified) {
      return cached;
    }
    final map = CampusMap(
      response.body ?? cached!.bytes,
      validators: validators,
      updatedAt: response.notModified
          ? cached!.updatedAt
          : DateTime.now().toUtc(),
    );
    try {
      await _writes.write(version, () => _write(map));
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.write,
        error: error,
      );
    }
    return map;
  }

  Future<void> _write(CampusMap map) async {
    final header = {
      'resource': map.validators?.resource.toString(),
      'etag': map.validators?.etag,
      'lastModified': map.validators?.lastModified,
      'updatedAt': map.updatedAt?.toUtc().toIso8601String(),
    };
    final metadata = utf8.encode('${jsonEncode(header)}\n');
    if (metadata.length > _maxHeaderBytes) return;
    final directory = await _directory();
    await directory.create(recursive: true);
    // Store the validators together with the image and replace them in one rename.
    final staging = await directory.createTemp('neuq_one_campus_map-');
    try {
      final file = File.fromUri(staging.uri.resolve(_fileName));
      final output = await file.open(mode: FileMode.write);
      try {
        await output.writeFrom(metadata);
        await output.writeFrom(map.bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      await file.rename(File.fromUri(directory.uri.resolve(_fileName)).path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static bool _isPng(Uint8List bytes) {
    if (bytes.length < 20) return false;
    final data = ByteData.sublistView(bytes);
    // Check the PNG signature and complete IEND chunk before decoding.
    return data.getUint32(0) == 0x89504E47 &&
        data.getUint32(4) == 0x0D0A1A0A &&
        data.getUint32(bytes.length - 12) == 0 &&
        data.getUint32(bytes.length - 8) == 0x49454E44 &&
        data.getUint32(bytes.length - 4) == 0xAE426082;
  }

  static bool _isLegacyWebP(Uint8List bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
      String.fromCharCodes(bytes, 8, 12) == 'WEBP' &&
      ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 ==
          bytes.length;

  static Future<void> _validateImage(Uint8List bytes) async {
    if (bytes.length > _maxBytes) throw const FormatException('校园地图文件过大');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 8192 ||
            descriptor.height > 8192 ||
            descriptor.width * descriptor.height > 32000000) {
          throw const FormatException('校园地图尺寸过大');
        }
        final codec = await descriptor.instantiateCodec();
        try {
          if (codec.frameCount != 1) {
            throw const FormatException('校园地图应为静态图片');
          }
          (await codec.getNextFrame()).image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
