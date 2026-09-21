import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/service/reader/local_book_navigation_controller.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/src/rust/api/file_ops.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/workspace/method/file_manager_actions.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/service/file_manager_tab_bridge.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_entry_context_menu.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_toolbar.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';
part 'parts/file_manager_card_model_part.dart';
part 'parts/file_manager_card_session_part.dart';
part 'parts/file_manager_card_navigation_part.dart';
part 'parts/file_manager_card_tree_part.dart';
part 'parts/file_manager_card_search_part.dart';
part 'parts/file_manager_card_file_ops_part.dart';
part 'parts/file_manager_card_open_part.dart';
part 'parts/file_manager_card_toolbar_part.dart';
part 'parts/file_manager_card_view_part.dart';


/// Rust 驱动的文件浏览卡片。
///
/// 卡片不保存路径、页签、历史或穿透结果；这些状态都来自
/// `rossi_local_core::FileManagerState` 的快照。Flutter 这里只做布局、事件转发和
/// 把 Rust 返回的 `openedPath` 交给已有 Reader 路由。
class FileManagerCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const FileManagerCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<FileManagerCard> createState() => _FileManagerCardState();
}

class _FileManagerCardState extends State<FileManagerCard> {
  /// 增量搜索的防抖窗口。再短会让每敲一个字都发一次桥调用，再长打中文
  /// （拼音候选要来回改）会感觉没反应。
  static const _searchDebounceDuration = Duration(milliseconds: 180);

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _pathController = TextEditingController();
  final _homeButtonKey = GlobalKey();

  /// 面包屑的横向位置。路径放不下时滚到**末尾**（最深那层可见），放得下就停在开头 ——
  /// 用 `reverse` 达不到这个区别，它会把短路径也顶到右边，看着像整条右对齐。
  /// 目录列那一行同一个毛病，用同一套画法。
  final _breadcrumbScroll = ScrollController();
  final _directoryColumnScroll = ScrollController();
  String? _breadcrumbRevealedPath;
  String? _columnsRevealedPath;

  bool _editingPath = false;
  bool _searchExpanded = false;
  Timer? _searchDebounce;

  /// 最近一次**发给**核心的搜索原文。用来区分「核心把我的输入回显了」和
  /// 「核心自己改了查询」（切页签、导航会清空）—— 前者不能覆盖输入框里的原始文本。
  String? _pendingSearchQuery;
  bool _searchPending = false;

  /// 这一次搜索是否仍在遍历中。结果本身**不在**这里 —— 命中由 Rust 写进页签，
  /// 快照的 `entries` 就是它，UI 不另存一份（否则换布局重建卡片就会丢结果，
  /// 且列表出现两个真本）。
  bool _searchRunning = false;
  int _searchSerial = 0;

  /// 上一次为「搜索条件签名」跑过遍历的签名，见 [_searchSignatureOf]。
  String _searchSignature = '';

  /// 最近搜索词。正本在 `settings.db`，这里只是这一屏的缓存。
  List<String> _searchHistory = const [];
  bool _searchHistoryLoaded = false;
  static const _searchHistoryLimit = 8;
  BigInt? _sessionId;
  FileManagerSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  int _requestSerial = 0;
  bool _disposed = false;

  /// 选中态 / 内部剪贴板 / 撤销栈的投影。**正本在 Rust 的 `FileOpsSession` 里**
  /// ——和路径、页签、搜索命中一样，卡片不自己存一份（存了就会出现两个真本，
  /// 换布局重建卡片时其中一个会丢）。
  ///
  /// 它与 [_snapshot] 的 `generation` 是配套的：列表换代后（前进/后退/搜索/排序）
  /// 旧的选中下标就作废了，Rust 会在下一次读选中态时按路径重新绑定，
  /// 所以这里必须跟着重读（见 [_refreshOps]）。
  FileOpsSnapshot? _ops;

  /// [_ops] 里 `selectedPaths` 的集合形式。列表逐行问「我在不在选中集合里」，
  /// 用 List 的 `contains` 就成了每帧 O(行数 × 选中数)。
  Set<String> _selectedPaths = const {};

