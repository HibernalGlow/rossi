part of 'navigation_bar.dart';

extension _NavigationBarLayout on _NavigationBarState {
  Widget _buildNavigationLayout() {
    final context = this.context;
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    // 开关仅在 Android 展示；同时限制实际行为，避免同步设置后影响其他平台。
    final backPressExitEnabled =
        Platform.isAndroid && globalSettingState.backPressExitEnabled;

    final nav = globalSettingState.navigationSetting;
    // 「这台设备有没有侧栏这种东西」= 本机有没有工作台入口，与
    // `hasWorkspaceEntry` 同源（那颗按钮就挂在侧栏这一支的底部动作区里）。
    // 它回答的是**平台能力**，不是「这一屏有多宽」—— 后者在下一行。
    final sidebarCapable = hasWorkspaceEntry(context);
    final layout = resolveNavigationLayout(
      sidebarCapable: sidebarCapable,
      width: MediaQuery.sizeOf(context).width,
      autoSwitchOnNarrow: nav.autoNarrowMobileLayout,
      narrowWidth: nav.narrowNavigationWidth,
    );

    // 两支各自一份**主区**清单 + 一份**底部快捷区**清单（用户在「自定义导航」
    // 里增删排序过）。主区空清单 = 用出厂清单（见 `decodeNavigationEntryIds`）；
    // 底部那一段 `null` = 没设置过用出厂、`[]` = 用户全隐藏了
    // （见 `decodeNavigationActionIds`）。
    final allowed = availableNavigationEntries(
      showPluginHome: globalSettingState.showPluginHome,
      showPluginCloudFavorite: globalSettingState.showPluginCloudFavorite,
    );
    final mainFallback = defaultNavigationEntries();
    final actionFallback = defaultNavigationActions(allowed);
    final desktopEntries = resolveNavigationEntryIds(
      stored: nav.desktopPageIds,
      allowed: allowed,
      fallback: mainFallback,
    );
    final mobileEntries = resolveNavigationEntryIds(
      stored: nav.mobilePageIds,
      allowed: allowed,
      fallback: mainFallback,
    );
    final desktopActions = resolveNavigationActionIds(
      stored: nav.desktopActionIds,
      allowed: allowed,
      fallback: actionFallback,
    );
    final mobileActions = resolveNavigationActionIds(
      stored: nav.mobileActionIds,
      allowed: allowed,
      fallback: actionFallback,
    );

    final useSidebar = layout == NavigationLayout.sidebar;
    final entries = useSidebar ? desktopEntries : mobileEntries;
    final selectedIndex = _syncSelection(entries);
    // 底部快捷区 = 这一支的底部清单，**减掉主区里已经有的那几条** ——
    // 一个入口只出现在一处。用户把底部那几条全隐藏时它是空的，底部整块
    // （侧栏那排按钮 / Dock 尾部那颗按钮）随之消失。
    final bottomEntries = [
      for (final id in (useSidebar ? desktopActions : mobileActions))
        if (!entries.contains(id)) id,
    ];

    return MemoryOverlayWidget(
      enabled: globalSettingState.enableMemoryDebug,
      updateInterval: Duration(seconds: 1),
      child: Builder(
        builder: (context) {
          // 开关关掉就等于回到改造前：侧栏关掉走 `NavigationRail`，
          // Dock 关掉走 `PersistentTabView` 自带的那条底栏。四条分支共用
          // 同一份 `entries` 与同一套「当前页身份」记账，于是「当前在哪一页」
          // 不会因为换个壳而分叉。
          if (useSidebar && nav.sidebarEnabled) {
            return _buildSidebarLayout(
              entries: entries,
              selectedIndex: selectedIndex,
              expanded: nav.sidebarExpanded,
              bottomEntries: bottomEntries,
            );
          }
          if (!useSidebar && nav.dockEnabled) {
            return _buildDockLayout(
              entries: entries,
              selectedIndex: selectedIndex,
              backPressExitEnabled: backPressExitEnabled,
              bottomEntries: bottomEntries,
              longPressCustomize: nav.dockLongPressCustomize,
              longPressDuration: Duration(
                milliseconds: nav.dockLongPressMilliseconds,
              ),
            );
          }
          if (sidebarCapable) {
            return _buildLegacyRailLayout(
              entries: entries,
              // 旧侧栏的底部动作区读的是**全部动作**，不是用户那段清单：
              // 它是「关掉开关 = 回到改造前那一屏」的退路，而改造前那一屏就
              // 是「栏底一排动作」。更要紧的是主区里已经有的动作在旧布局里
              // **没有位置**（`NavigationRail` 只画页面），只读底部段会让那些
              // 动作整个消失。搜索剔掉 —— 这一支在栏底单独挂了它一颗按钮，
              // 全量传进去会把「搜索」画两遍。
              actions: _legacyRailActions(allowed),
            );
          }
          return _buildLegacyTabView(
            entries: entries,
            backPressExitEnabled: backPressExitEnabled,
          );
        },
      ),
    );
  }
}
