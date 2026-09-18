import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

/// **面板切换工具栏** —— 停靠在泳道**顶栏**（栏头）里的一排面板页签。
///
/// 这是 neoview 的 `ReaderPanelBar` 在 `dock: "top"` 时的形态：
/// 面板栏被 portal 进泳道的 title slot，横向排成一列小页签
/// （`h-7 … flex-row … [&_[data-reader-panel-bar-tab]]:size-7`）。
/// 于是 Reader / 面板的动作跟着**自己那条泳道**走，而不是挂在侧边或全局工具条上。
///
/// 三个手势各占一个入口，互不抢：
/// - **左键**：切换该泳道的激活面板；
/// - **按住拖动**：轨内重排；拖到**另一条泳道**的页签条上 = 把面板搬过去；
/// - **右键**：把面板从页签条上收起（可从「已收起」入口恢复）。
///
/// 页签条本身**可横向滚动**：泳道被拖窄时页签不溢出、不换行、不报错。
class PanelTabStrip extends StatefulWidget {
  const PanelTabStrip({super.key, required this.side, this.maxWidth = 260});

  /// 这条页签条属于哪一侧（左 / 右面板泳道）。
  final WorkspacePanelSide side;

  /// 页签条的最大宽度（泳道窄时里面自己滚动）。
  final double maxWidth;

  /// 页签尺寸（neoview title-mounted 的 `size-7`）。
  static const double tabSize = 28.0;

  @override
  State<PanelTabStrip> createState() => _PanelTabStripState();
}

class _PanelTabStripState extends State<PanelTabStrip> {
  String? _dragging;
  int? _hoverIndex;
  bool _foreignHover = false;

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
        .where((p) => registry.effectivePanelLayout(p, board).side == widget.side)
        .toList();

    if (panels.isEmpty && hidden.isEmpty) return const SizedBox.shrink();

    final activeId = state.activePanel[widget.side.laneId] ??
        (panels.isEmpty ? null : panels.first.id);

    final tabs = <Widget>[];
    for (var i = 0; i < panels.length; i++) {
      tabs.add(_buildDropSlot(i, theme));
      tabs.add(_buildTab(panels[i], activeId, i, theme, cubit));
    }
    tabs.add(_buildDropSlot(panels.length, theme));

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final draggedId = details.data;
          if (draggedId == _dragging) return false;
          final panel = registry.find(draggedId);
          return panel != null &&
              panel.canMove &&
              registry.effectivePanelLayout(panel, board).side != widget.side;
        },
        onAcceptWithDetails: (details) {
          final draggedId = details.data;
          setState(() {
            _foreignHover = false;
            _dragging = null;
            _hoverIndex = null;
          });
          final siblings = [
            for (final p in panels)
              if (p.id != draggedId) p.id,
          ];
          cubit.placePanel(
            panelId: draggedId,
            side: widget.side,
            siblingIds: siblings,
            insertIndex: siblings.length,
          );
          cubit.setActivePanel(widget.side.laneId, draggedId);
        },
        onMove: (_) {
          if (!_foreignHover) setState(() => _foreignHover = true);
        },
        onLeave: (_) {
          if (_foreignHover) setState(() => _foreignHover = false);
        },
        builder: (context, candidate, rejected) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _foreignHover
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(mainAxisSize: MainAxisSize.min, children: tabs),
                  ),
                ),
                if (hidden.isNotEmpty) _buildHiddenMenu(theme, hidden, cubit),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 两个页签之间的插入位（拖动时亮成一根竖线）。
  Widget _buildDropSlot(int index, ThemeData theme) {
    final active = _hoverIndex == index;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _dragging != null && details.data != _dragging,
      onAcceptWithDetails: (details) {
        setState(() {
          _hoverIndex = null;
          _dragging = null;
        });
        _reorder(context.read<WorkspaceCubit>(), details.data, index);
      },
      builder: (context, candidate, rejected) {
        final highlight = active || candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: highlight ? 2.5 : 1.5,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 1),
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
        padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
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

    if (!panel.canMove) return button;

    return LongPressDraggable<String>(
      data: panel.id,
      delay: const Duration(milliseconds: 220),
      onDragStarted: () => setState(() => _dragging = panel.id),
      onDragEnd: (_) => setState(() {
        _dragging = null;
        _hoverIndex = null;
      }),
      onDraggableCanceled: (velocity, offset) => setState(() {
        _dragging = null;
        _hoverIndex = null;
      }),
      feedback: Material(
        color: Colors.transparent,
        child: _DragChip(panel: panel, theme: theme),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: button),
      child: MouseRegion(
        onEnter: (_) {
          if (_dragging != null && _dragging != panel.id) {
            setState(() => _hoverIndex = index);
          }
        },
        child: button,
      ),
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
                Text(panel.title, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_rounded,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 3),
            Text(
              '${hidden.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 轨内重排。插入下标要**扣掉自己**：拖动时自己已经在序列里，
  /// 不减掉这一位就会往错误的方向偏一格。
  void _reorder(WorkspaceCubit cubit, String panelId, int insertIndex) {
    final board = cubit.state.board;
    final panels = WorkspacePanelRegistry.I.panelsForSide(widget.side, board);
    final currentIndex = panels.indexWhere((p) => p.id == panelId);
    if (currentIndex < 0) return;

    final siblings = [
      for (final p in panels)
        if (p.id != panelId) p.id,
    ];
    final target = insertIndex > currentIndex ? insertIndex - 1 : insertIndex;
    if (target == currentIndex) return;

    cubit.placePanel(
      panelId: panelId,
      side: widget.side,
      siblingIds: siblings,
      insertIndex: target,
    );
  }

  void _hide(WorkspaceCubit cubit, WorkspacePanelDefinition panel) {
    final board = cubit.state.board;
    final panels = WorkspacePanelRegistry.I.panelsForSide(widget.side, board);
    // 最后一条页签不能被收起 —— 否则这条泳道就没法切面板，也没法恢复。
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
