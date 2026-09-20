import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/method/shelf_entry_actions.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';

/// 阅读历史面板。视图部分与书签面板、文件管理器共用一套（`library_view`）。
///
/// 与书签面板的差别只在数据：历史带章节与页码，排序的「时间」是最后阅读，
/// 另外它没有书签列表那一轨。
class HistoryShelfCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 卡片在面板轨道上的位置动作，由宿主（面板 / 抽屉）传入。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const HistoryShelfCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<HistoryShelfCard> createState() => _HistoryShelfCardState();
}

class _HistoryShelfCardState extends State<HistoryShelfCard> {
  static const _kDetailsColumns = [
    // 「章节」没有对应的排序字段（排序口径见 ShelfSortField），所以表头
    // 只是标签，不做成能点了没反应的假可点区。
    LibraryColumn(key: 'chapter', label: '章节', width: 110, sortable: false),
    LibraryColumn(key: 'source', label: '来源', width: 70),
    LibraryColumn(key: 'time', label: '最后阅读', width: 90),
  ];

  final _searchController = TextEditingController();
  LibraryViewMode _viewMode = LibraryViewMode.coverList;
  ShelfSort _sort = const ShelfSort(field: ShelfSortField.time);
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 繁简同搜，口径与书签面板一致。
  String _normalize(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '';
    return t2s(lower);
  }

  @override
  Widget build(BuildContext context) {
    // 条目的右键（触摸端长按）菜单。开关在「设置 → 书架 → 卡片交互」，
    // 默认开；关掉时连手势都不挂（见 ShelfEntryContextMenuRegion.enabled）。
    // 用 watch 而不是 read：在设置页把它关掉后切回来，卡片当场就该没反应。
    final menuEnabled = context
        .watch<GlobalSettingCubit>()
        .state
        .bookshelfSetting
        .shelfCardContextMenu;

    final queryBuilder = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);

