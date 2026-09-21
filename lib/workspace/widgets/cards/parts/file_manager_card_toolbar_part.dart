// ignore_for_file: invalid_use_of_protected_member
part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardToolbarPart on _FileManagerCardState {
  /// 工具栏对齐 neoview 文件卡：单行三段 —— 导航 / 主工具组 / 更多组。
  ///
  /// 导航那一段按卡片宽度二选一：够宽摊开成五颗标准图标钮，窄下来收成一颗掌。
  /// 几何与配色只有一个口径，见 `file_manager_toolbar.dart` 的
  /// [FileManagerToolbarMetrics] 与 [FileManagerToolbarIconButton]。
  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    // 只订阅本功能自己的开关，别的设置变了不重建这张卡片。
    final homeEnabled = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.homeEnabled,
    );
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
      return FileManagerToolbarIconButton(
        icon: icon,
        tooltip: tooltip,
        selected: active,
        enabled: !_busy,
        onPressed: onPressed,
      );
    }

    // 隐藏滚动条：窄卡片下主工具组横向滚动，但不显示滚动条本身。
    // 宽度问的是**卡片**：这一行自己在横向滚动视图里拿到的是无限宽约束，
    // 在那里面量不出「放不放得下」。
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedNavigation =
            constraints.maxWidth >=
            FileManagerToolbarMetrics.expandedNavigationMinWidth;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // —— 导航组 ——
                // 够宽就摊开成后退/前进/上一级/主页/刷新五颗标准键，
                // 窄下来才把五个方向收成一颗掌形控件（NeoView 的 FolderNavigationPad）。
                FileManagerNavigation(
                  expanded: expandedNavigation,
                  busy: _busy,
                  loading: _busy,
                  canGoBack: activeTab.canGoBack,
                  canGoForward: activeTab.canGoForward,
                  canGoUp: snapshot.canGoUp,
                  homeKey: _homeButtonKey,
                  homeEnabled: homeEnabled,
                  hasHome: snapshot.homePath != null,
                  atHome: snapshot.isHome,
                  onNavigateBack: () =>
                      _apply((id) => fileManagerGoBack(id: id)),
                  onNavigateForward: () =>
                      _apply((id) => fileManagerGoForward(id: id)),
                  onNavigateUp: () => _apply((id) => fileManagerGoUp(id: id)),
                  // 设过主页 = 单击回主页；没设过 = 单击把当前目录设为主页，
                  // 这样第一次用的人不必先猜「要长按/右键」。
                  onGoHome: snapshot.homePath != null
                      ? () => _apply((id) => fileManagerGoHome(id: id))
                      : () => _setHomePath(snapshot.activePath),
                  onHomeMenu: () => _openHomeMenu(snapshot),
                  onRefresh: () => _apply((id) => fileManagerRefresh(id: id)),
                ),
                const FileManagerToolbarSeparator(),

                // —— 主工具组 ——
                FluentPopupMenuButton<FileManagerViewMode>(
                  tooltip: '视图模式：${snapshot.viewMode.label}',
                  enabled: !_busy,
                  style: FileManagerToolbarIconButton.style(context),
                  icon: Icon(snapshot.viewMode.icon),
                  onSelected: (mode) => _apply(
                    (id) => fileManagerSetViewMode(id: id, mode: mode),
                  ),
                  itemBuilder: (_) => [
                    for (final mode in FileManagerViewMode.values)
                      FluentPopupMenuItem(
                        value: mode,
                        leading: Icon(mode.icon, size: 16),
                        selected: mode == snapshot.viewMode,
                        title: Text(mode.label),
                      ),
                  ],
                ),
                const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup),
                FluentPopupMenuButton<String>(
                  tooltip: '排序：${fields[snapshot.sortField]}',
                  enabled: !_busy,
                  style: FileManagerToolbarIconButton.style(context),
                  icon: const Icon(Icons.sort_rounded),
                  onSelected: (value) {
                    if (value == 'order') {
                      _apply(
                        (id) => fileManagerSetSort(
                          id: id,
                          field: snapshot.sortField,
                          order:
                              snapshot.sortOrder ==
                                  FileManagerSortOrder.ascending
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
                      FluentPopupMenuItem(
                        value: 'field:${field.key.name}',
                        selected: field.key == snapshot.sortField,
                        title: Text(field.value),
                      ),
                    const FluentPopupMenuItem.divider(),
                    FluentPopupMenuItem(
                      value: 'order',
                      title: Text(
                        snapshot.sortOrder == FileManagerSortOrder.ascending
                            ? '切换为降序'
                            : '切换为升序',
                      ),
                    ),
                    FluentPopupMenuItem(
                      value: 'temporary',
                      selected: snapshot.sortTemporary,
                      enabled: snapshot.canSortPreference,
                      title: const Text('临时排序（不记住本目录）'),
                    ),
                  ],
                ),
                // 搜索键不参与 _busy 门控：展开/收起只是 UI 状态切换。
                const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup),
                FileManagerToolbarIconButton(
                  icon: Icons.search_rounded,
                  tooltip: _searchExpanded ? '收起搜索' : '搜索（空格分词，-排除）',
                  selected: _searchExpanded || snapshot.searchQuery.isNotEmpty,
                  onPressed: () {
                    setState(() => _searchExpanded = !_searchExpanded);
                    if (_searchExpanded) _loadSearchHistory();
                  },
                ),
                const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup),
                action(
                  icon: Icons.account_tree_outlined,
                  tooltip: _treeEnabled ? '关闭文件树' : '文件树',
                  active: _treeEnabled,
                  onPressed: () => _setTreeEnabled(!_treeEnabled),
                ),
                const SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup),
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
                const FileManagerToolbarSeparator(),
                FluentPopupMenuButton<String>(
                  tooltip: '更多',
                  enabled: !_busy,
                  style: FileManagerToolbarIconButton.style(context),
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) {
                    if (value.startsWith('filter:')) {
                      final name = value.substring('filter:'.length);
                      final filter = FileManagerEntryFilter.values.firstWhere(
                        (filter) => filter.name == name,
                      );
                      _apply(
                        (id) =>
                            fileManagerSetEntryFilter(id: id, filter: filter),
                      );
                      return;
                    }
                    switch (value) {
                      case 'fileOps':
                        _setFileOperationsEnabled(!_fileOpsEnabled);
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
                            (id) =>
                                fileManagerSetMaxDepth(id: id, depth: depth),
                          );
                        }
                    }
                  },
                  itemBuilder: (context) => [
                    FluentPopupMenuItem(
                      value: 'fileOps',
                      selected: _fileOpsEnabled,
                      title: const Text('文件操作（复制 / 移动 / 删除）'),
                    ),
                    const FluentPopupMenuItem.divider(),
                    FluentPopupMenuItem(
                      value: 'hidden',
                      selected: snapshot.showHiddenFiles,
                      title: const Text('显示隐藏文件'),
                    ),
                    FluentPopupMenuItem(
                      value: 'directories',
                      selected: snapshot.directoriesFirst,
                      title: const Text('文件夹优先'),
                    ),
                    FluentPopupMenuItem(
                      value: 'children',
                      selected: snapshot.showChildNames,
                      title: const Text('显示子文件名'),
                    ),
                    FluentPopupMenuItem(
                      value: 'mode',
                      title: Text(
                        snapshot.internalItemsMode ==
                                FileManagerInternalItemsMode.single
                            ? '子文件：显示一个'
                            : '子文件：显示全部',
                      ),
                    ),
                    const FluentPopupMenuItem.divider(),
                    for (final depth in [1, 2, 3, 5, 10, 32])
                      FluentPopupMenuItem(
                        value: '$depth',
                        selected: snapshot.maxDepth == depth,
                        title: Text(
                          depth == 32 ? '穿透深度：最多 32 层' : '穿透深度：$depth 层',
                        ),
                      ),
                    const FluentPopupMenuItem.divider(),
                    for (final filter in filters.entries)
                      FluentPopupMenuItem(
                        value: 'filter:${filter.key.name}',
                        selected: filter.key == snapshot.entryFilter,
                        title: Text('类型：${filter.value}'),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                Text(
                  '${snapshot.entries.length} 项',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
