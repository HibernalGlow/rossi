import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/gpu/gpu_present_page.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/service/lifecycle/foreground_task/foreground_task_service.dart';
import 'package:zephyr/service/lifecycle/notification_service.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/service/open_intent/open_intent_consumer.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/util/manage_cache.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/memory/memory_overlay_widget.dart';
import 'package:zephyr/widgets/image_sleep.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/event/event.dart';
import 'package:zephyr/widgets/navigation/navigation_customization_dialog.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/navigation/navigation_layout.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/widgets/navigation/navigation_entries.dart';
import 'package:zephyr/widgets/navigation/navigation_sidebar.dart';
import 'package:zephyr/workspace/model/workspace_presence.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';
import 'package:zephyr/icons/icons.dart';

@RoutePage()
class NavigationBar extends StatefulWidget {
  const NavigationBar({super.key});

  @override
  State<NavigationBar> createState() => _NavigationBarState();
}

class _NavigationBarState extends State<NavigationBar> {
  // _controller 控制底部导航栏 / 底栏插槽与页面切换
  late PersistentTabController _controller;

  /// 当前页的**身份**，不是下标。
  ///
  /// 侧栏与底部 Dock 各有自己的条目清单（用户在「自定义导航」里能增删排序），
  /// 同一页在两边下标不同 —— 记下标会在切布局或改清单时指到别的页上。
  ///
  /// 它**永远落在一个页面上**：清单里还有「动作」（工作台 / 打开本地漫画 /
  /// GPU 上屏 / 搜索），那些点了推路由、不换页，不能当「当前页」。
  /// `null` = 还没定：`build` 会把它落到清单里第一条页面（开屏页见
  /// `_entryForWelcomeIndex`）。
  NavigationEntryId? _currentPageId;

  /// 当前这一支布局的条目清单（身份，按显示顺序）。由 `build` 每帧刷新，
  /// 供 `_handleExitOnBack` 这类离 build 很远的回调把身份换算成下标。
  List<NavigationEntryId> _activePageIds = const [];

  /// 去过哪些页。
  ///
  /// `IndexedStack` 会把所有页一次建起来（改造前手机那支是懒建的），而开屏
  /// 只该建书架那一页 —— 于是没去过的页一律摆个空盒子。按**身份**记而不是
  /// 按下标：清单一改（用户在自定义里增删排序），下标会指到别的页上。
  final Set<NavigationEntryId> _visitedPages = <NavigationEntryId>{};
  final debouncer = Debouncer(milliseconds: 100);
  DateTime? _lastLoginNavigateAt;
  String? _lastLoginPluginId;
  late HideOnScrollSettings hideOnScrollSettings;

  /// 系统右键菜单递来的路径（见 `lib/service/open_intent/`）。
  StreamSubscription<List<String>>? _openIntentSubscription;

  static bool _notificationsInitialized = false; // ← 使用静态变量，跨实例共享
  bool _isInitializingNotifications = false;
  static bool _followUpdateChecked = false;

