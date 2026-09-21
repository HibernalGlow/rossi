// ignore_for_file: invalid_use_of_protected_member
part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardNavigationPart on _FileManagerCardState {
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
  /// 把一条横向滚动的行停在「开头，除非放不下才滚到末尾」。
  ///
  /// 帧后是因为要等布局完成才知道 `maxScrollExtent` 是多少；内容放得下时它是 0，
  /// 于是这一句等价于「保持左对齐」。
  void _revealTail(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
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
    if (_breadcrumbRevealedPath != snapshot.activePath) {
      _breadcrumbRevealedPath = snapshot.activePath;
      _revealTail(_breadcrumbScroll);
    }
    return Row(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey('file-manager-breadcrumb-scroll'),
              controller: _breadcrumbScroll,
              scrollDirection: Axis.horizontal,
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
                                (id) => fileManagerNavigate(
                                  id: id,
                                  path: part.path,
                                ),
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
        ),
        _buildPathActionsMenu(
          context,
          snapshot,
          showTabActions: snapshot.tabs.length <= 1,
        ),
      ],
    );
  }
  /// 面包屑行尾唯一的那颗键：路径与（页签行收起时的）页签动作都收在这里，
  /// 对齐 neo 的「路径操作」菜单。
  ///
  /// 「目录列」的开关只有这一处 —— 工具栏上曾经也有一颗，同一件事就有了两个入口。
  /// [showTabActions] 为真表示页签行被收掉了（单页签），这时新建与恢复已关闭页签
  /// 也搬进这颗菜单，否则它们就没有入口。
  Widget _buildPathActionsMenu(
    BuildContext context,
    FileManagerSnapshot snapshot, {
    required bool showTabActions,
  }) {
    final withTabActions = showTabActions && snapshot.canCreateTab;
    return FluentPopupMenuButton<String>(
      tooltip: '路径操作',
      visualDensity: VisualDensity.compact,
      enabled: !_busy,
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      onSelected: (value) {
        if (value.startsWith('reopen:')) {
          final tabId = BigInt.tryParse(value.substring('reopen:'.length));
          if (tabId == null) return;
          _apply((id) => fileManagerReopenClosedTab(id: id, tabId: tabId));
          return;
        }
        switch (value) {
          case 'new-tab':
            _apply((id) => fileManagerNewTab(id: id));
          case 'columns':
            _apply(
              (id) => fileManagerSetDirectoryColumns(
                id: id,
                enabled: !snapshot.directoryColumnsEnabled,
              ),
            );
          case 'edit':
            _editPath(snapshot);
        }
      },
      itemBuilder: (_) => [
        if (withTabActions) ...[
          const FluentPopupMenuItem(
            value: 'new-tab',
            leading: Icon(Icons.add_rounded, size: 16),
            title: Text('新建页签'),
          ),
          for (final tab in snapshot.recentlyClosed.reversed)
            FluentPopupMenuItem(
              value: 'reopen:${tab.id}',
              leading: const Icon(Icons.history_rounded, size: 16),
              title: Text('恢复页签：${tab.title}'),
            ),
          const FluentPopupMenuItem.divider(),
        ],
        FluentPopupMenuItem(
          value: 'columns',
          leading: const Icon(Icons.view_column_outlined, size: 16),
          title: Text(snapshot.directoryColumnsEnabled ? '收起目录列' : '展开目录列'),
        ),
        const FluentPopupMenuItem(
          value: 'edit',
          leading: Icon(Icons.edit_outlined, size: 16),
          title: Text('编辑路径'),
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
        if (_columnsRevealedPath != snapshot.activePath) {
          _columnsRevealedPath = snapshot.activePath;
          _revealTail(_directoryColumnScroll);
        }
        return SizedBox(
          height: 200,
          child: SingleChildScrollView(
            controller: _directoryColumnScroll,
            scrollDirection: Axis.horizontal,
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
          FluentPopupMenuButton<BigInt>(
            tooltip: '恢复已关闭页签',
            visualDensity: VisualDensity.compact,
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
                FluentPopupMenuItem(
                  value: tab.id,
                  title: Text(
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
    return FluentPopupMenuButton<String>(
      tooltip: '页签操作：${tab.title}',
      visualDensity: VisualDensity.compact,
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
        FluentPopupMenuItem(
          value: 'pin',
          title: Text(tab.pinned ? '取消固定' : '固定页签'),
        ),
        FluentPopupMenuItem(
          value: 'duplicate',
          enabled: snapshot.canCreateTab,
          title: const Text('复制页签'),
        ),
        const FluentPopupMenuItem.divider(),
        FluentPopupMenuItem(
          value: 'close',
          enabled: tab.canClose,
          title: const Text('关闭页签'),
        ),
        FluentPopupMenuItem(
          value: 'others',
          enabled: tab.canCloseOthers,
          title: const Text('关闭其他页签'),
        ),
        FluentPopupMenuItem(
          value: 'left',
          enabled: tab.canCloseLeft,
          title: const Text('关闭左侧页签'),
        ),
        FluentPopupMenuItem(
          value: 'right',
          enabled: tab.canCloseRight,
          title: const Text('关闭右侧页签'),
        ),
      ],
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
}
