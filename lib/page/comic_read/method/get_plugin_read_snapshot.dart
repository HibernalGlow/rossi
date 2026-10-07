import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/model/comic_read_snapshot.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/page/comic_read/model/plugin_read_launch.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/adapters/download_chapter_matcher.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';

Future<NormalComicEpInfo> getPluginReadSnapshot(
  String comicId,
  int order,
  String from,
  dynamic comicInfo,
  String? selectedChapterId,
  String requestId,
  String logicalKey,
  String storageChapterId,
  ChapterExtern chapterExtern,
) async {
  const adapter = DownloadChapterAdapter();
  const matcher = DownloadChapterMatcher();
  DownloadChapter? chapter;
  if (requestId.trim().isEmpty && logicalKey.trim().isEmpty) {
    final chapterRefs = resolveUnifiedComicChapters(comicInfo, from);
    final chapters = chapterRefs.map(adapter.fromChapterRef).toList();
    final normalizedChapterId = (selectedChapterId ?? '').trim();
    if (normalizedChapterId.isNotEmpty) {
      chapter = matcher.find(chapters, normalizedChapterId);
    }
    chapter ??= matcher.findByOrder(chapters, order);
    chapter ??= (chapters.isNotEmpty ? chapters.first : null);
  }

  final resolvedChapterId = _resolveReadSnapshotChapterId(
    chapter,
    requestId,
    order,
  );

  final extern = <String, dynamic>{
    ...chapterExtern,
    ...?chapter?.extern,
    'order': order,
  };

  final candidates = <String>[];
  candidates.add(resolvedChapterId);
  if (comicId != resolvedChapterId) {
    candidates.add(comicId);
  }
  candidates.add('');

  final snapshotSw = Stopwatch()..start();
  var attempts = 0;
  ComicReadSnapshot? snapshot;
  // 封面「直接阅读」已经把这一章的快照取回来了（那一次同时带回整本目录）。
  // 章节 key 对得上就复用，对不上照旧回源 —— 所以这条路最差等于改之前。
  final launch = comicInfo is PluginReadLaunch ? comicInfo : null;
  final reusedLaunchSnapshot =
      launch != null && launch.matches(resolvedChapterId);
  if (reusedLaunchSnapshot) {
    snapshot = launch.snapshot;
  } else {
    for (final candidate in candidates) {
      attempts++;
      final current = await _fetchSnapshot(
        from: from,
        comicId: comicId,
        order: order,
        chapterId: candidate,
        extern: extern,
      );
      snapshot = current;
      if (current.chapter.pages.isNotEmpty) {
        break;
      }
    }
  }
  logger.d(
    '[read-start] read-snapshot from=$from '
    '${reusedLaunchSnapshot ? "复用起读快照" : "候选=$attempts/${candidates.length}"} '
    '${snapshotSw.elapsedMilliseconds}ms '
    '页=${snapshot?.chapter.pages.length ?? 0} 章节=${snapshot?.chapters.length ?? 0}',
  );

  snapshot ??= const ComicReadSnapshot(
    source: '',
    comic: ComicReadSnapshotComic(id: '', source: '', title: ''),
    chapter: ComicReadSnapshotChapter(id: '', name: '', order: 0, pages: []),
    chapters: [],
  );

  final fallbackChapterId = snapshot.chapter.id.isNotEmpty
      ? snapshot.chapter.id
      : resolvedChapterId;
  final logicalChapterId = _resolveLogicalChapterId(
    chapter,
    selectedChapterId,
    logicalKey,
    order,
    fallbackChapterId,
  );
  final resolvedStorageChapterId = storageChapterId.trim().isNotEmpty
      ? storageChapterId.trim()
      : chapter?.effectiveStorageId ?? '';
  return snapshot.toNormalEpInfo(
    logicalChapterId: logicalChapterId,
    storageChapterId: resolvedStorageChapterId,
  );
}

String _resolveReadSnapshotChapterId(
  DownloadChapter? chapter,
  String requestId,
  int order,
) {
  final explicitRequestId = requestId.trim();
  if (explicitRequestId.isNotEmpty) {
    return explicitRequestId;
  }

  final requestIdFromChapter = chapter?.effectiveRequestId ?? '';
  if (requestIdFromChapter.isNotEmpty) {
    return requestIdFromChapter;
  }

  return order.toString();
}

String _resolveLogicalChapterId(
  DownloadChapter? chapter,
  String? selectedChapterId,
  String logicalKey,
  int order,
  String fallbackChapterId,
) {
  final explicitLogicalKey = logicalKey.trim();
  if (explicitLogicalKey.isNotEmpty) {
    return explicitLogicalKey;
  }

  final logicalKeyFromChapter = chapter?.id ?? '';
  if (logicalKeyFromChapter.isNotEmpty) {
    return logicalKeyFromChapter;
  }

  final explicitSelectedChapterId = (selectedChapterId ?? '').trim();
  if (explicitSelectedChapterId.isNotEmpty) {
    return explicitSelectedChapterId;
  }

  if (fallbackChapterId.trim().isNotEmpty) {
    return fallbackChapterId.trim();
  }

  return order.toString();
}

Future<ComicReadSnapshot> _fetchSnapshot({
  required String from,
  required String comicId,
  required int order,
  required String chapterId,
  required Map<String, dynamic> extern,
}) async {
  final core = <String, dynamic>{'comicId': comicId};
  if (chapterId.trim().isNotEmpty) {
    core['chapterId'] = chapterId;
  }

  final response = await callUnifiedComicPlugin(
    from: from,
    fnPath: 'getReadSnapshot',
    core: core,
    extern: extern,
  );
  return ComicReadSnapshot.fromMap(response);
}