  /// 选中态有自己的请求序号：它和列表快照是两条独立的线，共用一个序号会
  /// 让「点一下选中」和「敲一下搜索」互相把对方的回包当陈旧结果丢掉。
  int _opsSerial = 0;

  /// 这一帧的「文件操作」总开关（全局设置）。
  ///
  /// 存成字段而不是每次现查：`context.select` 不去重，而列表里**每一行**都要问
  /// 一次「要不要挂右键菜单」——每行各订阅一次，一屏就是几十个订阅。
  /// 在 [build] 里订阅一次、同一个 build pass 里大家读它。
  bool _fileOpsEnabled = true;

  /// 文件树面板。展开/懒扫描/游标的正本在 Rust 的 `FolderPaneState` 里，
  /// 这里只有「开没开」与最近一次投影。
  bool _treeEnabled = false;
  FileManagerTreeSnapshot? _tree;
  BigInt? _treeGeneration;
  Timer? _treePoll;
  int _treeSerial = 0;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _treePoll?.cancel();
    // 先摘登记再关会话：反过来的话，两个动作之间有一个窗口期，
    // 别人正好在这时候请求「新页签」会拿到一个马上要消失的会话。
    FileManagerTabBridge.instance.detach(this);
    _searchController.dispose();
    _searchFocus.dispose();
    _pathController.dispose();
    _breadcrumbScroll.dispose();
    _directoryColumnScroll.dispose();
    final id = _sessionId;
    if (id != null) {
      fileManagerClose(id: id);
      // 与 `file_manager_close` 成对：选中态 / 剪贴板 / 撤销栈住在另一张表里，
      // 只关前者会留下一份没人再用的会话状态（以及一个还挂着的取消旗子）。
      fileOpsClose(id: id);
    }
    super.dispose();
  }

  /// 落盘的主页路径（全局设置）。空串 = 用户还没设过。
  ///
  /// 这是「跨重启」的唯一来源：Rust 会话里的 `home_path` 只活在这一次会话里，
  /// 卡片重建（换布局、收起再展开）或重启应用都会重新问这里要。
  String get _persistedHomePath =>
      context.read<GlobalSettingCubit>().state.fileManagerSetting.homePath;

  /// 「记住每个目录的视图与排序」的落盘开关（全局设置）。
  bool get _persistedRememberViewState => context
      .read<GlobalSettingCubit>()
      .state
      .fileManagerSetting
      .rememberViewState;

  /// 新建会话该落在哪个目录，`null` = 交给核心选默认目录。
  ///
  /// 「启动时默认打开主页」是一条**用户主动要**的行为，而主页键开着与否是他对
  /// 「主页」这一节的总表态 —— 关掉主页键后还偷偷把启动落点挪到主页目录，
  /// 就成了一个没处解释的第三条路径，所以这里与主页键同源。
  /// 失效路径不必在这里挡：核心的 `resolve_openable_path` 认不出目录时会向上找到
  /// 最近的、还在的父目录（一个都没有才落到默认目录），
  /// 于是「主页目录被删了」表现为「停在它原来的位置」，而不是开卡即报错。
  String? get _startPath {
    final setting = context.read<GlobalSettingCubit>().state.fileManagerSetting;
    if (!setting.openHomeOnStart || !setting.homeEnabled) return null;
    return setting.homePath.isEmpty ? null : setting.homePath;
  }

  /// 已经提交给会话的「记忆视图」开关值。
  ///
  /// 守卫的意义：同步是发在 build 之后的，判据来自快照；如果这一次提交没有生效
  /// （比如会话刚好出错），两边会一直不一致 —— 没有这个守卫就是每帧重发一次桥调用。
  /// 有它以后语义变成「每次用户改动最多补发一次」：要重试得等用户再改。
  bool? _syncedRememberViewState;

  // ── 多选与文件操作 ────────────────────────────────────────────────────────
  //
  // 三层分工，与卡片其余部分同构：
  //
  // - **有哪些项、哪一项可用、点一下算打开还是选上** —— 纯函数，见
  //   `lib/workspace/model/file_manager_entry_menu_spec.dart`（判据
  //   `dart run test/workspace/file_manager_entry_menu_check.dart`）；
  // - **问用户要参数、把结果说给他听** —— `lib/workspace/method/file_manager_actions.dart`；
  // - **把动作发给核心** —— 只有这里知道会话 id、忙状态与请求序号，所以桥调用留在这一层。

  Future<void> _loadSearchHistory() async {
    if (_searchHistoryLoaded || _disposed) return;
    _searchHistoryLoaded = true;
    try {
      final history = await fileManagerSearchHistory(
        limit: _searchHistoryLimit,
      );
      if (!mounted || history.isEmpty) return;
      setState(() => _searchHistory = history);
    } catch (_) {
      // 同上：读不到就当这次没有历史。
    }
  }

  /// 输入即搜：防抖到 [_searchDebounceDuration]，回车走 `_submitSearch` 立即提交。
  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      _searchDebounceDuration,
      () => _submitSearch(query),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final theme = Theme.of(context);
    // 设置页改开关时这张卡片不会重建，所以在这里对齐一次；排到帧后是因为
    // 同步本身会 `setState`，在 build 期间发起会撞上「构建期间改状态」。
    final remember = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.rememberViewState,
    );
    // 写操作总开关。订阅放在这里（而不是逐行 `select`）的理由见 [_fileOpsEnabled]。
    _fileOpsEnabled = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.fileOperations,
    );
    if (snapshot != null &&
        !_busy &&
        _syncedRememberViewState != remember &&
        snapshot.rememberViewState != remember) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncRememberViewState(remember);
      });
    }
    if (snapshot != null) {
      _followTreeOn(snapshot.generation);
    }
    if (widget.isStandalone) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: _buildBody(context, snapshot),
        ),
      );
    }
    return CollapsibleCard(
      cardId: WorkspaceCardRegistry.localFolder,
      title: '文件浏览',
      icon: Icons.folder_copy_rounded,
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
      onHide: widget.onHide,
      trailing: snapshot == null
          ? null
          : Text(
              '${snapshot.tabs.length}/${snapshot.maxTabs}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      child: _buildBody(context, snapshot),
    );
  }

  Widget _buildBody(BuildContext context, FileManagerSnapshot? snapshot) {
    if (snapshot == null) {
      final loadingWidget = Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : _ErrorState(message: _error!, onRetry: _startSession),
      );
      if (widget.isStandalone) {
        return loadingWidget;
      }
      return SizedBox(height: 180, child: loadingWidget);
    }
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 只有一个页签时整行没有信息量（对齐 neo 的 tabs-single-hidden）：
        // 新建与恢复改由面包屑的「路径操作」菜单承担，见 [_buildPathActionsMenu]。
        if (snapshot.tabs.length > 1) ...[
          _buildTabs(context, snapshot),
          const SizedBox(height: 6),
        ],
        _buildToolbar(context, snapshot),
        _buildBreadcrumbs(context, snapshot),
        if (snapshot.directoryColumnsEnabled)
          _buildDirectoryColumns(context, snapshot),
        if (_treeEnabled) _buildFileTree(context),
        const SizedBox(height: 6),
        if (_searchExpanded || snapshot.searchQuery.isNotEmpty) ...[
          _buildSearchField(context, snapshot),
          const SizedBox(height: 4),
          _buildSearchOptions(context, snapshot),
          const SizedBox(height: 6),
        ],
        _buildRoots(context, snapshot),
        if (_error != null) _buildInlineError(context),
        // 操作条紧贴列表上方：它管的就是下面那一批行。
        if (_fileOpsEnabled && _selectedPaths.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildSelectionBar(context, snapshot),
        ],
        const SizedBox(height: 6),
      ],
    );
    if (!widget.isStandalone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [controls, _buildEntries(context, snapshot)],
      );
    }
    // 上/下边栏可能很矮：控件区域可滚动，始终给目录内容保留可用高度。
    return LayoutBuilder(
      builder: (context, constraints) {
        final reservedListHeight = (constraints.maxHeight * 0.4).clamp(
          0.0,
          120.0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - reservedListHeight,
              ),
              child: SingleChildScrollView(child: controls),
            ),
            Expanded(child: _buildEntries(context, snapshot)),
          ],
        );
      },
    );
  }

  /// 视图模式映射。渲染全部走 `LibraryEntryList`，这一层只剩
  /// 「把 `FileManagerEntry` 说成共享行模型听得懂的话」。
  static const _thumbModes = {
    LibraryViewMode.coverList,
    LibraryViewMode.mosaicList,
    LibraryViewMode.coverGrid,
    LibraryViewMode.mosaicGrid,
  };

  static const _detailsTitleColumn = LibraryColumn(
    key: 'name',
    label: '名称',
    flex: LibraryViewLayout.detailsTitleFlex,
  );

  static const _detailsColumns = [
    LibraryColumn(key: 'type', label: '类型', width: 70),
    LibraryColumn(key: 'size', label: '大小', width: 75, alignRight: true),
    LibraryColumn(key: 'date', label: '修改时间', width: 110),
  ];

  Widget _buildEntries(BuildContext context, FileManagerSnapshot snapshot) {
    final mode = fileManagerLibraryMode(snapshot.viewMode);
    final searching =
        snapshot.searchQuery.isNotEmpty ||
        snapshot.entryFilter != FileManagerEntryFilter.all;
    // `snapshot.entries` 就是该画的东西：普通浏览时是当前目录，搜索结果页签时
    // 是命中列表。这一层不需要知道这两种情况的存在。
    final query = snapshot.searchQuery;
    return LibraryEntryList(
      mode: mode,
      entries: [
        for (final entry in snapshot.entries)
          _libraryEntry(context, entry, mode),
      ],
      emptyText: snapshot.searchActive && query.isNotEmpty
          ? '子目录里没有匹配「$query」的条目'
          : searching
          ? '没有符合搜索或类型筛选的条目'
          : '当前目录没有可浏览的漫画或媒体文件',
      enabled: !_busy,
      busy: _busy,
      standalone: widget.isStandalone,
      // 关掉「文件操作」时整块不挂：连右键手势都没有，列表回到纯浏览。
      wrapRow: _fileOpsEnabled ? _wrapEntryRow : null,
      onTap: (row) => _onEntryTap(row.source! as FileManagerEntry),
      canDoubleTap: (row) => (row.source! as FileManagerEntry).isArchive,
      onDoubleTap: (row) => _openArchive(row.source! as FileManagerEntry),
      titleColumn: _detailsTitleColumn,
      columns: _detailsColumns,
      sortKey: snapshot.sortField.name,
      sortAscending: snapshot.sortOrder == FileManagerSortOrder.ascending,
      onSort: (key) =>
          _toggleSort(snapshot, FileManagerSortField.values.byName(key)),
    );
  }

  LibraryEntry _libraryEntry(
    BuildContext context,
    FileManagerEntry entry,
    LibraryViewMode mode,
  ) {
    final hasSize = !entry.isDir && entry.size > BigInt.zero;
    return LibraryEntry(
      key: entry.path,
      title: entry.name,
      source: entry,
      subtitle: _subtitle(entry, mode),
      metaText: hasSize ? _formatSize(entry.size) : null,
      media:
          (
            context, {
            required width,
            required height,
            required radius,
            required fit,
          }) => FileManagerThumbnailWidget(
            entry: entry,
            width: width,
            height: height,
            borderRadius: radius,
            fit: fit,
          ),
      badge: _semanticIcon(context, entry),
      thumbModes: _thumbModes,
      subLines: [for (final child in entry.childNames) _subLine(child)],
      detailCells: [
        _formatType(entry),
        _formatSize(entry.size),
        _formatDate(entry.modifiedSecs.toInt()),
      ],
      overlayText: entry.childNames.isEmpty
          ? null
          : '${entry.childNames.length} 项',
      trailing: _trailing(context, entry, mode),
    );
  }

}

