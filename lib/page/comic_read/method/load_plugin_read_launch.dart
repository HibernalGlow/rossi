import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/model/comic_read_snapshot.dart';
import 'package:zephyr/page/comic_read/model/plugin_read_launch.dart';

/// 用**一次** `getReadSnapshot` 同时拿到「章节目录 + 目标章的页列表」，供封面卡
/// 「直接阅读」起读时取代先抓整本详情的做法。
///
/// 返回 null 表示这条路走不通（插件没在快照里给 `chapters`、没实现
/// `getReadSnapshot`、或直接报错），调用方应当退回原来的「先 `getComicDetail`
/// 再进阅读器」那条路 —— 所以这里刻意不把错误往上抛：报错留给那条会正确提示的路，
/// 而不是在最开始就吞掉或弹一个用户看不懂的失败。
Future<PluginReadLaunch?> loadPluginReadLaunch({
  required String comicId,
  required String from,
  UnifiedComicHistory? history,
}) async {
  final core = <String, dynamic>{'comicId': comicId};
  final wantedChapterKey = (history?.chapterId ?? '').trim();
  if (wantedChapterKey.isNotEmpty) {
    core['chapterId'] = wantedChapterKey;
  }
  final extern = <String, dynamic>{};
  final chapterOrder = history?.chapterOrder ?? 0;
  if (chapterOrder > 0) {
    extern['order'] = chapterOrder;
  }

  late final Map<String, dynamic> map;
  try {
    map = await callUnifiedComicPlugin(
      from: from,
      fnPath: 'getReadSnapshot',
      core: core,
      extern: extern,
    );
  } catch (e) {
    logger.w('[read-start] 快照起读不可用，退回整本详情: $e');
    return null;
  }

  final snapshot = ComicReadSnapshot.fromMap(map);
  return pluginReadLaunchFromSnapshot(
    snapshot: snapshot,
    fallbackComicId: comicId,
  );
}

/// 把一次 `getReadSnapshot` 的返回折算成起读用的「目录 + 已取到的那一章」。
///
/// 目录为空即返回 null —— 说明这个插件没在快照里给 `chapters`，调用方得退回
/// 先抓整本详情那条路。
PluginReadLaunch? pluginReadLaunchFromSnapshot({
  required ComicReadSnapshot snapshot,
  required String fallbackComicId,
}) {
  if (snapshot.chapters.isEmpty) {
    return null;
  }

  final chapterRefs = sortChaptersByOrder(
    snapshot.chapters
        .map(
          (ref) => UnifiedComicChapterRef(
            id: ref.id,
            name: ref.name,
            order: ref.order,
            requestId: ref.requestId,
            storageChapterId: ref.storageChapterId,
            logicalKey: ref.logicalKey,
            extern: ref.extern,
          ),
        )
        .toList(),
    (ref) => ref.order,
  );

  final resolvedComicId = snapshot.comic.id.trim();
  return PluginReadLaunch(
    comicId: resolvedComicId.isEmpty ? fallbackComicId : resolvedComicId,
    chapterRefs: chapterRefs,
    snapshot: snapshot,
    fetchedChapterKeys: <String>{
      snapshot.chapter.id,
      snapshot.chapter.requestId,
      snapshot.chapter.logicalKey,
    }.where((key) => key.trim().isNotEmpty).toSet(),
  );
}
