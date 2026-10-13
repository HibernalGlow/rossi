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
    // ignore: invalid_use_of_protected_member
    setState(() => _editingPath = true);
  }

  Future<void> _submitPath() async {
    final accepted = await _apply(
      (id) => fileManagerNavigateText(id: id, text: _pathController.text),
    );
    // ignore: invalid_use_of_protected_member
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
            // ignore: invalid_use_of_protected_member
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
              icon: const GlyphIcon(AppGlyphs.check, size: 18),
            ),
            IconButton(
              tooltip: '取消路径编辑',
              onPressed: _busy
                  ? null
                  // ignore: invalid_use_of_protected_member
                  : () => setState(() => _editingPath = false),
              icon: const GlyphIcon(AppGlyphs.close, size: 18),
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
                    if (!part.isRoot)
                      const GlyphIcon(AppGlyphs.chevronForward, size: 14),
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
    // 与工具栏那三颗同一套弹出器：托盘从这颗键长出来（FlClash 的
    // `CommonPopupRoute`），项集在 build 时构造好。
    return CommonPopupBox(
      targetBuilder: (open) => IconButton(
        tooltip: '路径操作',
        visualDensity: VisualDensity.compact,
        onPressed: !_busy ? open : null,
        icon: const GlyphIcon(AppGlyphs.more, size: 18),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          if (withTabActions) ...[
            CommonPopupMenuItem(
              label: '新建页签',
              glyph: AppGlyphs.add,
              onPressed: () => _apply((id) => fileManagerNewTab(id: id)),
            ),
            for (final tab in snapshot.recentlyClosed.reversed)
              CommonPopupMenuItem(
                label: '恢复页签：${tab.title}',
                glyph: AppGlyphs.history,
                onPressed: () => _apply(
                  (id) => fileManagerReopenClosedTab(id: id, tabId: tab.id),
                ),
              ),
            const CommonPopupMenuItem.divider(),
          ],
          CommonPopupMenuItem(
            label: '编辑路径',
            glyph: AppGlyphs.edit,
            onPressed: () => _editPath(snapshot),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SpringLensBar(
                lensCorner: ControlShape.corner,
                tabSizes: [
                  for (final tab in snapshot.tabs) _tabExtent(context, tab),
                ],
                selectedIndex: snapshot.tabs.indexWhere(
                  (tab) => tab.id == snapshot.activeTabId,
                ),
                draggable: !_busy,
                semanticContainer: false,
                onSelected: (index) {
                  if (!_busy) {
                    _apply(
                      (id) => fileManagerActivateTab(
                        id: id,
                        tabId: snapshot.tabs[index].id,
                      ),
                    );
                  }
                },
                tabs: [
                  for (final tab in snapshot.tabs)
                    SpringLensTab(
                      child: _buildTabContextMenu(
                        context,
                        snapshot,
                        tab,
                        child: Row(
                          children: [
                            Expanded(
                              child: Theme(
                                // RawChip 的 Material 会读取 canvasColor；透明 Ink
                                // 本身不足以去掉它那层底，背景只由切换条绘制。
                                data: theme.copyWith(
                                  canvasColor: Colors.transparent,
                                ),
                                child: InputChip(
                                  shape: ControlShape.withCorner(
                                    ControlShape.compactCorner,
                                  ),
                                  color: const WidgetStatePropertyAll(
                                    Colors.transparent,
                                  ),
                                  surfaceTintColor: Colors.transparent,
                                  elevation: 0,
                                  pressElevation: 0,
                                  avatar: tab.pinned
                                      ? const GlyphIcon(AppGlyphs.pin, size: 12)
                                      : null,
                                  selected: tab.id == snapshot.activeTabId,
                                  showCheckmark: false,
                                  selectedColor: Colors.transparent,
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide.none,
                                  label: Text(
                                    tab.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    color: tab.id == snapshot.activeTabId
                                        ? theme.colorScheme.onSecondaryContainer
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _busy
                                      ? null
                                      : () => _apply(
                                          (id) => fileManagerActivateTab(
                                            id: id,
                                            tabId: tab.id,
                                          ),
                                        ),
                                  onDeleted: !_busy && tab.canClose
                                      ? () => _apply(
                                          (id) => fileManagerCloseTab(
                                            id: id,
                                            tabId: tab.id,
                                          ),
                                        )
                                      : null,
                                  deleteIcon: const GlyphIcon(
                                    AppGlyphs.close,
                                    size: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          FluentPopupMenuButton<BigInt>(
            tooltip: '恢复已关闭页签',
            visualDensity: VisualDensity.compact,
            enabled:
                !_busy &&
                snapshot.canCreateTab &&
                snapshot.recentlyClosed.isNotEmpty,
            icon: const GlyphIcon(AppGlyphs.history, size: 18),
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
            icon: const GlyphIcon(AppGlyphs.add),
          ),
        ],
      ),
    );
  }

  double _tabExtent(BuildContext context, FileManagerTab tab) {
    final painter = TextPainter(
      text: TextSpan(
        text: tab.title,
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 11),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout(maxWidth: 130);
    final width = painter.width;
    painter.dispose();
    // 标签内边距、固定标记与关闭键也属于这一格；操作菜单不再占位。
    return width.clamp(30, 130) +
        32 +
        (tab.canClose ? 24 : 0) +
        (tab.pinned ? 18 : 0);
  }

  Widget _buildTabContextMenu(
    BuildContext context,
    FileManagerSnapshot snapshot,
    FileManagerTab tab, {
    required Widget child,
  }) {
    void run(Future<FileManagerSnapshot> Function(BigInt id) action) {
      if (!mounted || _busy) return;
      unawaited(_apply(action));
    }

    void openAt(Offset position) {
      if (_busy || !mounted) return;
      // 走 [showCommonPopupMenu]（[CommonPopupRoute] 那份 FlClash 动画）——
      // 与本卡那张「路径操作」同一套：托盘从右键 / 长按那一点长出来、
      // 放不下时自己朝上翻，不再是 Fluent 的原地淡入缩放。
      unawaited(
        showCommonPopupMenu(
          context: context,
          position: position,
          items: [
            CommonPopupMenuItem(
              label: tab.pinned ? '取消固定' : '固定页签',
              onPressed: () => run(
                (id) => fileManagerToggleTabPinned(id: id, tabId: tab.id),
              ),
            ),
            CommonPopupMenuItem(
              label: '从此页签新建',
              onPressed: snapshot.canCreateTab
                  ? () => run(
                      (id) => fileManagerNewTab(
                        id: id,
                        path: tab.path,
                        sourceTabId: tab.id,
                      ),
                    )
                  : null,
            ),
            CommonPopupMenuItem(
              label: '复制页签',
              onPressed: snapshot.canCreateTab
                  ? () => run(
                      (id) => fileManagerDuplicateTab(id: id, tabId: tab.id),
                    )
                  : null,
            ),
            const CommonPopupMenuItem.divider(),
            CommonPopupMenuItem(
              label: '关闭页签',
              onPressed: tab.canClose
                  ? () =>
                        run((id) => fileManagerCloseTab(id: id, tabId: tab.id))
                  : null,
            ),
            CommonPopupMenuItem(
              label: '关闭其他页签',
              onPressed: tab.canCloseOthers
                  ? () => run(
                      (id) => fileManagerCloseOtherTabs(id: id, tabId: tab.id),
                    )
                  : null,
            ),
            CommonPopupMenuItem(
              label: '关闭左侧页签',
              onPressed: tab.canCloseLeft
                  ? () => run(
                      (id) => fileManagerCloseTabsLeft(id: id, tabId: tab.id),
                    )
                  : null,
            ),
            CommonPopupMenuItem(
              label: '关闭右侧页签',
              onPressed: tab.canCloseRight
                  ? () => run(
                      (id) => fileManagerCloseTabsRight(id: id, tabId: tab.id),
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: _busy
          ? null
          : (details) => openAt(details.globalPosition),
      onLongPressStart: _busy
          ? null
          : (details) {
              HapticFeedback.selectionClick();
              openAt(details.globalPosition);
            },
      child: child,
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
            avatar: GlyphIcon(
              selected ? AppGlyphs.storage : AppGlyphs.folder,
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
