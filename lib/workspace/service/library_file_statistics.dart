import 'dart:async';
import 'dart:io';

/// 可重建的布局度量，不改变文件核心的排序、筛选或导航状态。
class LibraryFileStatistics {
  const LibraryFileStatistics(this.count, this.bytes, {this.complete = true});
  final int count;
  final int bytes;
  final bool complete;
}

/// 同时最多两条异步枚举；换目录时取消旧批次，链接不跟随，缓存有容量上限。
class LibraryFileStatisticsCache {
  final _cache = <String, (DateTime, LibraryFileStatistics)>{};
  int _generation = 0;
  String? _request;
  bool _disposed = false;
  final Map<String, LibraryFileStatistics> values = {};

  Future<void> prepare(
    List<String> directories, {
    required bool recursive,
    required bool showHidden,
    required String revision,
    required void Function() onReady,
  }) async {
    final request =
        '$revision:$recursive:$showHidden:${directories.join('\u0000')}';
    if (_disposed || _request == request) return;
    _request = request;
    final generation = ++_generation;
    values.clear();
    var cursor = 0;
    final now = DateTime.now();
    Future<void> worker() async {
      while (!_disposed &&
          generation == _generation &&
          cursor < directories.length) {
        final path = directories[cursor++];
        final key = '$path:$recursive:$showHidden';
        final cached = _cache[key];
        LibraryFileStatistics? stats;
        if (cached != null &&
            now.difference(cached.$1) < const Duration(minutes: 2)) {
          stats = cached.$2;
        } else {
          stats = await scanLibraryDirectory(
            path,
            recursive: recursive,
            showHidden: showHidden,
            cancelled: () => _disposed || generation != _generation,
          );
        }
        if (_disposed || generation != _generation) return;
        if (stats != null) {
          values[path] = stats;
          _cache[key] = (now, stats);
          if (_cache.length > 128) _cache.remove(_cache.keys.first);
        }
      }
    }

    await Future.wait([worker(), worker()]);
    if (!_disposed && generation == _generation) onReady();
  }

  void invalidate() {
    _cache.clear();
    _request = null;
    _generation++;
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}

/// 数量含目录条目，体积只累加普通文件；无权限区域标记为不完整。
Future<LibraryFileStatistics?> scanLibraryDirectory(
  String root, {
  required bool recursive,
  required bool showHidden,
  required bool Function() cancelled,
}) async {
  var count = 0;
  var bytes = 0;
  var complete = true;
  final pending = <String>[root];
  while (pending.isNotEmpty) {
    if (cancelled()) return null;
    final directory = pending.removeLast();
    try {
      await for (final entity in Directory(
        directory,
      ).list(followLinks: false)) {
        if (cancelled()) return null;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!showHidden && name.startsWith('.')) continue;
        if (entity is Link) continue;
        count++;
        if (entity is File) {
          try {
            bytes += (await entity.stat()).size;
          } on FileSystemException {
            complete = false;
          }
        } else if (recursive && entity is Directory) {
          pending.add(entity.path);
        }
      }
    } on FileSystemException {
      complete = false;
    }
  }
  return LibraryFileStatistics(count, bytes, complete: complete);
}
