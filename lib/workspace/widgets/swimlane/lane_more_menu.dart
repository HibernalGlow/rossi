import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';

/// 泳道栏头的「更多」菜单：这条泳道动作的**完整清单**。
///
/// ## 为什么需要它
///
/// 栏头那一行只塞得下 独占 / 折叠 两颗按钮，于是其余动作此前只有两条入口，
/// 而且都发现不了：
///
/// - **重置宽度**只有「双击标题」，界面上没有任何提示；
/// - **面板栏换停靠边 / 转悬浮**只能右键那个拖动把手，而默认形态
///   （`pinned + dock: top`，页签条挂进栏头）**刻意不画把手**
///   （`PanelTabStrip(showHandle: false)`，见 `SwimlaneColumn._buildHeader`）。
///   于是「把页签条从栏头里挪出去」在默认布局下**根本不可达** ——
///   用户只能接受这一种版式。
///
/// ## 为什么独占 / 折叠在菜单里重复一份
///
/// 菜单是清单，不是补充：少一项就会变成「有时候这里能做、有时候得去栏头找」。
///
/// 但这两项的**标签**读的是记账（`layout.soloLaneId`）而不是栏头用的
/// `effectiveSoloLaneId`：后者还要求「同时是激活泳道」。用后者做标签的话，
/// 一条「solo 记着但没生效」的泳道会显示「独占该栏」，按下去却把它**关掉** ——
/// 标签必须与 `toggleSoloLane` 实际要做的那件事一致。
///
/// ## 这里**没有**什么
///
/// 全屏 / 最小化那类窗口控件。它们改的是**窗口**而不是这条泳道，
/// 归桌面外壳（`ADR-0013`）。
class LaneMoreMenu extends StatelessWidget {
  const LaneMoreMenu({
    super.key,
    required this.laneId,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.panelSide,
  });

  final String laneId;

  /// 折叠 / 独占 / 重置宽度走宿主传下来的回调，而不是自己调 cubit：
  /// 这三个动作在 `SwimlaneWorkspace` 那一层还捎带着「激活这条泳道」的记账，
  /// 在这里另开一条路会让同一个按钮有两种结果。
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final VoidCallback? onResetWidth;