    return StreamBuilder<List<UnifiedComicHistory>>(
      stream: queryBuilder.watch(triggerImmediately: true).map((q) => q.find()),
      builder: (context, snapshot) {
        final body = _buildBody(
          context,
          snapshot.data ?? const [],
          menuEnabled,
        );
        if (widget.isStandalone) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: body,
          );
        }
        return CollapsibleCard(
          cardId: 'history',
          title: '阅读历史 (History)',
          icon: Icons.history_rounded,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onMoveUp: widget.onMoveUp,
          onMoveDown: widget.onMoveDown,
          onHide: widget.onHide,
          child: body,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<UnifiedComicHistory> all,
    bool menuEnabled,
  ) {
    final entities = <String, UnifiedComicHistory>{
      for (final item in all) item.uniqueKey: item,
    };
    final visible = searchAndSortShelf(
      [for (final item in all) _searchable(item)],
      keyword: _keyword,
      sort: _sort,
      normalize: _normalize,
    );
    final rows = [
      for (final entry in visible)
        if (entities[entry.key] case final item?) _row(item),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfListToolbar(
          viewMode: _viewMode,
          onViewMode: (mode) => setState(() => _viewMode = mode),
          sort: _sort,
          onSort: (sort) => setState(() => _sort = sort),
          searchController: _searchController,
          onKeywordChanged: (value) => setState(() => _keyword = value),
          count: rows.length,
        ),
        const SizedBox(height: 6),
        if (widget.isStandalone)
          Expanded(child: _buildList(context, rows, menuEnabled))
        else
          _buildList(context, rows, menuEnabled),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<LibraryEntry> rows,
    bool menuEnabled,
  ) {
    return LibraryEntryList(
      mode: _viewMode,
      entries: rows,
      standalone: widget.isStandalone,
      emptyText: rows.isEmpty && _keyword.trim().isNotEmpty
          ? '没有匹配的阅读记录'
          : '暂无阅读历史',
      onTap: (row) => _open(context, row.source! as UnifiedComicHistory),
      titleColumn: const LibraryColumn(
        key: 'title',
        label: '标题',
        flex: LibraryViewLayout.detailsTitleFlex,
      ),
      columns: _kDetailsColumns,
      sortKey: switch (_sort.field) {
        ShelfSortField.title => 'title',
        ShelfSortField.author => 'author',
        ShelfSortField.source => 'source',
        ShelfSortField.time => 'time',
      },
      sortAscending: _sort.ascending,
      onSort: (key) => setState(
        () => _sort = _sort.toggled(ShelfSortField.values.byName(key)),
      ),
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicHistory),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicHistory, action),
        child: child,
      ),
    );
  }

  ShelfSearchable _searchable(UnifiedComicHistory item) {
    final author = shelfCreatorName(item.creator);
    return ShelfSearchable(
      key: item.uniqueKey,
      title: item.title,
      author: author,
      source: item.source,
      time: item.lastReadAt,
      haystack: shelfHaystack(
        comicId: item.comicId,
        title: item.title,
        description: item.description,
        creator: item.creator,
        titleMeta: item.titleMeta,
        metadata: item.metadata,
      ),
    );
  }

  LibraryEntry _row(UnifiedComicHistory item) {
    final theme = Theme.of(context);
    final cover = unifiedComicFromUnifiedHistory(item).cover;
    final source = shelfSourceLabel(source: item.source, comicId: item.comicId);
    final chapter = shelfChapterLabel(
      title: item.title,
      chapterTitle: item.chapterTitle,
    );
    final time = formatShelfTime(item.lastReadAt);
    return LibraryEntry(
      key: item.uniqueKey,
      title: item.title,
      source: item,
      subtitle: joinShelfMeta([source, chapter, 'P.${item.pageIndex + 1}']),
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
      badge: Icon(
        Icons.menu_book_rounded,
        color: theme.colorScheme.primary,
      ),
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [chapter.isEmpty ? '—' : chapter, source, time],
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
        color: theme.colorScheme.primary,
        tooltip: '继续阅读',
        visualDensity: VisualDensity.compact,
        onPressed: () => _open(context, item),
      ),
    );
  }

  void _open(BuildContext context, UnifiedComicHistory item) {
    // 本地来源与插件来源的分岔在 openComicItem 里统一处理 —— 这里曾经
    // 无条件推详情页，本地漫画会被当成「插件 id = local」而加载失败。
    openComicItem(context, comicId: item.comicId, from: item.source);
  }

  ShelfEntryMenuInput _menuInput(UnifiedComicHistory item) {
    return ShelfEntryMenuInput(
      kind: ShelfEntryKind.history,
      canOpenInFileManagerTab: resolveFileManagerTabPath(item.comicId) != null,
      isFavorite: isShelfEntryFavorite(item.uniqueKey),
    );
  }

  void _onMenuAction(
    BuildContext context,
    UnifiedComicHistory item,
    ShelfEntryAction action,
  ) {
    switch (action) {
      case ShelfEntryAction.open:
        _open(context, item);
      case ShelfEntryAction.openInFileManagerTab:
        openShelfEntryInFileManagerTab(context, comicId: item.comicId);
      case ShelfEntryAction.copyTitle:
        copyShelfEntryTitle(context, title: item.title);
      case ShelfEntryAction.copyLink:
        copyShelfEntryLink(context, source: item.source, comicId: item.comicId);
      case ShelfEntryAction.toggleFavorite:
        // 菜单里这一项在「已收藏」时是灰的，走到这里就一定是「还没收藏」。
        // 还是再查一次：菜单弹出与用户点下之间隔着一次数据库写入不是不可能。
        if (isShelfEntryFavorite(item.uniqueKey)) return;
        addHistoryEntryToFavorites(item);
        showSuccessToast(
          t.shelfMenu.favoriteAdded(title: item.title),
          context: context,
        );
      case ShelfEntryAction.remove:
        _remove(context, item);
    }
  }

  /// 「从历史记录移除」：破坏性 ⇒ 先问一句，再落库，最后才提示成功。
  Future<void> _remove(BuildContext context, UnifiedComicHistory item) async {
    final confirmed = await confirmShelfEntryRemoval(
      context,
      kind: ShelfEntryKind.history,
      title: item.title,
    );
    if (!confirmed || !context.mounted) return;
    removeShelfEntryFromHistory(item.uniqueKey);
    showSuccessToast(
      t.shelfMenu.historyRemoved(title: item.title),
      context: context,
    );
  }
}
