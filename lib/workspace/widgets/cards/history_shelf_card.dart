import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/method/shelf_entry_actions.dart';
import 'package:zephyr/workspace/method/shelf_port_flow.dart';
import 'package:zephyr/workspace/model/history_library_portable.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/service/history_library_service.dart';
import 'package:zephyr/workspace/service/shelf_view_state_store.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_timeline_view.dart';

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

  /// 时间线那一档。与 `_viewMode` 各存各的：开着时间线时 `_viewMode` 保持原样，
  /// 关掉就回到用户上一眼看惯的那一档。
  bool _timeline = false;

  /// 导入 / 导出在飞。与书签卡片同一口径：那两颗键在读写文件期间必须收着，
  /// 否则一次导入没跑完又点一次，两份计划会抢同一批行。
  bool _busy = false;

  /// 视图档位与排序的落盘。卡片会被面板回收重建（换泳道、收起再展开、重启），
  /// 那两个值原先只是 State 字段，于是每次重建都回到出厂的「封面列表 + 按时间」。
  final _viewMemory = ShelfViewMemory(WorkspacePanelId.history);

  @override
  void initState() {
    super.initState();
    unawaited(_restoreViewState());
  }

  Future<void> _restoreViewState() async {
    final saved = await _viewMemory.restore();
    if (saved == null || !mounted) return;
    setState(() {
      // 名字不认识就当没存过（枚举改过名 / 偏好文件来自更新的版本）：
      // 视图状态是可重建的东西，为它让整张卡片红屏不成立。
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
      // 时间线**固定按时间倒序**（最近的在最上面），不跟着 `_sort` 走：
      // 一条按标题排好的时间线会切出一堆上下来回的日期段，那不是时间线。
      // 工具栏里排序那颗键在这时是灰的，所以这里不需要解释「你排的序呢」。
      sort: _timeline
          ? const ShelfSort(field: ShelfSortField.time)
          : _sort,
      normalize: _normalize,
    );
    // 插件 id 是一串 uuid，行上得换成插件自己报的名字（口径见 pluginDisplayNames）。
    final pluginNames = pluginDisplayNames();
    final rows = [
      for (final entry in visible)
        if (entities[entry.key] case final item?) _row(item, pluginNames),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfListToolbar(
          viewMode: _viewMode,
          onViewMode: (mode) {
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
          count: rows.length,
          busy: _busy,
          portLabel: '历史数据',
          onExport: _export,
          onImport: _import,
          timelineOn: _timeline,
          onTimeline: () {
            setState(() => _timeline = !_timeline);
            _rememberViewState();
          },
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
    if (_timeline) return _buildTimeline(context, rows, menuEnabled);
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
      onSort: (key) {
        setState(
          () => _sort = _sort.toggled(ShelfSortField.values.byName(key)),
        );
        _rememberViewState();
      },
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicHistory),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicHistory, action),
        child: child,
      ),
    );
  }

  /// 时间线档：按「最后阅读」那一天分段。
  ///
  /// 行内容仍然由 `ShelfTimelineView` 转给 `LibraryEntrySurface`，这里只负责
  /// 供时间与右键壳子 —— 与列表档共用同一套，两档不会长歪。
  Widget _buildTimeline(
    BuildContext context,
    List<LibraryEntry> rows,
    bool menuEnabled,
  ) {
    final timeline = ShelfTimelineView(
      entries: rows,
      standalone: widget.isStandalone,
      timeOf: (row) => (row.source! as UnifiedComicHistory).lastReadAt,
      emptyText: _keyword.trim().isNotEmpty ? '没有匹配的阅读记录' : '暂无阅读历史',
      onTap: (row) => _open(context, row.source! as UnifiedComicHistory),
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicHistory),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicHistory, action),
        child: child,
      ),
    );
    return widget.isStandalone
        ? Expanded(child: timeline)
        : timeline;
  }

  // ── 导入 / 导出 ───────────────────────────────────────────────────────────
  //
  // 管路（权限、选目录、iOS 的分享面板回退、确认对话框、忙状态）在
  // `method/shelf_port_flow.dart`，与书签面板共用一份。
  //
  // 历史原先**根本没有**这一组入口 —— 书签有导出导入而历史只能靠设置页那个
  // 会先清库的整库 ZIP 备份。两侧现在对称。

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
  }

  Future<void> _export() async {
    final items = HistoryLibraryService.collect();
    await exportShelfDocument(
      context: context,
      label: '阅读历史',
      fileStem: 'history',
      count: items.length,
      encode: () => encodeHistoryLibrary(items),
      onBusyChanged: _setBusy,
    );
  }

  Future<void> _import() => importShelfDocument(
    context: context,
    label: '阅读历史',
    fileLabel: '历史记录文件',
    planFrom: (path) async {
      final HistoryMergePlan plan;
      try {
        plan = await HistoryLibraryService.planFromFile(path);
      } on HistoryLibraryFormatException catch (e) {
        throw ShelfFormatException(e.message);
      }
      return ShelfImportPlan(
        summary: plan.summary,
        writeCount: plan.writes.length,
        rejectedLines: [
          for (final rejection in plan.rejected)
            '${rejection.label} — ${rejection.reason}',
        ],
        // 历史的合并语义与书签不同，所以这句话必须说清楚（口径见
        // `planHistoryImport`）：一条都不删，且本地那条读得更靠后时保留本地。
        note: '只合并：一条历史都不会删除；本地进度比文件里更新的，保留本地。',
        apply: () => HistoryLibraryService.applyPlan(plan),
      );
    },
    onBusyChanged: _setBusy,
  );

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

  LibraryEntry _row(UnifiedComicHistory item, Map<String, String> pluginNames) {
    final theme = Theme.of(context);
    final cover = unifiedComicFromUnifiedHistory(item).cover;
    final source = shelfSourceLabel(
      source: item.source,
      comicId: item.comicId,
      pluginName: shelfPluginName(pluginNames, item.source),
    );
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
      badge: Icon(Icons.menu_book_rounded, color: theme.colorScheme.primary),
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [chapter.isEmpty ? '—' : chapter, source, time],
      onRead: () => _read(item),
      // 行档图标钮：28 命中区 + 18 图标，与书签卡、文件管理器同一口径
      // （原来是 22，比工具栏那 20 还大，一行里最抢眼的成了次要动作）。
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
        color: theme.colorScheme.primary,
        tooltip: t.comicEntry.resumeRead,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        // 这颗图标一直写的是「继续阅读」，但历史上它走 _open —— 插件来源其实
        // 跳的是详情页。封面按钮既然把「直接起读」做出来了，这里就接上真的。
        onPressed: () => _read(item),
      ),
    );
  }

  /// 直接起读，不进详情页（语义见 [startComicQuickRead]）。
  Future<void> _read(UnifiedComicHistory item) =>
      startComicQuickRead(context, comicId: item.comicId, from: item.source);

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
