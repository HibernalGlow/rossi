import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

/// 工作台顶栏 —— **悬停揭示，不常驻**。
///
/// 泳道模式下每条泳道已经自带栏头（lane header owns collapse / reorder /
/// solo / width），工作台再压一条自己的顶栏就是**第二层顶栏**：白占一行高度，
/// 而且和 macOS 窗口标题栏叠在一起。所以这里改成 neoview 那样「内容顶到最上面」，
/// 顶栏只在鼠标贴到窗口最顶端时淡入。
///
/// 但工作台级别的两个动作不能因此消失：
/// - **退出工作台**：工作台是 `Navigator.push` 上来的整页，没有系统返回按钮，
///   去掉顶栏后它就是唯一入口（另外还有 `Esc`，见 `BreezeWorkspacePage`）；
/// - **重置布局**：四边栏模式没有泳道栏头，只有这里有地方放它。
///
/// 揭示规则（两段 hover，互不打架）：
/// - 触发带 = 窗口最顶端 [triggerHeight] 像素，**垫在顶栏下层**。
///   于是顶栏不可见时鼠标能穿到它、可见时被顶栏接住 —— 顶栏自己也是
///   [MouseRegion]，鼠标从触发带滑到顶栏上时 `_barHover` 立刻接管，
///   不会出现「滑下去就收起来」的抖动。
/// - 鼠标离开顶栏（往下超过 [barHeight] 或移出窗口）才收起。
class WorkspaceTopChrome extends StatefulWidget {
  const WorkspaceTopChrome({
    super.key,
    required this.onExit,
    required this.onResetLayout,
  });

  /// 退出工作台（回到进入前的页面）。
  final VoidCallback onExit;

  /// 重置布局。
  ///
  /// 由宿主传入而不是直接调 `cubit.resetLayout`：重置不只是「状态回默认」，
  /// 还要把**磁盘上的那份快照**一并作废 —— 否则重启之后它会被旧快照覆盖回来，
  /// 用户看到的是「重置了，但重启又变回去了」。而磁盘那一层在工作台页面上，
  /// 不在这个顶栏里。
  final VoidCallback onResetLayout;

  /// 顶栏高度 —— 与泳道栏头同高，揭示时正好接管那一行。
  static const double barHeight = 46;

  /// 触发带高度。**必须矮**：顶栏一出现就盖住泳道栏头，
  /// 触发带太高会让「操作泳道栏头」时顶栏反复闪现。
  static const double triggerHeight = 10;

  @override
  State<WorkspaceTopChrome> createState() => _WorkspaceTopChromeState();
}

class _WorkspaceTopChromeState extends State<WorkspaceTopChrome> {
  bool _triggerHover = false;
  bool _barHover = false;

  bool get _visible => _triggerHover || _barHover;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: WorkspaceTopChrome.barHeight,
        child: Stack(
          children: [
            // 触发带（下层）：顶栏不可见时鼠标穿到这里召唤它。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: WorkspaceTopChrome.triggerHeight,
              child: MouseRegion(
                onEnter: (_) => setState(() => _triggerHover = true),
                onExit: (_) => setState(() => _triggerHover = false),
                child: const SizedBox.expand(),
              ),
            ),

            // 顶栏本体（上层）：不可见时不吃鼠标事件。
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_visible,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _barHover = true),
                  onExit: (_) => setState(() => _barHover = false),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    opacity: _visible ? 1 : 0,
                    child: _buildBar(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final cubit = context.read<WorkspaceCubit>();
        final isSwimlane = state.mode == WorkspaceMode.swimlane;
        final target = state.readerTarget;

        return Container(
          height: WorkspaceTopChrome.barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // 不透明：顶栏揭示时正好叠在泳道栏头那一行上，
            // 半透明会让下面那行字透出来变成鬼影。
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                tooltip: '退出工作台（Esc 亦可）',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onExit,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.dashboard_customize_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '工作台',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isSwimlane ? '多列泳道' : '沉浸四边栏',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),

              // 当前在读哪一本 —— 泳道模式有栏头显示书名，四边栏模式只剩这里。
              if (target != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '· ${target.displayTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              if (target != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '关闭当前漫画（回到空态）',
                  visualDensity: VisualDensity.compact,
                  onPressed: cubit.closeReader,
                ),
              IconButton(
                icon: Icon(
                  isSwimlane
                      ? Icons.fullscreen_rounded
                      : Icons.view_column_rounded,
                  size: 18,
                ),
                tooltip: isSwimlane ? '切换为沉浸四边栏' : '切换为多列泳道',
                visualDensity: VisualDensity.compact,
                onPressed: cubit.toggleMode,
              ),
              IconButton(
                icon: const Icon(Icons.restore_rounded, size: 18),
                tooltip: '重置布局（不影响当前正在读的这一本）',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onResetLayout,
              ),
            ],
          ),
        );
      },
    );
  }
}
