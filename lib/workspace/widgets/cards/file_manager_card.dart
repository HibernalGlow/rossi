import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

extension FileManagerViewModeX on FileManagerViewMode {
  String get label {
    switch (this) {
      case FileManagerViewMode.compact:
        return '紧凑列表';
      case FileManagerViewMode.coverList:
        return '封面列表';
      case FileManagerViewMode.mosaicList:
        return '横幅';
      case FileManagerViewMode.details:
        return '详细信息';
      case FileManagerViewMode.coverGrid:
        return '封面网格';
      case FileManagerViewMode.mosaicGrid:
        return '自由缩略图';
    }
  }

  IconData get icon {
    switch (this) {
      case FileManagerViewMode.compact:
        return Icons.view_headline_rounded;
      case FileManagerViewMode.coverList:
        return Icons.table_rows_rounded;
      case FileManagerViewMode.mosaicList:
        return Icons.view_agenda_rounded;
      case FileManagerViewMode.details:
        return Icons.table_chart_rounded;
      case FileManagerViewMode.coverGrid:
        return Icons.grid_view_rounded;
      case FileManagerViewMode.mosaicGrid:
        return Icons.grid_on_rounded;
    }
  }
}

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
  final _searchController = TextEditingController();
  final _pathController = TextEditingController();
  bool _editingPath = false;
  bool _searchExpanded = false;
  BigInt? _sessionId;
  FileManagerSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  int _requestSerial = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchController.dispose();
    _pathController.dispose();
    final id = _sessionId;
    if (id != null) fileManagerClose(id: id);
    super.dispose();
  }

  /// 落盘的主页路径（全局设置）。空串 = 用户还没设过。
  ///
  /// 这是「跨重启」的唯一来源：Rust 会话里的 `home_path` 只活在这一次会话里，
  /// 卡片重建（换布局、收起再展开）或重启应用都会重新问这里要。
  String get _persistedHomePath =>
      context.read<GlobalSettingCubit>().state.fileManagerSetting.homePath;

  Future<void> _startSession() async {
    if (_busy) return;
    if (_sessionId != null) {
      await _reload();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final home = _persistedHomePath;
      final id = await fileManagerCreate(
        homePath: home.isEmpty ? null : home,
      );
      if (_disposed) {
        fileManagerClose(id: id);
        return;
      }
      _sessionId = id;
      await _reload();
    } catch (error) {
      _showError(error);
    }
  }

  /// 把某个目录设为主页：**先写全局设置，再改本次会话**。
  ///
  /// 顺序有意义 —— 会话里的值只影响这一次的界面，写盘才是「下次启动还记得」。
  /// 持久化里可能留着一个已经失效的路径（目录被删 / 移动盘没插），那种情况
  /// 由 `_startSession` 注入时被 Rust 拒绝，UI 用
  /// 「`persistedHomePath` 非空但 `snapshot.homePath` 为空」判定失效。
  Future<void> _setHomePath(String path) async {
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: path),
    );
    await _apply((id) => fileManagerSetHomePath(id: id, path: path));
  }

  Future<void> _clearHomePath() async {
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: ''),
    );
    await _apply((id) => fileManagerSetHomePath(id: id, path: null));
  }

  Future<void> _reload() async {
    final id = _sessionId;
    if (id == null) return;
    final serial = ++_requestSerial;
    setState(() => _busy = true);
    try {
      final snapshot = await fileManagerSnapshot(id: id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _acceptSnapshot(snapshot);
        _error = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<bool> _apply(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return false;
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action(id);
      if (!mounted || serial != _requestSerial) return false;
      setState(() {
        _acceptSnapshot(snapshot);
        _busy = false;
      });
      return true;
    } catch (error) {
      if (!mounted || serial != _requestSerial) return false;
      _showError(error);
      return false;
    }
  }

  Future<void> _openEntry(
    FileManagerEntry entry, {
    bool forceEnter = false,
  }) async {
    await _openAction(
      (id) => fileManagerOpenEntry(
        id: id,
        path: entry.path,
        forceEnter: forceEnter,
      ),
    );
  }

  Future<void> _openArchive(FileManagerEntry entry) async {
    if (!entry.isArchive) return;
    await _openAction((id) => fileManagerOpenArchive(id: id, path: entry.path));
  }

  Future<void> _openAction(
    Future<FileManagerActionResult> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return;
    final serial = ++_requestSerial;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action(id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _acceptSnapshot(result.snapshot);
      });
      final openedPath = result.openedPath;
      if (openedPath != null && mounted && serial == _requestSerial) {
        // Keep the card busy while the reader route is on top. This makes the
        // second pointer-up of a double-click unable to enqueue another route.
        await _openReader(openedPath);
      }
      if (!mounted || serial != _requestSerial) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  Future<void> _openChild(FileManagerChild child) async {
    await _openEntry(_entryFromChild(child));
  }

  Future<void> _openArchiveChild(FileManagerChild child) async {
    if (!child.isArchive) return;
    await _openArchive(_entryFromChild(child));
  }

  FileManagerEntry _entryFromChild(FileManagerChild child) {
    return FileManagerEntry(
      path: child.path,
      name: child.name,
      isDir: child.isDir,
      isArchive: child.isArchive,
      isImage: child.isImage,
      isVideo: child.isVideo,
      isAudio: child.isAudio,
      size: BigInt.zero,
      modifiedSecs: 0,
      hasChildren: false,
      childNames: const [],
    );
  }

  Future<void> _openReader(String path) async {
    if (!mounted) return;
    await context.pushRoute(
      ComicReadRoute(
        comicId: path,
        order: 0,
        from: 'local_file_manager',
        epsNumber: 1,
        type: ComicEntryType.normal,
        comicInfo: path,
        stringSelectCubit: StringSelectCubit(),
      ),
    );
  }

  void _acceptSnapshot(FileManagerSnapshot snapshot) {
    _snapshot = snapshot;
    if (_searchController.text != snapshot.searchQuery) {
      _searchController.value = TextEditingValue(
        text: snapshot.searchQuery,
        selection: TextSelection.collapsed(offset: snapshot.searchQuery.length),
      );
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final theme = Theme.of(context);
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
        _buildTabs(context, snapshot),
        const SizedBox(height: 6),
        _buildToolbar(context, snapshot),
        _buildBreadcrumbs(context, snapshot),
        if (snapshot.directoryColumnsEnabled)
          _buildDirectoryColumns(context, snapshot),
        const SizedBox(height: 6),
        if (_searchExpanded || snapshot.searchQuery.isNotEmpty) ...[
          _buildSearchField(context, snapshot),
          const SizedBox(height: 6),
        ],
        _buildRoots(context, snapshot),
        if (_error != null) _buildInlineError(context),
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

  void _editPath(FileManagerSnapshot snapshot) {
    _pathController.value = TextEditingValue(
      text: snapshot.activePath,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: snapshot.activePath.length,
      ),
    );
    setState(() => _editingPath = true);
  }

  Future<void> _submitPath() async {
    final accepted = await _apply(
      (id) => fileManagerNavigateText(id: id, text: _pathController.text),
    );
    if (accepted && mounted) setState(() => _editingPath = false);
  }

  Widget _buildBreadcrumbs(BuildContext context, FileManagerSnapshot snapshot) {
    if (_editingPath) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_busy) setState(() => _editingPath = false);
          },
        },
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('file-manager-path-input'),
                controller: _pathController,
                autofocus: true,
                enabled: !_busy,
                textInputAction: TextInputAction.go,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '目录路径',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitPath(),
              ),
            ),
            IconButton(
              tooltip: '转到目录',
              onPressed: _busy ? null : _submitPath,
              icon: const Icon(Icons.check, size: 18),
            ),
            IconButton(
              tooltip: '取消路径编辑',
              onPressed: _busy
                  ? null
                  : () => setState(() => _editingPath = false),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                for (final part in snapshot.breadcrumbs) ...[
                  if (!part.isRoot) const Icon(Icons.chevron_right, size: 14),
                  Tooltip(
                    message: part.path,
                    child: TextButton(
                      key: ValueKey('file-manager-breadcrumb:${part.path}'),
                      onPressed: _busy
                          ? null
                          : part.isCurrent
                          ? () => _editPath(snapshot)
                          : () => _apply(
                              (id) =>
                                  fileManagerNavigate(id: id, path: part.path),
                            ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          part.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '编辑目录路径',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _editPath(snapshot),
          icon: const Icon(Icons.edit_outlined, size: 16),
        ),
        IconButton(
          tooltip: snapshot.directoryColumnsEnabled ? '收起目录列导航' : '展开目录列导航',
          visualDensity: VisualDensity.compact,
          onPressed: _busy
              ? null
              : () => _apply(
                  (id) => fileManagerSetDirectoryColumns(
                    id: id,
                    enabled: !snapshot.directoryColumnsEnabled,
                  ),
                ),
          icon: Icon(
            Icons.view_column_outlined,
            size: 18,
            color: snapshot.directoryColumnsEnabled
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDirectoryColumns(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / 2).clamp(150.0, 240.0);
        return SizedBox(
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final column in snapshot.directoryColumns)
                  SizedBox(
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _apply(
                                    (id) => fileManagerNavigate(
                                      id: id,
                                      path: column.path,
                                    ),
                                  ),
                            child: Text(
                              column.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: column.error != null
                                ? SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        column.error!,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  )
                                : column.entries.isEmpty
                                ? const Center(child: Text('没有子目录'))
                                : ListView.builder(
                                    itemCount: column.entries.length,
                                    itemBuilder: (context, index) {
                                      final entry = column.entries[index];
                                      return ListTile(
                                        key: ValueKey(
                                          'file-manager-column:${entry.path}',
                                        ),
                                        dense: true,
                                        selected: entry.selected,
                                        leading: const Icon(
                                          Icons.folder_outlined,
                                          size: 18,
                                        ),
                                        title: Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: _busy
                                            ? null
                                            : () => _apply(
                                                (id) => fileManagerNavigate(
                                                  id: id,
                                                  path: entry.path,
                                                ),
                                              ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabs(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final tab = snapshot.tabs[index];
                final selected = tab.id == snapshot.activeTabId;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabMenu(snapshot, tab),
                    InputChip(
                      selected: selected,
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(tab.title, overflow: TextOverflow.ellipsis),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () => _apply(
                              (id) =>
                                  fileManagerActivateTab(id: id, tabId: tab.id),
                            ),
                      onDeleted: !_busy && tab.canClose
                          ? () => _apply(
                              (id) =>
                                  fileManagerCloseTab(id: id, tabId: tab.id),
                            )
                          : null,
                      deleteIcon: const Icon(Icons.close, size: 13),
                    ),
                  ],
                );
              },
            ),
          ),
          PopupMenuButton<BigInt>(
            tooltip: '恢复已关闭页签',
            enabled:
                !_busy &&
                snapshot.canCreateTab &&
                snapshot.recentlyClosed.isNotEmpty,
            icon: const Icon(Icons.history_rounded, size: 18),
            onSelected: (tabId) => _apply(
              (id) => fileManagerReopenClosedTab(id: id, tabId: tabId),
            ),
            itemBuilder: (_) => [
              for (final tab in snapshot.recentlyClosed.reversed)
                PopupMenuItem(
                  value: tab.id,
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '新建页签',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _busy || !snapshot.canCreateTab
                ? null
                : () => _apply((id) => fileManagerNewTab(id: id)),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildTabMenu(FileManagerSnapshot snapshot, FileManagerTab tab) {
    return PopupMenuButton<String>(
      tooltip: '页签操作：${tab.title}',
      enabled: !_busy,
      icon: Icon(
        tab.pinned ? Icons.push_pin_rounded : Icons.more_vert_rounded,
        size: 16,
      ),
      onSelected: (action) => _apply(
        (id) => switch (action) {
          'pin' => fileManagerToggleTabPinned(id: id, tabId: tab.id),
          'duplicate' => fileManagerDuplicateTab(id: id, tabId: tab.id),
          'others' => fileManagerCloseOtherTabs(id: id, tabId: tab.id),
          'left' => fileManagerCloseTabsLeft(id: id, tabId: tab.id),
          'right' => fileManagerCloseTabsRight(id: id, tabId: tab.id),
          _ => fileManagerCloseTab(id: id, tabId: tab.id),
        },
      ),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'pin', child: Text(tab.pinned ? '取消固定' : '固定页签')),
        PopupMenuItem(
          value: 'duplicate',
          enabled: snapshot.canCreateTab,
          child: const Text('复制页签'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          enabled: tab.canClose,
          child: const Text('关闭页签'),
        ),
        PopupMenuItem(
          value: 'others',
          enabled: tab.canCloseOthers,
          child: const Text('关闭其他页签'),
        ),
        PopupMenuItem(
          value: 'left',
          enabled: tab.canCloseLeft,
          child: const Text('关闭左侧页签'),
        ),
        PopupMenuItem(
          value: 'right',
          enabled: tab.canCloseRight,
          child: const Text('关闭右侧页签'),
        ),
      ],
    );
  }

  /// 可折叠搜索框：由工具栏的搜索键展开；已有生效查询时强制显示。
  Widget _buildSearchField(BuildContext context, FileManagerSnapshot snapshot) {
    return TextField(
      controller: _searchController,
      enabled: !_busy,
      autofocus: snapshot.searchQuery.isEmpty,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: '当前目录名称 · 回车搜索',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: IconButton(
          tooltip: '清除搜索并收起',
          icon: const Icon(Icons.clear, size: 16),
          onPressed: _busy
              ? null
              : () {
                  _apply((id) => fileManagerSetSearchQuery(id: id, query: ''));
                  setState(() => _searchExpanded = false);
                },
        ),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (query) =>
          _apply((id) => fileManagerSetSearchQuery(id: id, query: query)),
    );
  }

  /// 工具栏对齐 neoview 文件卡：单行三段 —— 导航掌 / 主工具组 / 更多组。
  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    final activeTab = snapshot.tabs.firstWhere(
      (tab) => tab.id == snapshot.activeTabId,
    );
    const filters = {
      FileManagerEntryFilter.all: '全部',
      FileManagerEntryFilter.folders: '文件夹',
      FileManagerEntryFilter.archives: '归档',
      FileManagerEntryFilter.images: '图片',
      FileManagerEntryFilter.video: '视频',
      FileManagerEntryFilter.audio: '音频',
    };
    const fields = {
      FileManagerSortField.name: '名称',
      FileManagerSortField.type: '类型',
      FileManagerSortField.size: '大小',
      FileManagerSortField.date: '修改日期',
      FileManagerSortField.random: '随机',
    };

    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      bool active = false,
    }) {
      return IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: active ? theme.colorScheme.primary : null,
        ),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : onPressed,
      );
    }

    // 主页键：单击跳主页；右键 / 长按把当前目录设为主页。
    // 说明：IconButton 自带 Tooltip 默认长按触发，会抢走外层长按手势，
    // 因此这里自建 Tooltip（tap 触发）并把两种手势都留给外层 GestureDetector。
    Widget homeButton() {
      final homeTooltip =
          snapshot.homePath == null
              ? '主页（未设置 · 右键/长按设为当前目录）'
              : '主页（右键/长按改为当前目录）';
      final button = IconButton(
        icon: Icon(
          snapshot.isHome ? Icons.home_rounded : Icons.home_outlined,
          size: 18,
          color: snapshot.isHome ? theme.colorScheme.primary : null,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: _busy || snapshot.homePath == null
            ? null
            : () => _apply((id) => fileManagerGoHome(id: id)),
      );
      if (!snapshot.canSetHome) {
        return Tooltip(message: homeTooltip, child: button);
      }
      void setHome() => _apply(
        (id) => fileManagerSetHomePath(id: id, path: snapshot.activePath),
      );
      return GestureDetector(
        onSecondaryTapUp: (_) => setHome(),
        onLongPress: setHome,
        child: Tooltip(
          message: homeTooltip,
          triggerMode: TooltipTriggerMode.tap,
          child: button,
        ),
      );
    }

    // 隐藏滚动条：窄卡片下主工具组横向滚动，但不显示滚动条本身。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // —— 导航掌 ——
            action(
              icon: Icons.arrow_back_rounded,
              tooltip: '后退',
              onPressed: activeTab.canGoBack
                  ? () => _apply((id) => fileManagerGoBack(id: id))
                  : null,
            ),
            action(
              icon: Icons.arrow_forward_rounded,
              tooltip: '前进',
              onPressed: activeTab.canGoForward
                  ? () => _apply((id) => fileManagerGoForward(id: id))
                  : null,
            ),
            action(
              icon: Icons.arrow_upward_rounded,
              tooltip: '上一级',
              onPressed: snapshot.canGoUp
                  ? () => _apply((id) => fileManagerGoUp(id: id))
                  : null,
            ),
            homeButton(),
            action(
              icon: Icons.refresh_rounded,
              tooltip: '刷新',
              onPressed: () => _apply((id) => fileManagerRefresh(id: id)),
            ),

            // —— 主工具组 ——
            PopupMenuButton<FileManagerViewMode>(
              tooltip: '视图模式：${snapshot.viewMode.label}',
              enabled: !_busy,
              icon: Icon(snapshot.viewMode.icon, size: 18),
              onSelected: (mode) =>
                  _apply((id) => fileManagerSetViewMode(id: id, mode: mode)),
              itemBuilder: (_) => [
                for (final mode in FileManagerViewMode.values)
                  CheckedPopupMenuItem(
                    value: mode,
                    checked: mode == snapshot.viewMode,
                    child: Row(
                      children: [
                        Icon(mode.icon, size: 16),
                        const SizedBox(width: 8),
                        Text(mode.label),
                      ],
                    ),
                  ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: '排序：${fields[snapshot.sortField]}',
              enabled: !_busy,
              icon: const Icon(Icons.sort_rounded, size: 18),
              onSelected: (value) {
                if (value == 'order') {
                  _apply(
                    (id) => fileManagerSetSort(
                      id: id,
                      field: snapshot.sortField,
                      order:
                          snapshot.sortOrder == FileManagerSortOrder.ascending
                          ? FileManagerSortOrder.descending
                          : FileManagerSortOrder.ascending,
                    ),
                  );
                  return;
                }
                if (value == 'temporary') {
                  _apply(
                    (id) => fileManagerSetSortTemporary(
                      id: id,
                      enabled: !snapshot.sortTemporary,
                    ),
                  );
                  return;
                }
                if (value.startsWith('field:')) {
                  final name = value.substring('field:'.length);
                  final field = FileManagerSortField.values.firstWhere(
                    (field) => field.name == name,
                  );
                  _apply(
                    (id) => fileManagerSetSort(
                      id: id,
                      field: field,
                      order: snapshot.sortOrder,
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                for (final field in fields.entries)
                  CheckedPopupMenuItem(
                    value: 'field:${field.key.name}',
                    checked: field.key == snapshot.sortField,
                    child: Text(field.value),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'order',
                  child: Text(
                    snapshot.sortOrder == FileManagerSortOrder.ascending
                        ? '切换为降序'
                        : '切换为升序',
                  ),
                ),
                CheckedPopupMenuItem(
                  value: 'temporary',
                  checked: snapshot.sortTemporary,
                  enabled: snapshot.canSortPreference,
                  child: const Text('临时排序（不记住本目录）'),
                ),
              ],
            ),
            // 搜索键不参与 _busy 门控：展开/收起只是 UI 状态切换。
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                size: 18,
                color: _searchExpanded || snapshot.searchQuery.isNotEmpty
                    ? theme.colorScheme.primary
                    : null,
              ),
              tooltip: _searchExpanded ? '收起搜索' : '搜索当前目录',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _searchExpanded = !_searchExpanded),
            ),
            action(
              icon: Icons.view_week_rounded,
              tooltip: snapshot.directoryColumnsEnabled ? '关闭目录列' : '目录列',
              active: snapshot.directoryColumnsEnabled,
              onPressed: () => _apply(
                (id) => fileManagerSetDirectoryColumns(
                  id: id,
                  enabled: !snapshot.directoryColumnsEnabled,
                ),
              ),
            ),
            action(
              icon: Icons.alt_route_rounded,
              tooltip: snapshot.penetrationEnabled ? '关闭穿透模式' : '穿透模式',
              active: snapshot.penetrationEnabled,
              onPressed: () => _apply(
                (id) => fileManagerSetPenetration(
                  id: id,
                  enabled: !snapshot.penetrationEnabled,
                ),
              ),
            ),

            // —— 更多组 ——
            PopupMenuButton<String>(
              tooltip: '更多',
              enabled: !_busy,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (value) {
                if (value.startsWith('filter:')) {
                  final name = value.substring('filter:'.length);
                  final filter = FileManagerEntryFilter.values.firstWhere(
                    (filter) => filter.name == name,
                  );
                  _apply(
                    (id) => fileManagerSetEntryFilter(id: id, filter: filter),
                  );
                  return;
                }
                switch (value) {
                  case 'hidden':
                    _apply(
                      (id) => fileManagerSetShowHiddenFiles(
                        id: id,
                        enabled: !snapshot.showHiddenFiles,
                      ),
                    );
                  case 'directories':
                    _apply(
                      (id) => fileManagerSetDirectoriesFirst(
                        id: id,
                        enabled: !snapshot.directoriesFirst,
                      ),
                    );
                  case 'children':
                    _apply(
                      (id) => fileManagerSetShowChildNames(
                        id: id,
                        enabled: !snapshot.showChildNames,
                      ),
                    );
                  case 'mode':
                    _apply(
                      (id) => fileManagerSetInternalItemsMode(
                        id: id,
                        mode:
                            snapshot.internalItemsMode ==
                                FileManagerInternalItemsMode.single
                            ? FileManagerInternalItemsMode.all
                            : FileManagerInternalItemsMode.single,
                      ),
                    );
                  default:
                    final depth = int.tryParse(value);
                    if (depth != null) {
                      _apply(
                        (id) => fileManagerSetMaxDepth(id: id, depth: depth),
                      );
                    }
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'hidden',
                  checked: snapshot.showHiddenFiles,
                  child: const Text('显示隐藏文件'),
                ),
                CheckedPopupMenuItem(
                  value: 'directories',
                  checked: snapshot.directoriesFirst,
                  child: const Text('文件夹优先'),
                ),
                CheckedPopupMenuItem(
                  value: 'children',
                  checked: snapshot.showChildNames,
                  child: const Text('显示子文件名'),
                ),
                PopupMenuItem(
                  value: 'mode',
                  child: Text(
                    snapshot.internalItemsMode ==
                            FileManagerInternalItemsMode.single
                        ? '子文件：显示一个'
                        : '子文件：显示全部',
                  ),
                ),
                const PopupMenuDivider(),
                for (final depth in [1, 2, 3, 5, 10, 32])
                  CheckedPopupMenuItem(
                    value: '$depth',
                    checked: snapshot.maxDepth == depth,
                    child: Text(depth == 32 ? '穿透深度：最多 32 层' : '穿透深度：$depth 层'),
                  ),
                const PopupMenuDivider(),
                for (final filter in filters.entries)
                  CheckedPopupMenuItem(
                    value: 'filter:${filter.key.name}',
                    checked: filter.key == snapshot.entryFilter,
                    child: Text('类型：${filter.value}'),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Text(
              '${snapshot.entries.length} 项',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoots(BuildContext context, FileManagerSnapshot snapshot) {
    if (snapshot.roots.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: snapshot.roots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final root = snapshot.roots[index];
          final selected = snapshot.activePath == root.path;
          return ActionChip(
            label: Text(root.label, style: const TextStyle(fontSize: 11)),
            avatar: Icon(
              selected ? Icons.storage_rounded : Icons.folder_outlined,
              size: 15,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _busy
                ? null
                : () => _apply(
                    (id) => fileManagerNavigate(id: id, path: root.path),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildInlineError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 15,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _buildEntries(BuildContext context, FileManagerSnapshot snapshot) {
    if (snapshot.entries.isEmpty) {
      final emptyText = Center(
        child: Text(
          snapshot.searchQuery.isNotEmpty ||
                  snapshot.entryFilter != FileManagerEntryFilter.all
              ? '没有符合搜索或类型筛选的条目'
              : '当前目录没有可浏览的漫画或媒体文件',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
      if (widget.isStandalone) {
        return emptyText;
      }
      return SizedBox(height: 170, child: emptyText);
    }

    final Widget viewWidget = switch (snapshot.viewMode) {
      FileManagerViewMode.compact => _buildCompactList(context, snapshot),
      FileManagerViewMode.coverList => _buildCoverList(context, snapshot),
      FileManagerViewMode.mosaicList => _buildMosaicList(context, snapshot),
      FileManagerViewMode.details => _buildDetailsTable(context, snapshot),
      FileManagerViewMode.coverGrid => _buildCoverGrid(context, snapshot),
      FileManagerViewMode.mosaicGrid => _buildMosaicGrid(context, snapshot),
    };

    final content = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: viewWidget,
      ),
    );
    final list = widget.isStandalone
        ? content
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 440),
            child: content,
          );
    return Stack(
      fit: widget.isStandalone ? StackFit.expand : StackFit.loose,
      children: [
        list,
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- 1. 紧凑列表 (Compact List): 单行 ~34px 高度，彩色语义图标 + 紧凑元数据 ---
  Widget _buildCompactList(BuildContext context, FileManagerSnapshot snapshot) {
    return ListView.separated(
      primary: false,
      itemCount: snapshot.entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _buildCompactListEntry(context, snapshot.entries[index]),
    );
  }

  Widget _buildCompactListEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            _buildSemanticIcon(context, entry, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (entry.childNames.isNotEmpty)
                    _buildChildNames(context, entry.childNames),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (entry.isDir)
              IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                tooltip: '进入文件夹',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _busy
                    ? null
                    : () => _openEntry(entry, forceEnter: true),
              )
            else if (entry.size > BigInt.zero)
              Text(
                _formatSize(entry.size),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- 2. 封面列表 (Cover List): 双行 ~74px 高度，封面方块 + 标题 + 穿透子文件名/日期大小 ---
  Widget _buildCoverList(BuildContext context, FileManagerSnapshot snapshot) {
    return ListView.separated(
      primary: false,
      itemCount: snapshot.entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _buildCoverListEntry(context, snapshot.entries[index]),
    );
  }

  Widget _buildCoverListEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    final hasSize = !entry.isDir && entry.size > BigInt.zero;
    final hasDate = entry.modifiedSecs.toInt() > 0;
    String subtitleText = _formatType(entry);
    if (hasSize) {
      subtitleText += ' · ${_formatSize(entry.size)}';
    }
    if (hasDate) {
      subtitleText += ' · ${_formatDate(entry.modifiedSecs.toInt())}';
    }

    return InkWell(
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FileManagerThumbnailWidget(
              entry: entry,
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (entry.childNames.isNotEmpty)
                    _buildChildNames(context, entry.childNames)
                  else
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (entry.isDir)
              IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                tooltip: '进入文件夹',
                visualDensity: VisualDensity.compact,
                onPressed: _busy
                    ? null
                    : () => _openEntry(entry, forceEnter: true),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.play_circle_outline_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  // --- 3. 横幅 (Mosaic List): 宽卡片网格 ~92px 高，左侧宽缩略图横幅 + 右侧元数据 ---
  Widget _buildMosaicList(BuildContext context, FileManagerSnapshot snapshot) {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      primary: false,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 92,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: snapshot.entries.length,
      itemBuilder: (context, index) =>
          _buildMosaicListEntry(context, snapshot.entries[index]),
    );
  }

  Widget _buildMosaicListEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 88,
              child: FileManagerThumbnailWidget(
                entry: entry,
                width: 88,
                height: 92,
                borderRadius: BorderRadius.zero,
                fit: BoxFit.cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (entry.childNames.isNotEmpty)
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildChildNames(context, entry.childNames),
                        ),
                      )
                    else
                      Row(
                        children: [
                          _buildSemanticIcon(context, entry, size: 13),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              !entry.isDir && entry.size > BigInt.zero
                                  ? '${_formatType(entry)} · ${_formatSize(entry.size)}'
                                  : _formatType(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. 详细信息 (Details Table): 表格视图，含名称、类型、大小、修改时间表头，支持点击表头排序 ---
  Widget _buildDetailsTable(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 460.0;
        final tableWidth = constraints.maxWidth < minTableWidth
            ? minTableWidth
            : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDetailsHeader(context, snapshot),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    primary: false,
                    itemCount: snapshot.entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _buildDetailsRow(
                      context,
                      snapshot,
                      snapshot.entries[index],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsHeader(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _buildSortableHeaderCell(
              context,
              snapshot: snapshot,
              field: FileManagerSortField.name,
              label: '名称',
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 70,
            child: _buildSortableHeaderCell(
              context,
              snapshot: snapshot,
              field: FileManagerSortField.type,
              label: '类型',
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 75,
            child: _buildSortableHeaderCell(
              context,
              snapshot: snapshot,
              field: FileManagerSortField.size,
              label: '大小',
              alignRight: true,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 110,
            child: _buildSortableHeaderCell(
              context,
              snapshot: snapshot,
              field: FileManagerSortField.date,
              label: '修改时间',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortableHeaderCell(
    BuildContext context, {
    required FileManagerSnapshot snapshot,
    required FileManagerSortField field,
    required String label,
    bool alignRight = false,
  }) {
    final theme = Theme.of(context);
    final isActive = snapshot.sortField == field;
    final isAsc = snapshot.sortOrder == FileManagerSortOrder.ascending;

    return InkWell(
      onTap: _busy ? null : () => _toggleSort(snapshot, field),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisAlignment: alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                isAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsRow(
    BuildContext context,
    FileManagerSnapshot snapshot,
    FileManagerEntry entry,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  _buildSemanticIcon(context, entry, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 70,
              child: Text(
                _formatType(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 75,
              child: Text(
                _formatSize(entry.size),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 110,
              child: Text(
                _formatDate(entry.modifiedSecs.toInt()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 5. 封面网格 (Cover Grid): 竖版 2:3 海报比例封面网格，标题两行 ---
  Widget _buildCoverGrid(BuildContext context, FileManagerSnapshot snapshot) {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      primary: false,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisExtent: 180,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: snapshot.entries.length,
      itemBuilder: (context, index) =>
          _buildCoverGridEntry(context, snapshot.entries[index]),
    );
  }

  Widget _buildCoverGridEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FileManagerThumbnailWidget(
                    entry: entry,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                  if (entry.childNames.isNotEmpty)
                    Positioned(
                      left: 2,
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${entry.childNames.length} 项',
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildSemanticIcon(context, entry, size: 12),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!entry.isDir && entry.size > BigInt.zero)
                    Text(
                      _formatSize(entry.size),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 9,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 6. 自由缩略图 (Mosaic Grid): 1:1 正方形高密度缩略图网格，单行紧凑标题 ---
  Widget _buildMosaicGrid(BuildContext context, FileManagerSnapshot snapshot) {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      primary: false,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisExtent: 130,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: snapshot.entries.length,
      itemBuilder: (context, index) =>
          _buildMosaicGridEntry(context, snapshot.entries[index]),
    );
  }

  Widget _buildMosaicGridEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FileManagerThumbnailWidget(
                entry: entry,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSort(
    FileManagerSnapshot snapshot,
    FileManagerSortField field,
  ) async {
    final order =
        snapshot.sortField == field &&
            snapshot.sortOrder == FileManagerSortOrder.ascending
        ? FileManagerSortOrder.descending
        : FileManagerSortOrder.ascending;
    await _apply(
      (id) => fileManagerSetSort(id: id, field: field, order: order),
    );
  }

  Widget _buildSemanticIcon(
    BuildContext context,
    FileManagerEntry entry, {
    double size = 18,
  }) {
    final colors = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    if (entry.isDir) {
      icon = Icons.folder_rounded;
      color = colors.tertiary;
    } else if (entry.isArchive) {
      icon = Icons.auto_stories_rounded;
      color = colors.primary;
    } else if (entry.isImage) {
      icon = Icons.image_outlined;
      color = colors.secondary;
    } else if (entry.isVideo) {
      icon = Icons.movie_outlined;
      color = colors.secondary;
    } else if (entry.isAudio) {
      icon = Icons.audio_file_outlined;
      color = colors.secondary;
    } else {
      icon = Icons.insert_drive_file_outlined;
      color = colors.outline;
    }
    return Icon(icon, size: size, color: color);
  }

  String _formatDate(int secs) {
    if (secs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final year = dt.year.toString();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$min';
  }

  String _formatType(FileManagerEntry entry) {
    if (entry.isDir) return '文件夹';
    final lower = entry.name.toLowerCase();
    if (entry.isArchive) {
      if (lower.endsWith('.zip')) return 'ZIP 归档';
      if (lower.endsWith('.cbz')) return 'CBZ 归档';
      if (lower.endsWith('.rar')) return 'RAR 归档';
      if (lower.endsWith('.cbr')) return 'CBR 归档';
      if (lower.endsWith('.7z')) return '7Z 归档';
      if (lower.endsWith('.tar') || lower.endsWith('.tar.gz')) return 'TAR 归档';
      return '压缩归档';
    }
    if (entry.isImage) return '图片';
    if (entry.isVideo) return '视频';
    if (entry.isAudio) return '音频';
    final dot = entry.name.lastIndexOf('.');
    if (dot != -1 && dot < entry.name.length - 1) {
      return '${entry.name.substring(dot + 1).toUpperCase()} 文件';
    }
    return '文件';
  }

  Widget _buildChildNames(
    BuildContext context,
    List<FileManagerChild> children,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final child in children)
          InkWell(
            onTap: _busy ? null : () => _openChild(child),
            onDoubleTap: child.isArchive && !_busy
                ? () => _openArchiveChild(child)
                : null,
            child: Row(
              children: [
                Icon(
                  child.isDir
                      ? Icons.folder_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatSize(BigInt bytes) {
    if (bytes <= BigInt.zero) return '';
    const suffixes = ['B', 'KiB', 'MiB', 'GiB'];
    var index = 0;
    var value = bytes.toDouble();
    while (value >= 1024 && index < suffixes.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.amber),
        const SizedBox(height: 6),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('重试'),
        ),
      ],
    );
  }
}
