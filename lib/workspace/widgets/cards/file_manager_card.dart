import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/src/rust/api/file_manager.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

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
      final id = await fileManagerCreate();
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
        _buildSearchAndFilter(context, snapshot),
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

  Widget _buildSearchAndFilter(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
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
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          enabled: !_busy,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            hintText: '当前目录名称 · 回车搜索',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: IconButton(
              tooltip: '清除搜索',
              icon: const Icon(Icons.clear, size: 16),
              onPressed: _busy
                  ? null
                  : () => _apply(
                      (id) => fileManagerSetSearchQuery(id: id, query: ''),
                    ),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (query) =>
              _apply((id) => fileManagerSetSearchQuery(id: id, query: query)),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            PopupMenuButton<FileManagerEntryFilter>(
              tooltip: '筛选文件类型',
              enabled: !_busy,
              onSelected: (filter) => _apply(
                (id) => fileManagerSetEntryFilter(id: id, filter: filter),
              ),
              itemBuilder: (_) => [
                for (final filter in filters.entries)
                  CheckedPopupMenuItem(
                    value: filter.key,
                    checked: filter.key == snapshot.entryFilter,
                    child: Text(filter.value),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('类型：${filters[snapshot.entryFilter]}'),
              ),
            ),
            PopupMenuButton<FileManagerSortField>(
              tooltip: '排序字段',
              enabled: !_busy,
              onSelected: (field) => _apply(
                (id) => fileManagerSetSort(
                  id: id,
                  field: field,
                  order: snapshot.sortOrder,
                ),
              ),
              itemBuilder: (_) => [
                for (final field in fields.entries)
                  CheckedPopupMenuItem(
                    value: field.key,
                    checked: field.key == snapshot.sortField,
                    child: Text(field.value),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('排序：${fields[snapshot.sortField]}'),
              ),
            ),
            IconButton(
              tooltip: snapshot.sortOrder == FileManagerSortOrder.ascending
                  ? '切换为降序'
                  : '切换为升序',
              icon: Icon(
                snapshot.sortOrder == FileManagerSortOrder.ascending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 16,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: _busy
                  ? null
                  : () => _apply(
                      (id) => fileManagerSetSort(
                        id: id,
                        field: snapshot.sortField,
                        order:
                            snapshot.sortOrder == FileManagerSortOrder.ascending
                            ? FileManagerSortOrder.descending
                            : FileManagerSortOrder.ascending,
                      ),
                    ),
            ),
            Text(
              '${snapshot.entries.length} 项',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : onPressed,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          action(
            icon: Icons.arrow_back_rounded,
            tooltip: '后退',
            onPressed:
                snapshot.tabs
                    .firstWhere((tab) => tab.id == snapshot.activeTabId)
                    .canGoBack
                ? () => _apply((id) => fileManagerGoBack(id: id))
                : null,
          ),
          action(
            icon: Icons.arrow_forward_rounded,
            tooltip: '前进',
            onPressed:
                snapshot.tabs
                    .firstWhere((tab) => tab.id == snapshot.activeTabId)
                    .canGoForward
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
          action(
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            onPressed: () => _apply((id) => fileManagerRefresh(id: id)),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: snapshot.viewMode == FileManagerViewMode.list
                ? '网格视图'
                : '列表视图',
            onPressed: _busy
                ? null
                : () => _apply(
                    (id) => fileManagerSetViewMode(
                      id: id,
                      mode: snapshot.viewMode == FileManagerViewMode.list
                          ? FileManagerViewMode.grid
                          : FileManagerViewMode.list,
                    ),
                  ),
            icon: Icon(
              snapshot.viewMode == FileManagerViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '文件浏览设置',
            enabled: !_busy,
            icon: const Icon(Icons.tune_rounded, size: 18),
            onSelected: (value) {
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
                case 'penetration':
                  _apply(
                    (id) => fileManagerSetPenetration(
                      id: id,
                      enabled: !snapshot.penetrationEnabled,
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
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'penetration',
                checked: snapshot.penetrationEnabled,
                child: const Text('穿透模式'),
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
            ],
          ),
        ],
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
    final content = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: snapshot.viewMode == FileManagerViewMode.grid
          ? GridView.builder(
              padding: const EdgeInsets.all(6),
              primary: false,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisExtent: 104,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: snapshot.entries.length,
              itemBuilder: (context, index) =>
                  _buildGridEntry(context, snapshot.entries[index]),
            )
          : ListView.separated(
              primary: false,
              itemCount: snapshot.entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _buildListEntry(context, snapshot.entries[index]),
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

  Widget _buildListEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        leading: FileManagerThumbnailWidget(
          entry: entry,
          width: 36,
          height: 36,
          borderRadius: BorderRadius.circular(6),
        ),
        title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: entry.childNames.isEmpty
            ? (entry.isArchive ||
                      entry.isImage ||
                      entry.isVideo ||
                      entry.isAudio
                  ? Text(
                      _formatSize(entry.size),
                      style: theme.textTheme.labelSmall,
                    )
                  : null)
            : _buildChildNames(context, entry.childNames),
        trailing: entry.isDir
            ? IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                tooltip: '进入文件夹',
                visualDensity: VisualDensity.compact,
                onPressed: _busy
                    ? null
                    : () => _openEntry(entry, forceEnter: true),
              )
            : const Icon(Icons.play_circle_outline_rounded, size: 18),
      ),
    );
  }

  Widget _buildGridEntry(BuildContext context, FileManagerEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: _busy ? null : () => _openEntry(entry),
      onDoubleTap: entry.isArchive && !_busy ? () => _openArchive(entry) : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FileManagerThumbnailWidget(
              entry: entry,
              width: 38,
              height: 38,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.childNames.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildChildNames(context, entry.childNames),
                      ),
                    ),
                  ] else if (!entry.isDir)
                    Text(
                      _formatSize(entry.size),
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
