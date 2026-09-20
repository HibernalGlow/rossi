import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';

/// **面板操作栏** —— 泳道里的那一条面板页签。
///
/// 它同时是三件事：
///
/// 1. **面板切换**：左键点页签；
/// 2. **面板搬运**：按住页签拖动 —— 轨内换位，或拖到**另一条泳道**的页签条上；
/// 3. **它自己的摆放**：按住把手拖动 = 钉到某条边或转成悬浮（neoview 的
///    `ReaderPanelBar`）；右键把手 = 切换「钉住 / 悬浮」与「是否限制在本泳道内」。
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
  static const double tabSize = 28.0;

  /// 拖动判定为「真的拖了」的最小位移（防误触：手抖一下不该换停靠边）。
  static const double dragSlop = 4.0;

  // ── 版式常量 ─────────────────────────────────────────────────────────────
  //
  // 这几颗数**不只**是本文件画图用的：栏头要按「这条页签条实际要占多宽」决定
  // 右边那几颗按钮让不让位（见 `titleMountedWidth` 与 `SwimlaneColumn._fitHeader`）。
  // 于是画图与算账必须读同一份数 —— 各写一套的结局是栏头按一份旧账留位置，
  // 最后一个图标被齐根裁掉。

  /// 页签左右各 1.5 的内边距。
  static const double tabHPadding = 1.5;

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
  /// 问的是与 `build` 同一份记账（注册表 + 这一侧的隐藏项），所以「这一档到底
  /// 有没有页签条」两处是同一个答案：`panels.isEmpty && hidden.isEmpty` 时
  /// `build` 直接 `SizedBox.shrink()`，这里也返回 0。
  static double titleMountedWidth(
    WorkspacePanelSide side,
    WorkspaceBoardLayout board,
  ) {
    final registry = WorkspacePanelRegistry.I;
    final tabs = registry.panelsForSide(side, board).length;
    final hidden = registry
        .hiddenPanels(board)
        .where((p) => registry.effectivePanelLayout(p, board).side == side)
        .length;
    if (tabs == 0 && hidden == 0) return 0;

    final width =
        stripHPadding * 2 +
        tabStride * tabs +
        trailingSlotWidth +
        (hidden > 0 ? hiddenMenuWidth(hidden) : 0);
    // 向上取整：栏头拿它判「装不装得下」，宁可提前一档让位，
    // 也不要差半个像素把最后一个图标裁掉。
    return width.ceilToDouble();
  }

  @override
  State<PanelTabStrip> createState() => _PanelTabStripState();
}

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
    final hidden = registry
        .hiddenPanels(board)
        .where(
          (p) => registry.effectivePanelLayout(p, board).side == widget.side,
        )
        .toList();

    if (panels.isEmpty && hidden.isEmpty) return const SizedBox.shrink();

    final activeId =
        state.activePanel[widget.side.laneId] ??
        (panels.isEmpty ? null : panels.first.id);

    final tabs = <Widget>[];
    for (var i = 0; i < panels.length; i++) {
      tabs.add(_buildDropSlot(i, theme));
      tabs.add(_buildTab(panels[i], activeId, i, theme, cubit));
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
        // 用 `ListView` 而不是 `SingleChildScrollView`：只有前者能 `shrinkWrap`。
        // **内联**（挂进栏头 / 抽屉，`bounds == null`）时必须按内容取宽 ——
        // 视口默认**撑满**给它的主轴宽度，于是 2 个页签也要掉 260px，
        // 而栏头那一行总共只有 340–380px：页签条把预算吃光，
        // 栏头再多加一颗按钮就顶出黄黑斜纹。
        // 自己摆放（钉边 / 悬浮）那一档不收缩：那里的宽度是摆位算出来的，
        // 撑满才是想要的（拖动时落点要铺满整根轨）。
        child: ListView(
          scrollDirection: widget.vertical ? Axis.vertical : Axis.horizontal,
          primary: false,
          shrinkWrap: widget.bounds == null,
          children: tabs,
        ),
      ),
      if (hidden.isNotEmpty) _buildHiddenMenu(theme, hidden, cubit),
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
        onSecondaryTapUp: (details) =>
            _openSettingsMenu(context, details, cubit),
        child: Tooltip(
          message: '面板栏（拖动换边或转悬浮，右键设置）',
          waitDuration: const Duration(milliseconds: 500),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: Icon(
              widget.vertical
                  ? Icons.drag_indicator_rounded
                  : Icons.drag_handle_rounded,
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

  Future<void> _openSettingsMenu(
    BuildContext context,
    TapUpDetails details,
    WorkspaceCubit cubit,
  ) async {
    final lane = cubit.state.layout.lanes[widget.side.laneId];
    if (lane == null) return;
    final bar = lane.panelBar;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final action = await showMenu<_PanelBarAction>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_PanelBarAction>(
          value: _PanelBarAction.toggleMode,
          child: _menuRow(
            bar.mode == PanelBarMode.pinned
                ? Icons.push_pin_outlined
                : Icons.push_pin,
            bar.mode == PanelBarMode.pinned ? '改为悬浮' : '固定到当前位置',
          ),
        ),
        PopupMenuItem<_PanelBarAction>(
          value: _PanelBarAction.toggleConstrained,
          child: _menuRow(
            bar.constrained ? Icons.lock_outline : Icons.lock_open_outlined,
            bar.constrained ? '允许移出泳道' : '限制在本泳道',
          ),
        ),
        const PopupMenuDivider(),
        for (final dock in PanelBarDock.values)
          PopupMenuItem<_PanelBarAction>(
            value: _PanelBarAction.dockTo(dock),
            child: _menuRow(
              _dockIcon(dock),
              '停靠到${_dockLabel(dock)}',
              checked: bar.mode == PanelBarMode.pinned && bar.dock == dock,
            ),
          ),
      ],
    );
    if (action == null) return;

    switch (action.kind) {
      case _PanelBarActionKind.toggleMode:
        if (bar.mode == PanelBarMode.pinned) {
          cubit.setLanePanelBar(
            widget.side.laneId,
            bar.copyWith(mode: PanelBarMode.floating),
          );
        } else {
          // 「固定到当前位置」= 钉回它记录下来的那条边。
          cubit.setLanePanelBar(
            widget.side.laneId,
            bar.copyWith(mode: PanelBarMode.pinned),
          );
        }
      case _PanelBarActionKind.toggleConstrained:
        cubit.setLanePanelBar(
          widget.side.laneId,
          bar.copyWith(constrained: !bar.constrained),
        );
      case _PanelBarActionKind.dock:
        cubit.setLanePanelBar(
          widget.side.laneId,
          bar.copyWith(mode: PanelBarMode.pinned, dock: action.dock!),
        );
    }
  }

  Widget _menuRow(IconData icon, String label, {bool checked = false}) {
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        if (checked) const Icon(Icons.check_rounded, size: 15),
      ],
    );
  }

  static IconData _dockIcon(PanelBarDock dock) => switch (dock) {
    PanelBarDock.left => Icons.vertical_split_rounded,
    PanelBarDock.right => Icons.vertical_split_rounded,
    PanelBarDock.top => Icons.horizontal_split_rounded,
    PanelBarDock.bottom => Icons.horizontal_split_rounded,
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
  ) {
    final active = panel.id == activeId;
    final tooltip =
        '${panel.title}'
        '${panel.canMove ? '（按住拖动可排序 / 拖到另一条泳道的页签条可换泳道）' : ''}'
        '${panel.canHide ? '　右键收起' : ''}';

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
            onSecondaryTap: panel.canHide ? () => _hide(cubit, panel) : null,
            child: SizedBox(
              width: PanelTabStrip.tabSize,
              height: PanelTabStrip.tabSize,
              child: Icon(
                panel.icon,
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

    if (!panel.canMove) return dropBefore;

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

  Widget _buildHiddenMenu(
    ThemeData theme,
    List<WorkspacePanelDefinition> hidden,
    WorkspaceCubit cubit,
  ) {
    return PopupMenuButton<String>(
      tooltip: '已收起的面板',
      onSelected: (id) {
        cubit.setPanelVisible(id, true);
        cubit.setActivePanel(widget.side.laneId, id);
      },
      itemBuilder: (context) => [
        for (final panel in hidden)
          PopupMenuItem<String>(
            value: panel.id,
            child: Row(
              children: [
                Icon(panel.icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(panel.title, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PanelTabStrip.hiddenHPadding,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_rounded,
              size: PanelTabStrip.hiddenIconWidth,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: PanelTabStrip.hiddenIconGap),
            Text(
              '${hidden.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 收起一个面板（右键）。最后一条页签不能被收起 —— 否则这条泳道就
  /// 既没法切面板、也没法恢复。
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

/// 右键菜单的动作。
enum _PanelBarActionKind { toggleMode, toggleConstrained, dock }

class _PanelBarAction {
  const _PanelBarAction._(this.kind, this.dock);

  static const _PanelBarAction toggleMode = _PanelBarAction._(
    _PanelBarActionKind.toggleMode,
    null,
  );
  static const _PanelBarAction toggleConstrained = _PanelBarAction._(
    _PanelBarActionKind.toggleConstrained,
    null,
  );

  static _PanelBarAction dockTo(PanelBarDock dock) =>
      _PanelBarAction._(_PanelBarActionKind.dock, dock);

  final _PanelBarActionKind kind;
  final PanelBarDock? dock;
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
          Icon(
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
