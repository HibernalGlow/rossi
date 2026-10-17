import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/service/download/download_storage_layout.dart';
import 'package:zephyr/service/download/download_storage_summary.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/widgets/comic_entry/models/unified_comic_list_item_mapper.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/service/shelf_view_state_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_book_details.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/service/reader/shelf_book_navigation.dart';

/// 已离线（有下载记录）的漫画，按最近下载排序。
Stream<List<UnifiedComicDownload>> watchOfflineComics() {
  return objectbox.unifiedDownloadBox
      .query(UnifiedComicDownload_.deleted.equals(false))
      .order(UnifiedComicDownload_.downloadedAt, flags: Order.descending)
      .watch(triggerImmediately: true)
      .map((query) => query.find());
}

/// 离线漫画区复用书签与历史的六档视图和时间线。
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
          // 空列表不摆按钮：那一下点下去只可能量出「什么都没有」，
          // 而旁边已经写着「还没有已下载的漫画」。
          if (records.isNotEmpty) ...[
            const Spacer(),
            _OfflineStorageStat(records: records),
          ],
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
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: OfflineComicLibrary(records: records),
      ),
    ),
  ];
}

class OfflineComicLibrary extends StatefulWidget {
  const OfflineComicLibrary({super.key, required this.records});

  final List<UnifiedComicDownload> records;

  @override
  State<OfflineComicLibrary> createState() => _OfflineComicLibraryState();
}

class _OfflineComicLibraryState extends State<OfflineComicLibrary> {
  static List<LibraryColumn> get _columns => [
    LibraryColumn(key: 'author', label: '作者', width: 90),
    LibraryColumn(key: 'source', label: '来源', width: 70),
    LibraryColumn(key: 'time', label: t.comicList.downloadedAtLabel, width: 90),
  ];

  final _canvasKey = GlobalKey<LibraryEditorialCanvasState>();
  final _viewMemory = ShelfViewMemory('download-offline');
  final _searchController = TextEditingController();
  LibraryViewMode _viewMode = LibraryViewMode.coverGrid;
  ShelfSort _sort = const ShelfSort(field: ShelfSortField.time);
  String _keyword = '';
  bool _timeline = false;
  bool _viewChosen = false;

  @override
  void initState() {
    super.initState();
    _restoreViewState();
  }

  Future<void> _restoreViewState() async {
    final saved = await _viewMemory.restore();
    if (saved == null || !mounted || _viewChosen) return;
    setState(() {
      _viewMode =
          shelfEnumByName(LibraryViewMode.values, saved.viewMode) ?? _viewMode;
      final field = shelfEnumByName(ShelfSortField.values, saved.sortField);
      if (field != null) {
        _sort = ShelfSort(field: field, ascending: saved.sortAscending);
      }
      _timeline = saved.timeline;
    });
  }

