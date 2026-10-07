import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
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
import 'package:zephyr/workspace/model/bookmark_library_portable.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/service/bookmark_library_service.dart';
import 'package:zephyr/workspace/service/shelf_view_state_store.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_toolbar.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLists();
    unawaited(_restoreViewState());
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
    _searchController.dispose();
    super.dispose();
  }

  void _loadLists() {
    setState(() => _folders = BookmarkLibraryService.lists());
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
          icon: Icons.bookmark_added_rounded,
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
        _buildListRail(context),
        const SizedBox(height: 6),
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
    if (_timeline) return _buildTimeline(context, rows, libraryEmpty, menuEnabled);
    return LibraryEntryList(
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
  Widget _buildTimeline(
    BuildContext context,
    List<LibraryEntry> rows,
    bool libraryEmpty,
    bool menuEnabled,
  ) {
    final timeline = ShelfTimelineView(
      entries: rows,
      standalone: widget.isStandalone,
      timeOf: (row) => (row.source! as UnifiedComicFavorite).updatedAt,
      emptyText: libraryEmpty
          ? '还没有书签，去详情页点收藏吧'
          : _keyword.trim().isNotEmpty
          ? '没有匹配的书签'
          : '这个列表里还没有书签',
      onTap: (row) => _open(context, row.source! as UnifiedComicFavorite),
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicFavorite),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicFavorite, action),
        child: child,
      ),
    );
    return widget.isStandalone ? Expanded(child: timeline) : timeline;
  }

  // ── 列表轨 ────────────────────────────────────────────────────────────────

  Widget _buildListRail(BuildContext context) {
    final chips = <Widget>[
      _listChip(label: '全部', path: _kAllLists),
      _listChip(label: '未分类', path: kComicFolderRootPath),
      for (final folder in _folders)
        _listChip(label: folder.name, path: '/${folder.name}'),
    ];

    return Row(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        ),
        // 两颗键走本区图标钮的同一份度量（40 见方、图标 20），不再用
        // `size: 18` + `visualDensity: compact` 的裸 IconButton —— 否则
        // 列表轨与下面的工具栏是两条不同高度的带，看着就是两个东西。
        FileManagerToolbarIconButton(
          icon: Icons.playlist_add_rounded,
          tooltip: '新建书签列表',
          enabled: !_busy,
          onPressed: () => _editList(null),
        ),
        if (_selectedList != _kAllLists &&
            _selectedList != kComicFolderRootPath)
          FileManagerToolbarIconButton(
            icon: Icons.edit_outlined,
            tooltip: '重命名 / 删除当前列表',
            enabled: !_busy,
            onPressed: () => _editList(_selectedList),
          ),
      ],
    );
  }

  Widget _listChip({required String label, required String path}) {
    return ShelfListChip(
      label: label,
      selected: path == _selectedList,
      onTap: () => setState(() {
        _selectedList = path;
        _folders = BookmarkLibraryService.lists();
      }),
    );
  }

  /// 新建 / 重命名 / 删除一个书签列表。不传 path 表示新建。
  Future<void> _editList(String? selected) async {
    final editing = selected != null && selected != _kAllLists;
    final current = editing ? selected : null;
    final result = await showDialog<_ListEditorResult>(
      context: context,
      builder: (context) => _ListEditorDialog(
        initialName: current?.split('/').last ?? '',
        editing: current != null,
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
    final cover = unifiedComicFromUnifiedFavorite(item).cover;
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
      source: item,
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
      badge: Icon(Icons.menu_book_rounded, color: theme.colorScheme.primary),
      // 书签一共就几百条，每一档都值得画封面；文件管理器不这么想。
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [author.isEmpty ? '—' : author, source, time],
      onRead: () => _read(item),
      // 行上的图标钮走**行档**，不是工具栏那条 40 的带：文件管理器那侧已验收的
      // 画法就是 28 命中区 + 16~18 图标 + `padding: zero`（见
      // `parts/file_manager_card_view_part.dart` 的 `_trailing`）。
      // 原来是 `size: 13`，比行里的正文字还小，读起来不像一个能按的东西。
      trailing: IconButton(
        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
        color: theme.colorScheme.onSurfaceVariant,
        tooltip: '打开',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: () => _open(context, item),
      ),
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

class _ListEditorDialog extends StatefulWidget {
  const _ListEditorDialog({required this.initialName, required this.editing});

  final String initialName;
  final bool editing;

  @override
  State<_ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<_ListEditorDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? '重命名书签列表' : '新建书签列表'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '列表名称', isDense: true),
        onSubmitted: (value) => context.pop(_ListEditorResult(value)),
      ),
      actions: [
        if (widget.editing)
          TextButton(
            onPressed: () =>
                context.pop(const _ListEditorResult('', delete: true)),
            child: const Text('删除列表'),
          ),
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => context.pop(_ListEditorResult(_controller.text)),
          child: Text(t.common.save),
        ),
      ],
    );
  }
}
