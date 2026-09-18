import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit() : super(WorkspaceState.initial());

  /// 切换工作区模式（泳道 <-> 四边栏互斥）
  void toggleMode() {
    final nextMode = state.mode == WorkspaceMode.swimlane
        ? WorkspaceMode.edges
        : WorkspaceMode.swimlane;
    emit(state.copyWith(mode: nextMode));
  }

  void setMode(WorkspaceMode mode) {
    if (state.mode == mode) return;
    emit(state.copyWith(mode: mode));
  }

  /// 调整特定泳道宽度
  void updateLaneWidth(String laneId, double delta) {
    final currentLane = state.layout.lanes[laneId];
    if (currentLane == null) return;

    final newWidth = (currentLane.width + delta).clamp(
      currentLane.minWidth,
      currentLane.maxWidth,
    );

    final updatedLanes = Map<String, LaneConfig>.from(state.layout.lanes);
    updatedLanes[laneId] = currentLane.copyWith(width: newWidth);

    emit(state.copyWith(
      layout: state.layout.copyWith(lanes: updatedLanes),
    ));
  }

  /// 切换泳道折叠状态（折叠成 44dp 紧凑条）
  void toggleLaneCollapsed(String laneId) {
    final currentLane = state.layout.lanes[laneId];
    if (currentLane == null) return;

    final updatedLanes = Map<String, LaneConfig>.from(state.layout.lanes);
    updatedLanes[laneId] = currentLane.copyWith(
      collapsed: !currentLane.collapsed,
    );

    emit(state.copyWith(
      layout: state.layout.copyWith(lanes: updatedLanes),
    ));
  }

  /// 切换泳道独占（Solo）状态
  void toggleSoloLane(String laneId) {
    final currentSolo = state.layout.soloLaneId;
    final nextSolo = currentSolo == laneId ? null : laneId;

    emit(state.copyWith(
      layout: state.layout.copyWith(
        soloLaneId: () => nextSolo,
      ),
    ));
  }

  /// 切换卡片展开/折叠
  void toggleCardExpanded(String cardId) {
    final current = state.cardExpanded[cardId] ?? true;
    final updated = Map<String, bool>.from(state.cardExpanded);
    updated[cardId] = !current;
    emit(state.copyWith(cardExpanded: updated));
  }

  /// 切换四边栏边缘抽屉
  void toggleEdgeDrawer(String edgeKey) {
    switch (edgeKey) {
      case 'left':
        emit(state.copyWith(
          layout: state.layout.copyWith(edgeLeftOpen: !state.layout.edgeLeftOpen),
        ));
      case 'right':
        emit(state.copyWith(
          layout: state.layout.copyWith(edgeRightOpen: !state.layout.edgeRightOpen),
        ));
      case 'top':
        emit(state.copyWith(
          layout: state.layout.copyWith(edgeTopOpen: !state.layout.edgeTopOpen),
        ));
      case 'bottom':
        emit(state.copyWith(
          layout: state.layout.copyWith(edgeBottomOpen: !state.layout.edgeBottomOpen),
        ));
    }
  }

  void closeAllEdgeDrawers() {
    emit(state.copyWith(
      layout: state.layout.copyWith(
        edgeLeftOpen: false,
        edgeRightOpen: false,
        edgeTopOpen: false,
        edgeBottomOpen: false,
      ),
    ));
  }

  /// 重置布局为默认
  void resetLayout() {
    emit(state.copyWith(
      layout: WorkspaceLayoutConfig.defaults(),
    ));
  }
}
