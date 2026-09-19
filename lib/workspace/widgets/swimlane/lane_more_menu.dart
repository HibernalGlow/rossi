import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';

/// 「常规宽度」输入框的判据锚点。
///
/// 判据按 key 找它，而不是 `find.byType(TextField)`：`TextField` 这个名字
/// `material_ui` 与 `flutter/material` 各有一份，测试里 import 的是哪一份
/// 决定它找不找得到。
const Key laneWidthFieldKey = ValueKey<String>('lane-width-field');

/// 泳道栏头的「更多」菜单：这条泳道动作的完整清单。
///
/// 项集对齐 neoview 的 `ReaderLaneMoreMenu`
/// （`src/nodes/neoview/features/workspace/ReaderSwimlaneWorkspace.tsx`）：
/// 独占 → 常规宽度 / 恢复默认宽度 → 操作栏（面板栏）→ 折叠。
/// **唯独少了参考里的「窗口控件」那一节**（归属泳道 / 用顶部标题栏 / 收起按钮）——
/// 用户明确要求先不做。
///
/// ## 为什么面板栏那一节要搬进这里
///
/// 参考把它放在**面板栏自己的**右键菜单上（`ReaderPanelBar`）。本项目默认形态是
/// 「面板栏挂进栏头」，而挂进栏头时**刻意不画拖动把手**
/// （`PanelTabStrip(showHandle: false)`）—— 没有把手就没有右键目标，于是
/// 「把页签条挪到别的边 / 转成悬浮」在默认布局下**根本不可达**：那套记账
/// （`panelBarMode / panelBarDock / panelBarConstrained`）读得到、存得下，
/// 就是改不动。搬进泳道菜单是补上这条通路。
///
/// ## 为什么独占项读的是记账，不是生效值
///
/// `effectiveSoloLaneId` 还要求「同时是激活泳道」。用它做标签的话，一条
/// 「solo 记着但当前没生效」的泳道会显示「独占该栏」，按下去却是**关掉**它 ——
/// 标签必须与 `toggleSoloLane` 实际要做的那件事一致。
class LaneMoreMenu extends StatelessWidget {
  const LaneMoreMenu({
    super.key,
    required this.laneId,
    required this.viewportWidth,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.panelSide,
  });

  final String laneId;

  /// 视口宽：阅读器泳道记的是**视口比例**，宽度输入框要把像素换算回比例，
  /// 只有宿主拿得到这个数（`SwimlaneWorkspace` 的条带 LayoutBuilder）。
  final double viewportWidth;

  /// 折叠 / 独占走宿主传下来的回调，而不是自己调 cubit：这两个动作在
  /// `SwimlaneWorkspace` 那一层还捎带着「激活这条泳道」的记账，
  /// 在这里另开一条路会让同一个按钮有两种结果。
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final VoidCallback? onResetWidth;

