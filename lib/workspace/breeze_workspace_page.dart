import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
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
    _stateSubscription = _cubit.stream.listen(_handleStateChanged);
    unawaited(_restoreLayout());
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
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
      final store = widget.store ?? WorkspaceLayoutFileStore(await _dataDir());
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

  /// 应用数据目录。
  ///
  /// 与 ObjectBox 的库文件放同一个父目录：布局快照是同一类「应用自己的状态」，
  /// 放在一起也让「备份 / 清理」只需要认一个地方。
  Future<Directory> _dataDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}zephyr');
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

  /// 退出工作台。
  ///
  /// 工作台是用 `Navigator.push` 上来的整页，**没有系统返回按钮** ——
  /// 顶栏一撤，它就是唯一的可见出口（键盘侧由 `Esc` 兜底，
  /// Android 侧另有系统返回键）。只在「工作台确实是栈顶」时才弹：
  /// 详情页之类压在上面时不该把用户弹走。
  void _exitWorkspace() {
    if (!mounted) return;
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
  WorkspaceTopChromeMode get _chromeMode => WorkspaceTopChromeMode.forTargetPlatform(
    defaultTargetPlatform,
  );

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
                const SingleActivator(LogicalKeyboardKey.escape): _exitWorkspace,
              },
              // 有焦点才收得到按键；泳道里的输入框拿到焦点时，
              // `CallbackShortcuts` 仍会在它们没消费时沿焦点树上冒到这里。
              child: Focus(
                autofocus: true,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: chromeMode == WorkspaceTopChromeMode.persistent
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
                          // 揭示形态：内容从窗口最顶端开始铺满。
                          // `SafeArea` 只为移动端兜底（桌面端 `MediaQuery.padding`
                          // 本来就是 0，这里不会内缩，所以不留空档）。
                          : SafeArea(child: content),
                    ),

                    // 揭示形态的顶栏：叠在内容上层，默认不可见（不占高度、不吃鼠标）。
                    if (chromeMode == WorkspaceTopChromeMode.reveal)
                      WorkspaceTopChromeReveal(
                        onExit: _exitWorkspace,
                        onResetLayout: _resetLayout,
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
