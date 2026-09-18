import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
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

  static const double _resizerWidth = 10.0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) => LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final soloLaneId = state.layout.soloLaneId;
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: soloLaneId == null
                ? _buildStrip(context, state, viewportWidth)
                : _buildSolo(context, state, viewportWidth, soloLaneId),
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
  ) {
    final cubit = context.read<WorkspaceCubit>();
    final layout = state.layout;

    // 1. 各泳道先按自己的计量单位算宽度
    final widths = <String, double>{};
    var total = 0.0;
    for (final laneId in layout.laneOrder) {
      final lane = layout.lanes[laneId];
      if (lane == null) continue;
      final width = lane.collapsed
          ? WorkspaceLayoutConfig.collapsedLaneWidth
          : lane.resolveWidth(viewportWidth);
      widths[laneId] = width;
      total += width;
    }

    final visible = layout.laneOrder
        .where((id) => widths.containsKey(id) && !layout.lanes[id]!.collapsed)
        .toList();
    total += _resizerWidth * math.max(0, visible.length - 1);

    // 2. 富余宽度给阅读器；不够就保持各自存储宽度、整条带横向滚动
    final spare = viewportWidth - total;
    if (spare > 0 && visible.contains(LaneId.reader)) {
      widths[LaneId.reader] = widths[LaneId.reader]! + spare;
      total = viewportWidth;
    }
    final needsScroll = total > viewportWidth + 0.5;

    // 3. 按顺序拼装：泳道 + 相邻泳道之间的分隔条
    final children = <Widget>[];
    String? previousLaneId;
    for (final laneId in layout.laneOrder) {
      final lane = layout.lanes[laneId];
      if (lane == null || !widths.containsKey(laneId)) continue;

      final previous = previousLaneId;
      if (previous != null &&
          !lane.collapsed &&
          !layout.lanes[previous]!.collapsed) {
        children.add(
          LaneResizer(
            onDragDelta: (delta) =>
                cubit.dragLanePair(previous, laneId, delta, viewportWidth),
            onDoubleTapReset: () => cubit.resetLanePair(previous, laneId),
          ),
        );
      }

      children.add(
        SizedBox(
          width: widths[laneId],
          child: _buildLane(context, state, laneId, viewportWidth),
        ),
      );
      previousLaneId = laneId;
    }

    final strip = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    if (!needsScroll) return strip;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: total, child: strip),
    );
  }

  // ── Solo 独占 ─────────────────────────────────────────────────────────

  Widget _buildSolo(
    BuildContext context,
    WorkspaceState state,
    double viewportWidth,
    String soloLaneId,
  ) {
    final children = <Widget>[];
    for (final laneId in state.layout.laneOrder) {
      if (laneId == soloLaneId) {
        children.add(
          Expanded(
            child: _buildLane(context, state, laneId, viewportWidth, isSolo: true),
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
  }) {
    final cubit = context.read<WorkspaceCubit>();
    final config =
        state.layout.lanes[laneId] ?? LaneConfig(width: 380, title: laneId);
    final resolvedWidth = isSolo
        ? viewportWidth
        : config.resolveWidth(viewportWidth);

    final column = SwimlaneColumn(
      laneId: laneId,
      config: config,
      resolvedWidth: resolvedWidth,
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
