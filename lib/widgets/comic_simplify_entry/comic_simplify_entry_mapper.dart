import 'package:zephyr/service/comic_source_page/comic_source_page_store.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/type/pipe.dart';

import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

List<ComicSimplifyEntryInfo> mapToUnifiedComicSimplifyEntryInfoList(
  Iterable<dynamic> items,
) {
  return items.map((item) {
    final comic = item is UnifiedComicListItem
        ? item
        : (item as Map)
              .map((key, value) => MapEntry('$key', value))
              .let(Map<String, dynamic>.from)
              .debug((d) => d['cover'])
              .let(UnifiedComicListItem.fromJson);
    // 卡片这条路上拿到的是**原始 JSON**（聚合搜索、发现页的功能页数据），
    // 没经过列表解析那一站，所以这里也要记一次；`remember` 对同值是无操作，
    // 反复 build 不会变成反复写盘。
    ComicSourcePageStore.instance.remember(
      source: comic.source,
      comicId: comic.id,
      extern: comic.extern,
    );
    return comic.toSimplifyEntryInfo();
  }).toList();
}
