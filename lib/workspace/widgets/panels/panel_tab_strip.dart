import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/panels/workspace_panel_tabs.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// **面板操作栏** —— 泳道里的那一条面板页签。
///
/// 它同时是三件事：
///
/// 1. **面板切换**：点页签；常态下**按住横移**也能切（弹簧 lens 跟手）；
/// 2. **面板搬运**：**排序模式**下长按页签拖动 —— 轨内换位，或拖到**另一条
///    泳道**的页签条上；
/// 3. **它自己的摆放**：按住把手拖动 = 钉到某条边或转成悬浮（neoview 的
///    `ReaderPanelBar`）；右键把手 = 切换「钉住 / 悬浮」与「是否限制在本泳道内」。
///
/// ## 两种模式的手势是**相反**的（`interaction.panelTabSortMode`）
///
/// | | 常态（默认） | 排序模式 |
/// |---|---|---|
/// | 点页签 | 切换面板 | 切换面板 |
/// | 按住横移 | **切面板**（lens 跟手，跨格触感） | 什么都不做 |
/// | 长按拖动 | 什么都不做 | **拖排序 / 拖到另一条泳道** |
///
/// 这么分是因为拖排序**低频且带破坏性**（拖错了要把面板搬回来）。它在默认
/// 路径上就意味着每次切面板都得先想「我现在是想切还是想搬」。反过来之后，
/// 日常那一下永远是最轻的那条路径，想搬面板时主动开一档 —— 动作与意图对齐。
///
/// 为什么不能两档同时开：`LongPressDraggable`（220ms 延时）与lens 的跟手拖动
/// 抢的是**同一片手势区**，物理互斥。排序模式下必须把跟手整个关掉
/// （`SpringLensBar.draggable: false`），跨泳道搬运也只在这一档有 —— 那条路要
/// 离开当前泳道，落点语义与 lens 的横向落点不同，两条同时认领会打架。
///
/// 切档入口在**右键把手那个菜单**里（栏头挂进去时把手不画，那边走设置页）。
///
/// ## 挂进栏头 vs 自己浮着
///
/// `pinned + dock: top` 时它被**挂进泳道栏头**（neoview 的 `titleMounted`），
/// 于是不额外占位、也不画自己的底板 —— 这是本项目的默认形态。
/// 其余形态它自己带底板与阴影，位置由 `PanelBarPositioner` 按
/// `panelBarMode / panelBarDock / panelBarPositionX/Y` 算出来。
///
/// ## 跨侧拖动的插入位
///
/// 每个页签**自己**就是一个「插到我前面」的落点（下标 = 它在序列里的位置），
/// 末尾那个细缝是「追加到末尾」。于是「拖到哪儿就落在哪儿」不需要去读光标
/// 与每个页签的几何关系 —— 命中测试已经替我们做完了。
/// 早先版本把跨侧拖入固定写成「追加到末尾」（`insertIndex: siblings.length`），
/// 于是无论往哪儿放，面板都跑到最后一位。
///
/// 落点**不区分页签能不能移动**：`canMove: false` 只表示它自己不能被拖走
/// （上游整页那三个），它同样是「插到我前面」的一个位置。把这两件事混起来
/// 会让精确插入位在 5 个面板里失效 3 个 —— 往「工具」上拖会掉回追加。
/// 只有页签**之外**的空白区域才是「追加到末尾」。
class PanelTabStrip extends StatefulWidget {
  const PanelTabStrip({
    super.key,
    required this.side,
    this.bounds,
    this.laneBounds,
    this.vertical = false,
    this.floating = false,
    this.showHandle = false,
    this.maxWidth = 260,
  });

  /// 这条页签条属于哪一侧（左 / 右面板泳道）。
  final WorkspacePanelSide side;

  /// **摆放它的容器**（容器局部坐标）：钉住时是这条泳道；
  /// 「允许移出泳道」的悬浮态是整个工作台视口。
  ///
  /// 为 `null` = 不参与摆放（四边栏模式下它就是抽屉里的一条内联页签）。
  /// 那时也**不该有拖动把手** —— 没有容器坐标就没法回答「松手落在哪条边」。
  final PanelBarBounds? bounds;

