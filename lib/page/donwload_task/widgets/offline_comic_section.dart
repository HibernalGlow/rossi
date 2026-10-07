import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_entry/models/unified_comic_list_item_mapper.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';

/// 已离线（有下载记录）的漫画，按最近下载排序。
Stream<List<UnifiedComicDownload>> watchOfflineComics() {
  return objectbox.unifiedDownloadBox
      .query(UnifiedComicDownload_.deleted.equals(false))
      .order(UnifiedComicDownload_.downloadedAt, flags: Order.descending)
      .watch(triggerImmediately: true)
      .map((query) => query.find());
}

/// 离线漫画区：与书架同一套封面网格、同一张封面卡（`ComicSimplifyEntry`）。
///
/// 返回的是 sliver，调用方直接接在自己的 slivers 列表后面。
List<Widget> offlineComicSlivers(
  BuildContext context,
  List<UnifiedComicDownload> records,
) {
  final theme = Theme.of(context);
  final header = SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            t.download.offlineTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Text(
            '${records.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  if (records.isEmpty) {
    return [
      header,
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            t.download.offlineEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ];
  }

  return [
    header,
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      sliver: SliverGrid(
        gridDelegate: buildComicSimplifyEntryGridDelegate(),
        delegate: SliverChildBuilderDelegate((context, index) {
          final record = records[index];
          return ComicSimplifyEntry(
            key: ValueKey('offline-${record.uniqueKey}'),
            info: unifiedComicFromUnifiedDownload(
              record,
            ).toSimplifyEntryInfo(),
            type: ComicEntryType.download,
          );
        }, childCount: records.length),
      ),
    ),
  ];
}
