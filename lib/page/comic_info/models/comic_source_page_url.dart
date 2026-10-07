import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/service/comic_source_page/comic_source_page_store.dart';

/// 详情页「在原站打开」要跳的地址，按可靠性从高到低找：
/// ① 插件在详情里直接给的约定键；② 宿主早前从**列表项**记下的链接。
///
/// 故意不捡 chip 上的 `openWeb` 动作：插件用它指的多数是作者页 / 分类页，
/// 点完看着像「跳成功了」，其实不是这一本书 —— 宁可不显示，也不能跳错。
///
/// 键与收藏/历史同一口径（`图源:漫画 id`），所以从书架、历史、下载进来也命中。
Future<String> resolveComicSourcePageUrl({
  required NormalComicAllInfo? info,
  required String from,
  required String comicId,
  ComicSourcePageStore? store,
}) async {
  final sourceStore = store ?? ComicSourcePageStore.instance;

  for (final extern in <Map<String, dynamic>?>[
    info?.comicInfo.extern,
    info?.extern,
  ]) {
    final url = ComicSourcePageStore.urlFromExtern(extern);
    if (url.isNotEmpty) {
      // 顺手记下来：同一本书下次从收藏/历史进来，手上只有 id 时也能跳。
      sourceStore.rememberUrl(source: from, comicId: comicId, url: url);
      return url;
    }
  }

  await sourceStore.load();
  return sourceStore.urlOf(from, comicId);
}