  /// 有面板的泳道才有面板栏那一节（阅读器泳道没有）。
  final WorkspacePanelSide? panelSide;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '该泳道 (More)',
      itemBuilder: (context) => _buildItems(context),
      onSelected: (value) => _apply(context, value),
      child: Padding(
        // 刻意不用 `IconButton`：栏头那一行的预算已经很紧（见
        // `SwimlaneColumn._buildHeader` 里给页签条算宽的那段），
        // 这颗按钮只值 24px —— 与 `PanelTabStrip` 的「已收起」入口同一档。
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          Icons.more_vert_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildItems(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    final state = cubit.state;
    final lane = state.layout.lanes[laneId];
    if (lane == null) return const <PopupMenuEntry<String>>[];

    final solo = state.layout.soloLaneId == laneId;
    final bar = lane.panelBar;

    return [
      _item(
        value: 'solo',
        icon: solo
            ? Icons.center_focus_strong_rounded
            : Icons.center_focus_weak_rounded,
        label: solo ? '退出独占' : '独占该栏',
        checked: solo,
      ),
      const PopupMenuDivider(),
      // 宽度这一项点下去**不能**收起菜单（里面住着输入框）。
      _StaticMenuItem(child: _LaneWidthField(laneId: laneId, viewportWidth: viewportWidth)),
      _item(
        value: 'reset',
        icon: Icons.replay_rounded,
        label: '恢复默认宽度',
        enabled: onResetWidth != null,
        hint: '与双击栏头标题同一条路',
      ),
      if (panelSide != null) ...[
        const PopupMenuDivider(),
        _item(
          value: 'barMode',
          icon: bar.mode == PanelBarMode.pinned
              ? Icons.push_pin_outlined
              : Icons.push_pin,
          label: bar.mode == PanelBarMode.pinned ? '面板栏改为悬浮' : '面板栏固定到当前位置',
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
        _item(
          value: 'barReset',
          icon: Icons.undo_rounded,
          label: '恢复面板栏默认位置',
          hint: '回到「挂进栏头」这个默认形态',
        ),
      ],
      const PopupMenuDivider(),
      _item(
        value: 'collapse',
        icon: Icons.vertical_align_center_rounded,
        label: lane.collapsed ? '展开泳道' : '折叠为紧凑条',
        checked: lane.collapsed,
      ),
    ];
  }

  void _apply(BuildContext context, String value) {
    final cubit = context.read<WorkspaceCubit>();
    final lane = cubit.state.layout.lanes[laneId];
    if (lane == null) return;
    final bar = lane.panelBar;

    if (value.startsWith('dock:')) {
      final dock = PanelBarDock.values.firstWhere(
        (candidate) => candidate.name == value.substring('dock:'.length),
      );
      // 停靠与「钉住」是一件事的两半：从悬浮态点某条边就该同时钉回去 ——
      // 与拖动把手松手时 `panelBarDockCandidate` 那条路径同一个结果。
      cubit.setLanePanelBar(
        laneId,
        bar.copyWith(mode: PanelBarMode.pinned, dock: dock),
      );
      return;
    }

    switch (value) {
      case 'solo':
        onToggleSolo();
      case 'collapse':
        onToggleCollapse();
      case 'reset':
        onResetWidth?.call();
      case 'barMode':
        cubit.setLanePanelBar(
          laneId,
          bar.copyWith(
            mode: bar.mode == PanelBarMode.pinned
                ? PanelBarMode.floating
                : PanelBarMode.pinned,
          ),
        );
      case 'barConstrained':
        cubit.setLanePanelBar(laneId, bar.copyWith(constrained: !bar.constrained));
      case 'barReset':
        // 「默认」取的是**本项目**的默认（钉在顶部 = 挂进栏头），不是参考里那个
        // 悬浮默认值 —— 见 `PanelBarDock.defaultDock` 的说明。
        cubit.setLanePanelBar(laneId, const PanelBarLayout());
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

  /// 次要说明：只在「这条动作另有入口」时给一句（比如双击标题）。
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

/// 一项**点了不收起菜单**的菜单项。
///
/// `PopupMenuItemState.handleTap` 无条件 `Navigator.pop`，与 `value` 是否为空
/// **无关** —— 于是「不给 value」并不是「这一项不选中」，而是「选中并关掉菜单、
/// 什么也没返回」。放进输入框的那一项上，症状是鼠标点上去菜单先消失，
/// 文本框连焦点都拿不到。
class _StaticMenuItem extends PopupMenuItem<String> {
  const _StaticMenuItem({required super.child});

  @override
  PopupMenuItemState<String, PopupMenuItem<String>> createState() =>
      _StaticMenuItemState();
}

class _StaticMenuItemState extends PopupMenuItemState<String, _StaticMenuItem> {
  @override
  void handleTap() {
    // 什么都不做：这一项的内容（输入框）自己处理指针事件。
  }
}

/// 「常规宽度」输入框：改这一条泳道的宽度（参考里的 `commitWidth` 是 onBlur）。
class _LaneWidthField extends StatefulWidget {
  const _LaneWidthField({required this.laneId, required this.viewportWidth});

  final String laneId;
  final double viewportWidth;

  @override
  State<_LaneWidthField> createState() => _LaneWidthFieldState();
}

class _LaneWidthFieldState extends State<_LaneWidthField> {
  late final WorkspaceCubit _cubit;
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// 打开菜单时的宽度（也是「有没有改过」的基准）。
  late int _seed;

  /// 已经落过账就不重复落：失焦与回车会连着来，销毁时还会再来一次。
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    // cubit 在 initState 就抓在手里：`dispose` 里还要用它（那时
    // `context` 已经不能读了），而它比这个菜单活得久。
    _cubit = context.read<WorkspaceCubit>();
    final lane = _cubit.state.layout.lanes[widget.laneId];
    _seed = (lane?.resolveWidth(widget.viewportWidth) ?? 0).round();
    _controller = TextEditingController(text: '$_seed');
    _focusNode.addListener(
      () {
        if (!_focusNode.hasFocus) _commit();
      },
    );
  }

  @override
  void dispose() {
    // 输入完直接点菜单别处 / 按 Esc：焦点不一定还在文本框上，
    // 于是「失焦即落账」这条路走不到。销毁时补一次，用户看到的
    // 就是「我打的数生效了」，而不是「菜单一关数字又弹回去」。
    _commit();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (_committed) return;
    final px = int.tryParse(_controller.text.trim());
    if (px == null || px == _seed) return;
    _committed = true;
    final laneId = widget.laneId;
    final viewportWidth = widget.viewportWidth;
    // emit 推到**下一帧**：这两条路都可能在菜单路由被摘掉的那一帧里走到
    // （`Overlay` 在自己的 build 里摘节点，失焦也发生在那前后），
    // 在那里同步改状态会撞上「build 期间 markNeedsBuild」的断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cubit.setLaneWidth(laneId, px.toDouble(), viewportWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lane = context.select<WorkspaceCubit, LaneConfig?>(
      (c) => c.state.layout.lanes[widget.laneId],
    );
    final min = lane?.minWidth ?? 0;
    final max = lane?.maxWidth ?? 0;

    return Row(
      children: [
        Icon(
          Icons.straighten_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        const Text('常规宽度', style: TextStyle(fontSize: 12)),
        const Spacer(),
        SizedBox(
          width: 62,
          child: TextField(
            key: laneWidthFieldKey,
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _committed = false),
            onSubmitted: (_) {
              _commit();
              _focusNode.unfocus();
            },
          ),
        ),
        const SizedBox(width: 4),
        Text('px', style: theme.textTheme.labelSmall),
        const SizedBox(width: 6),
        // 夹取范围是这条泳道自己记的 min/max（`setLaneWidth` 按它夹）。
        Text(
          '${min.round()}–${max.round()}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