  /// 「启动直接进工作台」**每个进程只做一次**。
  ///
  /// 这一层万一被重建（换语言、换主题都会把整棵树重建），不该再弹一次工作台 ——
  /// 那时用户多半已经主动从里面退出来过了，再弹就成了关不掉的东西。
  static bool _workspaceAutoOpenHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      checkUpdate(context);
      _autoSync();
      manageCacheSize(context);
      DownloadQueueManager.instance.resetStuckTasks();
      DownloadQueueManager.instance.watchTasks(
        startupResumeDelay: const Duration(minutes: 1),
      );
      if (Platform.isAndroid) {
        await ForegroundTaskService.instance.syncOnAppStart();
      }
    });
    final globalSetting = objectbox.userSettingBox.get(1)!.globalSetting;
    // 开屏页存的仍然是**下标**（`welcomePageNum`，可能带着云端同步来的旧值），
    // 这里按**出厂清单**解成身份。解成身份而不是直接当下标用，是为了让
    // 「用户改过导航清单」之后，「启动落在第 2 页」不会突然指到别的页上 ——
    // 下标只在某一支布局的清单里才有意义（见 `_pageIdForWelcomeIndex`）。
    _currentPageId = _entryForWelcomeIndex(
      globalSetting.welcomePageNum,
      globalSetting.oldPageRollbackEnabled,
    );
    _controller = PersistentTabController(initialIndex: 0);
    // 启动落点。开关关着、或本机没有工作台入口时它逐字不动
    // （见 `resolveStartupLanding`）。
    _maybeOpenWorkspaceOnStart(globalSetting.startWithWorkspace);
    ForegroundTaskService.instance.init();

    initializeNotificationsOnce();
    _scheduleFollowUpdateCheck(context);

    // 每隔 5 分钟执行一次
    const duration = Duration(minutes: 5);
    Timer.periodic(duration, (Timer timer) async {
      await _autoSync();
    });

    // 用来手动触发同步
    eventBus.on<NoticeSync>().listen((event) {
      _autoSync(force: event.force);
    });

    eventBus.on<NeedLogin>().listen((event) {
      _goToLoginPage(event.from, message: event.message);
    });

    _openIntentSubscription = bindOpenIntents(context);
  }

  @override
  void dispose() {
    _openIntentSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 打开工作台（泳道 / 四边栏）。两个入口共用：四边栏布局 trailing 上的按钮，
  /// 以及「启动时直接打开工作台」。
  ///
  /// 走路由表（`context.pushRoute`）而不是 `Navigator.push`：工作台里摊的是上游
  /// 原版页面，它们会按 auto_route 的常规写法查自己那条路由，手工推的一页给不出
  /// 那个上下文（注册理由见 `AppRouter.routes`）。
  void _openWorkspace() {
    context.pushRoute(BreezeWorkspaceRoute());
  }

  /// 启动后是否**直接**进工作台（判定见 `resolveStartupLanding`）。
  ///
  /// 排到首帧之后：工作台是整页、`initState` 期间这一层
  /// 还没进 Navigator；而「有没有入口」要看 `MediaQuery`（`isTablet`）——
  /// 两者都要求先有帧。
  void _maybeOpenWorkspaceOnStart(bool startWithWorkspace) {
    if (_workspaceAutoOpenHandled) return;
    _workspaceAutoOpenHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final landing = resolveStartupLanding(
        startWithWorkspace: startWithWorkspace,
        workspaceEntryAvailable: workspaceAvailableOnDevice(context),
      );
      if (landing != StartupLanding.workspace) return;
      _openWorkspace();
    });
  }

  @override
  Widget build(BuildContext context) {
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
    final legacy = globalSettingState.oldPageRollbackEnabled;
    final allowed = availableNavigationEntries(legacy);
    final mainFallback = defaultNavigationEntries(legacy);
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

  /// 把「当前页身份」落到这一支的清单上，返回它在清单里的下标。
  ///
  /// 身份**不是**从下标反推的：清单被改过（某条被隐藏、被拖到别处）之后，
  /// 原来的下标指向的是另一条，而身份仍然指得回同一条。
  ///
  /// 返回的下标**一定落在一个页面上**：清单里可能有动作（工作台 / 搜索…），
  /// 它们点了不换页、不能当选中项 —— 否则「按下的那一格」与「画面上那一页」
  /// 会错开。清单里一条页面都不剩的极端情况本该由 `decodeNavigationEntryIds`
  /// 挡住（那样会退回出厂清单），这里再用 `orElse` 兜一层，不留空指针。
  int _syncSelection(List<NavigationEntryId> entries) {
    final current = _currentPageId;
    final resolved =
        (current != null && current.isPage && entries.contains(current))
        ? current
        : entries.firstWhere((id) => id.isPage, orElse: () => entries.first);
    _currentPageId = resolved;
    _activePageIds = entries;
    return entries.indexOf(resolved);
  }

  /// 切到某一条（侧栏、Dock、旧布局底栏三个入口共用）。
  ///
  /// 动作条目走的是「推一条路由」而不是换页：它不改 `_currentPageId`，
  /// 底栏的 lens 因此留在原地 —— 与改造前那几颗固定在侧栏底部的按钮同一行为。
  void _handleToEntry(NavigationEntryId id) {
    if (id.isAction) {
      _invokeAction(id);
      return;
    }
    if (_currentPageId == id) return;
    setState(() => _currentPageId = id);
  }

  /// 动作条目点下去干什么。
  ///
  /// 「推哪条路由」留在这一层（只有这里牵得进 `router.gr.dart`），
  /// `navigation_entries.dart` 因此还是纯的、判据里挂得起来。
  void _invokeAction(NavigationEntryId id) {
    switch (id) {
      case NavigationEntryId.workspace:
        _openWorkspace();
      case NavigationEntryId.openLocalComic:
        unawaited(_openLocalComic());
      case NavigationEntryId.gpuPresent:
        _openGpuPresent();
      case NavigationEntryId.search:
        _openSearch();
      case NavigationEntryId.customizeNavigation:
        unawaited(_openNavigationCustomization());
      // 页面不是动作 —— `isAction` 已经挡在上面，这几个 case 只是让 switch
      // 穷尽；加新动作时忘了在这儿派发，编译器不会响，所以宁可穷举。
      case NavigationEntryId.bookshelf:
      case NavigationEntryId.discover:
      case NavigationEntryId.more:
      case NavigationEntryId.oldHome:
      case NavigationEntryId.oldRank:
        break;
    }
  }

  /// 旧布局（`NavigationRail` / `PersistentTabView`）只认得页面。
  ///
  /// 那两支没有「点一下推路由、也不高亮」这种格子，所以被用户摆进主区的
  /// 动作在这一支里会让位 —— 它们由 [build] 里的 `_legacyRailActions` 补到
  /// 栏底那一排去，不会因为换个壳就消失。
  List<NavigationEntryId> _pageEntries(List<NavigationEntryId> entries) => [
    for (final id in entries)
      if (id.isPage) id,
  ];

  /// 旧侧栏（`NavigationRail`）栏底那一排动作。
  ///
  /// 取**全部**动作而不是用户那段底部清单，理由见 [build] 里调用点的注释
  /// （「关掉开关 = 回到改造前那一屏」，且主区里的动作在旧布局里没有位置）。
  /// 唯一的例外是「搜索」—— 那一支在栏底单独挂了它一颗按钮（改造前就是
  /// 这样），全量传进去会画两遍。
  List<NavigationEntryId> _legacyRailActions(List<NavigationEntryId> allowed) =>
      [
        for (final id in allowed)
          if (id.isAction && id != NavigationEntryId.search) id,
      ];

  /// 当前页在 [pages] 里的下标（旧布局用 —— 那边的下标空间是「只有页面」）。
  int _indexInPages(List<NavigationEntryId> pages) {
    final current = _currentPageId;
    final index = current == null ? -1 : pages.indexOf(current);
    return index < 0 ? 0 : index;
  }

  /// 页面栈。
  ///
  /// 用 `IndexedStack` 而不是每帧重建：切走再切回来时，页面自己的滚动位置与
  /// 内部状态都还在（与改造前 `PersistentTabView` 的 `stateManagement` 同效）。
  /// 未去过的页摆空盒子，理由见 `_visitedPages`。
  ///
  /// 下标按**条目**对齐（`IndexedStack` 的 index 就是清单下标），动作条目那几格
  /// 拿到的永远是 `SizedBox.shrink()`（`build()` 的约定）且从不是选中项。
  Widget _buildPageSwitcher({
    required List<NavigationEntryId> entries,
    required int selectedIndex,
  }) {
    _visitedPages
      ..removeWhere((id) => !entries.contains(id))
      ..add(entries[selectedIndex]);
    // 工作台在场 ⇒ 首页壳整个被盖住：把页面栈声明成「休眠」，
    // 里面的图片组件（ImageSleep）据此让出解码位图。scope 只包这一块 ——
    // 工作台内嵌的页面在别的路由子树里，拿不到它，不会跟着变灰。
    return ListenableBuilder(
      listenable: WorkspacePresence.present,
      child: IndexedStack(
        index: selectedIndex,
        sizing: StackFit.expand,
        children: [
          for (final id in entries)
            KeyedSubtree(
              key: ValueKey(id),
              child: _visitedPages.contains(id)
                  ? id.build()
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      builder: (context, pageStack) => WorkspaceImageSleepScope(
        asleep: WorkspacePresence.present.value,
        child: pageStack!,
      ),
    );
  }

  // ── 新版：Arc 侧栏（桌面 / 平板） ──────────────────────────────────────────

  /// 桌面 / 平板这一支：左侧栏（FlClash 的 Arc 化改造）+ 右侧内容。
  ///
  /// 侧栏自己处理展开态（够宽就地撑开、不够宽走浮层），也自己带底部动作区，
  /// 所以这里只负责把两列拼起来。
  ///
  /// [entries] 是**主区**（页面与动作都能放，动作点了推路由、不高亮）；
  /// [bottomEntries] 是**底部快捷区**（只放动作）。两段互斥，见 `build`。
  ///
  /// 那颗写死的「自定义导航」按钮退役了：它现在是一条普通动作
  /// （[NavigationEntryId.customizeNavigation]，默认就摆在底部快捷区里），
  /// 于是既能换位置也能隐藏。`onCustomize` 传 `null` 之后侧栏就不会再画它；
  /// 那个参数留着是为了不离上游太远（见 `navigation_sidebar.dart` 的边界表）。
  Widget _buildSidebarLayout({
    required List<NavigationEntryId> entries,
    required int selectedIndex,
    required bool expanded,
    required List<NavigationEntryId> bottomEntries,
  }) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Row(
        children: [
          NavigationSidebar(
            destinations: [
              for (final id in entries)
                SidebarDestination(glyph: id.glyph, label: id.label),
            ],
            selectedIndex: selectedIndex,
            expanded: expanded,
            onSelected: (index) => _handleToEntry(entries[index]),
            onToggle: _toggleSidebarExpanded,
            // 本仓桌面端用的是**自制标题栏**（`desktop_shell_frame.dart`），
            // 侧栏不会与 macOS 红绿灯重叠 —— 传 `Size.zero` 即可。留着这个
            // 参数是为了不离上游太远（那里侧栏贴着系统标题栏）。
            windowControls: Size.zero,
            actions: [
              for (final id in bottomEntries)
                SidebarAction(
                  glyph: id.glyph,
                  label: id.label,
                  onTap: () => _invokeAction(id),
                ),
            ],
            onCustomize: null,
            customizeLabel: null,
          ),
          Expanded(
            child: _buildPageSwitcher(
              entries: entries,
              selectedIndex: selectedIndex,
            ),
          ),
        ],
      ),
    );
  }

  // ── 新版：悬浮 Dock（窄屏 / 手机） ─────────────────────────────────────────

  /// 移动端这一支：底部悬浮胶囊 Dock + 内容。
  ///
  /// **内容从胶囊底下穿过去**（`extendBody: true`）：页面铺到屏幕底部，
  /// 胶囊四周因此是透的，而不是一块与页面同色的空带。留位不用各页自己算 ——
  /// 框架会给 body 的 `MediaQuery.padding.bottom` 设成底栏的**实际高度**
  /// （`_BodyBuilder`，`flutter/lib/src/material/scaffold.dart`），
  /// `SafeArea` 与 `padding: null` 的滚动视图（`MorePage` 是前者，
  /// 书架 / 发现是后者）都会照它让位。
  ///
  /// 与上游 FlClash 的差别在这里收窄了：上游把 dock 用 `Positioned` 浮在
  /// 每一页之上、由各页自己按 `NavigationDock.insetOf` 垫脚；本仓把这件
  /// 事交给 Scaffold 的 `extendBody`，得到同一观感而不必逐页改滚动内边距。
  ///
  /// [bottomEntries] 是**底部快捷区** —— 它在这一支里横排成胶囊尾部的一只
  /// 分组槽（与侧栏那一支同一份清单，只换排布方向）。那几条全隐藏时槽整个消失。
  Widget _buildDockLayout({
    required List<NavigationEntryId> entries,
    required int selectedIndex,
    required bool backPressExitEnabled,
    required List<NavigationEntryId> bottomEntries,
  }) {
    final body = _buildPageSwitcher(
      entries: entries,
      selectedIndex: selectedIndex,
    );
    return Scaffold(
      backgroundColor: context.backgroundColor,
      resizeToAvoidBottomInset: false,
      extendBody: true,
      bottomNavigationBar: NavigationDock(
        destinations: [
          for (final id in entries)
            NavigationDockDestination(glyph: id.glyph, label: id.label),
        ],
        selectedIndex: selectedIndex,
        onSelected: (index) => _handleToEntry(entries[index]),
        // 底部快捷区在 Dock 这一支里**横排**成一只分组槽。
        //
        // 与侧栏那一支是**同一份清单、同一只槽**，只换 `ActionGroup.axis`
        // （侧栏竖排、这里横排）。原先这里是「一颗 FAB 弹底部弹层」：清单要再点
        // 一次才看得见，弹层里还是竖排的列表 —— 同一条清单在两支里长得完全不像
        // 一回事。清单为空时槽整个不出现（而不是留一颗点了没反应的键）。
        trailing: bottomEntries.isEmpty
            ? null
            : ActionGroup(
                children: [
                  for (final (index, id) in bottomEntries.indexed) ...[
                    if (index > 0)
                      const SizedBox(width: ActionGroupMetrics.gapWithinGroup),
                    ActionIconButton(
                      glyph: id.glyph,
                      tooltip: id.label,
                      onPressed: () => _invokeAction(id),
                    ),
                  ],
                ],
              ),
      ),
      // 这一支没有 `PersistentTabView` 兜返回键了，自己接一下。
      // 开关关着时不拦（默认：交给系统退到上一页 / 退出应用）；开着时
      // 「先回第一条」由 `_handleExitOnBack` 判。
      body: backPressExitEnabled
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                unawaited(_handleExitOnBack(null));
              },
              child: body,
            )
          : body,
    );
  }

  // ── 旧布局（开关关掉时的退路） ─────────────────────────────────────────────

  /// 改造前的桌面 / 平板布局（`NavigationRail`），关掉侧栏开关时出现。
  ///
  /// 底部动作区与搜索按钮与改造前逐字一致 —— 「关掉」的意思应当是回到
  /// 改造前那一屏，而不是「侧栏没了、那几颗按钮也没了」。所以这里接的是
  /// **全部**动作 [actions]，而不是「没被摆进清单的那些」。
  ///
  /// 清单里的动作条目在这一支里不出现（`NavigationRail` 没有那种格子），
  /// 页面清单交给 `_pageEntries` 收窄。
  Widget _buildLegacyRailLayout({
    required List<NavigationEntryId> entries,
    required List<NavigationEntryId> actions,
  }) {
    final pages = _pageEntries(entries);
    final selectedIndex = _indexInPages(pages);
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _handleToEntry(pages[index]),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: context.backgroundColor,
                  destinations: [
                    for (final id in pages)
                      NavigationRailDestination(
                        icon: GlyphIcon(id.legacyIcon),
                        selectedIcon: GlyphIcon(id.legacySelectedIcon),
                        label: Text(id.label),
                      ),
                  ],
                  // v0.1 判据 A 的观察窗口。放在 `trailing`（默认 `trailingAtBottom:
                  // false`，渲染在最后一个 destination 正下方）而**不是**第四个
                  // destination：它不是 tab —— 加进去会连带改手机端底部导航的信息架构，
                  // 且会被常驻，把本地会话一直挂在那儿。这里是「动作」不是「视图」，
                  // 所以走 push。
                  trailing: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final id in actions)
                          IconButton(
                            icon: GlyphIcon(id.legacyIcon),
                            tooltip: id.tooltip,
                            onPressed: () => _invokeAction(id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IconButton(
                  icon: const GlyphIcon(AppGlyphs.search),
                  tooltip: t.common.search,
                  onPressed: _openSearch,
                ),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            // 这里传的是 `pages` 而不是 `entries`：`selectedIndex` 由
            // `_indexInPages` 算出来，是**页面空间**里的下标 —— 传全员清单
            // 会让"当前页"整体前移（动作插在中间时指到另一条上）。
            child: _buildPageSwitcher(
              entries: pages,
              selectedIndex: selectedIndex,
            ),
          ),
        ],
      ),
    );
  }

  /// 改造前的移动端布局（`PersistentTabView` 自带底栏），关掉 Dock 开关时出现。
  ///
  /// `PersistentTabView` 只认页面（它那条底栏没有「点了不换页」的格子），
  /// 且构造断言要求 2..6 条 —— 页面全集最多 5 条，收窄之后一定在范围内。
  Widget _buildLegacyTabView({
    required List<NavigationEntryId> entries,
    required bool backPressExitEnabled,
  }) {
    final pages = _pageEntries(entries);
    final selectedIndex = _indexInPages(pages);
    // 底栏的高亮是包自己的状态（`_controller.index`），而这里的真相是身份 ——
    // 把下标推回去，用户改过清单之后底栏才不会指着上一页。
    if (_controller.index != selectedIndex) {
      _controller.index = selectedIndex;
    }
    final activeColor = context.theme.colorScheme.primary;
    final inactiveColor = context.textColor;
    return PersistentTabView(
      context,
      controller: _controller,
      screens: [for (final id in pages) id.build()],
      items: [
        for (final id in pages)
          PersistentBottomNavBarItem(
            icon: GlyphIcon(id.legacyIcon),
            title: id.label,
            activeColorPrimary: activeColor,
            inactiveColorPrimary: inactiveColor,
          ),
      ],
      backgroundColor: context.backgroundColor,
      // 由组件自身的 PopScope 接收返回事件。此前把 PopScope 包在组件外层，
      // 容易被每个 tab 的内部 Navigator 先消费，导致开关看起来没有效果。
      handleAndroidBackButtonPress: !backPressExitEnabled,
      onWillPop: backPressExitEnabled ? _handleExitOnBack : null,
      resizeToAvoidBottomInset: false,
      hideNavigationBarWhenKeyboardAppears: false,
      stateManagement: true,
      navBarStyle: NavBarStyle.style3,
      onItemSelected: (index) => _handleToEntry(pages[index]),
    );
  }

  /// 返回键：先回第一条页面，已经在第一条就交给系统。
  Future<bool> _handleExitOnBack(BuildContext? _) async {
    // 子页面仍由各自的 Navigator 正常返回；只有当前页已无子页面时才会走到这里。
    // 取**第一条页面**而不是第一条条目 —— 清单第一位可能是动作（点了推路由，
    // 那样按返回键会莫名其妙弹出一个页面）。
    final pages = _pageEntries(_activePageIds);
    final first = pages.isEmpty ? null : pages.first;
    if (first != null && _currentPageId != first) {
      _handleToEntry(first);
      return false;
    }

    await SystemNavigator.pop();
    // 已由系统关闭 Activity，不再让组件继续 pop 根路由。
    return false;
  }

  // ── 侧栏底部动作区 / Dock 尾部溢出菜单（同一份清单） ───────────────────────

  /// 打开本地漫画。像素从 Rust 侧直接进合成链（见 `lib/gpu/`）。
  Future<void> _openLocalComic() async {
    try {
      final selected = await showLocalFileTreeSheet(context: context);
      if (selected == null || selected.isEmpty || !mounted) return;
      context.pushRoute(
        ComicReadRoute(
          comicId: selected,
          order: 0,
          from: 'local',
          epsNumber: 1,
          type: ComicEntryType.normal,
          comicInfo: selected,
          stringSelectCubit: StringSelectCubit(),
        ),
      );
    } catch (e, st) {
      debugPrint('打开本地漫画出错: $e\n$st');
    }
  }

  /// GPU 上屏（D3D12 共享纹理）：像素从 Rust 侧直接进合成链，
  /// 不再经 `ui.decodeImageFromPixels`。
  void _openGpuPresent() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const GpuPresentPage()));

  void _openSearch() => context.pushRoute(
    SearchRoute(searchState: SearchStates.initial(), aggregateMode: true),
  );

  /// 侧栏展开 / 收起。
  ///
  /// 存进**全局设置**而不是页面 State：换语言、换主题都会把整棵树重建，
  /// 住 State 的开关会跟着回默认（与阅读版式开关同一条口径）。
  void _toggleSidebarExpanded() {
    context.read<GlobalSettingCubit>().updateNavigationSetting(
      (current) => current.copyWith(sidebarExpanded: !current.sidebarExpanded),
    );
  }

  /// 打开「自定义导航栏」：两支布局各一张页签，每张里两段可拖拽清单
  /// （主区 / 底部快捷区）。
  ///
  /// 每次编辑立刻落进全局设置（弹窗自己持草稿、不点「保存」），所以关掉弹窗
  /// 之后侧栏 / Dock 已经跟着变了 —— 与 FlClash 那份 notifier 同一时机。
  ///
  /// 清单解析（存的是 id 字符串；主区那一段空 = 用出厂，底部那一段 `null` =
  /// 没设置过）交给 [showCustomNavigationDialogFor]，与「设置 → 外观」那一处
  /// 同一个入口。
  Future<void> _openNavigationCustomization() {
    final cubit = context.read<GlobalSettingCubit>();
    final state = cubit.state;
    return showCustomNavigationDialogFor(
      context,
      storedDesktopPageIds: state.navigationSetting.desktopPageIds,
      storedDesktopActionIds: state.navigationSetting.desktopActionIds,
      storedMobilePageIds: state.navigationSetting.mobilePageIds,
      storedMobileActionIds: state.navigationSetting.mobileActionIds,
      oldPageRollbackEnabled: state.oldPageRollbackEnabled,
      onChanged: (desktop, mobile) {
        cubit.updateNavigationSetting(
          (current) => current.copyWith(
            desktopPageIds: encodeNavigationEntryIds(desktop.main),
            mobilePageIds: encodeNavigationEntryIds(mobile.main),
            desktopActionIds: encodeNavigationEntryIds(desktop.actions),
            mobileActionIds: encodeNavigationEntryIds(mobile.actions),
          ),
        );
      },
    );
  }

  /// 开屏页。
  ///
  /// `welcomePageNum` 存的仍是**下标**（可能带着云端同步来的旧值），这里按
  /// **出厂清单**解成身份。用出厂清单而不是用户自己那份：那个数字是改造前
  /// 记下来的「第几个标签」，当时的清单就是出厂清单 —— 拿去套用户改过的清单
  /// 会指到别的页上。默认值取 `-1` 的是「工作台」哨兵，不是这里的取值。
  ///
  /// 出厂清单里全是页面，所以这里解出来的身份一定是个页面。
  NavigationEntryId _entryForWelcomeIndex(int rawIndex, bool legacy) {
    final defaults = defaultNavigationEntries(legacy);
    return defaults[rawIndex.clamp(0, defaults.length - 1)];
  }

  Future<void> _autoSync({bool force = false}) async {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final globalState = globalSettingCubit.state;

    if (!force && globalState.syncSetting.autoSync == false) {
      return;
    }

    if (!isSyncServiceConfigured(globalState)) {
      return;
    }

    // 这两条腿过去一条有门禁（成功）、一条裸奔（失败）：同步配错或断网时，
    // 失败提示每 5 分钟敲一次且永不停 —— 用户手上那个「同步通知」开关根本管不到它。
    // 现在两条都登记成事项，由逐事项开关与 10 分钟合并窗口一起管（见 ADR-0020）。
    // `force`（同步设置页里点出来的立即同步）按操作反馈直通。
    try {
      await autoSync(
        globalState,
        globalSettingCubit: globalSettingCubit,
        comicFollowCubit: context.read<ComicFollowCubit>(),
      );
      notifyAmbient(
        NotifyTopic.syncAutoSuccess,
        force ? t.navigation.syncSuccess : t.navigation.autoSyncSuccess,
        type: ToastType.success,
        userInitiated: force,
      );
    } catch (e, stackTrace) {
      logger.e(e.toString(), stackTrace: stackTrace);
      notifyAmbient(
        NotifyTopic.syncAutoFailure,
        t.navigation.syncFailedMessage(error: normalizeSearchErrorMessage(e)),
        title: force ? t.navigation.syncFailed : t.navigation.autoSyncFailed,
        type: ToastType.error,
        userInitiated: force,
      );
    }
  }

  void _goToLoginPage(String from, {String? message}) {
    try {
      final pluginId = from.trim();
      if (pluginId.isEmpty) {
        logger.w('Skip login navigation: empty plugin id');
        return;
      }

      final navigator = Navigator.maybeOf(context);
      if (navigator == null) {
        logger.w('Navigator not available');
        return;
      }

      debouncer.run(() {
        if (!mounted) {
          return;
        }

        final now = DateTime.now();
        final recentDuplicate =
            _lastLoginPluginId == pluginId &&
            _lastLoginNavigateAt != null &&
            now.difference(_lastLoginNavigateAt!).inMilliseconds < 1500;
        if (recentDuplicate) {
          return;
        }

        final hasLoginRoute = navigator.widget.pages.any(
          (route) => (route.name ?? '').contains('LoginRoute'),
        );
        if (hasLoginRoute) {
          return;
        }
        _lastLoginNavigateAt = now;
        _lastLoginPluginId = pluginId;
        unawaited(_confirmAndGoToLogin(pluginId, message: message));
      });
    } catch (e, stackTrace) {
      logger.e('Failed to navigate to login', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _confirmAndGoToLogin(String pluginId, {String? message}) async {
    if (!mounted) {
      return;
    }
    final goLogin = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (dialogContext) => PopupPanel(
        title: Text(t.navigation.needLoginTitle),
        content: Text(message ?? t.navigation.loginExpired),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.navigation.goLogin),
          ),
        ],
      ),
    );
    if (goLogin != true || !mounted) {
      return;
    }
    try {
      final navigator = Navigator.maybeOf(context);
      if (navigator == null) {
        return;
      }
      final hasLoginRoute = navigator.widget.pages.any(
        (route) => (route.name ?? '').contains('LoginRoute'),
      );
      if (hasLoginRoute) {
        return;
      }
      context.navigateTo(LoginRoute(from: pluginId));
    } catch (e, stackTrace) {
      logger.e('Failed to navigate to login', error: e, stackTrace: stackTrace);
    }
  }

  void _scheduleFollowUpdateCheck(BuildContext context) {
    if (_followUpdateChecked) {
      return;
    }
    _followUpdateChecked = true;

    Future.delayed(const Duration(minutes: 1), () async {
      try {
        if (!context.mounted) {
          return;
        }
        await context.read<ComicFollowCubit>().checkUpdates();
      } catch (e, stackTrace) {
        logger.e('启动后追更检测失败', error: e, stackTrace: stackTrace);
      }
    });
  }

  Future<void> initializeNotificationsOnce() async {
    // 应用级别检查
    if (_notificationsInitialized) {
      logger.d('Notifications already initialized globally');
      return;
    }

    // 实例级别检查
    if (_isInitializingNotifications) {
      logger.w('Notification initialization already in progress');
      return;
    }

    try {
      _isInitializingNotifications = true;

      // 延迟执行，避免与其他初始化冲突
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      await initializeNotifications();

      _notificationsInitialized = true;
      logger.d('Notifications initialized successfully');
    } catch (e, stackTrace) {
      logger.e(
        'Failed to initialize notifications',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isInitializingNotifications = false;
    }
  }
}
