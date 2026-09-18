import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/cards/workspace_reader_lane.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_bookshelf_lane.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_discover_lane.dart';
import 'package:zephyr/workspace/widgets/lane_resizer.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';

/// 水平泳道工作区容器（中央 Reader 阅读器 + 左侧书架 + 右侧发现与工具）
class SwimlaneWorkspace extends StatelessWidget {
  const SwimlaneWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final cubit = context.read<WorkspaceCubit>();
        final layout = state.layout;
        final soloLaneId = layout.soloLaneId;

        final leftConfig = layout.lanes[LaneId.left] ??
            const LaneConfig(width: 380, title: '书架 (Bookshelf)');
        final readerConfig = layout.lanes[LaneId.reader] ??
            const LaneConfig(width: 650, title: '阅读器 (Reader)');
        final rightConfig = layout.lanes[LaneId.right] ??
            const LaneConfig(width: 350, title: '发现与工具 (Tools)');

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;

            // 1. 如果处于 Solo 独占状态 (例如 Reader 独占放大)
            if (soloLaneId != null) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    if (soloLaneId != LaneId.left)
                      _buildCollapsedSide(context, cubit, LaneId.left, leftConfig),
                    if (soloLaneId == LaneId.right)
                      _buildCollapsedSide(context, cubit, LaneId.reader, readerConfig),
                    Expanded(
                      child: _buildLane(context, cubit, state, soloLaneId, isSolo: true),
                    ),
                    if (soloLaneId == LaneId.left)
                      _buildCollapsedSide(context, cubit, LaneId.reader, readerConfig),
                    if (soloLaneId != LaneId.right)
                      _buildCollapsedSide(context, cubit, LaneId.right, rightConfig),
                  ],
                ),
              );
            }

            // 2. 常规多泳道模式
            final leftW = leftConfig.collapsed
                ? WorkspaceLayoutConfig.collapsedLaneWidth
                : leftConfig.width;
            final rightW = rightConfig.collapsed
                ? WorkspaceLayoutConfig.collapsedLaneWidth
                : rightConfig.width;
            const resizerW = 10.0;
            final fixedSidesWidth = leftW + rightW + (resizerW * 2) + 24;

            // 弹性计算中央 Reader 泳道宽度
            final calculatedReaderW = max(readerConfig.minWidth, viewportWidth - fixedSidesWidth);
            final totalWidthRequired = leftW + calculatedReaderW + rightW + (resizerW * 2) + 16;
            final needsHorizontalScroll = totalWidthRequired > viewportWidth;

            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 左侧泳道 (完整复用 BookshelfPage)
                SizedBox(
                  width: leftW,
                  child: _buildLane(context, cubit, state, LaneId.left),
                ),

                // 分栏手柄 (左 <-> Reader)
                if (!leftConfig.collapsed)
                  LaneResizer(
                    onDragDelta: (delta) => cubit.updateLaneWidth(LaneId.left, delta),
                    onDoubleTapReset: () =>
                        cubit.updateLaneWidth(LaneId.left, 380.0 - leftConfig.width),
                  ),

                // 2. 中央阅读器泳道 (NeoView 核心 Reader Canvas)
                SizedBox(
                  width: needsHorizontalScroll ? readerConfig.width : calculatedReaderW,
                  child: _buildLane(context, cubit, state, LaneId.reader),
                ),

                // 分栏手柄 (Reader <-> 右)
                if (!rightConfig.collapsed)
                  LaneResizer(
                    onDragDelta: (delta) => cubit.updateLaneWidth(LaneId.right, -delta),
                    onDoubleTapReset: () =>
                        cubit.updateLaneWidth(LaneId.right, 350.0 - rightConfig.width),
                  ),

                // 3. 右侧泳道 (完整复用 DiscoverPage 与插件市场)
                SizedBox(
                  width: rightW,
                  child: _buildLane(context, cubit, state, LaneId.right),
                ),
              ],
            );

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: needsHorizontalScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalWidthRequired,
                        child: content,
                      ),
                    )
                  : content,
            );
          },
        );
      },
    );
  }

  Widget _buildCollapsedSide(
    BuildContext context,
    WorkspaceCubit cubit,
    String laneId,
    LaneConfig config,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: SwimlaneColumn(
        laneId: laneId,
        config: config.copyWith(collapsed: true),
        isSolo: false,
        onToggleCollapse: () => cubit.toggleLaneCollapsed(laneId),
        onToggleSolo: () => cubit.toggleSoloLane(laneId),
      ),
    );
  }

  Widget _buildLane(
    BuildContext context,
    WorkspaceCubit cubit,
    WorkspaceState state,
    String laneId, {
    bool isSolo = false,
  }) {
    final config =
        state.layout.lanes[laneId] ?? LaneConfig(width: 380, title: laneId);

    // 核心泳道内容分配 (左: 书架, 中: 阅读器, 右: 发现/插件)
    final child = switch (laneId) {
      LaneId.left => const EmbeddedBookshelfLane(),
      LaneId.reader => WorkspaceReaderLane(
          mode: WorkspaceMode.swimlane,
          onToggleMode: () => cubit.toggleMode(),
        ),
      LaneId.right => const EmbeddedDiscoverLane(),
      _ => const SizedBox.shrink(),
    };

    return SwimlaneColumn(
      laneId: laneId,
      config: config,
      isSolo: isSolo,
      onToggleCollapse: () => cubit.toggleLaneCollapsed(laneId),
      onToggleSolo: () => cubit.toggleSoloLane(laneId),
      onResetWidth: () => cubit.updateLaneWidth(
        laneId,
        (laneId == LaneId.left ? 380.0 : laneId == LaneId.right ? 350.0 : 650.0) -
            config.width,
      ),
      child: child,
    );
  }
}
