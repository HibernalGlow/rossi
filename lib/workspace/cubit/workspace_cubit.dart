import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit() : super(WorkspaceState.initial());

  // ── 激活泳道 ───────────────────────────────────────────────────────────

  /// 把交互交给 [laneId]。
  ///
  /// 它是「非激活泳道的第一下点击被吃掉」与「悬停 dwell 聚焦」共同的落点：
  /// 两种手势都只做这一件事，区别只在**由什么触发**（点击 / 驻留）。
  ///
  /// 不存在的泳道 id 直接忽略 —— 激活一条已经被下线 / 改名掉的泳道会让
  /// 「谁被激活」这个记账指向一个界面上没有的东西，而所有依赖它的判断
  /// （吞点击、solo 生效宽度）都会静默失准。
  void activateLane(String laneId) {
    if (state.activeLaneId == laneId) return;
    if (!state.layout.lanes.containsKey(laneId)) return;
    emit(state.copyWith(activeLaneId: () => laneId));
  }

  /// 悬停聚焦是否启用 / 三个延时（契约要求这三套延时可配且互相独立）。
  void setInteraction(WorkspaceInteractionSettings settings) {
    if (state.interaction == settings) return;
    emit(state.copyWith(interaction: settings));
  }

  /// 改某条泳道的**面板操作栏**记账（模式 / 停靠边 / 悬浮位置 / 是否限制在泳道内）。
  void setLanePanelBar(String laneId, PanelBarLayout panelBar) {
    final lane = state.layout.lanes[laneId];
    if (lane == null || lane.panelBar == panelBar) return;
    emit(
      state.copyWith(
        layout: state.layout.copyWith(
          lanes: _replaceLane(laneId, lane.copyWith(panelBar: panelBar)),
        ),
      ),
    );
  }

  // ── 快照（持久化） ─────────────────────────────────────────────────────

  /// 当前状态的完整快照（「什么该进快照」的口径写在 `WorkspaceLayoutSnapshot` 里）。
  ///
  /// 快照里**没有** `readerTarget`：它带着 cubit 与页面参数，
  /// 「冷启动要不要恢复上次那本」是阅读历史的职责，不是布局的。
  WorkspaceLayoutSnapshot get snapshot => WorkspaceLayoutSnapshot(
    mode: state.mode,
    layout: state.layout,
    board: state.board,
    activePanel: state.activePanel,
    activeLaneId: state.activeLaneId,
    interaction: state.interaction,
  );

  /// 用一份快照替换当前布局（启动时读盘、或「重置布局」）。
  ///
  /// **不动**正在读的那一本（与 [resetLayout] 同一条纪律）。
  void restore(WorkspaceLayoutSnapshot snapshot) {
    emit(
      state.copyWith(
        mode: snapshot.mode,
        layout: snapshot.layout,
        board: snapshot.board,
        activePanel: snapshot.activePanel,
        activeLaneId: () => snapshot.activeLaneId,
        interaction: snapshot.interaction,
      ),
    );
  }

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
  ///
  /// 顺带**激活阅读器泳道**：上游的推入可能是用户在左泳道里点出来的，
  /// 若只把书塞进泳道而不把交互交过去，书就开在一个不在视口里的地方
  /// （现象是「点了书架里的漫画，什么都没发生」）。
  void openReader(WorkspaceReaderTarget target) {
    final changed = state.readerTarget != target;
    final activate = state.activeLaneId != LaneId.reader;
    if (!changed && !activate) return;
    emit(
      state.copyWith(
        readerTarget: () => target,
        activeLaneId: () => LaneId.reader,
      ),
    );
  }

  /// 关闭当前这一本，阅读器泳道回到空态。
  void closeReader() {
    if (state.readerTarget == null) return;
    emit(state.copyWith(readerTarget: () => null));
  }

  // ── 面板泳道 ───────────────────────────────────────────────────────────

  /// 切换某条泳道当前显示的面板（各泳道各自记账）。
  void setActivePanel(String laneId, String panelId) {
    if (state.activePanel[laneId] == panelId) return;
    final updated = Map<String, String>.from(state.activePanel);
    updated[laneId] = panelId;
    emit(state.copyWith(activePanel: updated));
  }

  // ── 面板 / 卡片的布局记账 ──────────────────────────────────────────────

  /// 把面板放到 [side] 侧的指定位置（轨内重排与跨泳道搬移走的是同一个口子）。
  void placePanel({
    required String panelId,
    required WorkspacePanelSide side,
    required List<String> siblingIds,
    required int insertIndex,
  }) {
    emit(
      state.copyWith(
        board: state.board.placePanel(
          panelId: panelId,
          side: side,
          siblingIds: siblingIds,
          insertIndex: insertIndex,
        ),
      ),
    );
  }

  /// 显示 / 隐藏一个面板。
  void setPanelVisible(String panelId, bool visible) {
    final panel = WorkspacePanelRegistry.I.find(panelId);
    if (panel == null) return;
    final effective = WorkspacePanelRegistry.I.effectivePanelLayout(
      panel,
      state.board,
    );
    if (effective.visible == visible) return;

    final order = visible
        ? WorkspacePanelRegistry.I
              .panelsForSide(effective.side, state.board)
              .length
        : effective.order;
    emit(
      state.copyWith(
        board: state.board.setPanelVisible(
          panelId: panelId,
          side: effective.side,
          order: order,
          visible: visible,
        ),
      ),
    );
  }

  /// 在所属面板内上移 / 下移一张卡。
  ///
  /// 次序由**注册表算出的当前显示序列**决定 —— 不由调用方传进来，
  /// 否则「按错了一下」会把某张卡挪到一个谁也没想到的位置。
  void moveCardInPanel(String panelId, String cardId, int direction) {
    final registry = WorkspaceCardRegistry.I;
    final ordered = [
      for (final card in registry.cardsForPanel(panelId, state.board)) card.id,
    ];
    final next = state.board.moveCard(cardId, direction, ordered);
    if (next == null) return;
    emit(state.copyWith(board: next));
  }

  /// 展开 / 折叠一张卡。
  void setCardExpanded(String cardId, bool expanded) {
    final card = WorkspaceCardRegistry.I.find(cardId);
    if (card == null) return;
    final effective = WorkspaceCardRegistry.I.effectiveLayout(
      card,
      state.board,
    );
    emit(
      state.copyWith(
        board: state.board.setCardExpanded(
          cardId: cardId,
          panelId: effective.panelId,
          order: effective.order,
          expanded: expanded,
        ),
      ),
    );
  }

  /// 显示 / 隐藏一张卡。
  void setCardVisible(String cardId, bool visible) {
    final card = WorkspaceCardRegistry.I.find(cardId);
    if (card == null) return;
    final effective = WorkspaceCardRegistry.I.effectiveLayout(
      card,
      state.board,
    );
    emit(
      state.copyWith(
        board: state.board.setCardVisible(
          cardId: cardId,
          panelId: effective.panelId,
          order: effective.order,
          visible: visible,
        ),
      ),
    );
  }

  /// 把一张卡搬到另一个面板（同样是「卡片成员关系只有一处可改」的落点）。
  void placeCard({
    required String cardId,
    required String panelId,
    required int insertIndex,
  }) {
    final registry = WorkspaceCardRegistry.I;
    final siblings = [
      for (final card in registry.cardsForPanel(panelId, state.board))
        if (card.id != cardId) card.id,
    ];
    final fallbackCard = registry.find(cardId);
    final moved = state.board.placeCard(
      cardId: cardId,
      panelId: panelId,
      siblingCardIds: siblings,
      insertIndex: insertIndex,
      fallbackFor: (id) {
        final definition = registry.find(id) ?? fallbackCard;
        return CardLayout(
          panelId: definition?.defaultPanelId ?? panelId,
          visible: true,
          order: definition?.defaultOrder ?? 0,
          expanded: definition?.defaultExpanded ?? true,
        );
      },
    );
    emit(state.copyWith(board: moved));
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

  /// 泳道重排：把 [draggedLaneId] 挪到 [targetLaneId] 原来的位置上。
  ///
  /// 顺序是**通用顺序**（一串 id），所以将来加「浮动泳道」之类的标识
  /// 不需要换模型。阅读器泳道与面板泳道的宽度记账各自独立，
  /// 重排只改**谁在左、谁在右**，不动任何宽度。
  void reorderLane(String draggedLaneId, String targetLaneId) {
    if (draggedLaneId == targetLaneId) return;
    final order = List<String>.from(state.layout.laneOrder);
    final from = order.indexOf(draggedLaneId);
    final to = order.indexOf(targetLaneId);
    if (from < 0 || to < 0) return;

    order.removeAt(from);
    order.insert(to, draggedLaneId);
    emit(state.copyWith(layout: state.layout.copyWith(laneOrder: order)));
  }

  /// 切换泳道独占（Solo）状态。
  ///
  /// Solo 是**泳道自己的属性**，不是全局工作区状态：进入/退出 Solo 都不改写
  /// 该泳道记录下来的宽度（阅读器回到常规时用的还是它原来的比例）。
  ///
  /// 打开 Solo 时**顺带激活这条泳道**：solo 的生效宽度以「这条泳道同时是激活
  /// 泳道」为前提（见 `WorkspaceState.effectiveSoloLaneId`），不激活的话
  /// 用户按了独占却什么都没发生。关掉时不反向激活 —— 退出独占的用户
  /// 想要的是「回到多栏」，不是「跳到别处」。
  void toggleSoloLane(String laneId) {
    final currentSolo = state.layout.soloLaneId;
    final nextSolo = currentSolo == laneId ? null : laneId;

    emit(
      state.copyWith(
        layout: state.layout.copyWith(soloLaneId: () => nextSolo),
        activeLaneId: nextSolo != null ? () => laneId : null, // 关掉独占不动激活泳道
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

  /// 重置布局为默认（**不动**当前正在读的那一本）。
  ///
  /// 「重置」= 把布局记账清空 —— 因为空账就是「全部按注册表的默认值」，
  /// 所以重置不需要把默认值再抄一遍，也就不会漏掉后来新加的卡片。
  ///
  /// 同时把**激活泳道**与**交互设置**一并复位：这两项都属于「用户的布局偏好」，
  /// 用户按下「重置布局」时想的是「回到我什么都没调过的样子」，
  /// 留下一半调过的状态（例如「延时还是我改的那个」）比不重置更难解释。
  /// 调用方还应当把磁盘上的快照一并清掉（见 `WorkspaceLayoutPersistence.reset`），
  /// 否则重启之后那次重置会被旧快照覆盖回去。
  void resetLayout() {
    emit(
      state.copyWith(
        layout: WorkspaceLayoutConfig.defaults(),
        board: const WorkspaceBoardLayout(),
        activePanel: const <String, String>{},
        activeLaneId: () => null,
        interaction: const WorkspaceInteractionSettings(),
      ),
    );
  }
}
