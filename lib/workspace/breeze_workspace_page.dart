import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
import 'package:zephyr/workspace/widgets/chrome/workspace_top_chrome.dart';
import 'package:zephyr/workspace/widgets/edges/controlled_edge_shell.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

/// 工作台（neoview 式泳道 / 四边栏双呈现）。
///
/// 两条呈现共用同一份「现在在读哪一本」与同一份几何记账，**切模式不重开当前这一本**。
///
/// **本页没有自己的 AppBar**：泳道模式下每条泳道自带栏头，再压一条工作台顶栏
/// 就是第二层顶栏（下面还叠着 macOS 窗口标题栏）。工作台级别的动作
/// （退出 / 重置布局 / 切模式）收在**悬停揭示**的 `WorkspaceTopChrome` 里，
/// 平时不占高度，鼠标贴到窗口最顶端才淡入；`Esc` 是退出工作台的键盘路径。
@RoutePage()
class BreezeWorkspacePage extends StatefulWidget {
  const BreezeWorkspacePage({super.key});

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

  @override
  void initState() {
    super.initState();
    _cubit = WorkspaceCubit();
    _openInLane = _handleOpenInLane;
    // 工作台在场期间，上游页面推入的 ComicReadRoute 一律改派进阅读器泳道；
    // 其余推入由守卫交给「发起交互的那个面板」的局部导航栈
    // （登记随面板自己 attach / detach，见 `EmbeddedUpstreamPage`）。
    WorkspaceNavigationBridge.instance.attachReader(_openInLane);
  }

  @override
  void dispose() {
    WorkspaceNavigationBridge.instance.detachReader(_openInLane);
    _cubit.close();
    super.dispose();
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
  /// 顶栏一撤，它就是唯一的可见出口（键盘侧由 `Esc` 兜底）。
  /// 只在「工作台确实是栈顶」时才弹：详情页之类压在上面时不该把用户弹走。
  void _exitWorkspace() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WorkspaceCubit>.value(
      value: _cubit,
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, state) {
          final isSwimlane = state.mode == WorkspaceMode.swimlane;

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
                    // 内容从顶上铺满：没有 appBar，也没有额外的一行内边距。
                    // SafeArea 只为移动端「最低适配」兜底 —— 桌面端标题栏与内容区
                    // 本来就分离，`MediaQuery.padding` 是 0，这里不会内缩。
                    Positioned.fill(
                      child: SafeArea(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: isSwimlane
                              ? const SwimlaneWorkspace(
                                  key: ValueKey('swimlane'),
                                )
                              : const ControlledEdgeShell(
                                  key: ValueKey('edges'),
                                ),
                        ),
                      ),
                    ),

                    // 工作台顶栏：悬停揭示，默认不可见（不占高度、不吃鼠标）。
                    WorkspaceTopChrome(onExit: _exitWorkspace),
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
