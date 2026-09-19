import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';
import 'package:zephyr/workspace/service/workspace_layout_store.dart';
import 'package:zephyr/workspace/widgets/chrome/workspace_top_chrome.dart';
import 'package:zephyr/workspace/widgets/edges/controlled_edge_shell.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

/// 工作台（neoview 式泳道 / 四边栏双呈现）。
///
/// 两条呈现共用同一份「现在在读哪一本」与同一份几何记账，**切模式不重开当前这一本**。
///
/// **本页没有自己的 AppBar**：泳道模式下每条泳道自带栏头，再压一条工作台顶栏
/// 就是第二层顶栏（下面还叠着 macOS 窗口标题栏）。工作台级别的动作
/// （退出 / 重置布局 / 切模式）收在 `WorkspaceTopChrome` 里，两种形态：
///
/// - **桌面（有指针）**：悬停揭示 —— 平时不占高度，鼠标贴到窗口最顶端才淡入，
///   `Esc` 是退出工作台的键盘路径；
/// - **触摸屏（没有指针）**：常驻 —— 揭示式顶栏在那边**唤不出来**，
///   而工作台是 `Navigator.push` 上来的整页、没有系统返回按钮，
///   顶栏一撤就**没有可见出口**。所以那边顶栏占一行真实高度、内容从它下面开始。
///
/// **持久化也在这一层**：布局记账（模式、泳道顺序与宽度、折叠、激活面板与泳道、
/// 独占偏好、悬停/揭示的开关与延时、面板栏记账、面板与卡片记账）在启动时读盘、
/// 变化时去抖落盘。什么进快照、什么刻意不进，口径写在 `WorkspaceLayoutSnapshot`。
@RoutePage()
class BreezeWorkspacePage extends StatefulWidget {
  const BreezeWorkspacePage({
    super.key,
    this.store,
    this.debugLaneContentBuilder,
  });

  /// 布局快照的存取口。`null` = 用应用数据目录下的那个文件（正常启动路径）；
  /// 测试传内存实现，于是「重启回来的是不是同一套布局」可以在测试里验完。
  final WorkspaceLayoutStore? store;

  /// **判据用**的泳道内容替身，转手交给 `SwimlaneWorkspace`（理由与 [store] 同）。
  ///
  /// 这一页自己那点事 —— 启动读盘、变化去抖落盘、重置把磁盘上那份一起作废 ——
  /// 只有把这一页真的挂起来才验得到；而它的真内容（上游 `BookshelfPage` /
  /// `ComicReadPage`）要 ObjectBox、图源注册表、应用数据目录，判据里起不来。
  /// 应用路径**永不**传它。
  final Widget Function(String laneId)? debugLaneContentBuilder;

  /// 本页在导航栈里的名字。
  ///
  /// 它是用 `MaterialPageRoute` 直接推入的（不经 `router.gr.dart`），
  /// 所以名字要自己给 —— 工作台靠它判断「我是不是最上面那一页」。
  static const String routeName = 'BreezeWorkspacePage';

  @override
  State<BreezeWorkspacePage> createState() => _BreezeWorkspacePageState();
}

class _BreezeWorkspacePageState extends State<BreezeWorkspacePage> {
  late final WorkspaceCubit _cubit;

  /// 只取一次 tear-off 并留住它 —— 注销时必须传**同一个**回调对象。
  late final void Function(WorkspaceReaderTarget target) _openInLane;

  WorkspaceLayoutPersistence? _persistence;
  StreamSubscription<WorkspaceState>? _stateSubscription;

  /// 本页自己的路由对象（`didChangeDependencies` 里登记，`dispose` 里注销）。
  ///
  /// 根路由要靠它判断「现在最上面那一页是不是工作台」：面板里的一下「返回」只有
  /// 在那一刻才该由泳道接管（见 `WorkspaceNavigationBridge.handleBackInLane`）。
  ModalRoute<dynamic>? _workspaceRoute;

