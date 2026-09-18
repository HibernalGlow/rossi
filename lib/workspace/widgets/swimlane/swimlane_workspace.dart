import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';
import 'package:zephyr/workspace/widgets/lane_resizer.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_host.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';

/// 水平泳道工作区：**一条平面条带**，左面板 / 阅读器 / 右面板依次排列。
///
/// 三条不变量（来自 neoview 的 swimlane 契约）：
/// 1. 所有泳道共处**一条水平条带**，显出一条泳道靠**移动条带**，泳道之间**永不重叠、
///    永不浮在别人上面**；
/// 2. 面板泳道宽度是**绝对像素**、不按窗口宽夹取；阅读器泳道宽度是**视口比例**；
/// 3. 有富余宽度时富余全部给**阅读器**（中央弹性填充），不够时整条带横向滚动。
class SwimlaneWorkspace extends StatelessWidget {
  const SwimlaneWorkspace({super.key});

  /// 条带四周的外边距。
  ///
  /// **它是「可用宽度」与「视口宽度」的差**，两者不能混用 ——
  /// 算富余 / 判断要不要滚动时必须用**扣掉两条边距之后**的宽度。
  /// 差这 16px 的后果不是"挤一挤"，而是 Row 溢出、Flutter 把右侧 10%
  /// （`debug_overflow_indicator.dart` 里的 `_indicatorFraction`）涂成
  /// 黄黑斜纹，看起来像界面上多了一条莫名其妙的黄色装饰。
  ///
  /// 取值直接引用 [WorkspaceStripMetrics.defaultPadding]：判据
  /// （`dart run test/workspace/strip_metrics_check.dart`）加载不了 widget，
  /// 只有**同一个常量**才能保证两边算的是同一件事。
  static const double _stripPadding = WorkspaceStripMetrics.defaultPadding;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) => LayoutBuilder(
        builder: (context, constraints) {
          // 两个宽度各有各的用处，别合并：
          // - `viewportWidth`：阅读器泳道的**比例**要乘它（乘可用宽会把比例算歪）；
          // - `availableWidth`：条带实际能摆多宽 = 富余 / 滚动的判断基准。
          final viewportWidth = constraints.maxWidth;
          final availableWidth = math.max(
            0.0,
            viewportWidth - _stripPadding * 2,
          );
          final soloLaneId = state.layout.soloLaneId;
          return Padding(
            padding: const EdgeInsets.all(_stripPadding),
            child: soloLaneId == null
                ? _buildStrip(context, state, viewportWidth, availableWidth)
                : _buildSolo(context, state, availableWidth, soloLaneId),
          );
        },
      ),
    );
  }

  // ── 常规多泳道 ─────────────────────────────────────────────────────────

  Widget _buildStrip(
    BuildContext context,
    WorkspaceState state,
    double viewportWidth,
    double availableWidth,
  ) {
    final cubit = context.read<WorkspaceCubit>();

    // 宽度分配**全部**在 `WorkspaceStripMetrics` 里算（纯 Dart、可被
    // `dart run test/workspace/strip_metrics_check.dart` 断言）。
    // 这里只负责把它翻译成 widget —— 之前这套算术在本文件里另写了一份，
    // 于是「只在界面上悄悄坏掉」而判据看不见。
    final metrics = WorkspaceStripMetrics.resolve(
      layout: state.layout,
      viewportWidth: viewportWidth,
      availableWidth: availableWidth,
      resizerWidth: LaneResizer.width,
    );

    final children = <Widget>[];
    for (final slot in metrics.slots) {
      final laneId = slot.laneId;
      if (laneId == null) {
        final before = slot.beforeLaneId!;
        final after = slot.afterLaneId!;
        children.add(
          LaneResizer(
            onDragDelta: (delta) =>
                cubit.dragLanePair(before, after, delta, viewportWidth),
            onDoubleTapReset: () => cubit.resetLanePair(before, after),
          ),
        );
        continue;
      }

      children.add(
        SizedBox(
          width: slot.width,
          // 栏头里的「宽度」徽标要显示**实际**宽度：富余分给阅读器之后，
          // 它比 `LaneConfig.resolveWidth()` 算出来的标称值大（差的就是那份富余）。
          child: _buildLane(
            context,
            state,
            laneId,
            viewportWidth,
            resolvedWidth: slot.width,
          ),
        ),
      );
    }

    final strip = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    if (!metrics.needsScroll) return strip;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: metrics.contentWidth, child: strip),
    );
  }

  // ── Solo 独占 ─────────────────────────────────────────────────────────

  Widget _buildSolo(
    BuildContext context,
    WorkspaceState state,
    double availableWidth,
    String soloLaneId,
  ) {
    final children = <Widget>[];
    for (final laneId in state.layout.laneOrder) {
      if (laneId == soloLaneId) {
        children.add(
          Expanded(
            child: _buildLane(
              context,
              state,
              laneId,
              availableWidth,
              isSolo: true,
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _buildCollapsedRail(context, laneId),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _buildCollapsedRail(BuildContext context, String laneId) {
    final cubit = context.read<WorkspaceCubit>();
    final config = context.select(
      (WorkspaceCubit c) =>
          c.state.layout.lanes[laneId] ??
          LaneConfig(width: 380, title: laneId),
    );
    return SwimlaneColumn(
      laneId: laneId,
      config: config.copyWith(collapsed: true),
      resolvedWidth: WorkspaceLayoutConfig.collapsedLaneWidth,
      isSolo: false,
      onToggleCollapse: () => cubit.toggleLaneCollapsed(laneId),
      onToggleSolo: () => cubit.toggleSoloLane(laneId),
    );
  }

  // ── 单条泳道 ───────────────────────────────────────────────────────────

  Widget _buildLane(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    double viewportWidth, {
    bool isSolo = false,
    double? resolvedWidth,
  }) {
    final cubit = context.read<WorkspaceCubit>();
    final config =
        state.layout.lanes[laneId] ?? LaneConfig(width: 380, title: laneId);
    // 条带那边已经算好了**实际摆出来的宽度**（含分给阅读器的富余），直接用；
    // 没传（Solo 的独占泳道）时才退回标称值 —— 那时候宽度由 `Expanded` 定。
    final laneWidth = resolvedWidth ?? config.resolveWidth(viewportWidth);

    final column = SwimlaneColumn(
      laneId: laneId,
      config: config,
      resolvedWidth: laneWidth,
      isSolo: isSolo,
      titleOverride: laneId == LaneId.reader
          ? state.readerTarget?.displayTitle
          : null,
      headerActions: laneId == LaneId.reader
          ? _readerLaneActions(context, state, cubit)
          : const <Widget>[],
      // 面板切换工具栏停在**顶栏**里（左右两条面板泳道各一条），
      // 阅读器泳道没有面板可切，于是不挂。
      panelTabs: switch (laneId) {
        LaneId.left => const PanelTabStrip(side: WorkspacePanelSide.left),
        LaneId.right => const PanelTabStrip(side: WorkspacePanelSide.right),
        _ => null,
      },
      onToggleCollapse: () => cubit.toggleLaneCollapsed(laneId),
      onToggleSolo: () => cubit.toggleSoloLane(laneId),
      onResetWidth: () => cubit.resetLaneWidth(laneId),
      child: _buildLaneContent(context, state, laneId, cubit),
    );

    // 栏头图标就是**泳道重排**的把手：按住它拖到另一条泳道上，两条互换位置。
    // （neoview：lane header owns collapse, reorder, focus, width。）
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != laneId,
      onAcceptWithDetails: (details) => cubit.reorderLane(details.data, laneId),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: column,
        );
      },
    );
  }

  /// 阅读器泳道栏头的附加控件。
  ///
  /// 模式切换**放在这里而不是工作台顶栏**：neoview 的契约是泳道模式下
  /// Reader 的动作跟着 Reader 泳道走，而不是挂在一个全局工具条上。
  List<Widget> _readerLaneActions(
    BuildContext context,
    WorkspaceState state,
    WorkspaceCubit cubit,
  ) {
    final isSwimlane = state.mode == WorkspaceMode.swimlane;
    return [
      IconButton(
        icon: Icon(
          isSwimlane ? Icons.fullscreen_rounded : Icons.view_column_rounded,
          size: 18,
        ),
        tooltip: isSwimlane ? '切换为沉浸四边栏 (Edges)' : '切换为多列泳道 (Swimlane)',
        visualDensity: VisualDensity.compact,
        onPressed: () => cubit.toggleMode(),
      ),
      if (state.readerTarget != null)
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: '关闭当前漫画 (回到空态)',
          visualDensity: VisualDensity.compact,
          onPressed: () => cubit.closeReader(),
        ),
    ];
  }

  Widget _buildLaneContent(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    WorkspaceCubit cubit,
  ) {
    switch (laneId) {
      // 左 / 右：**面板泳道** —— 图标轨切换面板，面板里是卡片
      // （左：书架卡片的「书架」面板 + 完整复用上游 BookshelfPage 的面板；
      //   右：完整复用上游 DiscoverPage / MorePage 的面板 + 图源与本地卡片）。
      case LaneId.left:
        return const LanePanelHost(side: WorkspacePanelSide.left);

      // 中：**阅读器** —— 上游原版 ComicReadPage（空态则为画板）
      case LaneId.reader:
        return WorkspaceReaderHost(target: state.readerTarget);

      case LaneId.right:
        return const LanePanelHost(side: WorkspacePanelSide.right);

      default:
        return const SizedBox.shrink();
    }
  }
}
