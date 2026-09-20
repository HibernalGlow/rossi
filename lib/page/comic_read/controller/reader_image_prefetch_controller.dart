import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/comic_read/widgets/modes/read_mode_utils.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';

/// 负责把当前阅读位置之后的图片提前写入图片缓存。
///
/// 预加载只负责网络/文件缓存，不直接创建图片 Widget，避免把大量图片加入
/// 当前页面的布局树；真正显示时仍由阅读模式 Widget 负责加载和布局。
class ReaderImagePrefetchController {
  final Set<String> _requestedKeys = <String>{};
  bool _disposed = false;

  Future<void> prefetch({
    required List<ReadModeEntry> entries,
    required String comicId,
    required String from,
    required int count,
  }) async {
    if (_disposed || count <= 0 || entries.isEmpty) return;
    if (isLocalComicSource(from, comicId)) return;

    final pending = <({ReadModeEntry entry, String key})>[];
    for (final entry in entries.take(count)) {
      if (_disposed) return;
      final doc = entry.doc;
      final chapterId = entry.chapterId;
      if (entry.type != ReadModeEntryType.image ||
          doc == null ||
          chapterId == null ||
          chapterId.isEmpty ||
          doc.extern['isLocalGpu'] == true ||
          isLocalComicSource(from, doc.fileServer)) {
        continue;
      }

      final storageChapterId = doc.storageChapterId.trim();
      final resolvedChapterId = storageChapterId.isNotEmpty
          ? storageChapterId
          : chapterId;
      final key = _buildKey(
        from: from,
        comicId: comicId,
        chapterId: resolvedChapterId,
        path: doc.path,
      );
      if (_requestedKeys.add(key)) {
        pending.add((entry: entry, key: key));
      }
    }

    // 预取以前逐页 await：当前页、下一页、下下页会形成串行下载，用户翻得快时
    // 下一页往往还没落盘。开一个小的固定并发窗口，让网络/磁盘与解码重叠；
    // 不使用 Future.wait 全量并发，避免一次翻页把连接数和内存都打满。
    final int workerCount = pending.length < 3 ? pending.length : 3;
    var next = 0;
    Future<void> worker() async {
      while (!_disposed) {
        if (next >= pending.length) return;
        final item = pending[next++];
        final entry = item.entry;
        final doc = entry.doc!;
        final chapterId = entry.chapterId!;
        final storageChapterId = doc.storageChapterId.trim();
        try {
          final cachedPath = await getCachePicture(
            from: from,
            url: doc.fileServer,
            path: doc.path,
            cartoonId: comicId,
            chapterId: chapterId,
            storageChapterId: storageChapterId,
            pictureType: PictureType.page,
            extern: doc.extern,
          );
          if (cachedPath == '404') _requestedKeys.remove(item.key);
        } catch (_) {
          _requestedKeys.remove(item.key);
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
  }

  void dispose() {
    _disposed = true;
    _requestedKeys.clear();
  }

  String _buildKey({
    required String from,
    required String comicId,
    required String chapterId,
    required String path,
  }) => '$from|$comicId|$chapterId|$path';
}