  /// 它所属的那条泳道的矩形，**与 [bounds] 同一坐标系**。
  ///
  /// 换边停靠的判定必须用泳道矩形（契约的 `dockCandidate` 收的是
  /// `laneHost.getBoundingClientRect()`）：用视口矩形会让「不限制在泳道内」
  /// 的悬浮面板栏在**视口**边缘就吸附，于是它永远钉不到泳道自己的边上。
  final PanelBarBounds? laneBounds;

  /// 竖轨形态（钉在左 / 右两条边时）。
  final bool vertical;

  /// 悬浮态：自带底板与阴影。
  final bool floating;

  /// 是否画拖动把手。挂进栏头（title-mounted）时不画 ——
  /// 那一条本来就已经很挤，而且它此刻不能拖。
  final bool showHandle;

  /// 页签条的最大宽度（泳道窄时里面自己滚动）。
  final double maxWidth;

  /// 页签尺寸（neoview title-mounted 的 `size-7`）。
  static const double tabSize = PanelSwitcherTabs.iconSize;

  /// 拖动判定为「真的拖了」的最小位移（防误触：手抖一下不该换停靠边）。
  static const double dragSlop = 4.0;

  // ── 版式常量 ─────────────────────────────────────────────────────────────
  //
  // 这几颗数**不只**是本文件画图用的：栏头要按「这条页签条实际要占多宽」决定
  // 右边那几颗按钮让不让位（见 `titleMountedWidth` 与 `SwimlaneColumn._fitHeader`）。
  // 于是画图与算账必须读同一份数 —— 各写一套的结局是栏头按一份旧账留位置，
  // 最后一个图标被齐根裁掉。

  /// 页签左右各 1.5 的内边距。
  static const double tabHPadding = PanelSwitcherTabs.iconPadding;

  /// 插缝自身的宽（拖动时亮成 2.5，那 1px 不记账）。
  static const double dropSlotWidth = 1.5;

  /// 插缝左右各 1 的外边距。
  static const double dropSlotHMargin = 1.0;

  /// 底板左右各 2 的内边距。
  static const double stripHPadding = 2.0;

  /// 「已收起」入口：左右内边距、图标宽、图标与计数之间的缝、每个数字的宽。
  static const double hiddenHPadding = 4.0;
  static const double hiddenIconWidth = 14.0;
  static const double hiddenIconGap = 3.0;
  static const double hiddenDigitWidth = 7.0;

  /// 一个页签连着它前面那道插缝要占的宽。
  static double get tabStride =>
      tabSize + tabHPadding * 2 + dropSlotWidth + dropSlotHMargin * 2;

  /// 末尾那道「追加到末尾」的插缝。
  static double get trailingSlotWidth => dropSlotWidth + dropSlotHMargin * 2;

  /// 「已收起」那颗入口的宽（数字位数跟着收起的个数走）。
  static double hiddenMenuWidth(int hiddenCount) =>
      hiddenHPadding * 2 +
      hiddenIconWidth +
      hiddenIconGap +
      hiddenDigitWidth * '$hiddenCount'.length;

  /// **挂进栏头**（`pinned + dock: top`，本项目默认形态）这一档按内容取宽实际要占多宽。
  ///
  /// 内联时这条页签条是 `shrinkWrap` 的：给它一个上限，它只占自己要的那一段。
  /// 所以「还剩多少给标题、右边那几颗按钮要不要让位」必须拿**这个数**去算；
  /// 反过来先给标题预留一块、剩下的封顶给它，窄泳道上就会把图标裁掉。
  ///
  /// 面板隐藏后直接从面板栏彻底移除（不再保留隐藏入口图标），因此宽度只算可见面板。
  static double titleMountedWidth(
    WorkspacePanelSide side,
    WorkspaceBoardLayout board, {
    bool sortMode = false,
  }) {
    final registry = WorkspacePanelRegistry.I;
    final tabs = registry.panelsForSide(side, board).length;
    if (tabs == 0) return 0;

    final width =
        stripHPadding * 2 +
        (sortMode
            ? tabStride * tabs + trailingSlotWidth
            : (tabSize + tabHPadding * 2) * tabs);
    // 向上取整：栏头拿它判「装不装得下」，宁可提前一档让位，
    // 也不要差半个像素把最后一个图标裁掉。
    return width.ceilToDouble();
  }

