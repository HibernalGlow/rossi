import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_dwell.dart';
import 'package:zephyr/workspace/model/workspace_lane_focus.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';
import 'package:zephyr/workspace/model/workspace_pointer_mode.dart';
import 'package:zephyr/workspace/input/workspace_lane_input_router.dart';
import 'package:zephyr/workspace/input/workspace_lane_input_region.dart';
import 'package:zephyr/page/comic_read/widgets/radial/reader_radial_menu_overlay.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';
import 'package:zephyr/workspace/widgets/lane_resizer.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_host.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';
import 'package:zephyr/icons/icons.dart';

import 'package:zephyr/workspace/widgets/swimlane/workspace_lane_scroll_controller.dart';
import 'package:zephyr/i18n/strings.g.dart';

part 'swimlane_workspace_interaction.dart';

/// 水平泳道工作区：**一条平面条带**，左面板 / 阅读器 / 右面板依次排列。
///
/// 四条不变量（来自 neoview 的 swimlane 契约）：
/// 1. 所有泳道共处**一条水平条带**，显出一条泳道靠**移动条带**，泳道之间**永不重叠、
///    永不浮在别人上面**；
/// 2. 面板泳道宽度是**绝对像素**、不按窗口宽夹取；阅读器泳道宽度是**视口比例**；
/// 3. 有富余宽度时富余全部给**阅读器**（中央弹性填充），不够时整条带横向滚动；
/// 4. **独占不再是另一套版式**：solo 只是「那条泳道这一档的宽度 = 可用宽」，
///    仍然走同一条条带 —— 于是边缘驻留的**揭示**才有东西可滚。
///
/// 本页同时是**停留（dwell）**这件事的宿主：悬停聚焦与边缘揭示都是「指针停在
/// 某处够久」，两者的逻辑在 `WorkspaceDwell` 里（纯 Dart、可断言），
/// 这里只负责喂真实时钟与把结果翻译成滚动 / 激活。
class SwimlaneWorkspace extends StatefulWidget {
  const SwimlaneWorkspace({super.key, this.debugLaneContentBuilder});

  /// **判据用**的泳道内容替身；`null` = 真内容。
  ///
  /// 与 `BreezeWorkspacePage.store` 同一条理由（那个口子也是这样来的）：
  /// 泳道的**结构行为** —— 首个输入直接执行、悬停驻留定位、边缘驻留揭示、
  /// 条带滚到哪儿 —— 全都住在这一层，是框架层的事，与引擎无关，本该能断言；
  /// 而真内容（上游 `BookshelfPage` / `ComicReadPage`）需要整个应用的依赖
  /// （ObjectBox、图源注册表、应用数据目录），widget 判据里根本建不起来。
  /// 于是没有这个口子时，上面那些行为**一条运行时判据都写不出来**，
  /// 只剩纯逻辑那层（`lane_focus_check` / `dwell_check`）在自说自话。
  ///
  /// 应用路径**永不**传它（`BreezeWorkspacePage` 也不传），所以它存在与否
  /// 对线上行为的差别只有「内容由谁构造」，别的一字不改。
  final Widget Function(String laneId)? debugLaneContentBuilder;

  /// 条带四周的外边距。
  ///
  /// **它是「可用宽度」与「视口宽度」的差**，两者不能混用 ——
  /// 算富余 / 判断要不要滚动时必须用**扣掉两条边距之后**的宽度。
  /// 差这 16px 的后果不是"挤一挤"，而是 Row 溢出、Flutter 把右侧 10%
  /// （`debug_overflow_indicator.dart` 里的 `_indicatorFraction`）涂成
  /// 黄黑斜纹，看起来像界面上多了一条莫名其妙的黄色装饰。
  ///
  /// 取值直接引用 [WorkspaceStripMetrics.defaultPadding]：判据
  /// （`dart run test/workspace/strip_metrics_check.dart`）加载不了 widget，
  /// 只有**同一个常量**才能保证两边算的是同一件事。
  static const double _stripPadding = WorkspaceStripMetrics.defaultPadding;

  @override
  State<SwimlaneWorkspace> createState() => _SwimlaneWorkspaceState();
}