  /// 正在用读回来的快照替换状态：这一轮**不要再存一遍**（刚读完就写回去
  /// 是纯浪费，而且在慢盘上会与下一次真实改动抢同一个文件）。
  ///
  /// **旗子不能在 `restore()` 之后立刻撤**：`Cubit` 的状态流是
  /// `StreamController.broadcast()`（不是 `sync: true`），那次 `emit` 的通知
  /// 要等一个 microtask 才到监听者 —— 而那时旗子已经撤了，于是守卫等于没有，
  /// 症状是「每次启动都无端写一次盘」。所以把撤旗排到**那次投递之后**：
  /// `add` 先排队、这里后排队，顺序由 `scheduleMicrotask` 的 FIFO 保证。
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _cubit = WorkspaceCubit();
    _openInLane = _handleOpenInLane;
    // 工作台在场期间，上游页面推入的 ComicReadRoute 一律改派进阅读器泳道；
    // 其余推入由守卫交给「发起交互的那个面板」的局部导航栈
    // （登记随面板自己 attach / detach，见 `EmbeddedUpstreamPage`）。
    WorkspaceNavigationBridge.instance.attachReader(_openInLane);
    // 「设置 → 布局」在工作台在场时改的是**这份活的**状态（直接写盘会被下面的
    // 去抖落盘覆盖回去），登记与注销见 `WorkspaceLayoutBridge`。
    WorkspaceLayoutBridge.instance.attach(_cubit);
    _stateSubscription = _cubit.stream.listen(_handleStateChanged);
    unawaited(_restoreLayout());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 登记「我这一页」。重复登记同一个对象是幂等的。
    final route = ModalRoute.of(context);
    if (route != null) {
      _workspaceRoute = route;
      WorkspaceNavigationBridge.instance.attachWorkspaceRoute(route);
    }
  }

  @override
  void dispose() {
    final route = _workspaceRoute;
    if (route != null) {
      WorkspaceNavigationBridge.instance.detachWorkspaceRoute(route);
    }
    _stateSubscription?.cancel();
    WorkspaceLayoutBridge.instance.detach(_cubit);
    // 退出前把压着的改动写掉：拖完立刻关窗口这一下正好会落在去抖窗口里。
    unawaited(_persistence?.flush() ?? Future<void>.value());
    _persistence?.dispose();
    WorkspaceNavigationBridge.instance.detachReader(_openInLane);
    _cubit.close();
    super.dispose();
  }

  // ── 持久化 ─────────────────────────────────────────────────────────────

  Future<void> _restoreLayout() async {
    try {
      final store = widget.store ??
          WorkspaceLayoutFileStore(await workspaceLayoutDirectory());
      final persistence = WorkspaceLayoutPersistence(store: store);
      _persistence = persistence;
      final snapshot = await store.load();
      if (!mounted || snapshot == null) return;
      _restoring = true;
      _cubit.restore(snapshot);
      // 见 `_restoring` 的说明：必须等那次 `emit` 真的投递到监听者之后再撤旗。
      scheduleMicrotask(() => _restoring = false);
    } on Object {
      // 布局是**可重建**的东西：读盘失败不该挡住工作台打开。
      // （`WorkspaceLayoutFileStore` 内部已经吞掉了坏文件，这里兜的是
      //  「拿不到数据目录」这类环境问题。）
    }
  }

  void _handleStateChanged(WorkspaceState state) {
    if (_restoring) return;
    _persistence?.schedule(_cubit.snapshot);
  }

  /// 重置布局：状态回默认，**磁盘上那份也要作废**。
  ///
  /// 只重置状态的话，重启之后旧快照会把它覆盖回来 —— 用户看到的是
  /// 「重置了，但重启又变回去了」。
  ///
  /// 两件事的**顺序**也要紧，而且是反直觉的那一头：`resetLayout()` 那次
  /// `emit` 的通知是**异步**投递的，它会给去抖器排一次写盘；所以「作废磁盘」
  /// 必须排在**那之后**（`scheduleMicrotask`）。不然刚清掉的快照会被默认值
  /// 重新写回去 —— 重启结果虽然一样，但那已经不是「作废」，而是
  /// 「写了一份默认的」，白落一次盘。
  void _resetLayout() {
    _cubit.resetLayout();
    scheduleMicrotask(
      () => unawaited(_persistence?.reset() ?? Future<void>.value()),
    );
  }

  /// 守卫把一本漫画交给了泳道，工作台要负责**让用户看得见**。
  ///
  /// 「书架 → 详情页 → 开始阅读」这条路径上，详情页是压在工作台**上面**的一整页；
  /// 只把漫画塞进泳道而不管路由栈，用户会停在详情页上一脸茫然（书开在他身后）。
  /// 所以开完泳道后把工作台上面的页面弹掉 —— 一次 post-frame 之后再做，
  /// 让守卫那次被中止的导航先收尾。
  ///
  /// 用 `ModalRoute.isCurrent` 判断「我是不是最上面那一页」，而不是比路由名：
  /// 工作台是用 `Navigator.push` 直接推的，auto_route 自己的栈里根本没有它这一页。
  /// 这个判断同时挡住一个真会出事的写法 —— 万一工作台不在栈里，
  /// `popUntil` 会一路弹到根页面，把整个应用弹空。
  void _handleOpenInLane(WorkspaceReaderTarget target) {
    _cubit.openReader(target);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final workspaceRoute = ModalRoute.of(context);
      if (workspaceRoute == null || workspaceRoute.isCurrent) return;
      context.router.popUntil(
        (route) => route.settings.name == BreezeWorkspacePage.routeName,
      );
    });
  }

  /// 退出工作台（若阅读器处于全屏铺满状态则优先退出全屏）。
  ///
  /// 工作台是用 `Navigator.push` 上来的整页，**没有系统返回按钮** ——
  /// 顶栏一撤，它就是唯一的可见出口（键盘侧由 `Esc` 兜底，
  /// Android 侧另有系统返回键）。只在「工作台确实是栈顶」时才弹：
  /// 详情页之类压在上面时不该把用户弹走。
  void _exitWorkspace() {
    if (!mounted) return;
    if (_cubit.state.isReaderFullscreen) {
      _cubit.exitReaderFullscreen();
      return;
    }
    // 信息面板钉住时 `Esc` 先收面板（mimage 同款次序：面板在内容之上，
    // 第一下 `Esc` 该撤最上面那层，而不是连人带板退出工作台）。
    if (_cubit.state.infoPanelPinned) {
      _cubit.setInfoPanelPinned(false);
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).maybePop();
  }

  /// 顶栏形态 —— **触摸屏上揭示式顶栏等于没有出口**（`MouseRegion` 永远不触发，
  /// 而工作台是 `Navigator.push` 上来的整页、没有系统返回按钮、`Esc` 也用不上）。
  /// 所以那边保留**常驻**顶栏：占一行真实高度，内容从它下面开始。
  ///
  /// 判据是**平台有没有鼠标指针**（`defaultTargetPlatform`），不是「名字里带不带
  /// desk」—— 带触摸屏的 Windows 笔记本仍然有指针。用 `defaultTargetPlatform`
  /// 而不是 `dart:io` 的 `Platform` 还让判据能用 `debugDefaultTargetPlatformOverride`
  /// 把两种形态都跑一遍。
  WorkspaceTopChromeMode get _chromeMode =>
      WorkspaceTopChromeMode.forTargetPlatform(defaultTargetPlatform);

  /// **阅读器 context 优先**（用户 2026-09-19 定；对应 ADR-0015 的 context 优先级）。
  ///
  /// 阅读器的按键处理挂在它自己子树的 `Focus` 上，而打开阅读设置面板时
  /// `showModalBottomSheet` 会推入一条模态路由、把主焦点从阅读器子树拿走 ——
  /// 按键于是落到 `WidgetsApp` 默认的 `DirectionalFocusIntent`（方向焦点遍历）上，
  /// 表现为「左右键被设置面板吃掉、翻不动页」。
  ///
  /// 工作台这条 `Focus` 是那些模态路由的**祖先**：按键没被消费时会顺着焦点树冒到这里。
  /// 在这里把它转交给活跃阅读器，阅读器的键于是**不依赖焦点落在哪**。
  /// 又因为本 `Focus` 位于 `WidgetsApp` 默认快捷键的**后代**位置，
  /// 它会先于默认的 `DirectionalFocusIntent` 被咨询 —— 这正是能压过它的原因。
  ///
  /// 例外只有一条：**焦点在可编辑控件里时不抢** —— 方向键在输入框里是光标移动，
  /// 而文本编辑快捷键在焦点树上比这里更靠上（`DefaultTextEditingShortcuts`），
  /// 不豁免就会把光标移动吃掉。
  KeyEventResult _handleReaderFirstKeyEvent(
    KeyEvent event,
    WorkspaceState state,
  ) {
    final bridge = ReaderInputBridge.instance;
    if (!bridge.hasHandler) return KeyEventResult.ignored;
    // Dart 侧只做 adapter：报告「真实活跃的 context」，判定交给桥（将来是核心，ADR-0015）。
    bridge.setActiveContexts(_activeContextsFor(state));
    if (_isTextInputFocused()) return KeyEventResult.ignored;
    return bridge.dispatch(event);
  }

  /// **context adapter（Dart 侧）**：把工作台的真实状态翻译成 neoview 的 context 词汇。
  ///
  /// - 阅读器泳道在场（或尚无泳道被激活）→ `reader`；
  /// - 其它泳道被激活 → 那块内容按 `panel` 计，阅读器让位（不抢它的方向键）。
  ///
  /// **刻意不把「阅读器自己打开了设置面板」记成 `modal`**：那是阅读器自己的 UI，
  /// 不引入任何与 `reader` 竞争的绑定，于是左右键仍由 `reader` context 解析 ——
  /// 这正是它不该被设置面板抢走的原因；而真正的对话框（将来的 `modal`）若也绑了同一输入，
  /// 才会按 neoview 的优先级赢过 `reader`。
  Set<ReaderInputContext> _activeContextsFor(WorkspaceState state) {
    final activeLaneId = state.activeLaneId;
    if (activeLaneId == null || activeLaneId == LaneId.reader) {
      // 阅读器的当前页是一段视频时，`video`（优先级 150）与 `reader`（100）同时在场：
      // 绑了视频动作的输入归视频，没绑的照旧落回翻页 —— 这正是 neoview 的
      // context 叠加语义，也是那 24 条 `video.*` 动作唯一的可达路径。
      return ActiveVideoScope.instance.hasTarget
          ? const <ReaderInputContext>{
              ReaderInputContext.reader,
              ReaderInputContext.video,
            }
          : const <ReaderInputContext>{ReaderInputContext.reader};
    }
    return const <ReaderInputContext>{ReaderInputContext.panel};
  }

  /// 主焦点是否落在可编辑文本里（`TextField` / `TextFormField` 等）。
  bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WorkspaceCubit>.value(
      value: _cubit,
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, state) {
          final isSwimlane = state.mode == WorkspaceMode.swimlane;
          final chromeMode = _chromeMode;

          // 内容从顶上铺满：没有 appBar，也没有额外的一行内边距。
          final content = AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isSwimlane
                ? SwimlaneWorkspace(
                    key: const ValueKey('swimlane'),
                    debugLaneContentBuilder: widget.debugLaneContentBuilder,
                  )
                : const ControlledEdgeShell(key: ValueKey('edges')),
          );

          return Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    _exitWorkspace,
              },
              // 有焦点才收得到按键；泳道里的输入框拿到焦点时，
              // `CallbackShortcuts` 仍会在它们没消费时沿焦点树上冒到这里。
              child: Focus(
                autofocus: true,
                onKeyEvent: (_, event) =>
                    _handleReaderFirstKeyEvent(event, state),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: chromeMode == WorkspaceTopChromeMode.persistent &&
                              !state.isReaderFullscreen
                          // 常驻形态：顶栏在**正常流**里，内容从它下面开始 ——
                          // 这条路上不存在「顶栏盖住内容」那一档（那是揭示形态
                          // 才有的取舍）。内容因此不再自带顶部安全区：
                          // 顶栏已经连同状态栏一起把那一截吃掉了。
                          ? Column(
                              children: [
                                WorkspaceTopChrome(
                                  mode: chromeMode,
                                  onExit: _exitWorkspace,
                                  onResetLayout: _resetLayout,
                                ),
                                Expanded(
                                  child: SafeArea(top: false, child: content),
                                ),
                              ],
                            )
                          // 揭示形态或全屏：内容从窗口最顶端开始铺满。
                          // `SafeArea` 只为移动端兜底（桌面端 `MediaQuery.padding`
                          // 本来就是 0，这里不会内缩，所以不留空档）。
                          : SafeArea(top: !state.isReaderFullscreen, child: content),
                    ),

                    // 揭示形态的顶栏：叠在内容上层，默认不可见（不占高度、不吃鼠标）。
                    // 全屏铺满时隐藏顶栏，避免划过顶边时弹出遮挡。
                    if (chromeMode == WorkspaceTopChromeMode.reveal &&
                        !state.isReaderFullscreen)
                      WorkspaceTopChromeReveal(
                        onExit: _exitWorkspace,
                        onResetLayout: _resetLayout,
                        triggerZone: state.interaction.revealZones.top,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
