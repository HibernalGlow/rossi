/// 视频物化：把归档里的一个视频条目变成一个**可 seek 的本地文件**。
///
/// 额度与释放规则翻译自 neoview
/// `packages/nodes/neoview/src/application/reader/ReaderSeekableMediaCache.ts:6-60`
/// （单条目 2 GiB / 总量 4 GiB、singleflight、按等待者计数释放）。
///
/// 为什么必须物化：mpv / FFmpeg 走的是「按字节偏移随机读」，而 Rossi 的归档读取
/// 是「一次给整条目的字节」。把 700 MB 的 mp4 从 CBZ 里 `read_entry` 出来再喂
/// 一个内存缓冲，等于同时持有两份 —— 拖进度条会立刻把内存打爆。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一个已就绪的视频源。
class MaterializedVideo {
  const MaterializedVideo({
    required this.filePath,
    required this.fromArchive,
    this.sizeInBytes = 0,
  });

  /// 直接可交给播放引擎的路径。
  final String filePath;

  /// 是否来自归档（决定退出时要不要删临时文件）。
  final bool fromArchive;
  final int sizeInBytes;

  /// 交给 media_kit / mpv 的 URI。
  String get uri => 'file://${Uri.file(filePath).path}';
}

/// 物化额度与淘汰策略。
class VideoMaterializer {
  VideoMaterializer({Duration? keepAlive})
    : _keepAlive = keepAlive ?? const Duration(minutes: 2);

  static const int maxItemBytes = 2 * 1024 * 1024 * 1024;
  static const int maxTotalBytes = 4 * 1024 * 1024 * 1024;

  final Duration _keepAlive;
  final Map<String, _CachedEntry> _entries = <String, _CachedEntry>{};
  final Map<String, Future<MaterializedVideo>> _inFlight =
      <String, Future<MaterializedVideo>>{};
  Future<String> _root() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'rossi-video-cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// 缓存键：**内容身份**而不是播放位置。
  ///
  /// 上游用 `path + entry`，Rossi 多带 `size`：同一本书重新下载后条目名一样、
  /// 内容不一样，只按名字复用会把旧视频继续播给新内容。
  static String cacheKeyFor({
    required String sourcePath,
    required int pageIndex,
    required String entryName,
    required int size,
  }) => '${sha1Hex('$sourcePath|$entryName|$pageIndex|$size')}.bin';

  /// 文件夹来源：不物化，直接用原路径。
  static MaterializedVideo fromFolder(String path, {int size = 0}) =>
      MaterializedVideo(filePath: path, fromArchive: false, sizeInBytes: size);

  /// 归档来源：取字节 → 落盘 → 返回路径。
  ///
  /// [readBytes] 由调用方提供（Rossi 侧就是 `local_page_bytes`），这样这个类
  /// 不依赖 FFI，能在测试里跑真的文件 IO 而不必起一个 Rust 会话。
  Future<MaterializedVideo> materialize({
    required String sourcePath,
    required int pageIndex,
    required String entryName,
    required int entrySize,
    required Future<Uint8List> Function() readBytes,
  }) async {
    final root = await _root();
    final key = cacheKeyFor(
      sourcePath: sourcePath,
      pageIndex: pageIndex,
      entryName: entryName,
      size: entrySize,
    );

    final hit = _entries[key];
    if (hit != null) {
      hit.touch();
      return MaterializedVideo(
        filePath: hit.path,
        fromArchive: true,
        sizeInBytes: hit.bytes,
      );
    }

    // singleflight：同一页被「预览 + 正式播」两个入口同时要时只解一次。
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final work = _write(root, key, entryName, readBytes);
    _inFlight[key] = work;
    try {
      return await work;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<MaterializedVideo> _write(
    String root,
    String key,
    String entryName,
    Future<Uint8List> Function() readBytes,
  ) async {
    final bytes = await readBytes();
    if (bytes.lengthInBytes > maxItemBytes) {
      throw VideoMaterializeLimitExceeded(bytes.lengthInBytes, maxItemBytes);
    }
    await _evictTo(bytes.lengthInBytes);
    final path = p.join(root, '$key${p.extension(entryName)}');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    _entries[key] = _CachedEntry(path: path, bytes: bytes.lengthInBytes);
    _scheduleCleanup();
    return MaterializedVideo(
      filePath: path,
      fromArchive: true,
      sizeInBytes: bytes.lengthInBytes,
    );
  }

  /// 淘汰顺序：先丢最久没被看的，丢到放得下为止。
  Future<void> _evictTo(int incomingBytes) async {
    int total() => _entries.values.fold(0, (sum, e) => sum + e.bytes);
    final byLastSeen = SplayTreeMap<int, List<_CachedEntry>>();
    for (final e in _entries.values) {
      byLastSeen.putIfAbsent(e.lastSeenMs, () => <_CachedEntry>[]).add(e);
    }
    for (final group in byLastSeen.values) {
      if (total() + incomingBytes <= maxTotalBytes) break;
      for (final entry in group) {
        await _drop(entry);
      }
    }
  }

  Future<void> _drop(_CachedEntry entry) async {
    _entries.removeWhere((_, v) => v == entry);
    try {
      await File(entry.path).delete();
    } on FileSystemException {
      // 已经被删了就算成功。
    }
  }

  void _scheduleCleanup() {
    unawaited(
      Future<void>.delayed(_keepAlive * 2, () async {
        final cutoff = DateTime.now()
            .subtract(_keepAlive)
            .millisecondsSinceEpoch;
        final stale = _entries.entries
            .where((e) => e.value.lastSeenMs < cutoff)
            .toList(growable: false);
        for (final e in stale) {
          await _drop(e.value);
        }
      }),
    );
  }

  /// 阅读结束 / 换书时显式清空（音频与磁盘都要立刻还）。
  Future<void> clearAll() async {
    for (final entry in _entries.values.toList(growable: false)) {
      await _drop(entry);
    }
  }
}

class _CachedEntry {
  _CachedEntry({required this.path, required this.bytes})
    : lastSeenMs = DateTime.now().millisecondsSinceEpoch;

  final String path;
  final int bytes;
  int lastSeenMs;

  void touch() => lastSeenMs = DateTime.now().millisecondsSinceEpoch;
}

class VideoMaterializeLimitExceeded implements Exception {
  const VideoMaterializeLimitExceeded(this.actual, this.limit);

  final int actual;
  final int limit;

  @override
  String toString() => '视频条目 $actual 字节，超过单条目上限 $limit 字节';
}

String sha1Hex(String input) =>
    crypto.sha1.convert(utf8.encode(input)).toString();
