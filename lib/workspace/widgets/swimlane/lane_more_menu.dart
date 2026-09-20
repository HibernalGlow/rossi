import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';

/// 「常规宽度」输入框的判据锚点。
///
/// 判据按 key 找它，而不是 `find.byType(TextField)`：`TextField` 这个名字
/// `material_ui` 与 `flutter/material` 各有一份，测试里 import 的是哪一份
/// 决定它找不找得到。
const Key laneWidthFieldKey = ValueKey<String>('lane-width-field');

/// 一条泳道「更多」菜单的**内容与分派**：这条泳道动作的完整清单。
///
/// 项集对齐 neoview 的 `ReaderLaneMoreMenu`
/// （`src/nodes/neoview/features/workspace/ReaderSwimlaneWorkspace.tsx`）：
/// 独占 → 常规宽度 / 恢复默认宽度 → 操作栏（面板栏）→ 折叠 → **工作台那一节**。
/// **唯独少了参考里的「窗口控件」那一节**（归属泳道 / 用顶部标题栏 / 收起按钮）——
/// 用户明确要求先不做。
///
/// 最后那一节（顶栏开关 + 退出工作台）不是从参考搬来的，是**可达性**逼出来的：
/// 工作台顶栏默认不画（`WorkspaceInteractionSettings.showTopChrome`），
/// 于是「退出工作台」在鼠标侧只剩这里一个入口。
///
/// 它是一个值对象而不是 widget，因为这份菜单有**两个入口**：栏头那颗
/// [`LaneMoreMenu`] 按钮（左键），以及右键栏头的任意一处。后者要的正是
/// 「按钮被挤掉 / 看不见时也能改回来」那条退路，所以两条路必须是同一份项集
/// 与同一套分派，不能各写一遍。
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
class LaneMenu {
  const LaneMenu({
    required this.laneId,
    required this.viewportWidth,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.panelSide,
    this.showsAsRail = false,
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

  /// 这条泳道此刻**是不是按紧凑轨画的**。
  ///
  /// 「折叠 / 展开」那一项的标签读的是**用户看见的形态**，不是 `collapsed` 这条
  /// 记账：Reader 独占时的切换栏会把其余泳道挤成 44px 的轨，可它们并没有被谁折叠，
  /// 而且宿主在那一档把 `onToggleCollapse` 换成了「激活这条泳道」
  /// （见 `SwimlaneWorkspace._buildLane`）。对着一条轨写「折叠为紧凑条」、
  /// 按下去却是展开，标签就成了假话 —— 只有画它的那一层知道此刻是哪一种。
  final bool showsAsRail;

  /// 在**全局坐标** [position] 处弹出这份菜单（右键栏头那条路）。
  Future<void> show(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final items = buildItems(context);
    // `showMenu` 不接受空列表（路由里 assert），泳道刚被摘掉时就是这样。
    if (items.isEmpty) return;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (value == null || !context.mounted) return;
    apply(context, value);
  }

  List<PopupMenuEntry<String>> buildItems(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    final state = cubit.state;
    final lane = state.layout.lanes[laneId];
    if (lane == null) return const <PopupMenuEntry<String>>[];

    final solo = state.layout.soloLaneId == laneId;
    final bar = lane.panelBar;
    final collapsed = lane.collapsed || showsAsRail;
    final chrome = state.interaction.showTopChrome;

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
      //
      // `BlocProvider.value` 不是多余的：菜单项被挂进 `Overlay` 那条路由，
      // 而 `Overlay` 在页面的 `BlocProvider<WorkspaceCubit>` **之上** ——
      // 从输入框自己的 context 往上找是找不到的（`itemBuilder` 收的是按钮的
      // context，所以列表本身建得出来，只有项内部的查找会炸）。
      _StaticMenuItem(
        child: BlocProvider<WorkspaceCubit>.value(
          value: cubit,
          child: _LaneWidthField(
            laneId: laneId,
            viewportWidth: viewportWidth,
          ),
        ),
      ),
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
        label: collapsed ? '展开泳道' : '折叠为紧凑条',
        checked: collapsed,
      ),
      // ── 工作台级的那一节 ────────────────────────────────────────────────
      //
      // 顶栏默认不画（`WorkspaceInteractionSettings.showTopChrome`），于是「退出」
      // 与「把顶栏叫回来」这两件事在界面上只剩这里。它们出现在**每一条**泳道的
      // 菜单里，而不是只在哪一条：独占与折叠都会让别的栏头从视口里消失，
      // 出口不该跟着一起消失。
      const PopupMenuDivider(),
      _item(
        value: 'topChrome',
        icon: chrome
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        label: chrome ? '隐藏工作台顶栏' : '显示工作台顶栏',
        checked: chrome,
        hint: '顶栏 = 退出 / 书名 / 切模式 / 重置布局那一行',
      ),
      _item(
        value: 'exit',
        icon: Icons.arrow_back_rounded,
        label: '退出工作台',
        hint: '与 Esc、系统返回键同一条路',
      ),
    ];
  }

  void apply(BuildContext context, String value) {
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
      case 'topChrome':
        final interaction = cubit.state.interaction;
        cubit.setInteraction(
          interaction.copyWith(showTopChrome: !interaction.showTopChrome),
        );
      case 'exit':
        // 走桥而不是在这里 `Navigator.maybePop()`：退出这一步在页面上还捎带
        // 「先退全屏」与「不是栈顶就不动」两条判断，抄一份就有两处会漂移。
        WorkspaceNavigationBridge.instance.exitWorkspace();
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

/// 栏头那颗「更多」按钮：[LaneMenu] 的左键入口。
class LaneMoreMenu extends StatelessWidget {
  const LaneMoreMenu({super.key, required this.menu});

  final LaneMenu menu;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '该泳道 (More)',
      itemBuilder: menu.buildItems,
      onSelected: (value) => menu.apply(context, value),
      child: Padding(
        // 刻意不用 `IconButton`：栏头那一行的预算已经很紧（见
        // `SwimlaneColumn._buildHeader` 里给页签条算宽的那段），
        // 这颗按钮只值 24px —— 与 `PanelTabStrip` 的「已收起」入口同一档。
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          Icons.more_vert_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
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
                    color: theme.colorScheme.onSurfaceVariant,
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
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
