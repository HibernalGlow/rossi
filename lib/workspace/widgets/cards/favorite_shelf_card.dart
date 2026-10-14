import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/plugin/utils/plugin_display_name.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/expressive/shelf_list_editor.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/method/shelf_entry_actions.dart';
import 'package:zephyr/workspace/method/shelf_port_flow.dart';
import 'package:zephyr/workspace/model/bookmark_library_portable.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/service/bookmark_library_service.dart';
import 'package:zephyr/workspace/service/shelf_view_state_store.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_book_details.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_rail.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_timeline_view.dart';

/// 书签面板（库里叫收藏）。
///
/// 视图部分与文件管理器共用一套（`library_view`）：书签、历史、本地文件是三
/// 种数据源，不该有三套行渲染。列表切换、搜索、排序、导入导出的形态对照
/// neoview 的 `BookmarkListCard`。
class FavoriteShelfCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 卡片在面板轨道上的位置动作，由宿主（面板 / 抽屉）传入。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const FavoriteShelfCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<FavoriteShelfCard> createState() => _FavoriteShelfCardState();
}

class _FavoriteShelfCardState extends State<FavoriteShelfCard> {
  /// 「全部」这一档不是数据库里的列表，得用一个不可能撞上的哨兵。
  static const _kAllLists = '\u0000all';

  static const _kDetailsColumns = [
    LibraryColumn(key: 'author', label: '作者', width: 90),
    LibraryColumn(key: 'source', label: '来源', width: 70),
    LibraryColumn(key: 'time', label: '收藏时间', width: 90),
  ];

  final _canvasKey = GlobalKey<LibraryEditorialCanvasState>();
  final _searchController = TextEditingController();
  String _selectedList = _kAllLists;
  LibraryViewMode _viewMode = LibraryViewMode.coverList;
  ShelfSort _sort = const ShelfSort(field: ShelfSortField.time);
  String _keyword = '';
  List<ComicFolder> _folders = const [];
  bool _busy = false;

  /// 时间线那一档。与 `_viewMode` 各存各的：开着时间线时 `_viewMode` 保持原样，
  /// 关掉就回到用户上一眼看惯的那一档。
  bool _timeline = false;

  /// 视图档位与排序的落盘，口径与历史卡片一致。
  ///
  /// **刻意不记**当前选中的书签列表：那是一条筛选，恢复回来会让用户以为
  /// 「书签少了一半」，而少掉的那些并没有被删。
  final _viewMemory = ShelfViewMemory(WorkspacePanelId.favorite);

  /// 书签列表（`ComicFolder` 里 `type == favorite` 那一族）的变更流。
  StreamSubscription<void>? _foldersSub;

  /// 上一次读到的列表标识，用来把「别的类型也写这张表」造成的空转挡掉。
  String _foldersSignature = '';

  @override
  void initState() {
    super.initState();
    _loadLists();
    unawaited(_restoreViewState());
    // **必须订阅，不能只在 initState 读一次。** 这张面板是常驻的（切面板走
    // `RetainedPanelSwitcher`，State 不重建），而书架页的「收藏」模式同样能新建
    // 书签列表。早先版本只在自己增删改之后刷新，于是在书架页建的列表永远进不了
    // 这条分类轨 —— 看着就是「tab 少了」。口径与不刷新的后果都写在服务侧。
    _foldersSub = BookmarkLibraryService.watchListsChanged().listen((_) {
      _loadLists();
    });
  }