  @override
  State<PanelTabStrip> createState() => _PanelTabStripState();
}

/// 面板图标的 tooltip。`canHideByRightClick` = 「右键面板图标收起该面板」这个功能
/// 当前生不生效（全局开关 `panelTabRightClickHide` 且这一块面板本身可隐藏）。
///
/// tooltip 必须跟着开关走：开着「右键隐藏」的字样、点下去什么都不发生，
/// 比不写那句话更难解释 —— 用户会以为是自己点歪了。
String _tooltipFor(WorkspacePanelDefinition panel, bool canHideByRightClick) =>
    '${panel.title}'
    '${panel.canMove ? '（编辑布局后长按排序 / 换泳道）' : ''}'
    '${canHideByRightClick ? '　右键隐藏' : ''}';

class _PanelTabStripState extends State<PanelTabStrip> {
  String? _dragging;
  int? _hoverIndex;
  bool _foreignHover = false;

  /// 拖动开始那一刻浮层的左上角（由 [PanelBarPositioner] 回报的实际位置）。
  Offset? _dragBase;

  /// 拖动中的实时位置（容器局部坐标）。
  Offset? _liveOffset;

  /// 最近一次布局摆出来的位置。拖动起点就是它 —— 不去复算。
  Offset? _renderedOffset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<WorkspaceCubit>();
    final state = context.watch<WorkspaceCubit>().state;
    final board = state.board;
    final registry = WorkspacePanelRegistry.I;

    final panels = registry.panelsForSide(widget.side, board);
    if (panels.isEmpty) return const SizedBox.shrink();

    final activeId =
        state.activePanel[widget.side.laneId] ??
        (panels.isEmpty ? null : panels.first.id);

    final sortMode = state.interaction.panelTabSortMode;
    // 「右键面板图标 = 收起该面板」的开关（与排序模式同一份交互配置）。
    // 可隐藏性本身还要看这一块面板允不允许收起（`canHide`），两件事在
    // `_buildTab` / `WorkspacePanelTabs` 里合成一处判断。
    final rightClickHideEnabled = state.interaction.panelTabRightClickHide;

    final tabs = <Widget>[];
    for (var i = 0; i < panels.length; i++) {
      tabs.add(_buildDropSlot(i, theme));
      tabs.add(
        _buildTab(
          panels[i],
          activeId,
          i,
          theme,
          cubit,
          sortMode,
          rightClickHideEnabled,
        ),
      );
    }
    tabs.add(_buildDropSlot(panels.length, theme));

