import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/reader/workspace_reader_bridge.dart';
import 'package:zephyr/workspace/widgets/edges/controlled_edge_shell.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

/// 工作台（neoview 式泳道 / 四边栏双呈现）。
///
/// 两条呈现共用同一份「现在在读哪一本」与同一份几何记账，**切模式不重开当前这一本**。
/// 顶栏只留「返回 + 标题 + 重置布局」这类工作台自己的事 ——
/// 模式切换属于 Reader 的 chrome，放在阅读器泳道栏头里（见 `SwimlaneWorkspace`）。
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
    // 工作台在场期间，上游页面推入的 ComicReadRoute 一律改派进阅读器泳道。
    WorkspaceReaderBridge.instance.attach(_openInLane);
  }

  @override
  void dispose() {
    WorkspaceReaderBridge.instance.detach(_openInLane);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocProvider<WorkspaceCubit>.value(
      value: _cubit,
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, state) {
          final isSwimlane = state.mode == WorkspaceMode.swimlane;

          return Scaffold(
            appBar: AppBar(
              titleSpacing: 8,
              title: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '工作台 (NeoView Workspace)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isSwimlane ? '多列泳道' : '沉浸四边栏',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: '重置布局（不影响当前正在读的这一本）',
                  icon: const Icon(Icons.restore_rounded),
                  onPressed: _cubit.resetLayout,
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isSwimlane
                  ? const SwimlaneWorkspace(key: ValueKey('swimlane'))
                  : const ControlledEdgeShell(key: ValueKey('edges')),
            ),
          );
        },
      ),
    );
  }
}