  /// 有面板的那条泳道才给面板栏那一节（阅读器泳道没有面板栏）。
  final WorkspacePanelSide? panelSide;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '该泳道 (More)',
      itemBuilder: (context) => _buildItems(context),
      onSelected: (value) => _apply(context, value),
      child: Padding(
        // 不用 `IconButton`：栏头在 360px 的泳道里本来就已经挤到标题省略号，
        // 这颗按钮只值 24px（与 `PanelTabStrip` 的「已收起」入口同一档）。
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          Icons.more_vert_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  WorkspaceCubit _cubit(BuildContext context) => context.read<WorkspaceCubit>();

  List<PopupMenuEntry<String>> _buildItems(BuildContext context) {
    final state = _cubit(context).state;
    final lane = state.layout.lanes[laneId];
    if (lane == null) return const <PopupMenuEntry<String>>[];

    final order = state.layout.laneOrder;
    final index = order.indexOf(laneId);
    final canMovePrev = index > 0;
    final canMoveNext = index >= 0 && index < order.length - 1;
    final solo = state.layout.soloLaneId == laneId;
    final bar = lane.panelBar;

    return [
      _item(
        value: 'reset',
        icon: Icons.aspect_ratio_rounded,
        label: '重置该栏宽度',
        enabled: onResetWidth != null,
        hint: '回到这条泳道的推荐宽度（与双击标题同一条路）',
      ),
      _item(
        value: 'movePrev',
        icon: Icons.chevron_left_rounded,
        label: '左移一位',
        enabled: canMovePrev,
      ),
      _item(
        value: 'moveNext',
        icon: Icons.chevron_right_rounded,
        label: '右移一位',
        enabled: canMoveNext,
      ),
      const PopupMenuDivider(),
      _item(
        value: 'solo',
        icon: solo
            ? Icons.center_focus_strong_rounded
            : Icons.center_focus_weak_rounded,
        label: solo ? '退出独占' : '独占该栏',
        checked: solo,
      ),
      _item(
        value: 'collapse',
        icon: Icons.vertical_align_center_rounded,
        label: lane.collapsed ? '展开泳道' : '折叠为紧凑条',
        checked: lane.collapsed,
      ),
      if (panelSide != null) ...[
        const PopupMenuDivider(),
        _item(
          value: 'barMode',
          icon: bar.mode == PanelBarMode.pinned
              ? Icons.push_pin_outlined
              : Icons.push_pin,
          label: bar.mode == PanelBarMode.pinned ? '面板栏改为悬浮' : '面板栏固定',
          hint: bar.mode == PanelBarMode.pinned ? null : '钉回它记录下来的那条边',
        ),
        _item(
          value: 'barConstrained',
          icon: bar.constrained ? Icons.lock_outline : Icons.lock_open_outlined,
          label: bar.constrained ? '允许面板栏移出泳道' : '把面板栏限制在泳道内',
          checked: !bar.constrained,
        ),
        for (final dock in PanelBarDock.values)
          _item(
            value: 'dock:${dock.name}',
            icon: _dockIcon(dock),
            label: '面板栏停靠${_dockLabel(dock)}',
            checked: bar.mode == PanelBarMode.pinned && bar.dock == dock,
          ),
      ],
    ];
  }

  void _apply(BuildContext context, String value) {
    final cubit = _cubit(context);
    final state = cubit.state;
    final lane = state.layout.lanes[laneId];
    if (lane == null) return;

    if (value.startsWith('dock:')) {
      final dock = PanelBarDock.values.firstWhere(
        (candidate) => candidate.name == value.substring('dock:'.length),
      );
      // 停靠与「钉住」是一件事的两半：从悬浮态点某条边，就该同时钉回去
      // （与拖动把手松手时的 `panelBarDockCandidate` 那条路径同一个结果）。
      cubit.setLanePanelBar(
        laneId,
        lane.panelBar.copyWith(mode: PanelBarMode.pinned, dock: dock),
      );
      return;
    }

    switch (value) {
      case 'reset':
        onResetWidth?.call();
      case 'solo':
        onToggleSolo();
      case 'collapse':
        onToggleCollapse();
      case 'movePrev' || 'moveNext':
        final order = state.layout.laneOrder;
        final index = order.indexOf(laneId);
        final target = value == 'movePrev' ? index - 1 : index + 1;
        if (index < 0 || target < 0 || target >= order.length) return;
        cubit.reorderLane(laneId, order[target]);
      case 'barMode':
        cubit.setLanePanelBar(
          laneId,
          lane.panelBar.copyWith(
            mode: lane.panelBar.mode == PanelBarMode.pinned
                ? PanelBarMode.floating
                : PanelBarMode.pinned,
          ),
        );
      case 'barConstrained':
        cubit.setLanePanelBar(
          laneId,
          lane.panelBar.copyWith(constrained: !lane.panelBar.constrained),
        );
    }
  }

  PopupMenuItem<String> _item({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
    bool checked = false,
    String? hint,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: _LaneMenuRow(
        icon: icon,
        label: label,
        checked: checked,
        hint: hint,
      ),
    );
  }

  static IconData _dockIcon(PanelBarDock dock) => switch (dock) {
    PanelBarDock.left || PanelBarDock.right => Icons.vertical_split_rounded,
    PanelBarDock.top || PanelBarDock.bottom => Icons.horizontal_split_rounded,
  };

  static String _dockLabel(PanelBarDock dock) => switch (dock) {
    PanelBarDock.left => '左侧',
    PanelBarDock.right => '右侧',
    PanelBarDock.top => '顶部',
    PanelBarDock.bottom => '底部',
  };
}

class _LaneMenuRow extends StatelessWidget {
  const _LaneMenuRow({
    required this.icon,
    required this.label,
    this.checked = false,
    this.hint,
  });

  final IconData icon;
  final String label;
  final bool checked;

  /// 次要说明：只在「这条动作有别的路能走到」时给一句（比如双击标题）。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              if (hint != null)
                Text(
                  hint!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        if (checked) const Icon(Icons.check_rounded, size: 15),
      ],
    );
  }
}