    final children = <Widget>[
      if (widget.showHandle) ...[
        _buildHandle(context, theme, cubit),
        SizedBox(
          width: widget.vertical ? 0 : 2,
          height: widget.vertical ? 2 : 0,
        ),
      ],
      Flexible(
        child: sortMode
            // 排序模式：**原样**保留 `ListView` 那条路（含插缝、含
            // `LongPressDraggable`）。插缝在拖动时会亮起来给插入位提示，
            // 所以这一档不能换成 lens —— lens 是「按格位」的，插缝不占格位。
            ? ListView(
                scrollDirection: widget.vertical
                    ? Axis.vertical
                    : Axis.horizontal,
                primary: false,
                shrinkWrap: widget.bounds == null,
                children: tabs,
              )
            // 常态：选中态交给弹簧 lens，按住横移切面板。
            //
            // 插缝**不进 lens**（它不是目的地，只是拖动时的插入位提示；
            // 常态没有拖动，于是那一格让给它）。所以这里走
            // `SpringLensBar`，它的格位与内容自己排，插缝那一档仍在
            // 排序模式下才出现。
            : WorkspacePanelTabs(
                panels: panels,
                activeId: activeId,
                vertical: widget.vertical,
                canRightClickHide: rightClickHideEnabled,
                onSelected: (panel) =>
                    cubit.setActivePanel(widget.side.laneId, panel.id),
                onHide: (panel) => _hide(cubit, panel),
              ),
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.vertical ? 44 : widget.maxWidth,
        maxHeight: double.infinity,
      ),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final draggedId = details.data;
          if (draggedId == _dragging) return false;
          final panel = registry.find(draggedId);
          // 外层只接「跨侧拖进来、且没落在任何具体插入位上」的情况
          // （落在页签上时内层的落点先接到，它才知道准确的插入位）。
          return panel != null &&
              panel.canMove &&
              registry.effectivePanelLayout(panel, board).side != widget.side;
        },
        onAcceptWithDetails: (details) {
          setState(_clearDragState);
          // 落到本条页签条的空白处 = 追加到末尾。
          _acceptDrop(details.data, _panelCount(board));
        },
        onMove: (_) {
          if (!_foreignHover) setState(() => _foreignHover = true);
        },
        onLeave: (_) {
          if (_foreignHover) setState(() => _foreignHover = false);
        },
        builder: (context, candidate, rejected) {
          final body = AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: PanelTabStrip.stripHPadding,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: _foreignHover
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : widget.floating
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: widget.floating
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: widget.vertical
                ? Column(mainAxisSize: MainAxisSize.min, children: children)
                : Row(mainAxisSize: MainAxisSize.min, children: children),
          );

          // 拖动中：浮层跟光标走（位置由 positioner 的「实时位置」接管）。
          final bounds = widget.bounds;
          // 没有容器坐标（四边栏模式的内联页签）⇒ 不需要摆放，原样渲染。
          if (bounds == null) return body;