  Future<void> _restoreViewState() async {
    final saved = await _viewMemory.restore();
    if (saved == null || !mounted) return;
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
    _foldersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadLists() {
    if (!mounted) return;
    final folders = BookmarkLibraryService.lists();
    final signature = folders.map((folder) => folder.name).join('|');
    // `comicFolderBox` 是所有类型的收藏夹共用的一张表，书架 / 本地那侧的写也会
    // 推到这条流上；名称集合没变就不 setState，免得每次动书架都在重建这条轨。
    if (signature == _foldersSignature) return;
    _foldersSignature = signature;
    setState(() => _folders = folders);
  }

  /// 繁简同搜：口径与书架那边一致（trim + 小写 + t2s）。
  String _normalize(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '';
    return t2s(lower);
  }

  @override
  Widget build(BuildContext context) {
    // 条目的右键（触摸端长按）菜单。开关在「设置 → 书架 → 卡片交互」，
    // 默认开；关掉时连手势都不挂。用 watch：在设置页关掉后切回来当场就该没反应。
    final menuEnabled = context
        .watch<GlobalSettingCubit>()
        .state
        .bookshelfSetting
        .shelfCardContextMenu;

    final queryBuilder = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.deleted.equals(false))
        .order(UnifiedComicFavorite_.updatedAt, flags: Order.descending);

    return StreamBuilder<List<UnifiedComicFavorite>>(
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
          cardId: 'favorite',
          title: '书签 (Favorites)',
          icon: AppGlyphs.bookmark,
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
    List<UnifiedComicFavorite> all,
    bool menuEnabled,
  ) {
    final entities = <String, UnifiedComicFavorite>{
      for (final item in all) item.uniqueKey: item,
    };
    final memberKeys = _selectedList == _kAllLists
        ? null
        : BookmarkLibraryService.membersOf(_selectedList);
    final visible = searchAndSortShelf(
      selectShelf([
        for (final item in all) _searchable(item),
      ], memberKeys: memberKeys),
      keyword: _keyword,
      // 时间线**固定按时间倒序**（最近的在最上面），不跟着 `_sort` 走：
      // 一条按标题排好的时间线会切出一堆上下来回的日期段，那不是时间线。
      // 工具栏里排序那颗键在这时是灰的，所以这里不需要解释「你排的序呢」。
      sort: _timeline ? const ShelfSort(field: ShelfSortField.time) : _sort,
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
        _buildListRail(context),
        const SizedBox(height: 6),
        ShelfListToolbar(
          presentationButton: LibraryPresentationButton(
            canvasKey: _canvasKey,
            enabled: !_timeline,
          ),
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
          historyScope: 'bookmarks',
          onKeywordChanged: (value) => setState(() => _keyword = value),
          count: rows.length,
          busy: _busy,
          portLabel: '书签数据',
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
          Expanded(child: _buildList(context, rows, all.isEmpty, menuEnabled))
        else
          _buildList(context, rows, all.isEmpty, menuEnabled),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<LibraryEntry> rows,
    bool libraryEmpty,
    bool menuEnabled,
  ) {
    if (_timeline) {
      return _buildTimeline(context, rows, libraryEmpty, menuEnabled);
    }
    return LibraryEntryList(
      editorialKey: _canvasKey,
      editorialScope: 'bookmarks',
      detailBuilder: (context, row, close) {
        final item = row.source! as UnifiedComicFavorite;
        return LibraryBookDetails(
          entry: row,
          comicId: item.comicId,
          from: item.source,
          onClose: close,
        );
      },
      mode: _viewMode,
      entries: rows,
      standalone: widget.isStandalone,
      busy: _busy,
      emptyText: libraryEmpty
          ? '还没有书签，去详情页点收藏吧'
          : _keyword.trim().isNotEmpty
          ? '没有匹配的书签'
          : '这个列表里还没有书签',
      onTap: (row) => _open(context, row.source! as UnifiedComicFavorite),
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
        inputBuilder: () => _menuInput(row.source! as UnifiedComicFavorite),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicFavorite, action),
        child: child,
      ),
    );
  }

  /// 时间线档：按「收藏时间」那一天分段。
  ///
  /// 行内容仍然由 `ShelfTimelineView` 转给 `LibraryEntrySurface`，这里只供
  /// 时间与右键壳子 —— 与列表档共用同一套，两档不会长歪。
  final _timelineExpanded = <String>{};

  Widget _buildTimeline(
    BuildContext context,
    List<LibraryEntry> rows,
    bool libraryEmpty,
    bool menuEnabled,
  ) {
    final timeline = ShelfTimelineView(
      entries: rows,
      expandedKeys: _timelineExpanded,
      onCloseDetail: (key) => setState(() => _timelineExpanded.remove(key)),
      detailBuilder: (context, row, close) {
        final item = row.source! as UnifiedComicFavorite;
        return LibraryBookDetails(
          entry: row,
          comicId: item.comicId,
          from: item.source,
          onClose: close,
        );
      },
      standalone: widget.isStandalone,
      timeOf: (row) => (row.source! as UnifiedComicFavorite).updatedAt,
      emptyText: libraryEmpty
          ? '还没有书签，去详情页点收藏吧'
          : _keyword.trim().isNotEmpty
          ? '没有匹配的书签'
          : '这个列表里还没有书签',
      onTap: (row) => setState(() {
        if (!_timelineExpanded.remove(row.key)) _timelineExpanded.add(row.key);
      }),
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicFavorite),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicFavorite, action),
        child: child,
      ),
    );
    return timeline;
  }

  // ── 列表轨 ────────────────────────────────────────────────────────────────

  Widget _buildListRail(BuildContext context) => ShelfListRail(
    onCreate: _busy ? null : () => _editList(null),
    onEdit:
        !_busy &&
            _selectedList != _kAllLists &&
            _selectedList != kComicFolderRootPath
        ? () => _editList(_selectedList)
        : null,
    children: [
      _listChip(label: '全部', path: _kAllLists),
      _listChip(label: '未分类', path: kComicFolderRootPath),
      for (final folder in _folders)
        _listChip(label: folder.name, path: '/${folder.name}'),
    ],
  );

  Widget _listChip({required String label, required String path}) {
    return ShelfListChip(
      label: label,
      // 形状按**路径**定种子：重命名之后路径不变，那一档的轮廓就不跟着换
      // （见 `ShelfListChip.identity`）。
      identity: path,
      selected: path == _selectedList,
      onTap: () => setState(() => _selectedList = path),
    );
  }

  /// 新建 / 重命名 / 删除一个书签列表。不传 path 表示新建。
  Future<void> _editList(String? selected) async {
    final editing = selected != null && selected != _kAllLists;
    final current = editing ? selected : null;
    final result = await showPopupPanel<_ListEditorResult>(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (context) => ShelfListEditor(
        title: current != null ? '重命名书签列表' : '新建书签列表',
        label: '列表名称',
        description: '按主题整理书签。创建后可以把书签移动到这个列表。',
        initialName: current?.split('/').last ?? '',
        onSave: (name) => context.pop(_ListEditorResult(name)),
        onDelete: current == null
            ? null
            : () => context.pop(const _ListEditorResult('', delete: true)),
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (result.delete) {
        if (current == null) return;
        BookmarkLibraryService.deleteList(current);
        setState(() => _selectedList = _kAllLists);
      } else if (current != null) {
        BookmarkLibraryService.renameList(current, result.name);
        final renamed = '/${result.name}';
        if (_selectedList == current) setState(() => _selectedList = renamed);
      } else {
        BookmarkLibraryService.createList(result.name);
      }
    } on Object catch (e) {
      showErrorToast('$e', context: context);
    }
    _loadLists();
  }

  // ── 导入 / 导出 ───────────────────────────────────────────────────────────
  //
  // 管路（权限、选目录、iOS 的分享面板回退、确认对话框、忙状态）在
  // `method/shelf_port_flow.dart`，与历史面板共用一份；这里只剩「书签这一侧
  // 具体编码什么、怎么落库」。

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
  }

  Future<void> _export() async {
    final items = BookmarkLibraryService.collect();
    await exportShelfDocument(
      context: context,
      label: '书签',
      fileStem: 'bookmarks',
      count: items.length,
      encode: () => encodeBookmarkLibrary(items),
      onBusyChanged: _setBusy,
    );
  }

  Future<void> _import() => importShelfDocument(
    context: context,
    label: '书签',
    fileLabel: '书签文件',
    planFrom: (path) async {
      final BookmarkMergePlan plan;
      try {
        plan = await BookmarkLibraryService.planFromFile(path);
      } on BookmarkLibraryFormatException catch (e) {
        throw ShelfFormatException(e.message);
      }
      return ShelfImportPlan(
        summary: plan.summary,
        writeCount: plan.writes.length,
        rejectedLines: [
          for (final rejection in plan.rejected)
            '${rejection.label} — ${rejection.reason}',
        ],
        note: '只合并，不会删除或覆盖已有的书签。',
        apply: () {
          BookmarkLibraryService.applyPlan(plan);
          _loadLists();
        },
      );
    },
    onBusyChanged: _setBusy,
  );

  // ── 行 ────────────────────────────────────────────────────────────────────

  ShelfSearchable _searchable(UnifiedComicFavorite item) {
    final author = shelfCreatorName(item.creator);
    return ShelfSearchable(
      key: item.uniqueKey,
      title: item.title,
      author: author,
      source: item.source,
      time: item.updatedAt,
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

  LibraryEntry _row(
    UnifiedComicFavorite item,
    Map<String, String> pluginNames,
  ) {
    final theme = Theme.of(context);
    final comic = unifiedComicFromUnifiedFavorite(item);
    final cover = comic.cover;
    final author = shelfCreatorName(item.creator);
    final source = shelfSourceLabel(
      source: item.source,
      comicId: item.comicId,
      pluginName: shelfPluginName(pluginNames, item.source),
    );
    final time = formatShelfTime(item.updatedAt);
    return LibraryEntry(
      key: item.uniqueKey,
      title: item.title,
      description: item.description,
      tags: comic.toSimplifyEntryInfo().tags,
      source: item,
      timestamp: item.updatedAt,
      section: source,
      subtitle: joinShelfMeta([source, author.isEmpty ? time : author]),
      tertiary: time,
      metaText: source,
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
      badge: GlyphIcon(AppGlyphs.book, color: theme.colorScheme.primary),
      // 书签一共就几百条，每一档都值得画封面；文件管理器不这么想。
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [author.isEmpty ? '—' : author, source, time],
      onRead: () => _read(item),
    );
  }

  /// 封面那颗「直接阅读」：不进详情页，直接起读（语义见 [startComicQuickRead]）。
  Future<void> _read(UnifiedComicFavorite item) =>
      startComicQuickRead(context, comicId: item.comicId, from: item.source);

  void _open(BuildContext context, UnifiedComicFavorite item) {
    // 本地来源与插件来源的分岔在 openComicItem 里统一处理 —— 这里曾经
    // 无条件推详情页，本地漫画会被当成「插件 id = local」而加载失败。
    openComicItem(context, comicId: item.comicId, from: item.source);
  }

  ShelfEntryMenuInput _menuInput(UnifiedComicFavorite item) {
    return ShelfEntryMenuInput(
      kind: ShelfEntryKind.favorite,
      canOpenInFileManagerTab: resolveFileManagerTabPath(item.comicId) != null,
    );
  }

  void _onMenuAction(
    BuildContext context,
    UnifiedComicFavorite item,
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
        // 书签卡上没有这一项（见 buildShelfEntryMenuItems 的类型分支）。
        break;
      case ShelfEntryAction.remove:
        _remove(context, item);
    }
  }

  /// 「取消收藏」：破坏性 ⇒ 先问一句，再落库，最后才提示成功。
  Future<void> _remove(BuildContext context, UnifiedComicFavorite item) async {
    final confirmed = await confirmShelfEntryRemoval(
      context,
      kind: ShelfEntryKind.favorite,
      title: item.title,
    );
    if (!confirmed || !context.mounted) return;
    removeShelfEntryFromFavorites(item.uniqueKey);
    showSuccessToast(
      t.shelfMenu.favoriteRemoved(title: item.title),
      context: context,
    );
  }
}

class _ListEditorResult {
  const _ListEditorResult(this.name, {this.delete = false});

  final String name;
  final bool delete;
}
