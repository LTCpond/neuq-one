import 'dart:io';

/// Invalidates downloads that started before a clear and waits for any disk
/// writes already in progress before deleting their output.
class CacheWrites {
  int _version = 0;
  int? get version => _clearing == null ? _version : null;
  final _writing = <Future<void>>{};
  Future<void>? _clearing;

  bool current(int? version) => version != null && version == this.version;

  Future<void> write(int? version, Future<void> Function() operation) async {
    if (!current(version)) return;
    final writing = Future.sync(operation);
    _writing.add(writing);
    try {
      await writing;
    } finally {
      _writing.remove(writing);
    }
  }

  Future<void> clear(Future<void> Function() operation) =>
      _clearing ??= _clear(operation).whenComplete(() => _clearing = null);

  Future<void> _clear(Future<void> Function() operation) async {
    _version++;
    await Future.wait(
      _writing.toList().map((future) => future.catchError((Object _) {})),
    );
    await operation();
  }
}

Future<int> cacheFileBytes(FileSystemEntity entity) async {
  final type = await FileSystemEntity.type(entity.path, followLinks: false);
  if (type == FileSystemEntityType.file) return File(entity.path).length();
  if (type != FileSystemEntityType.directory) return 0;
  var size = 0;
  await for (final file in Directory(
    entity.path,
  ).list(recursive: true, followLinks: false)) {
    if (file is File) size += await file.length();
  }
  return size;
}

Future<void> deleteCacheEntity(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: entity is Directory);
  } on FileSystemException {
    if (await FileSystemEntity.type(entity.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      rethrow;
    }
  }
}
