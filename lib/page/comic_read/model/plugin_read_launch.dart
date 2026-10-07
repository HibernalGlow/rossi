import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/page/comic_read/model/comic_read_snapshot.dart';

/// 起读时**已经取到**的那一次 `getReadSnapshot` 结果。
///
/// 存在的理由：插件的 `getReadSnapshot` 内部本来就会抓一次详情页，并且顺手把
/// 整本章节目录放在 `data.chapters` 里带回来（`wnacg` / `ehentai` / 示例插件
/// 三份实现都是这样）。宿主却在起读前先单独 `await getComicDetail` 抓一遍整本
/// 详情，进阅读器后再 `getReadSnapshot` 又抓一遍 —— 同一本书的回源被做了三次。
///
/// 这里把「快照 + 由它派生的章节目录」打包成详情页同一种角色（`comicInfo`），
/// 于是：
/// - [pushComicReadRoute] 那套解析（选章、eps 数、规范 comicId）原样可用；
/// - [PageBloc] 拿到同一个 `comicInfo` 后，若章节对得上就直接用这份快照，
///   不再回源第二次。
///
/// 章节对不上时**照旧回源**，所以最差情况等于改动前的行为，不会更慢也不会读错章。
class PluginReadLaunch {
  const PluginReadLaunch({
    required this.comicId,
    required this.chapterRefs,
    required this.snapshot,
    required this.fetchedChapterKeys,
  });

  /// 插件在快照里给出的规范 comicId（历史记录的键就用它）。
  final String comicId;

  /// 由 `snapshot.chapters` 派生的整本章节目录。
  final List<UnifiedComicChapterRef> chapterRefs;

  final ComicReadSnapshot snapshot;

  /// 这次快照实际返回的是哪一章 —— 与请求时用的 key、以及插件回写的
  /// `chapter.id` / `requestId` / `logicalKey` 都算数，供阅读器判断「能不能直接用」。
  final Set<String> fetchedChapterKeys;

  /// 这份快照是不是 [PageBloc] 正要取的那一章。空页一律不算（那说明插件没吃这个 key）。
  bool matches(String chapterKey) {
    if (snapshot.chapter.pages.isEmpty) return false;
    final key = chapterKey.trim();
    return key.isNotEmpty && fetchedChapterKeys.contains(key);
  }
}
