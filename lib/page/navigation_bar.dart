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
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/util/manage_cache.dart';
import 'package:zephyr/gpu/local_file_tree_sheet.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/memory/memory_overlay_widget.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/event/event.dart';
import 'package:zephyr/page/bookshelf/bookshelf.dart';
import 'package:zephyr/page/discover/view/discover_page.dart';
import 'package:zephyr/page/more/view/more.dart';
import 'package:zephyr/page/old_page/old_home/old_home_page.dart';
import 'package:zephyr/page/old_page/old_ranking/old_ranking_page.dart';
import 'package:zephyr/workspace/breeze_workspace_page.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';

@RoutePage()
class NavigationBar extends StatefulWidget {
  const NavigationBar({super.key});

  @override
  State<NavigationBar> createState() => _NavigationBarState();
}

class _NavigationBarState extends State<NavigationBar> {
  // _controller 用于控制手机底部导航栏和页面切换
  late PersistentTabController _controller;
  // _selectedIndex 用于控制平板侧边导航栏和页面切换
  int _selectedIndex = 0;
  final debouncer = Debouncer(milliseconds: 100);
  DateTime? _lastLoginNavigateAt;
  String? _lastLoginPluginId;
  DateTime? _lastToastShownAt;
  (ToastType, String?, String, Duration?)? _lastToastEvent;
  late HideOnScrollSettings hideOnScrollSettings;

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
    final configuredIndex = globalSetting.welcomePageNum;
    final initialIndex = _normalizeWelcomePageIndex(
      configuredIndex,
      _buildPageList(globalSetting.oldPageRollbackEnabled).length,
    );
    _controller = PersistentTabController(initialIndex: initialIndex);
    _selectedIndex = initialIndex;
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
      _goToLoginPage(
        event.from,
        loginScheme: event.scheme,
        loginData: event.data,
        message: event.message,
      );
    });

    eventBus.on<ToastEvent>().listen((event) {
      _showToast(event);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 打开工作台（泳道 / 四边栏）。两个入口共用：四边栏布局 trailing 上的按钮，
  /// 以及「启动时直接打开工作台」。
  void _openWorkspace() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 带上名字：工作台靠它判断「我是不是最上面那一页」，
        // 详情页 →「开始阅读」时才知道要不要把自己弹回前台
        // （见 BreezeWorkspacePage.routeName）。
        settings: const RouteSettings(name: BreezeWorkspacePage.routeName),
        builder: (_) => const BreezeWorkspacePage(),
      ),
    );
  }

  /// 启动后是否**直接**进工作台（判定见 `resolveStartupLanding`）。
  ///
  /// 排到首帧之后：工作台是 `Navigator.push` 上来的整页，`initState` 期间这一层
  /// 还没进 Navigator；而「有没有入口」要看 `MediaQuery`（`isTablet`）——
  /// 两者都要求先有帧。
  void _maybeOpenWorkspaceOnStart(bool startWithWorkspace) {
    if (_workspaceAutoOpenHandled) return;
    _workspaceAutoOpenHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final landing = resolveStartupLanding(
        startWithWorkspace: startWithWorkspace,
        workspaceEntryAvailable: hasWorkspaceEntry(context),
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
    final pageList = _buildPageList(globalSettingState.oldPageRollbackEnabled);
    final navBarItems = _navBarItems(globalSettingState.oldPageRollbackEnabled);
    final navRailDestinations = _navRailDestinations(
      globalSettingState.oldPageRollbackEnabled,
    );
    final normalizedIndex = _normalizeWelcomePageIndex(
      _selectedIndex,
      pageList.length,
    );
    if (normalizedIndex != _selectedIndex) {
      _selectedIndex = normalizedIndex;
      _controller.index = normalizedIndex;
    }
    return MemoryOverlayWidget(
      enabled: globalSettingState.enableMemoryDebug,
      updateInterval: Duration(seconds: 1),
      child: Builder(
        builder: (context) {
          // 走不走四边栏布局，与「本机有没有工作台入口」是同一条判据 ——
          // 那个按钮就挂在这一支的 trailing 上（见 `hasWorkspaceEntry`）。
          if (hasWorkspaceEntry(context)) {
            return _buildTabletLayout(
              pageList: pageList,
              navRailDestinations: navRailDestinations,
            );
          } else {
            return _buildMobileLayout(
              pageList: pageList,
              navBarItems: navBarItems,
              backPressExitEnabled: backPressExitEnabled,
            );
          }
        },
      ),
    );
  }

  Widget _buildMobileLayout({
    required List<Widget> pageList,
    required List<PersistentBottomNavBarItem> navBarItems,
    required bool backPressExitEnabled,
  }) {
    return PersistentTabView(
      context,
      controller: _controller,
      screens: pageList,
      items: navBarItems,
      backgroundColor: context.backgroundColor,
      // 由组件自身的 PopScope 接收返回事件。此前把 PopScope 包在组件外层，
      // 容易被每个 tab 的内部 Navigator 先消费，导致开关看起来没有效果。
      handleAndroidBackButtonPress: !backPressExitEnabled,
      onWillPop: backPressExitEnabled ? _handleExitOnBack : null,
      resizeToAvoidBottomInset: false,
      hideNavigationBarWhenKeyboardAppears: false,
      stateManagement: true,
      navBarStyle: NavBarStyle.style3,
      onItemSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  Future<bool> _handleExitOnBack(BuildContext? _) async {
    // 子页面仍由 PersistentTabView 的内部 Navigator 正常返回；只有当前 tab
    // 已无子页面时才会调用这里。
    if (_controller.index != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      _controller.jumpToTab(0);
      return false;
    }

    await SystemNavigator.pop();
    // 已由系统关闭 Activity，不再让组件继续 pop 根路由。
    return false;
  }

  // 平板布局 (使用 NavigationRail)
  Widget _buildTabletLayout({
    required List<Widget> pageList,
    required List<NavigationRailDestination> navRailDestinations,
  }) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                      _controller.index = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: context.backgroundColor,
                  destinations: navRailDestinations,
                  // v0.1 判据 A 的观察窗口。放在 `trailing`（默认 `trailingAtBottom:
                  // false`，渲染在最后一个 destination 正下方）而**不是**第四个
                  // destination：它不是 tab —— 加进去会连带改手机端底部导航的信息架构，
                  // 且会被 `IndexedStack` 常驻，把本地会话一直挂在那儿。这里是「动作」
                  // 不是「视图」，所以走 push。
                  trailing: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.folder_open_outlined),
                          tooltip: '打开本地漫画（Breeze 原版阅读器 + GPU 零拷贝）',
                          onPressed: () async {
                            try {
                              final selected = await showLocalFileTreeSheet(
                                context: context,
                              );
                              if (selected != null &&
                                  selected.isNotEmpty &&
                                  mounted) {
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
                              }
                            } catch (e, st) {
                              debugPrint('打开本地漫画出错: $e\n$st');
                            }
                          },
                        ),
                        // GPU 上屏（D3D12 共享纹理）：像素从 Rust 侧直接进合成链，
                        // 不再经 `ui.decodeImageFromPixels`。同上，不补 i18n 词条。
                        IconButton(
                          icon: const Icon(Icons.memory_outlined),
                          tooltip: 'GPU 上屏（D3D12 共享纹理）',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const GpuPresentPage(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.dashboard_customize_outlined),
                          tooltip: '泳道/四边栏工作台 (NeoView Workspace)',
                          onPressed: _openWorkspace,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IconButton(
                  icon: Icon(Icons.search),
                  tooltip: t.common.search,
                  onPressed: () {
                    context.pushRoute(
                      SearchRoute(
                        searchState: SearchStates.initial(),
                        aggregateMode: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: pageList),
          ),
        ],
      ),
    );
  }

  // 底部导航栏的配置项
  List<PersistentBottomNavBarItem> _navBarItems(bool oldPageRollbackEnabled) {
    final activeColor = context.theme.colorScheme.primary;
    final inactiveColor = context.textColor;

    final items = <PersistentBottomNavBarItem>[
      PersistentBottomNavBarItem(
        icon: Icon(Icons.menu_book_sharp),
        title: t.navigation.bookshelf,
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.explore_outlined),
        title: t.navigation.discover,
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.apps_outlined),
        title: t.navigation.more,
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
    ];
    if (!oldPageRollbackEnabled) {
      return items;
    }

    return [
      PersistentBottomNavBarItem(
        icon: Icon(Icons.home_outlined),
        title: t.navigation.home,
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.leaderboard_outlined),
        title: t.navigation.rank,
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      ...items,
    ];
  }

  int _normalizeWelcomePageIndex(int rawIndex, int pageCount) {
    if (pageCount <= 0) {
      return 0;
    }
    return rawIndex.clamp(0, pageCount - 1);
  }

  // 为平板侧边导航栏生成 NavigationRailDestination
  List<NavigationRailDestination> _navRailDestinations(
    bool oldPageRollbackEnabled,
  ) {
    final destinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book_sharp),
        label: Text(t.navigation.bookshelf),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore),
        label: Text(t.navigation.discover),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.apps_outlined),
        selectedIcon: Icon(Icons.apps),
        label: Text(t.navigation.more),
      ),
    ];
    if (!oldPageRollbackEnabled) {
      return destinations;
    }
    return [
      NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: Text(t.navigation.home),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.leaderboard_outlined),
        selectedIcon: Icon(Icons.leaderboard),
        label: Text(t.navigation.rank),
      ),
      ...destinations,
    ];
  }

  List<Widget> _buildPageList(bool oldPageRollbackEnabled) {
    final pages = <Widget>[
      const BookshelfPage(),
      const DiscoverPage(),
      const MorePage(),
    ];
    if (!oldPageRollbackEnabled) {
      return pages;
    }
    return [const OldHomePage(), const OldRankingPage(), ...pages];
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

    try {
      await autoSync(
        globalState,
        globalSettingCubit: globalSettingCubit,
        comicFollowCubit: context.read<ComicFollowCubit>(),
      );
      if (globalState.syncSetting.syncNotify) {
        showSuccessToast(
          force ? t.navigation.syncSuccess : t.navigation.autoSyncSuccess,
        );
      }
    } catch (e, stackTrace) {
      logger.e(e.toString(), stackTrace: stackTrace);
      showErrorToast(
        t.navigation.syncFailedMessage(error: normalizeSearchErrorMessage(e)),
        title: force ? t.navigation.syncFailed : t.navigation.autoSyncFailed,
      );
    }
  }

  void _goToLoginPage(
    String from, {
    Map<String, dynamic>? loginScheme,
    Map<String, dynamic>? loginData,
    String? message,
  }) {
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
        if (!hasLoginRoute) {
          showErrorToast(message ?? t.navigation.loginExpired);

          _lastLoginNavigateAt = now;
          _lastLoginPluginId = pluginId;
          context.navigateTo(
            LoginRoute(
              from: pluginId,
              loginScheme: loginScheme,
              loginData: loginData,
            ),
          );
        }
      });
    } catch (e, stackTrace) {
      logger.e('Failed to navigate to login', error: e, stackTrace: stackTrace);
    }
  }

  void _showToast(ToastEvent event) {
    final now = DateTime.now();
    final toastEvent = (event.type, event.title, event.message, event.duration);
    if (_lastToastEvent == toastEvent &&
        _lastToastShownAt != null &&
        now.difference(_lastToastShownAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastToastEvent = toastEvent;
    _lastToastShownAt = now;

    // 一律走 toast：以前「正文 ≥ 30 字就退化成 commonDialog」，
    // 结果下载完成这种长文件名会弹一个「成功 + 取消/确定」的对话框拦住用户。
    // 现在长文本由提示条自己换行（见 ToastCard），不再有这条分支。
    ToastOverlayController.instance.show(
      context,
      type: event.type,
      title: event.title,
      message: event.message,
      duration: event.duration,
    );
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