class _SwimlaneWorkspaceState extends State<SwimlaneWorkspace>
    with _SwimlaneWorkspaceInteraction {
  // ── 每次 build 缓存下来的纯计算结果 ────────────────────────────────────
  //
  // 它们是 `LayoutBuilder` 里那几个纯函数的输出（视口宽、几何记账），
  // 而触发时机在 build 之外（定时器、指针回调、状态变化）。缓存一次纯函数
  // 的结果是安全的：同样的输入必然得到同样的输出。
  @override
  double _viewportWidth = 0;
  @override
  double _availableWidth = 0;
  double _availableHeight = 0;

  /// [MouseRegion] 自己的高度 —— 唤出区的 `y` / `height` 百分比是**相对它**算的。
  ///
  /// 不能拿 [_availableHeight] 顶替：那个值已经扣掉了条带内边距，而指针坐标
  /// 是相对整个 `MouseRegion` 的（内边距不吃指针）。两者混用会让唤出区
  /// 在竖直方向上整体偏小一圈，表现为「按画布上的位置摆了却命中不了」。
  @override
  double _viewportHeight = 0;
  @override
  WorkspaceLaneFocusGeometry? _geometry;

  // ── 泳道**内容**的实例缓存 ──────────────────────────────────────────────
  //
  // 一次「把交互交给另一条泳道」要重跑的只有外壳（边框、栏头、条带落点）；内容槽位
  // 拿到的必须是**同一个 widget 实例**。Flutter 在 `Element.updateChild`
  // （`framework.dart:4027`）见到 `child.widget == newWidget` 时整棵子树直接跳过 ——
  // 这条不是微优化，是「阅读器有没有被整页重 build」的分水岭：内容实例一换，
  // `WorkspaceReaderHost` 里那条 `Navigator` 就走到 `changedExternalState`
  // ⇒ `_forceRebuildPage` ⇒ 上游 `ComicReadPage` 全页重 build。
  //
  // 缓存的失效条件用**签名**表达，不靠「我记得哪些字段被读过」：签名 = 除
  // `activeLaneId` 之外的全部字段，逐字段比。宁可多重建，也不能漏重建。
  Object? _contentSignature;
  final Map<String, Widget> _laneContent = <String, Widget>{};

  /// 内容签名（**不含**「谁被激活」）。
  Object _signatureOf(WorkspaceState state) => (
    state.mode,
    state.layout,
    state.board,
    state.readerTarget,
    state.activePanel,
    state.interaction,
    state.isReaderFullscreen,
  );

  /// 签名变了才重出内容实例；没变就把上次那份交出去（于是子树被整段跳过）。
  void _syncLaneContent(
    BuildContext context,
    WorkspaceState state,
    WorkspaceCubit cubit,
  ) {
    final signature = _signatureOf(state);
    if (identical(signature, _contentSignature) ||
        signature == _contentSignature) {
      return;
    }
    _contentSignature = signature;
    for (final laneId in state.layout.laneOrder) {
      _laneContent[laneId] = _buildLaneContent(context, state, laneId, cubit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkspaceCubit, WorkspaceState>(
      listenWhen: (previous, next) =>
          previous.activeLaneId != next.activeLaneId ||
          previous.layout.soloLaneId != next.layout.soloLaneId ||
          previous.layout.laneOrder != next.layout.laneOrder ||
          previous.layout.lanes != next.layout.lanes,
      listener: (context, state) {
        if (!_activatingFromHover) {
          _inputRouter.selectExplicitly(state.activeLaneId ?? LaneId.reader);
        }
        _scheduleFocus();
      },
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            // 两个宽度各有各的用处，别合并：
            // - `viewportWidth`：阅读器泳道的**比例**要乘它（乘可用宽会把比例算歪）；
            // - `availableWidth`：条带实际能摆多宽 = 富余 / 滚动的判断基准。
            final viewportWidth = constraints.maxWidth;
            final stripPadding = state.isReaderFullscreen
                ? 0.0
                : SwimlaneWorkspace._stripPadding;
            final availableWidth = math.max(
              0.0,
              viewportWidth - stripPadding * 2,
            );
            _viewportWidth = viewportWidth;
            _availableWidth = availableWidth;
            _viewportHeight = constraints.maxHeight;
            _availableHeight = math.max(
              0.0,
              constraints.maxHeight - stripPadding * 2,
            );

            final metrics = WorkspaceStripMetrics.resolve(
              layout: state.layout,
              viewportWidth: viewportWidth,
              availableWidth: availableWidth,
              resizerWidth: LaneResizer.width,
              // **Reader 的**独占宽度不看激活态（见 `WorkspaceState.effectiveSoloLaneId`）：
              // 聚焦只移动条带，不把 Reader 按新宽度重排、重解一遍画面。
              // 面板泳道仍走老契约（生效要同时被激活），那条不对称的理由写在同一个 getter 上。
              soloLaneId: state.effectiveSoloLaneId,
              // 轨只给「不是当前激活」的那几条 —— 激活哪条，哪条就展开。
              activeLaneId: state.activeLaneId,
              // 触摸屏上这条切换轨是左右泳道**唯一**的把手：Reader 独占时其余两条
              // 被推出视口，而把它们推回来的那两种桌面办法在这边都不成立 ——
              // 边缘悬停驻留要 `PointerHoverEvent`（永不触发），横扫条带会被阅读器
              // 的翻页拖吃掉。所以这里按「有没有指针」把轨给出来，而不是去改
              // `showLaneNavigatorInSolo` 的存值：那是用户在设置里定的偏好，
              // 与 `WorkspaceTopChromeMode` 同一个口径（形态随设备走，偏好不动）。
              showLaneNavigatorInSolo:
                  state.interaction.showLaneNavigatorInSolo || !hasHoverPointer,
            );
            final geometry = WorkspaceLaneFocusGeometry.fromMetrics(metrics);
            _geometry = geometry;
            // 内容实例：只在「除激活态之外的任何一项」变了才重出。
            _syncLaneContent(context, state, context.read<WorkspaceCubit>());

            return MouseRegion(
              onHover: _handleStripHover,
              onExit: (_) => _handleStripExit(),
              child: Listener(
                onPointerDown: (event) =>
                    _inputRouter.trackPointer(event.pointer),
                onPointerUp: (event) => _handlePointerUp(event.pointer),
                onPointerCancel: (event) => _handlePointerUp(event.pointer),
                child: Padding(
                  padding: EdgeInsets.all(stripPadding),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: _buildStrip(
                          context,
                          state,
                          viewportWidth,
                          metrics,
                        ),
                      ),
                      // 不限制在本泳道内的悬浮面板栏浮在**工作台**这一层：
                      // 它必须能越出泳道边界，而泳道自己的 `Stack` 是裁剪的
                      // （越界的子节点连指针事件都收不到）。
                      ..._buildFloatingPanelBars(context, state, geometry),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 条带 ───────────────────────────────────────────────────────────────

  Widget _buildStrip(
    BuildContext context,
    WorkspaceState state,
    double viewportWidth,
    WorkspaceStripMetrics metrics,
  ) {
    final cubit = context.read<WorkspaceCubit>();
    final activeLaneId = state.activeLaneId;

    final children = <Widget>[];
    for (final slot in metrics.slots) {
      final laneId = slot.laneId;
      if (laneId == null) {
        final before = slot.beforeLaneId!;
        final after = slot.afterLaneId;
        if (after == null) {
          children.add(
            LaneResizer(
              onDragDelta: (delta) {
                cubit.dragLaneRightEdge(before, delta, viewportWidth);
                if (_scroll.hasClients) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scroll.hasClients) return;
                    final max = _scroll.position.maxScrollExtent;
                    if (delta > 0 && max > 0 && _scroll.offset < max) {
                      _scroll.jumpTo(max);
                    } else if (delta < 0 && _scroll.offset > max) {
                      _scroll.jumpTo(max);
                    }
                  });
                }
              },
              onDoubleTapReset: () => cubit.resetLaneWidth(before),
            ),
          );
        } else {
          children.add(
            LaneResizer(
              onDragDelta: (delta) =>
                  cubit.dragLanePair(before, after, delta, viewportWidth),
              onDoubleTapReset: () => cubit.resetLanePair(before, after),
            ),
          );
        }
        continue;
      }

      children.add(
        SizedBox(
          width: slot.width,
          child: _buildLane(
            context,
            state,
            laneId,
            viewportWidth,
            resolvedWidth: slot.width,
            isActive: (_inputRouter.targetLaneId ?? activeLaneId) == laneId,
            // 这条泳道**按紧凑轨来画**（自己折叠，或独占泳道旁边的切换栏）。
            // 用槽位的结果而不是 `config.collapsed`：后者只记用户折叠了谁，
            // 不知道「这一档它被挤到 44px 了」。
            isRail: slot.collapsed,
            isFullscreen: state.isReaderFullscreen && laneId == LaneId.reader,
          ),
        ),
      );
    }

    final strip = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    // 条带这一层的横向滚动**受控**：偏移由几何算出（`_applyOffset`），
    // 用户的拖动只用于「他自己想看别处」的场合。
    //
    // 「允许手动横向滚动」关掉时只拒**用户伸手**这一条路径（拖动与滚轮都走
    // `isScrollingEnabled` 这个闸），边界回弹与程序化 `animateTo` 一律照旧 ——
    // 用 `NeverScrollableScrollPhysics` 顶替会把后面那条也一起废掉，
    // 于是「激活左泳道」不再把条带滚过去，表现为「点了没反应」。
    //
    // Reader 全屏是这条规则的**第二道闸**：此时条带仍有可滚余量（其余泳道只是
    // 被推出视口），翻页那一下横拖会连阅读器一起拽走，所以默认把它掐掉。
    final userScrollAllowed =
        state.interaction.manualScrollEnabled &&
        !(state.isReaderFullscreen &&
            state.interaction.blockManualScrollInReaderFullscreen);
    final contentScrollBehavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      // 泳道中的鼠标按住拖动留给文本选区，包括输入框内部的横向滚动层。
      // 触屏拖动、触控板与滚轮仍按原有配置滚动。
      behavior: contentScrollBehavior.copyWith(
        dragDevices: contentScrollBehavior.dragDevices.difference({
          PointerDeviceKind.mouse,
        }),
      ),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: userScrollAllowed
            ? const ClampingScrollPhysics()
            : const _ProgrammaticScrollPhysics(),
        child: SizedBox(width: metrics.contentWidth, child: strip),
      ),
    );
  }

  Widget _buildLane(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    double viewportWidth, {
    required bool isActive,
    double? resolvedWidth,
    bool isRail = false,
    bool isFullscreen = false,
  }) {
    final cubit = context.read<WorkspaceCubit>();
    final config =
        state.layout.lanes[laneId] ?? LaneConfig(width: 380, title: laneId);
    final laneWidth = resolvedWidth ?? config.resolveWidth(viewportWidth);

    final column = SwimlaneColumn(
      laneId: laneId,
      config: config,
      resolvedWidth: laneWidth,
      viewportWidth: viewportWidth,
      isSolo: state.effectiveSoloLaneId == laneId,
      isFullscreen: isFullscreen,
      isActive: isActive,
      isRail: isRail,
      // 驻留已经「停住」、最后那段延时还在走 —— 先把边框亮起来。
      focusArmed: _armedHoverLaneId == laneId,
      titleOverride: laneId == LaneId.reader
          ? state.readerTarget?.displayTitle
          : null,
      headerActions: laneId == LaneId.reader
          ? _readerLaneActions(context, state, cubit)
          : const <Widget>[],
      // 面板页签由泳道自己按记账摆放（挂进栏头 / 钉在某条边 / 悬浮在泳道内）——
      // 它需要泳道自己的尺寸，只有 `SwimlaneColumn` 那一层知道。
      panelSide: switch (laneId) {
        LaneId.left => WorkspacePanelSide.left,
        LaneId.right => WorkspacePanelSide.right,
        _ => null,
      },
      // 切换栏里的那几条轨：点它是「把交互交给这条泳道」（Reader 的独占随即让位），
      // **不是**折叠 —— 它本来就没被用户折叠，去 toggle 会把「显示切换栏」
      // 变成「把这条泳道永久折起来」，与用户点它时想要的正好相反。
      onToggleCollapse: isRail && !config.collapsed
          ? () => cubit.activateLane(laneId)
          : () => cubit.toggleLaneCollapsed(laneId),
      onToggleSolo: () => cubit.toggleSoloLane(laneId),
      onResetWidth: () => cubit.resetLaneWidth(laneId),
      child: _buildInteractiveContent(laneId),
    );

    return MouseRegion(
      onEnter: (_) => _handleLaneHoverEnter(laneId, state, isRail: isRail),
      onExit: (_) => _handleLaneHoverExit(laneId),
      child: Listener(
        // 只记操作归属；第一下由命中的内容直接执行。
        onPointerDown: (event) => _handleLanePointerDown(laneId, event.pointer),
        child: _buildLaneDragTarget(context, cubit, laneId, column),
      ),
    );
  }

  /// 命中内容直接执行。信号层只保护连续滚轮的归属，不拦点击。
  Widget _buildInteractiveContent(String laneId) => WorkspaceLaneInputRegion(
    acceptWheel: () => _handleLaneWheel(laneId),
    onPanZoomStart: (pointer) => _handleLanePointerDown(laneId, pointer),
    onPanZoomEnd: _handlePointerUp,
    child: _laneContent[laneId]!,
  );

  /// 栏头图标是**泳道重排**的把手：按住它拖到另一条泳道上，两条互换位置。
  /// （neoview：lane header owns collapse, reorder, focus, width。）
  Widget _buildLaneDragTarget(
    BuildContext context,
    WorkspaceCubit cubit,
    String laneId,
    Widget child,
  ) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != laneId,
      onAcceptWithDetails: (details) => cubit.reorderLane(details.data, laneId),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    );
  }

  /// 阅读器泳道栏头的附加控件。
  ///
  /// 模式切换**放在这里而不是工作台顶栏**：neoview 的契约是泳道模式下
  /// Reader 的动作跟着 Reader 泳道走，而不是挂在一个全局工具条上。
  List<Widget> _readerLaneActions(
    BuildContext context,
    WorkspaceState state,
    WorkspaceCubit cubit,
  ) {
    final isSwimlane = state.mode == WorkspaceMode.swimlane;
    return [
      IconButton(
        icon: GlyphIcon(
          isSwimlane ? AppGlyphs.columnsTwo : AppGlyphs.columnsThree,
          size: 18,
        ),
        tooltip: isSwimlane
            ? t.workspace.switchToWorkholeEn
            : t.workspace.switchToSwimlaneEn,
        visualDensity: VisualDensity.compact,
        onPressed: () => cubit.toggleMode(),
      ),
      if (state.readerTarget != null)
        IconButton(
          icon: const GlyphIcon(AppGlyphs.close, size: 18),
          tooltip: t.workspace.closeCurrentComicPlain,
          visualDensity: VisualDensity.compact,
          onPressed: () => cubit.closeReader(),
        ),
    ];
  }

  Widget _buildLaneContent(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    WorkspaceCubit cubit,
  ) {
    // 判据用的替身（见 `debugLaneContentBuilder`）：只换内容，不换别的。
    final probe = widget.debugLaneContentBuilder;
    if (probe != null) return probe(laneId);

    switch (laneId) {
      // 左 / 右：**面板泳道** —— 图标轨切换面板，面板里是卡片
      // （左：书架卡片的「书架」面板 + 完整复用上游 BookshelfPage 的面板；
      //   右：完整复用上游 DiscoverPage / MorePage 的面板 + 图源与本地卡片）。
      case LaneId.left:
        return const LanePanelHost(side: WorkspacePanelSide.left);

      // 中：**阅读器** —— 上游原版 ComicReadPage（空态则为画板）
      case LaneId.reader:
        return WorkspaceReaderHost(target: state.readerTarget);

      case LaneId.right:
        return const LanePanelHost(side: WorkspacePanelSide.right);

      default:
        return const SizedBox.shrink();
    }
  }

  // ── 越出泳道的悬浮面板栏 ────────────────────────────────────────────────

  /// 把「允许移出泳道」的悬浮面板栏画在工作台这一层。
  ///
  /// 位置由**已经算好的几何**推出来：条带是「已知宽度的一串槽位 + 一个滚动偏移」，
  /// 所以某条泳道在视口里的矩形就是 `[start - offset, start - offset + width]`。
  /// 不需要去问 `GlobalKey` 要真实位置 —— 那会引入一次额外的布局往返，
  /// 而且在条带动画期间拿到的还是上一帧的位置。
  ///
  /// 坐标系：这一层 `Stack` 在条带的内边距**里面**，所以它的原点与条带内容原点
  /// 重合，泳道矩形不需要再补偿那 8px。
  List<Widget> _buildFloatingPanelBars(
    BuildContext context,
    WorkspaceState state,
    WorkspaceLaneFocusGeometry geometry,
  ) {
    final bars = <Widget>[];
    final scrollOffset = _scroll.hasClients ? _scroll.offset : 0.0;

    for (final laneId in state.layout.laneOrder) {
      final lane = state.layout.lanes[laneId];
      if (lane == null) continue;
      final panelBar = lane.panelBar;
      if (panelBar.mode != PanelBarMode.floating || panelBar.constrained) {
        continue;
      }
      // 阅读器泳道没有面板栏。
      final side = WorkspacePanelSide.tryParse(laneId);
      if (side == null) continue;

      final start = geometry.start[laneId];
      final width = geometry.width[laneId];
      if (start == null || width == null) continue;

      final laneLeft = start - scrollOffset;
      final laneRight = laneLeft + width;
      // 泳道整个在视口之外时**不画**它那条游离的面板栏：一块「属于某条看不见的
      // 泳道」的浮层会让人以为它是工作台级别的工具条。
      if (laneRight <= 0 || laneLeft >= _availableWidth) continue;

      final viewportBounds = PanelBarBounds(
        left: 0,
        top: 0,
        width: _availableWidth,
        height: _availableHeight,
      );
      // 换边停靠的判定仍然要对**泳道自己的矩形**做（契约的 `dockCandidate`
      // 收的就是 laneHost 的矩形）：拿视口矩形去判定的话，这类浮层在视口边缘
      // 就会被吸附，于是它永远钉不到自己那条泳道的边上。
      final laneBounds = PanelBarBounds(
        left: laneLeft,
        top: 0,
        width: width,
        height: _availableHeight,
      );

      bars.add(
        Positioned.fill(
          child: PanelBarPositioner(
            layout: panelBar,
            boundsOf: (_) => viewportBounds,
            child: PanelTabStrip(
              side: side,
              bounds: viewportBounds,
              laneBounds: laneBounds,
              floating: true,
              showHandle: true,
            ),
          ),
        ),
      );
    }
    return bars;
  }
}

/// 像素坐标 → 唤出区用的百分比（0..100）。
///
/// 尺寸非正时返回 0 而不是除一下：`LayoutBuilder` 在第一次布局前会给到 0 宽，
/// 而 0 恰好落在左唤出区里 —— 但那会儿 `_viewportWidth <= 0` 的守卫
/// 已经把整条判定短路掉了。
double _percentOf(double value, double total) =>
    total <= 0 ? 0 : value / total * 100;

/// 「只让程序滚，不让人滚」的滚动物理。
///
/// 与 [ClampingScrollPhysics] 只差一个闸口：`isScrollingEnabled` 为假时
/// `Scrollable` 不会挂上拖动识别器，滚轮的 `handlePointerSignalEvent` 也提前返回，
/// 而边界回弹、惯性、`animateTo` 全部原样继承 ——
/// 这正是「允许手动横向滚动」要的语义（见 `_buildStrip`）。
class _ProgrammaticScrollPhysics extends ClampingScrollPhysics {
  const _ProgrammaticScrollPhysics({super.parent});

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;

  @override
  _ProgrammaticScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ProgrammaticScrollPhysics(parent: buildParent(ancestor));
  }
}