          return PanelBarPositioner(
            layout:
                state.layout.lanes[widget.side.laneId]?.panelBar ??
                const PanelBarLayout(),
            boundsOf: (_) => bounds,
            liveOffset: _liveOffset,
            onPositioned: (offset) => _renderedOffset = offset,
            child: body,
          );
        },
      ),
    );
  }

  void _clearDragState() {
    _dragging = null;
    _hoverIndex = null;
    _foreignHover = false;
  }

  int _panelCount(WorkspaceBoardLayout board) =>
      WorkspacePanelRegistry.I.panelsForSide(widget.side, board).length;

  // ── 拖动把手 ───────────────────────────────────────────────────────────

  Widget _buildHandle(
    BuildContext context,
    ThemeData theme,
    WorkspaceCubit cubit,
  ) {
    return MouseRegion(
      cursor: _liveOffset != null
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        onPanCancel: _handlePanCancel,
        // 右键与长按是**同一个菜单的两个入口**，不是两套行为：触摸屏上没有
        // `onSecondaryTapUp`，而这个把手的 `GestureDetector` 里没有别人注册长按，
        // 所以长按在这条把手上是空出来的（页签上的长按不行 —— 那里被
        // `LongPressDraggable` 的 220ms 拖动延时占了）。
        onSecondaryTapUp: (details) =>
            _openSettingsMenuAt(context, details.globalPosition, cubit),
        onLongPressStart: (details) =>
            _openSettingsMenuAt(context, details.globalPosition, cubit),
        child: Tooltip(
          message: t.workspace.panelBarHint,
          waitDuration: const Duration(milliseconds: 500),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: GlyphIcon(
              AppGlyphs.dragHandle,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    _dragBase = _renderedOffset ?? Offset.zero;
    setState(() => _liveOffset = _dragBase);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final base = _dragBase;
    if (base == null) return;
    setState(() {
      final current = _liveOffset ?? base;
      _liveOffset = current + details.delta;
    });
  }

  void _handlePanCancel() {
    setState(() {
      _liveOffset = null;
      _dragBase = null;
    });
  }

  /// 松手：够近就钉到那条边，否则转成**悬浮**（neoview 的同一套判定）。
  void _handlePanEnd(DragEndDetails details) {
    final live = _liveOffset;
    final base = _dragBase;
    final size = context.size;
    setState(() {
      _liveOffset = null;
      _dragBase = null;
    });
    if (live == null || base == null || size == null) return;
    // 手抖一下不该换停靠边。
    if ((live - base).distance < PanelTabStrip.dragSlop) return;

    final bounds = widget.bounds;
    final laneBounds = widget.laneBounds;
    if (bounds == null || laneBounds == null) return;

    final cubit = context.read<WorkspaceCubit>();
    final lane = cubit.state.layout.lanes[widget.side.laneId];
    if (lane == null) return;

    final candidate = panelBarDockCandidate(
      lane: laneBounds,
      x: live.dx + size.width / 2,
      y: live.dy + size.height / 2,
    );

    if (candidate != null) {
      cubit.setLanePanelBar(
        widget.side.laneId,
        lane.panelBar.copyWith(mode: PanelBarMode.pinned, dock: candidate),
      );
      return;
    }

    final percent = panelBarPercentFromOffset(
      bounds: bounds,
      left: live.dx,
      top: live.dy,
      barWidth: size.width,
      barHeight: size.height,
    );
    cubit.setLanePanelBar(
      widget.side.laneId,
      lane.panelBar.copyWith(
        mode: PanelBarMode.floating,
        positionX: percent.x,
        positionY: percent.y,
      ),
    );
  }

  // ── 右键菜单：钉住 / 悬浮、是否限制在本泳道、换成哪条边 ─────────────────

  Future<void> _openSettingsMenuAt(
    BuildContext context,
    Offset globalPosition,
    WorkspaceCubit cubit,
  ) async {
    final lane = cubit.state.layout.lanes[widget.side.laneId];
    if (lane == null) return;
    final bar = lane.panelBar;
    final pinned = bar.mode == PanelBarMode.pinned;
    final sortMode = cubit.state.interaction.panelTabSortMode;

    void setBar(PanelBarLayout next) =>
        cubit.setLanePanelBar(widget.side.laneId, next);

    // 走 [showCommonPopupMenu]（[CommonPopupRoute] 那份 FlClash 动画）——
    // 与栏头那颗 ⋮、文件管理器那张「更多」同一套：托盘从右键 / 长按那一点
    // 长出来、放不下时自己朝上翻，不再是 Fluent 的原地淡入缩放。
    await showCommonPopupMenu(
      context: context,
      position: globalPosition,
      items: [
        CommonPopupMenuItem(
          label: pinned ? t.workspace.switchToFloating : t.workspace.pinHere,
          glyph: AppGlyphs.pin,
          checked: pinned,
          onPressed: () => setBar(
            bar.copyWith(
              mode: pinned ? PanelBarMode.floating : PanelBarMode.pinned,
            ),
          ),
        ),
        CommonPopupMenuItem(
          label: bar.constrained
              ? t.workspace.allowLeaveLane
              : t.workspace.confineToThisLane,
          glyph: bar.constrained ? AppGlyphs.lock : AppGlyphs.lockOpen,
          onPressed: () => setBar(bar.copyWith(constrained: !bar.constrained)),
        ),
        const CommonPopupMenuItem.divider(),
        CommonPopupMenuItem(
          // 父行只留短名，解释下移到第二行 —— 菜单宽只由 `label` 定，
          // 整段塞进单行会被截断。
          label: t.workspace.sortMode,
          glyph: AppGlyphs.sort,
          checked: sortMode,
          content: CommonPopupMenuTitle(
            label: t.workspace.sortMode,
            hint: sortMode
                ? t.workspace.restoreSwipeAfterExit
                : t.workspace.longPressDragReorder,
          ),
          onPressed: () {
            // 排序模式是**工作台交互**设置（不是本条 bar 的摆放），所以走
            // `setInteraction` 而不是 `setLanePanelBar` —— 它管的是「所有
            // 泳道的页签条」，跟着 `workspace_layout.json` 的 `interaction` 块走。
            final interaction = cubit.state.interaction;
            cubit.setInteraction(
              interaction.copyWith(
                panelTabSortMode: !interaction.panelTabSortMode,
              ),
            );
          },
        ),
        const CommonPopupMenuItem.divider(),
        for (final dock in PanelBarDock.values)
          CommonPopupMenuItem(
            label: t.workspace.dockToLabel(label: _dockLabel(dock)),
            glyph: _dockIcon(dock),
            checked: pinned && bar.dock == dock,
            onPressed: () =>
                setBar(bar.copyWith(mode: PanelBarMode.pinned, dock: dock)),
          ),
      ],
    );
  }

  static Glyph _dockIcon(PanelBarDock dock) => switch (dock) {
    PanelBarDock.left => AppGlyphs.columnsTwo,
    PanelBarDock.right => AppGlyphs.columnsTwo,
    PanelBarDock.top => AppGlyphs.rowsTwo,
    PanelBarDock.bottom => AppGlyphs.rowsTwo,
  };

  static String _dockLabel(PanelBarDock dock) => switch (dock) {
    PanelBarDock.left => '左侧',
    PanelBarDock.right => '右侧',
    PanelBarDock.top => '顶部',
    PanelBarDock.bottom => '底部',
  };

  // ── 插入位 ─────────────────────────────────────────────────────────────

  /// 两个页签之间的插入位（拖动时亮成一根线）。
  Widget _buildDropSlot(int index, ThemeData theme) {
    final active = _hoverIndex == index;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _shouldAcceptAt(details.data),
      onAcceptWithDetails: (details) => _acceptDrop(details.data, index),
      builder: (context, candidate, rejected) {
        final highlight = active || candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.vertical
              ? 16
              : (highlight ? 2.5 : PanelTabStrip.dropSlotWidth),
          height: widget.vertical ? (highlight ? 2.5 : 1.5) : 16,
          margin: const EdgeInsets.symmetric(
            horizontal: PanelTabStrip.dropSlotHMargin,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: highlight
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }

  /// 这个插入位接不接受 [draggedId]。
  ///
  /// 同侧（**本条页签条自己正在拖**）与跨侧都要接：前者是**轨内换位**，
  /// 后者是**换泳道**。判断依据只能是「这个面板能不能移动」。
  ///
  /// 曾经写的是 `draggedId != _dragging` —— 而 `_dragging` 装的正是被拖的那个
  /// 面板 id，于是这一行把「本条自己正在拖」这一支**整个拒掉**；外层又只接
  /// 跨侧（`draggedId == _dragging` 直接 false），结果是**轨内换位完全不可达**：
  /// 拖动时每个落点都拒绝，整个手势静默失败，而界面上看不出任何异常。
  ///
  /// 也不能改成 `_dragging != null`：跨侧拖动时对面的 `_dragging` 是 `null`
  /// （每个 `PanelTabStrip` 各有各的 State），本条根本不知道谁在拖。
  bool _shouldAcceptAt(String draggedId) {
    final panel = WorkspacePanelRegistry.I.find(draggedId);
    return panel != null && panel.canMove;
  }

  /// 落进 [index] 这个插入位。
  ///
  /// 下标换算分两支：**同一个序列里换位**要把自己那一格扣掉
  /// （拖动时自己还在序列里，不扣就会偏一格）；**跨侧拖入**不用扣
  /// （[siblingIds] 已经把自己排除掉了）。
  void _acceptDrop(String panelId, int index) {
    final cubit = context.read<WorkspaceCubit>();
    final board = cubit.state.board;
    final registry = WorkspacePanelRegistry.I;
    final panels = registry.panelsForSide(widget.side, board);
    final currentIndex = panels.indexWhere((p) => p.id == panelId);

    setState(_clearDragState);

    final siblings = [
      for (final p in panels)
        if (p.id != panelId) p.id,
    ];
    final target = currentIndex >= 0 && index > currentIndex
        ? index - 1
        : index;

    cubit.placePanel(
      panelId: panelId,
      side: widget.side,
      siblingIds: siblings,
      insertIndex: target,
    );
    cubit.setActivePanel(widget.side.laneId, panelId);
  }

  // ── 页签 ───────────────────────────────────────────────────────────────

  Widget _buildTab(
    WorkspacePanelDefinition panel,
    String? activeId,
    int index,
    ThemeData theme,
    WorkspaceCubit cubit,
    bool sortMode,
    bool rightClickHideEnabled,
  ) {
    final active = panel.id == activeId;
    final canHideByRightClick = panel.canHide && rightClickHideEnabled;
    final tooltip = _tooltipFor(panel, canHideByRightClick);

    final button = Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PanelTabStrip.tabHPadding,
          vertical: 2,
        ),
        child: Material(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => cubit.setActivePanel(widget.side.laneId, panel.id),
            onSecondaryTap: canHideByRightClick
                ? () => _hide(cubit, panel)
                : null,
            child: SizedBox(
              width: PanelTabStrip.tabSize,
              height: PanelTabStrip.tabSize,
              child: AnimatedGlyphIcon(
                panel.icon,
                filled: active,
                size: 16,
                color: active
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );

    // 页签**自己**是「插到我前面」的落点：命中测试已经确定了指针落在哪个页签上，
    // 于是插入位不需要再拿光标去和每个页签的矩形比一遍。
    //
    // 这一层对**所有**页签都装，包括 `canMove: false` 的那些（上游整页：
    // 书架 / 发现 / 工具）。「不能移动」是说它自己不能被拖走，**不是**说
    // 别的东西不能插到它前面 —— 早先版本在这里提前 return，于是这几个页签
    // 落在拖放系统之外，往它们身上拖会掉回外层那条「追加到末尾」的路
    // （5 个面板里有 3 个是这一类，等于精确插入位大半是失效的）。
    final dropBefore = MouseRegion(
      onEnter: (_) {
        if (_dragging != null && _dragging != panel.id) {
          setState(() => _hoverIndex = index);
        }
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => _shouldAcceptAt(details.data),
        onAcceptWithDetails: (details) => _acceptDrop(details.data, index),
        builder: (context, candidate, rejected) => button,
      ),
    );

    // **只有排序模式才装拖动外壳。** 常态的手势位让给 lens 的跟手拖动
    // （两片区域物理互斥）；而这一档常态根本不会走到这里 —— 见 `build`
    // 里按 `sortMode` 分流的那一段。
    if (!panel.canMove || !sortMode) return dropBefore;

    return LongPressDraggable<String>(
      data: panel.id,
      delay: const Duration(milliseconds: 220),
      onDragStarted: () => setState(() => _dragging = panel.id),
      onDragEnd: (_) => setState(_clearDragState),
      onDraggableCanceled: (velocity, offset) => setState(_clearDragState),
      feedback: Material(
        color: Colors.transparent,
        child: _DragChip(panel: panel, theme: theme),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: button),
      child: dropBefore,
    );
  }

  /// 隐藏一个面板（右键）。最后一条页签不能被隐藏 —— 否则这条泳道变空。
  void _hide(WorkspaceCubit cubit, WorkspacePanelDefinition panel) {
    final board = cubit.state.board;
    final panels = WorkspacePanelRegistry.I.panelsForSide(widget.side, board);
    if (panels.length <= 1) return;
    cubit.setPanelVisible(panel.id, false);
    if (cubit.state.activePanel[widget.side.laneId] == panel.id) {
      final fallback = panels.firstWhere((p) => p.id != panel.id);
      cubit.setActivePanel(widget.side.laneId, fallback.id);
    }
  }
}

/// 拖动时跟着光标走的小标签。
class _DragChip extends StatelessWidget {
  const _DragChip({required this.panel, required this.theme});

  final WorkspacePanelDefinition panel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(
            panel.icon,
            size: 14,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 6),
          Text(
            panel.title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
