part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardToolbarPart on _FileManagerCardState {
  /// 工具栏对齐 neoview 文件卡：单行三段 —— 导航 / 主工具组 / 更多组。
  ///
  /// 导航那一段按卡片宽度二选一：够宽摊开成五颗标准图标钮，窄下来收成一颗掌。
  /// 几何与配色只有一个口径，见 `file_manager_toolbar.dart` 的
  /// [FileManagerToolbarMetrics] 与 [FileManagerToolbarIconButton]。
  ///
  /// 三个弹出菜单（视图 / 排序 / 更多）走 FlClash 那份弹出器
  /// （`common_popup.dart`）：托盘从触发键长出来，内容由糊变清 ——
  /// 与泳道栏头那颗 ⋮ 同一套动画，不再是 Fluent 的原地淡入缩放。
  Widget _buildToolbar(BuildContext context, FileManagerSnapshot snapshot) {
    final theme = Theme.of(context);
    // 只订阅本功能自己的开关，别的设置变了不重建这张卡片。
    final homeEnabled = context.select<GlobalSettingCubit, bool>(
      (cubit) => cubit.state.fileManagerSetting.homeEnabled,
    );
    final activeTab = snapshot.tabs.firstWhere(
      (tab) => tab.id == snapshot.activeTabId,
    );
    // 文案与图标成对存放：一个语义只有一份，菜单项与 tooltip 不会各说各话。
    // 类型过滤的图标直接沿用 `file_manager_thumbnail.dart` 里条目本来的类型图标，
    // 同一颗图形在列表行和过滤菜单里指同一种文件。「全部」用九宫格，避免和
    // 二级菜单父行那颗 `category` 撞成同一选择。
    const filters = {
      FileManagerEntryFilter.all: ('全部', AppGlyphs.apps),
      FileManagerEntryFilter.folders: ('文件夹', AppGlyphs.folder),
      FileManagerEntryFilter.archives: ('归档', AppGlyphs.openBook),
      FileManagerEntryFilter.images: ('图片', AppGlyphs.photos),
      FileManagerEntryFilter.video: ('视频', AppGlyphs.playCircle),
      FileManagerEntryFilter.audio: ('音频', AppGlyphs.music),
    };
    const fields = {
      FileManagerSortField.name: ('名称', AppGlyphs.textShort),
      FileManagerSortField.type: ('类型', AppGlyphs.category),
      FileManagerSortField.size: ('大小', AppGlyphs.resize),
      FileManagerSortField.date: ('修改日期', AppGlyphs.calendar),
      FileManagerSortField.random: ('随机', AppGlyphs.dice),
    };
    // 深度只有一个写法：父行与子项共用，收起与展开时读到的字不会变样。
    String depthLabel(int depth) => depth == 32 ? '最多 32 层' : '$depth 层';
    // 二级菜单收起时父行是唯一的状态出口（子菜单的箭头会顶掉勾选标记），
    // 于是把当前值写进父行标签，而不是留一个光秃秃的组名。
    final filterLabel = '类型：${filters[snapshot.entryFilter]!.$1}';

    Widget toggle({
      Glyph? icon,
      Glyph? glyph,
      required String tooltip,
      required bool on,
      required VoidCallback? onPressed,
    }) {
      return FileManagerToolbarToggleButton(
        icon: icon,
        glyph: glyph,
        tooltip: tooltip,
        on: on,
        enabled: !_busy,
        onPressed: onPressed,
      );
    }

    /// 菜单触发键：与 [FileManagerToolbarIconButton] 同一份几何配色，
    /// 按下去由 [CommonPopupBox] 推出 FlClash 那份托盘弹出路由。
    /// 项集在 build 时构造好（回调闭包的是 state 的方法，不需要路由里的东西）。
    Widget popupTrigger({
      required String tooltip,
      required Widget icon,
      required List<CommonPopupMenuItem> items,
    }) {
      return CommonPopupBox(
        targetBuilder: (open) => IconButton(
          tooltip: tooltip,
          onPressed: !_busy ? open : null,
          style: FileManagerToolbarIconButton.style(context),
          icon: icon,
        ),
        popupBuilder: (_) => CommonPopupMenu(items: items),
      );
    }

    // 分组只靠间距分级，两个数各写一次：组内 4、组间 12。槽里的每一颗键
    // （含菜单触发键）都是 40 见方，所以槽只是给这一组画一圈底，不改高度带。
    const within = SizedBox(width: FileManagerToolbarMetrics.gapWithinGroup);
    const between = SizedBox(width: FileManagerToolbarMetrics.gapBetweenGroups);

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
                // —— 导航槽 ——
                // 够宽就摊开成后退/前进/上一级/主页/刷新五颗标准键，
                // 窄下来才把五个方向收成一颗掌形控件（NeoView 的 FolderNavigationPad）。
                // 两种画法都坐在同一颗下沉槽里，组与组之间只靠 gapBetweenGroups 分开。
                FileManagerToolbarGroup(
                  bubbleTargets: false,
                  children: [
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
                      onNavigateUp: () =>
                          _apply((id) => fileManagerGoUp(id: id)),
                      // 设过主页 = 单击回主页；没设过 = 单击把当前目录设为主页，
                      // 这样第一次用的人不必先猜「要长按/右键」。
                      onGoHome: snapshot.homePath != null
                          ? () => _apply((id) => fileManagerGoHome(id: id))
                          : () => _setHomePath(snapshot.activePath),
                      onHomeMenu: () => _openHomeMenu(snapshot),
                      onRefresh: () =>
                          _apply((id) => fileManagerRefresh(id: id)),
                    ),
                  ],
                ),
                between,

                // —— 主工具槽 ——
                // 视图 / 排序 / 搜索 / 文件树 / 穿透 /（多选）全在**一只**槽里：
                // 它们管的是「眼下这一屏怎么看」，是一组。原先这几颗散着排，
                // 与导航槽并排看就是「一边有底一边没有」——统一到这一槽里。
                FileManagerToolbarGroup(
                  children: [
                    popupTrigger(
                      tooltip: '条目样式：${snapshot.viewMode.label}',
                      icon: GlyphIcon(snapshot.viewMode.icon),
                      items: [
                        for (final mode in FileManagerViewMode.values)
                          CommonPopupMenuItem(
                            label: mode.label,
                            glyph: mode.icon,
                            checked: mode == snapshot.viewMode,
                            onPressed: () => _apply(
                              (id) =>
                                  fileManagerSetViewMode(id: id, mode: mode),
                            ),
                          ),
                      ],
                    ),
                    within,
                    popupTrigger(
                      tooltip: '排序：${fields[snapshot.sortField]!.$1}',
                      icon: const GlyphIcon(AppGlyphs.sort),
                      items: [
                        for (final field in fields.entries)
                          CommonPopupMenuItem(
                            label: field.value.$1,
                            glyph: field.value.$2,
                            checked: field.key == snapshot.sortField,
                            onPressed: () => _apply(
                              (id) => fileManagerSetSort(
                                id: id,
                                field: field.key,
                                order: snapshot.sortOrder,
                              ),
                            ),
                          ),
                        const CommonPopupMenuItem.divider(),
                        CommonPopupMenuItem(
                          label:
                              snapshot.sortOrder ==
                                  FileManagerSortOrder.ascending
                              ? '切换为降序'
                              : '切换为升序',
                          // 箭头指本次点击后的方向，与上面的字段图标同一读法。
                          glyph:
                              snapshot.sortOrder ==
                                  FileManagerSortOrder.ascending
                              ? AppGlyphs.arrowDown
                              : AppGlyphs.arrowUp,
                          onPressed: () => _apply(
                            (id) => fileManagerSetSort(
                              id: id,
                              field: snapshot.sortField,
                              order:
                                  snapshot.sortOrder ==
                                      FileManagerSortOrder.ascending
                                  ? FileManagerSortOrder.descending
                                  : FileManagerSortOrder.ascending,
                            ),
                          ),
                        ),
                        CommonPopupMenuItem(
                          label: '临时排序（不记住本目录）',
                          glyph: AppGlyphs.hourglass,
                          checked: snapshot.sortTemporary,
                          onPressed: snapshot.canSortPreference
                              ? () => _apply(
                                  (id) => fileManagerSetSortTemporary(
                                    id: id,
                                    enabled: !snapshot.sortTemporary,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                    // 搜索键不参与 _busy 门控：展开/收起只是 UI 状态切换。
                    within,
                    FileManagerToolbarToggleButton(
                      glyph: AppGlyphs.search,
                      tooltip: _searchExpanded ? '收起搜索' : '搜索（空格分词，-排除）',
                      on: _searchExpanded || snapshot.searchQuery.isNotEmpty,
                      onPressed: () {
                        // ignore: invalid_use_of_protected_member
                        setState(() => _searchExpanded = !_searchExpanded);
                      },
                    ),
                    within,
                    popupTrigger(
                      tooltip: '内容布局：${snapshot.layoutMode.label}',
                      icon: GlyphIcon(snapshot.layoutMode.icon),
                      items: [
                        for (final mode in FileManagerLayoutMode.values)
                          CommonPopupMenuItem(
                            label: mode.label,
                            glyph: mode.icon,
                            checked: mode == snapshot.layoutMode,
                            onPressed: () => _apply(
                              (id) =>
                                  fileManagerSetLayoutMode(id: id, mode: mode),
                            ),
                          ),
                      ],
                    ),
                    within,
                    toggle(
                      glyph: AppGlyphs.passThrough,
                      tooltip: snapshot.penetrationEnabled ? '关闭穿透模式' : '穿透模式',
                      on: snapshot.penetrationEnabled,
                      onPressed: () => _apply(
                        (id) => fileManagerSetPenetration(
                          id: id,
                          enabled: !snapshot.penetrationEnabled,
                        ),
                      ),
                    ),

                    // 多选模式那颗开关。书架用的是浮动的 checklist 圆钮，这里跟着本卡
                    // 自己的工具栏走：它管的是**下面这批行的手感**，不是「更多」里那种
                    // 一次性动作。关掉「文件操作」总开关时它整块不出现（那时没有多选）。
                    if (_fileOpsEnabled) ...[
                      within,
                      toggle(
                        glyph: AppGlyphs.selectAll,
                        tooltip: _selectionModeOn ? '退出多选' : '多选',
                        on: _selectionModeOn,
                        onPressed: _toggleSelectionMode,
                      ),
                    ],
                  ],
                ),

                // —— 更多槽 ——
                // 只剩一颗 ⋮ 时槽就是一颗独立圆，这正是 FlClash 顶栏那颗的形态。
                between,
                FileManagerToolbarGroup(
                  children: [
                    popupTrigger(
                      tooltip: '更多',
                      icon: const GlyphIcon(AppGlyphs.more),
                      items: [
                        CommonPopupMenuItem(
                          label: '文件操作（复制 / 移动 / 删除）',
                          glyph: AppGlyphs.folderCopy,
                          checked: _fileOpsEnabled,
                          onPressed: () =>
                              _setFileOperationsEnabled(!_fileOpsEnabled),
                        ),
                        const CommonPopupMenuItem.divider(),
                        CommonPopupMenuItem(
                          label: '显示隐藏文件',
                          glyph: AppGlyphs.eye,
                          checked: snapshot.showHiddenFiles,
                          onPressed: () => _apply(
                            (id) => fileManagerSetShowHiddenFiles(
                              id: id,
                              enabled: !snapshot.showHiddenFiles,
                            ),
                          ),
                        ),
                        CommonPopupMenuItem(
                          label: '文件夹优先',
                          glyph: AppGlyphs.folder,
                          checked: snapshot.directoriesFirst,
                          onPressed: () => _apply(
                            (id) => fileManagerSetDirectoriesFirst(
                              id: id,
                              enabled: !snapshot.directoriesFirst,
                            ),
                          ),
                        ),
                        CommonPopupMenuItem(
                          label: '显示子文件名',
                          glyph: AppGlyphs.subtitles,
                          checked: snapshot.showChildNames,
                          onPressed: () => _apply(
                            (id) => fileManagerSetShowChildNames(
                              id: id,
                              enabled: !snapshot.showChildNames,
                            ),
                          ),
                        ),
                        CommonPopupMenuItem(
                          label:
                              snapshot.internalItemsMode ==
                                  FileManagerInternalItemsMode.single
                              ? '子文件：显示一个'
                              : '子文件：显示全部',
                          glyph: AppGlyphs.layers,
                          onPressed: () => _apply(
                            (id) => fileManagerSetInternalItemsMode(
                              id: id,
                              mode:
                                  snapshot.internalItemsMode ==
                                      FileManagerInternalItemsMode.single
                                  ? FileManagerInternalItemsMode.all
                                  : FileManagerInternalItemsMode.single,
                            ),
                          ),
                        ),
                        const CommonPopupMenuItem.divider(),
                        // 二级分类：两个六项单选组收进 subItems。全展开时这张菜单有
                        // 20 行，高度已经不像一个菜单；顶层只留「一次点到位」的开关。
                        // 父行标签必须带当前值 —— 子菜单行画的是箭头而不是勾选标记
                        // （`common_popup.dart` 的 `_buildRow` 里 subItems 优先），
                        // 收起之后父行就是唯一的状态出口。
                        CommonPopupMenuItem(
                          label: '穿透深度：${depthLabel(snapshot.maxDepth)}',
                          // 与工具栏那颗穿透开关同一颗：这一组调的就是它的深度。
                          glyph: AppGlyphs.passThrough,
                          subItems: [
                            for (final depth in [1, 2, 3, 5, 10, 32])
                              CommonPopupMenuItem(
                                label: depthLabel(depth),
                                glyph: AppGlyphs.passThrough,
                                checked: snapshot.maxDepth == depth,
                                onPressed: () => _apply(
                                  (id) => fileManagerSetMaxDepth(
                                    id: id,
                                    depth: depth,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        CommonPopupMenuItem(
                          label: filterLabel,
                          glyph: AppGlyphs.category,
                          subItems: [
                            for (final filter in filters.entries)
                              CommonPopupMenuItem(
                                label: filter.value.$1,
                                glyph: filter.value.$2,
                                checked: filter.key == snapshot.entryFilter,
                                onPressed: () => _apply(
                                  (id) => fileManagerSetEntryFilter(
                                    id: id,
                                    filter: filter.key,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                // 计数**不进槽**：槽是「一组可按的东西」，一段数字坐进去会读成
                // 一颗按不动的键。与书架那条工具栏同一个口径。
                between,
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
