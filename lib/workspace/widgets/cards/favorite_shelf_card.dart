import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/permission.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/method/shelf_entry_actions.dart';
import 'package:zephyr/workspace/model/bookmark_library_portable.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/service/bookmark_library_service.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';

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

  @override
  void initState() {
    super.initState();
    _loadLists();
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
      selectShelf(
        [for (final item in all) _searchable(item)],
        memberKeys: memberKeys,
      ),
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
        _buildListRail(context),
        const SizedBox(height: 6),
        ShelfListToolbar(
          viewMode: _viewMode,
          onViewMode: (mode) => setState(() => _viewMode = mode),
          sort: _sort,
          onSort: (sort) => setState(() => _sort = sort),
          searchController: _searchController,
          onKeywordChanged: (value) => setState(() => _keyword = value),
          count: rows.length,
          trailing: _buildPortActions(context),
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
      onSort: (key) => setState(
        () => _sort = _sort.toggled(ShelfSortField.values.byName(key)),
      ),
      wrapRow: (context, row, child) => ShelfEntryContextMenuRegion(
        enabled: menuEnabled,
        inputBuilder: () => _menuInput(row.source! as UnifiedComicFavorite),
        onAction: (context, action) =>
            _onMenuAction(context, row.source! as UnifiedComicFavorite, action),
        child: child,
      ),
    );
  }

  // ── 列表轨 ────────────────────────────────────────────────────────────────

  Widget _buildListRail(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      _listChip(context, label: '全部', path: _kAllLists),
      _listChip(context, label: '未分类', path: kComicFolderRootPath),
      for (final folder in _folders)
        _listChip(context, label: folder.name, path: '/${folder.name}'),
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
        IconButton(
          icon: const Icon(Icons.playlist_add, size: 18),
          tooltip: '新建书签列表',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _editList(null),
        ),
        if (_selectedList != _kAllLists &&
            _selectedList != kComicFolderRootPath)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '重命名 / 删除当前列表',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _editList(_selectedList),
          )
        else
          Icon(
            Icons.bookmark_added_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _listChip(
    BuildContext context, {
    required String label,
    required String path,
  }) {
    final selected = path == _selectedList;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _selectedList = path;
          _folders = BookmarkLibraryService.lists();
        }),
        visualDensity: VisualDensity.compact,
      ),
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

  Widget _buildPortActions(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.file_download_outlined, size: 18),
          tooltip: '导出书签为 JSON',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : _export,
        ),
        IconButton(
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          tooltip: '从 JSON 导入书签',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : _import,
        ),
      ],
    );
  }

  Future<void> _export() async {
    // Android 写用户目录要「所有文件访问」权限，否则 Permission denied。
    final granted = await requestExportPermission();
    if (!granted) {
      if (mounted) showErrorToast(t.comicInfo.exportPermissionDenied);
      return;
    }
    final items = BookmarkLibraryService.collect();
    if (items.isEmpty) {
      if (mounted) showWarningToast('书签还是空的，没有可导出的内容');
      return;
    }
    final fileName =
        '$appDisplayName-bookmarks-${DateTime.now().millisecondsSinceEpoch}.json';
    final String target;
    if (Platform.isIOS) {
      // iOS 的 file_selector 没有 getDirectoryPath，先写缓存再走分享面板。
      target = p.join(await getCachePath(), fileName);
    } else {
      final dir = await getDirectoryPath();
      if (dir == null || dir.trim().isEmpty || !mounted) return;
      target = p.join(dir, fileName);
    }

    setState(() => _busy = true);
    try {
      await File(target).writeAsString(encodeBookmarkLibrary(items));
      if (!mounted) return;
      if (Platform.isIOS) {
        showSuccessToast('已写入缓存，请在分享面板里保存');
        await OpenFile.open(target);
      } else {
        showSuccessToast('已导出 ${items.length} 条书签\n$target');
      }
    } on Object catch (e, s) {
      logger.e('导出书签失败', error: e, stackTrace: s);
      if (mounted) showErrorToast('导出书签失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '书签文件', extensions: ['json'], mimeTypes: [
          'application/json',
        ]),
      ],
    );
    if (picked?.path case final path?) {
      await _importFrom(path);
    }
  }

  Future<void> _importFrom(String path) async {
    setState(() => _busy = true);
    try {
      // 先出计划再落库：用户点完文件至少要看见「要动多少条」。
      final plan = await BookmarkLibraryService.planFromFile(path);
      if (!mounted) return;
      final confirmed = await _confirmImport(plan);
      if (!confirmed || !mounted) return;
      BookmarkLibraryService.applyPlan(plan);
      _loadLists();
      if (mounted) showSuccessToast(plan.summary);
    } on BookmarkLibraryFormatException catch (e) {
      if (mounted) showErrorToast('读不了这个文件：${e.message}');
    } on Object catch (e, s) {
      logger.e('导入书签失败', error: e, stackTrace: s);
      if (mounted) showErrorToast('导入书签失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmImport(BookmarkMergePlan plan) async {
    final rejected = plan.rejected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入书签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.summary),
            const SizedBox(height: 8),
            const Text('只合并，不会删除或覆盖已有的书签。'),
            if (rejected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '跳过的条目：\n${rejected.take(5).map((r) => '· ${r.label} — ${r.reason}').join('\n')}',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: plan.writes.isEmpty
                ? null
                : () => dialogContext.pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

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

  LibraryEntry _row(UnifiedComicFavorite item) {
    final theme = Theme.of(context);
    final cover = unifiedComicFromUnifiedFavorite(item).cover;
    final author = shelfCreatorName(item.creator);
    final source = shelfSourceLabel(source: item.source, comicId: item.comicId);
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
      badge: Icon(
        Icons.menu_book_rounded,
        color: theme.colorScheme.primary,
      ),
      // 书签一共就几百条，每一档都值得画封面；文件管理器不这么想。
      thumbModes: LibraryViewMode.values.toSet(),
      detailCells: [author.isEmpty ? '—' : author, source, time],
      onRead: () => _read(item),
      trailing: IconButton(
        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
        color: theme.colorScheme.onSurfaceVariant,
        tooltip: '打开',
        visualDensity: VisualDensity.compact,
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
            onPressed: () => context.pop(const _ListEditorResult('', delete: true)),
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
