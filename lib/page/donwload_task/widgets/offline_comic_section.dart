import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/download/models/unified_comic_download.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';

/// 已离线（有下载记录）的漫画，按最近下载排序。
Stream<List<UnifiedComicDownload>> watchOfflineComics() {
  return objectbox.unifiedDownloadBox
      .query(UnifiedComicDownload_.deleted.equals(false))
      .order(UnifiedComicDownload_.downloadedAt, flags: Order.descending)
      .watch(triggerImmediately: true)
      .map((query) => query.find());
}

/// 下载管理页里的「已离线」区：标题 + 列表（或空态）。
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
    SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _OfflineComicTile(record: records[index]);
      }, childCount: records.length),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 16)),
  ];
}

class _OfflineComicTile extends StatelessWidget {
  final UnifiedComicDownload record;

  const _OfflineComicTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.download_done_rounded, color: Colors.green),
        title: Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_chaptersText()),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          openComicItem(
            context,
            comicId: record.comicId,
            from: record.source,
            type: ComicEntryType.download,
          );
        },
      ),
    );
  }

  /// 「已下 12 / 共 120 章」；拿不到在线目录时只报已下的章数。
  String _chaptersText() {
    final downloaded = _safeCount(() => resolveDownloadChapters(record).length);
    final catalog = _safeCount(() => readChapterCatalog(record).length);
    if (downloaded == null) return '';
    if (catalog == null || catalog <= 0) {
      return t.download.offlineChapterCountOnly(count: downloaded);
    }
    return t.download.offlineChapterCount(
      completed: downloaded,
      total: catalog,
    );
  }

  /// 老记录的 chapters / detailJson 可能是坏 JSON：读不出就当没这条信息，
  /// 不该让整列表红掉。
  int? _safeCount(int Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}
