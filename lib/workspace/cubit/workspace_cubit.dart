import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit() : super(WorkspaceState.initial());

  // ── 模式 ───────────────────────────────────────────────────────────────

  /// 切换工作区模式（泳道 <-> 四边栏互斥）。
  ///
  /// 切模式**不**重开当前这一本、不换页、不改另一套几何 —— 只换呈现方式。
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

  // ── 阅读器泳道 ─────────────────────────────────────────────────────────

  /// 在阅读器泳道里打开一本（上游推入 `ComicReadRoute` 时也会走到这里）。
  void openReader(WorkspaceReaderTarget target) {
    if (state.readerTarget == target) return;
    emit(state.copyWith(readerTarget: () => target));
  }

  /// 关闭当前这一本，阅读器泳道回到空态。
  void closeReader() {
    if (state.readerTarget == null) return;
    emit(state.copyWith(readerTarget: () => null));
  }

  // ── 面板泳道 ───────────────────────────────────────────────────────────

  /// 切换某条面板泳道当前显示的面板（各泳道各自记账）。
  void setActivePanel(String laneId, String panelId) {
    if (state.activePanel[laneId] == panelId) return;
    final updated = Map<String, String>.from(state.activePanel);
    updated[laneId] = panelId;
    emit(state.copyWith(activePanel: updated));
  }

  // ── 几何 ───────────────────────────────────────────────────────────────

  /// 拖拽**两个相邻泳道之间**的分隔条：把左侧泳道加宽 [delta]，
  /// 右侧泳道相应收窄 —— 分隔条于是始终跟着光标走。
  ///
  /// 两个关键细节：
  /// - **用实际让出的距离，不用请求的距离**。任一侧先撞到自己的 min/max 时，
  ///   只应用还让得动的那部分，否则分隔条会漂离光标、两张脸对不上账。
  /// - 面板泳道改的是**绝对像素**；阅读器泳道改的是**视口比例** ——
  ///   「用户想要多宽」不依赖当时的窗口宽度，改窗口大小仍然成立。
  ///
  /// [viewportWidth] 由宿主在 `LayoutBuilder` 里给出。
  void dragLanePair(
    String leftLaneId,
    String rightLaneId,
    double delta,
    double viewportWidth,
  ) {
    final leftLane = state.layout.lanes[leftLaneId];
    final rightLane = state.layout.lanes[rightLaneId];
    if (leftLane == null || rightLane == null) return;

    final leftWidth = leftLane.resolveWidth(viewportWidth);
    final rightWidth = rightLane.resolveWidth(viewportWidth);

    final maxGrow = math.min(
      leftLane.maxWidth - leftWidth,
      rightWidth - rightLane.minWidth,
    );
    final maxShrink = -math.min(
      leftWidth - leftLane.minWidth,
      rightLane.maxWidth - rightWidth,
    );

    final applied = delta.clamp(maxShrink, maxGrow);
    if (applied == 0) return;

    final updated = Map<String, LaneConfig>.from(state.layout.lanes);
    updated[leftLaneId] = _withWidth(
      leftLane,
      leftWidth + applied,
      viewportWidth,
    );
    updated[rightLaneId] = _withWidth(
      rightLane,
      rightWidth - applied,
      viewportWidth,
    );
    emit(state.copyWith(layout: state.layout.copyWith(lanes: updated)));
  }

  /// 双击栏顶标题：把该泳道恢复到推荐宽度。
  void resetLaneWidth(String laneId) {
    final recommended = WorkspaceLayoutConfig.defaults().lanes[laneId];
    if (recommended == null || state.layout.lanes[laneId] == null) return;

    final updated = _replaceLane(laneId, recommended);
    emit(state.copyWith(layout: state.layout.copyWith(lanes: updated)));
  }

  /// 双击**分隔条**：把它两侧的泳道都恢复到推荐宽度。
  ///
  /// 分隔条骑在两条泳道中间，只重置一侧会让另一侧留在被拖歪的位置上 ——
  /// 「恢复默认」在这种控件上应当是整条缝的事。
  void resetLanePair(String firstLaneId, String secondLaneId) {
    final defaults = WorkspaceLayoutConfig.defaults().lanes;
    final updated = Map<String, LaneConfig>.from(state.layout.lanes);
    var changed = false;
    for (final laneId in [firstLaneId, secondLaneId]) {
      final recommended = defaults[laneId];
      if (recommended == null || !updated.containsKey(laneId)) continue;
      updated[laneId] = recommended;
      changed = true;
    }
    if (!changed) return;
    emit(state.copyWith(layout: state.layout.copyWith(lanes: updated)));
  }

  /// 切换泳道折叠状态（折叠成 44dp 紧凑条）
  void toggleLaneCollapsed(String laneId) {
    final lane = state.layout.lanes[laneId];
    if (lane == null) return;

    final updated = _replaceLane(
      laneId,
      lane.copyWith(collapsed: !lane.collapsed),
    );
    emit(state.copyWith(layout: state.layout.copyWith(lanes: updated)));
  }

  /// 切换泳道独占（Solo）状态。
  ///
  /// Solo 是**泳道自己的属性**，不是全局工作区状态：进入/退出 Sole 都不改写
  /// 该泳道记录下来的宽度（阅读器回到常规时用的还是它原来的比例）。
  void toggleSoloLane(String laneId) {
    final currentSolo = state.layout.soloLaneId;
    final nextSolo = currentSolo == laneId ? null : laneId;

    emit(
      state.copyWith(
        layout: state.layout.copyWith(soloLaneId: () => nextSolo),
      ),
    );
  }

  Map<String, LaneConfig> _replaceLane(String laneId, LaneConfig to) {
    final updated = Map<String, LaneConfig>.from(state.layout.lanes);
    updated[laneId] = to;
    return updated;
  }

  /// 把宽度写回配置：比例泳道同时记下「新的比例」，像素泳道只记像素。
  LaneConfig _withWidth(LaneConfig lane, double px, double viewportWidth) {
    if (lane.widthRatio == null || viewportWidth <= 0) {
      return lane.copyWith(width: px);
    }
    return lane.copyWith(width: px, widthRatio: () => px / viewportWidth);
  }

  // ── 卡片与四边栏（edges 模式） ─────────────────────────────────────────

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
        emit(
          state.copyWith(
            layout: state.layout.copyWith(
              edgeLeftOpen: !state.layout.edgeLeftOpen,
            ),
          ),
        );
      case 'right':
        emit(
          state.copyWith(
            layout: state.layout.copyWith(
              edgeRightOpen: !state.layout.edgeRightOpen,
            ),
          ),
        );
      case 'top':
        emit(
          state.copyWith(
            layout: state.layout.copyWith(
              edgeTopOpen: !state.layout.edgeTopOpen,
            ),
          ),
        );
      case 'bottom':
        emit(
          state.copyWith(
            layout: state.layout.copyWith(
              edgeBottomOpen: !state.layout.edgeBottomOpen,
            ),
          ),
        );
    }
  }

  void closeAllEdgeDrawers() {
    emit(
      state.copyWith(
        layout: state.layout.copyWith(
          edgeLeftOpen: false,
          edgeRightOpen: false,
          edgeTopOpen: false,
          edgeBottomOpen: false,
        ),
      ),
    );
  }

  /// 重置布局为默认（**不动**当前正在读的那一本）
  void resetLayout() {
    emit(
      state.copyWith(
        layout: WorkspaceLayoutConfig.defaults(),
        activePanel: WorkspaceState.initial().activePanel,
      ),
    );
  }
}
