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
import 'package:zephyr/workspace/model/workspace_workhole.dart';
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
    // 「Reader 聚焦时自动独占」：把交互交给 Reader 时顺带把独占也给它。
    //
    // 只在**这一条**路径上加，且激活别的泳道时**不清除**独占偏好 ——
    // 与契约一致（`激活别的泳道会让 Reader 变回常规宽度，但不清除 solo 偏好`）：
    // 退出独占要么是用户自己按的，要么是偏好关了的，不该由「点了左栏」代劳。
    final soloReader =
        state.interaction.autoSoloOnFocus &&
        laneId == LaneId.reader &&
        state.layout.soloLaneId != LaneId.reader;
    emit(
      state.copyWith(
        activeLaneId: () => laneId,
        layout: soloReader
            ? state.layout.copyWith(soloLaneId: () => LaneId.reader)
            : null,
      ),
    );
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
    emit(state.copyWith(mode: nextMode, isReaderFullscreen: false));
  }

  void setMode(WorkspaceMode mode) {
    if (state.mode == mode) return;
    emit(state.copyWith(mode: mode, isReaderFullscreen: false));
  }

  // ── 阅读器泳道 ─────────────────────────────────────────────────────────

  /// 在阅读器泳道里打开一本（上游推入 `ComicReadRoute` 时也会走到这里）。
  ///
  /// **默认顺带激活阅读器泳道**：上游的推入可能是用户在左泳道里点出来的，
  /// 若只把书塞进泳道而不把交互交过去，书就开在一个不在视口里的地方
  /// （现象是「点了书架里的漫画，什么都没发生」）。
  ///
  /// 这一下要不要做，由 `WorkspaceInteractionSettings.autoFocusReaderOnOpen` 定
  /// （设置 → 布局 → 泳道焦点与独占）。关掉时**只有这一点变化**：书照样开进
  /// 中央阅读器泳道，条带一动不动 —— 用户原来在浏览的那条泳道仍在手上，
  /// 于是不必每次读完再把它唤回来。代价（阅读器整个在视口外时，这一下看起来
  /// 像「没反应」）写在那个字段上。
  ///
  /// 两条读入口都汇到这里：详情页那颗「阅读」与封面那颗「直接阅读」推的是
  /// **同一个** `ComicReadRoute`（详情页内那一下只是不经过根路由守卫），
  /// 所以这颗开关对两者一起生效。
  void openReader(WorkspaceReaderTarget target) {
    final changed = state.readerTarget != target;
    final focus = state.interaction.autoFocusReaderOnOpen;
    final activate = focus && state.activeLaneId != LaneId.reader;
    if (!changed && !activate) return;
    emit(
      state.copyWith(
        readerTarget: () => target,
        activeLaneId: activate ? () => LaneId.reader : null,
      ),
    );
  }

  /// 关闭当前这一本，阅读器泳道回到空态。
  void closeReader() {
    if (state.readerTarget == null) return;
    emit(state.copyWith(readerTarget: () => null, isReaderFullscreen: false));
  }

  /// 切换阅读器铺满窗口全屏状态。
  ///
  /// 在 solo 聚焦基础上去掉顶栏、内边距与边框，使阅读器自身铺满当前窗口。
  void toggleReaderFullscreen() {
    if (state.readerTarget == null) return;
    setReaderFullscreen(!state.isReaderFullscreen);
  }

  /// 进入 / 退出阅读器铺满窗口全屏。
  void setReaderFullscreen(bool fullscreen) {
    if (state.isReaderFullscreen == fullscreen) return;
    if (fullscreen) {
      emit(
        state.copyWith(
          isReaderFullscreen: true,
          activeLaneId: () => LaneId.reader,
          layout: state.layout.copyWith(soloLaneId: () => LaneId.reader),
        ),
      );
    } else {
      emit(
        state.copyWith(
          isReaderFullscreen: false,
          layout: state.layout.copyWith(soloLaneId: () => null),
        ),
      );
    }
  }

  /// 退出阅读器铺满窗口全屏（供 Esc / 快捷键等触发）。
  void exitReaderFullscreen() {
    if (state.isReaderFullscreen) {
      setReaderFullscreen(false);
    }
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

  /// 直接更新完整泳道几何与顺序配置（供设置页看板修改泳道顺序等）。
  void setLayout(WorkspaceLayoutConfig layout) {
    if (state.layout == layout) return;
    emit(state.copyWith(layout: layout));
  }

  /// 直接更新面板与卡片布局记账（供设置页看板批量更新面板排序与显隐）。
  void setBoard(
    WorkspaceBoardLayout board, {
    Map<String, String>? activePanel,
  }) {
    if (state.board == board && activePanel == null) return;
    emit(state.copyWith(board: board, activePanel: activePanel));
  }

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

  /// 面板在看板里**还没有布局记录**时的默认记录：取注册表已经算好的有效布局。
  PanelLayout _fallbackPanelLayout(String panelId, WorkspacePanelSide side) {
    final registry = WorkspacePanelRegistry.I;
    final def = registry.find(panelId);
    if (def == null) return PanelLayout(visible: true, order: 0, side: side);
    return registry.effectivePanelLayout(def, state.board);
  }

  /// 在看板中把面板放到 [side] 侧的指定位置，同时保留各面板自身的显示/隐藏状态。
  void arrangePanelInBoard({
    required String panelId,
    required WorkspacePanelSide side,
    required int insertIndex,
    bool? visible,
  }) {
    final registry = WorkspacePanelRegistry.I;
    final panel = registry.find(panelId);
    if (panel == null) return;
    final currentLayout = registry.effectivePanelLayout(panel, state.board);
    if (!panel.canMove && currentLayout.side != side) return;

    final siblings = [
      for (final p in registry.allPanelsForSide(side, state.board))
        if (p.id != panelId) p.id,
    ];
    final nextBoard = state.board.arrangePanel(
      panelId: panelId,
      side: side,
      siblingIds: siblings,
      insertIndex: insertIndex,
      visible: visible,
      fallbackFor: (id) => _fallbackPanelLayout(id, side),
    );
    emit(state.copyWith(board: nextBoard));
  }

  /// 在看板中将某条泳道内的面板上移（`direction = -1`）或下移（`direction = 1`）。
  void movePanelInBoard(
    WorkspacePanelSide side,
    String panelId,
    int direction,
  ) {
    final registry = WorkspacePanelRegistry.I;
    final ordered = [
      for (final p in registry.allPanelsForSide(side, state.board)) p.id,
    ];
    final nextBoard = state.board.movePanel(
      panelId,
      direction,
      ordered,
      fallbackFor: (id) => _fallbackPanelLayout(id, side),
    );
    if (nextBoard == null) return;
    emit(state.copyWith(board: nextBoard));
  }

  /// 显示 / 隐藏一个面板（可选保持其当前顺序而不重排到末尾）。
  void setPanelVisible(
    String panelId,
    bool visible, {
    bool preserveOrder = false,
  }) {
    final panel = WorkspacePanelRegistry.I.find(panelId);
    if (panel == null) return;
    final effective = WorkspacePanelRegistry.I.effectivePanelLayout(
      panel,
      state.board,
    );
    if (effective.visible == visible) return;

    final order = preserveOrder
        ? effective.order
        : (visible
              ? WorkspacePanelRegistry.I
                    .panelsForSide(effective.side, state.board)
                    .length
              : effective.order);
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

  /// 仅重置泳道顺序与面板看板布局（保留泳道宽度、交互设置与卡片内部布局）。
  void resetSwimlaneAndPanelLayout() {
    emit(
      state.copyWith(
        layout: state.layout.copyWith(
          laneOrder: LaneId.defaultOrder,
        ),
        board: state.board.resetPanels(),
        activePanel: const <String, String>{},
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

  /// 调整卡片的尺寸跨度。
  void resizeCardInPanel(String cardId, int widthSpan, int heightSpan) {
    final card = WorkspaceCardRegistry.I.find(cardId);
    if (card == null) return;
    final effective = WorkspaceCardRegistry.I.effectiveLayout(
      card,
      state.board,
    );
    emit(
      state.copyWith(
        board: state.board.resizeCard(
          cardId: cardId,
          panelId: effective.panelId,
          order: effective.order,
          widthSpan: widthSpan,
          heightSpan: heightSpan,
        ),
      ),
    );
  }

  /// 恢复卡片的默认全宽与自适应高度（清除手动 heightSpan 覆盖）。
  void resetCardAutoHeight(String cardId) {
    final card = WorkspaceCardRegistry.I.find(cardId);
    if (card == null) return;
    final effective = WorkspaceCardRegistry.I.effectiveLayout(
      card,
      state.board,
    );
    emit(
      state.copyWith(
        board: state.board.resetCardAutoHeight(
          cardId: cardId,
          panelId: effective.panelId,
          order: effective.order,
          defaultWidthSpan: card.defaultWidthSpan,
        ),
      ),
    );
  }

  /// 批量重排面板内的卡片次序。
  void reorderCardsInPanel(String panelId, List<String> orderedCardIds) {
    emit(
      state.copyWith(
        board: state.board.reorderCards(
          panelId: panelId,
          orderedCardIds: orderedCardIds,
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

  /// 把某条泳道的宽度写成一个**绝对值**（栏头「更多」菜单里的宽度输入框）。
  ///
  /// 与 [dragLanePair] 的区别：那条是「两条之间挪距离」，两侧都得让得动，
  /// 于是它要拿邻居的 min/max 一起夹；这一条只改**自己**，只夹到自己记录的
  /// min/max —— 结果可能把条带撑出横向滚动，那正是用户要的
  /// （面板泳道的宽度**不按当前窗口宽夹取**，见 `LaneConfig` 顶部的说明）。
  ///
  /// [viewportWidth] 与 [dragLanePair] 同一个含义：阅读器泳道记的是视口比例，
  /// 只有拿到视口宽才能把「用户输入的像素」换算回比例。
  void setLaneWidth(String laneId, double px, double viewportWidth) {
    final lane = state.layout.lanes[laneId];
    if (lane == null) return;
    final width = px.clamp(lane.minWidth, lane.maxWidth).toDouble();
    final updated = _replaceLane(
      laneId,
      _withWidth(lane, width, viewportWidth),
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
  /// 打开 Solo 时**顺带激活这条泳道**：面板泳道那档仍然需要它（生效宽度以
  /// 「同时被激活」为前提，见 `WorkspaceState.effectiveSoloLaneId`），而 Reader
  /// 那档现在只需要「条带滚过去让你看见」这一半 —— 两边都在说同一件事：
  /// 按了独占就该看到它。关掉时不反向激活 —— 退出独占的用户
  /// 想要的是「回到多栏」，不是「跳到别处」。
  void toggleSoloLane(String laneId) {
    final currentSolo = state.layout.soloLaneId;
    final nextSolo = currentSolo == laneId ? null : laneId;

    emit(
      state.copyWith(
        layout: state.layout.copyWith(soloLaneId: () => nextSolo),
        activeLaneId: nextSolo != null ? () => laneId : null, // 关掉独占不动激活泳道
        isReaderFullscreen: false,
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

  /// 设置左右 Workhole 的展开状态。
  void setEdgeWorkholeOpen(WorkspacePanelSide side, bool open) {
    final current = switch (side) {
      WorkspacePanelSide.left => state.layout.edgeLeftOpen,
      WorkspacePanelSide.right => state.layout.edgeRightOpen,
    };
    if (current == open) return;

    emit(
      state.copyWith(
        layout: switch (side) {
          WorkspacePanelSide.left => state.layout.copyWith(edgeLeftOpen: open),
          WorkspacePanelSide.right => state.layout.copyWith(
            edgeRightOpen: open,
          ),
        },
      ),
    );
  }

  /// 记录左右 Workhole 的档位，或记录用户拖拽得到的自定义宽度。
  void setEdgeWorkholeSize(
    WorkspacePanelSide side,
    WorkspaceWorkholeSize size, {
    double? width,
  }) {
    final normalizedWidth = width != null && width.isFinite && width > 0
        ? width
        : null;
    final layout = switch (side) {
      WorkspacePanelSide.left => state.layout.copyWith(
        edgeLeftOpen: true,
        edgeLeftSize: size,
        edgeLeftWidth: () =>
            size == WorkspaceWorkholeSize.custom ? normalizedWidth : null,
      ),
      WorkspacePanelSide.right => state.layout.copyWith(
        edgeRightOpen: true,
        edgeRightSize: size,
        edgeRightWidth: () =>
            size == WorkspaceWorkholeSize.custom ? normalizedWidth : null,
      ),
    };
    if (layout == state.layout) return;
    emit(state.copyWith(layout: layout));
  }

  /// 将 Workhole 恢复到默认的 workbench 档位。
  void resetEdgeWorkholeSize(WorkspacePanelSide side) {
    setEdgeWorkholeSize(side, WorkspaceWorkholeSize.workbench);
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
        isReaderFullscreen: false,
      ),
    );
  }
}