  void _rememberViewState() {
    _viewChosen = true;
    _viewMemory.remember(
      ShelfViewState(
        viewMode: _viewMode.name,
        sortField: _sort.field.name,
        sortAscending: _sort.ascending,
        timeline: _timeline,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entities = {for (final item in widget.records) item.uniqueKey: item};
    final visible = searchAndSortShelf(
      [
        for (final item in widget.records)
          ShelfSearchable(
            key: item.uniqueKey,
            title: item.title,
            author: shelfCreatorName(item.creator),
            source: item.source,
            time: item.downloadedAt,
            haystack: shelfHaystack(
              comicId: item.comicId,
              title: item.title,
              description: item.description,
              creator: item.creator,
              titleMeta: item.titleMeta,
              metadata: item.metadata,
            ),
          ),
      ],
      keyword: _keyword,
      sort: _timeline ? const ShelfSort(field: ShelfSortField.time) : _sort,
    );
    final pluginNames = pluginDisplayNames();
    final navigationEntries = [
      for (final entry in visible)
        if (entities[entry.key] case final item?)
          ShelfBookNavigationEntry(
            key: shelfBookNavigationIdentity(item.source, item.comicId),
            comicId: item.comicId,
            from: item.source,
            type: isLocalComicSource(item.source, item.comicId)
                ? ComicEntryType.history
                : ComicEntryType.download,
          ),
    ];
    final navigationToken = ShelfBookNavigationRegistry.instance.register(
      scope: 'download-offline',
      entries: navigationEntries,
    );
    final rows = [
      for (final entry in visible)
        if (entities[entry.key] case final item?)
          _row(context, item, pluginNames, navigationToken),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfListToolbar(
          presentationButton: LibraryPresentationButton(canvasKey: _canvasKey),
          viewMode: _viewMode,
          onViewMode: (mode) {
            _canvasKey.currentState?.showLegacyView();
            setState(() => _viewMode = mode);
            _rememberViewState();
          },
          sort: _sort,
          onSort: (sort) {
            setState(() => _sort = sort);
            _rememberViewState();
          },
          searchController: _searchController,
          onKeywordChanged: (value) => setState(() => _keyword = value),
          searchHint: t.reader.searchOfflineComics,
          historyScope: 'download-offline',
          count: rows.length,
          timelineOn: _timeline,
          onTimeline: () {
            setState(() => _timeline = !_timeline);
            _rememberViewState();
          },
        ),
        const SizedBox(height: 6),
        LibraryEntryList(
          editorialKey: _canvasKey,
          editorialScope: 'download-offline',
          initialEditorial: false,
          shrinkWrap: true,
          timeline: _timeline,
          timelineTimeOf: (row) =>
              (row.source! as UnifiedComicDownload).downloadedAt,
          detailBuilder: (context, row, close) {
            final item = row.source! as UnifiedComicDownload;
            return LibraryBookDetails(
              entry: row,
              comicId: item.comicId,
              from: item.source,
              extern: {ShelfBookNavigationRegistry.contextKey: navigationToken},
              type: isLocalComicSource(item.source, item.comicId)
                  ? ComicEntryType.history
                  : ComicEntryType.download,
              onClose: close,
            );
          },
          tapOpensDetail: false,
          mode: _viewMode,
          entries: rows,
          onTap: (row) => _open(context, row, navigationToken),
          emptyText: t.reader.noMatchingOfflineComics,
          standalone: true,
          titleColumn: const LibraryColumn(
            key: 'title',
            label: '标题',
            flex: LibraryViewLayout.detailsTitleFlex,
          ),
          columns: _columns,
          sortKey: _sort.field.name,
          sortAscending: _sort.ascending,
          onSort: (key) {
            setState(
              () => _sort = _sort.toggled(ShelfSortField.values.byName(key)),
            );
            _rememberViewState();
          },
        ),
      ],
    );
  }

  LibraryEntry _row(
    BuildContext context,
    UnifiedComicDownload item,
    Map<String, String> pluginNames,
    String navigationToken,
  ) {
    final comic = unifiedComicFromUnifiedDownload(item);
    final cover = comic.cover;
    final author = shelfCreatorName(item.creator);
    final source = shelfSourceLabel(
      source: item.source,
      comicId: item.comicId,
      pluginName: shelfPluginName(pluginNames, item.source),
    );
    final time = formatShelfTime(item.downloadedAt);
    return LibraryEntry(
      key: item.uniqueKey,
      source: item,
      title: item.title,
      description: item.description,
      tags: comic.toSimplifyEntryInfo().tags,
      timestamp: item.downloadedAt,
      section: source,
      subtitle: joinShelfMeta([source, author]),
      tertiary: time,
      metaText: time,
      media:
          (
            context, {
            required width,
            required height,
            required radius,
            required fit,
          }) => ClipRRect(
            borderRadius: radius,
            child: CoverWidget(
              fileServer: cover.url,
              path: cover.cachePath,
              id: item.comicId,
              pictureType: PictureType.cover,
              from: item.source,
              roundedCorner: false,
              width: width,
              height: height,
            ),
          ),
      badge: GlyphIcon(
        AppGlyphs.downloadDone,
        color: Theme.of(context).colorScheme.primary,
      ),
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [author.isEmpty ? '—' : author, source, time],
      onRead: () => startComicQuickRead(
        context,
        comicId: item.comicId,
        from: item.source,
        navigationToken: navigationToken,
      ),
      onLongPress: () => _confirmDelete(context, item),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UnifiedComicDownload item,
  ) async {
    await showPopupPanel<void>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) => PopupPanel(
        title: Text(t.comicEntry.deleteDownload),
        content: Text(t.comicEntry.deleteDownloadConfirm(title: item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await deleteComicDownloadDirectory(item.source, item.comicId);
                objectbox.unifiedDownloadBox.remove(item.id);
              } catch (_) {
                showErrorToast(t.comicEntry.deleteFailed);
              }
            },
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, LibraryEntry row, String navigationToken) {
    final item = row.source! as UnifiedComicDownload;
    openComicItem(
      context,
      comicId: item.comicId,
      from: item.source,
      navigationToken: navigationToken,
      type: isLocalComicSource(item.source, item.comicId)
          ? ComicEntryType.history
          : ComicEntryType.download,
    );
  }
}

/// 「共占用多少」是点一下才去量的读数，不是每次刷新都全盘扫一遍。
///
/// 统计要走完每一本的所有兼容目录，几十本就是一次递归遍历库；挂在页面构建路径上
/// 会把「打开这页」变成「扫描磁盘」，所以这里是显式动作 + 结果缓存。
/// 一根都没量到时**不给字节数**：那句「共 0 B」会被读成「没占地方」。
class _OfflineStorageStat extends StatefulWidget {
  const _OfflineStorageStat({required this.records});

  final List<UnifiedComicDownload> records;

  @override
  State<_OfflineStorageStat> createState() => _OfflineStorageStatState();
}

class _OfflineStorageStatState extends State<_OfflineStorageStat> {
  bool _running = false;
  int? _totalBytes;

  @override
  void didUpdateWidget(covariant _OfflineStorageStat oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 离线库变了（新下完、清理过），上一次的读数就不该继续挂着。
    if (oldWidget.records.length != widget.records.length) {
      _totalBytes = null;
    }
  }

  Future<void> _measure() async {
    if (_running) return;
    setState(() => _running = true);
    final stats = <DownloadStorageStat>[];
    for (final record in widget.records) {
      stats.add(
        await measureComicDownloadStorage(
          from: record.source,
          comicId: record.comicId,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _totalBytes = hasMeasuredStorage(stats)
          ? totalDownloadStorageBytes(stats)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_running) {
      return Text(
        t.download.offlineMeasuring,
        style: theme.textTheme.bodySmall,
      );
    }
    final totalBytes = _totalBytes;
    if (totalBytes != null) {
      return Text(
        t.download.offlineTotalSize(size: formatDownloadBytes(totalBytes)),
        style: theme.textTheme.bodySmall,
      );
    }
    return TextButton(
      onPressed: _measure,
      child: Text(
        t.download.offlineMeasureSize,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
