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
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';
import 'package:zephyr/workspace/widgets/lane_resizer.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_bar_positioner.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_host.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_column.dart';

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
  /// 泳道的**结构行为** —— 吃第一下点击、悬停驻留聚焦、边缘驻留揭示、
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

  /// 视口左右两侧的**边缘揭示触发带**宽度。
  ///
  /// 指针进到这条带里才开始为「揭示相邻泳道」计时。它必须**明显地窄**：
  /// 太宽的话用户在 Reader 正常翻页时就会不断触发揭示，画面自己动起来。
  static const double edgeRevealZone = 28;

  /// 让滑条 / 轨道动起来的时长。
  static const Duration _scrollDuration = Duration(milliseconds: 220);

  @override
  State<SwimlaneWorkspace> createState() => _SwimlaneWorkspaceState();
}

class _SwimlaneWorkspaceState extends State<SwimlaneWorkspace> {
  final ScrollController _scroll = ScrollController();

  /// 单调时钟。用 [Stopwatch] 而不是 `DateTime.now()`：系统时间被改（或 NTP
  /// 校正）时 wall clock 会跳，而 dwell 的「够久了没有」经不起一次向后跳
  /// —— 那会让计时器一直不触发，表现为「悬停聚焦偶尔失灵」。
  final Stopwatch _clock = Stopwatch()..start();

  /// 三个驻留计时器：悬停聚焦 / 边缘揭示 / 揭示后恢复。
  final WorkspaceDwell _hoverDwell = WorkspaceDwell();
  final WorkspaceDwell _edgeDwell = WorkspaceDwell();
  final WorkspaceDwell _restoreDwell = WorkspaceDwell();

  Timer? _ticker;

  /// **瞬态**的边缘揭示目标（不是持久化项，也不进 cubit）。
  ///
  /// 契约要求揭示「transient and does not change the active lane」，
  /// 所以它不进状态记账 —— 进了就会被一起存盘 / 被别处读到，
  /// 于是「指针不在旁边时仍然揭示着」这种状态就有了存在的可能。
  String? _revealedLaneId;

  /// 指针当前在哪条泳道（用于判断「离开了被揭示的泳道没有」）。
  String? _hoveredLaneId;

  /// 是否正按着指针（按下期间抑制揭示与自动恢复）。
  bool _pointerDown = false;

  // ── 每次 build 缓存下来的纯计算结果 ────────────────────────────────────
  //
  // 它们是 `LayoutBuilder` 里那几个纯函数的输出（视口宽、几何记账），
  // 而触发时机在 build 之外（定时器、指针回调、状态变化）。缓存一次纯函数
  // 的结果是安全的：同样的输入必然得到同样的输出。
  double _viewportWidth = 0;
  double _availableWidth = 0;
  double _availableHeight = 0;
  WorkspaceLaneFocusGeometry? _geometry;

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ── 状态变化 → 移动条带 ────────────────────────────────────────────────

  /// 「激活泳道 / solo 偏好变了」⇒ 条带该重新选址。
  ///
  /// 用 post-frame 而不是当场滚：这次状态变化正处在 build 中间，
  /// 几何（`_geometry`）要等这次 build 结束才是新的。
  void _scheduleFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyOffset();
    });
  }

  /// 把条带滚到「当前该在的位置」。
  void _applyOffset() {
    final geometry = _geometry;
    if (geometry == null || !_scroll.hasClients || _viewportWidth <= 0) return;
    final state = context.read<WorkspaceCubit>().state;
    final target = _targetOffset(state, geometry);
    if ((_scroll.offset - target).abs() < 0.5) return;
    _scroll.animateTo(
      target,
      duration: SwimlaneWorkspace._scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  /// 当前该停在哪：揭示优先于激活泳道。
  double _targetOffset(WorkspaceState state, WorkspaceLaneFocusGeometry geometry) {
    final revealed = _revealedLaneId;
    if (revealed != null && revealed != state.activeLaneId) {
      return geometry.revealOffset(
        laneId: revealed,
        viewportWidth: _viewportWidth,
      );
    }

    final active = state.activeLaneId;
    if (active == null || !geometry.containsLane(active)) {
      return geometry.clampOffset(_scroll.offset, _viewportWidth);
    }

    return geometry.focusOffset(
      laneId: active,
      viewportWidth: _viewportWidth,
      currentOffset: _scroll.offset,
      readerLaneId: LaneId.reader,
      readerPeekWidth: state.interaction.readerPeekWidth,
      // 用户开着 Reader 独占偏好、但激活的是别的泳道时，给 Reader 留一条缝
      // —— 契约：`keeps a narrow portion of Reader visible where possible
      // so a single Reader click can restore the solo view`。
      keepReaderVisible:
          state.layout.soloLaneId == LaneId.reader && active != LaneId.reader,
    );
  }

  // ── 时钟循环 ───────────────────────────────────────────────────────────

  int get _nowMs => _clock.elapsedMilliseconds;

  /// 只有真的有待发项时才开着 —— 一个永久 60Hz 的定时器会让工作台
  /// 一直占着一份 CPU，便携机上直接表现为续航变差。
  void _ensureTicker() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _pollDwells(),
    );
  }

  void _stopTickerIfIdle() {
    if (_hoverDwell.isPending || _edgeDwell.isPending || _restoreDwell.isPending) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
  }

  void _pollDwells() {
    if (!mounted) return;
    final now = _nowMs;
    final cubit = context.read<WorkspaceCubit>();

    final hoveredLane = _hoverDwell.takeDue(now);
    if (hoveredLane != null) cubit.activateLane(hoveredLane);

    final revealSide = _edgeDwell.takeDue(now);
    if (revealSide != null) {
      setState(() => _revealedLaneId = revealSide);
      _applyOffset();
    }

    if (_restoreDwell.takeDue(now) != null) {
      setState(() => _revealedLaneId = null);
      _applyOffset();
    }

    _stopTickerIfIdle();
  }

  // ── 指针 ───────────────────────────────────────────────────────────────

  /// Reader 悬停聚焦。
  ///
  /// 只对**阅读器**这一条泳道生效：契约里这项能力就叫 `Reader hover-focus`
  /// （`An optional, configurable dwell inside an inactive Reader lane activates
  /// it`）。若对所有泳道都生效，用户把指针挪到面板泳道上方想看看就绪状态时，
  /// 激活态会自己跑掉。
  void _handleLaneHoverEnter(String laneId, WorkspaceState state) {
    _hoveredLaneId = laneId;
    // 进了被揭示的那条泳道 ⇒ 取消「回到 Reader」的计时（用户在看它）。
    if (laneId == _revealedLaneId) {
      _restoreDwell.cancel();
    }

    if (!state.interaction.hoverFocusEnabled) return;
    if (laneId != LaneId.reader) return;
    if (laneId == state.activeLaneId) return;
    if (_pointerDown) return;

    _hoverDwell.enter(
      laneId,
      nowMs: _nowMs,
      delayMs: state.interaction.hoverFocusDelayMs,
    );
    _ensureTicker();
  }

  void _handleLaneHoverExit(String laneId) {
    if (_hoveredLaneId == laneId) _hoveredLaneId = null;
    _hoverDwell.leave(laneId);
    if (laneId == _revealedLaneId) {
      _maybeScheduleRestore(context.read<WorkspaceCubit>().state);
    }
    _stopTickerIfIdle();
  }

  /// 条带范围内的悬停：判定「指针是否停在视口边缘」。
  void _handleStripHover(PointerHoverEvent event) {
    final state = context.read<WorkspaceCubit>().state;
    final soloArmed =
        state.layout.soloLaneId == LaneId.reader &&
        state.activeLaneId == LaneId.reader;

    // 抑制条件（契约：`Reader pointer capture, an active drag, composition,
    // a modal, or a floating menu suppresses edge reveal and automatic
    // restoration`）。这里覆盖的是「指针按着 / 正在拖动」与「没有独占可回」；
    // 弹层与输入法组合由下面 `_handleLanePointerDown` 的按下抑制间接覆盖。
    if (!soloArmed || _pointerDown || _viewportWidth <= 0) {
      _edgeDwell.cancel();
      _maybeScheduleRestore(state);
      _stopTickerIfIdle();
      return;
    }

    final x = event.localPosition.dx;
    String? candidate;
    if (x <= SwimlaneWorkspace.edgeRevealZone) {
      candidate = LaneId.left;
    } else if (x >= _viewportWidth - SwimlaneWorkspace.edgeRevealZone) {
      candidate = LaneId.right;
    }
    if (candidate != null && !state.layout.lanes.containsKey(candidate)) {
      candidate = null;
    }
    // 揭示 Reader 自己没有意义（它已经在视口里）。
    if (candidate == LaneId.reader) candidate = null;

    if (candidate != null) {
      _restoreDwell.cancel();
      _edgeDwell.enter(
        candidate,
        nowMs: _nowMs,
        delayMs: state.interaction.edgeRevealDelayMs,
      );
      _ensureTicker();
      return;
    }

    _edgeDwell.cancel();
    // 指针还在被揭示的那条泳道里 ⇒ 不是「离开」，别急着收回。
    if (_revealedLaneId != null && _hoveredLaneId != _revealedLaneId) {
      _maybeScheduleRestore(state);
    }
    _stopTickerIfIdle();
  }

  void _handleStripExit() {
    _edgeDwell.cancel();
    _hoverDwell.cancel();
    _hoveredLaneId = null;
    _maybeScheduleRestore(context.read<WorkspaceCubit>().state);
    _stopTickerIfIdle();
  }

  /// 离开一条**未被激活**的揭示 ⇒ 延时回到 Reader。
  void _maybeScheduleRestore(WorkspaceState state) {
    final revealed = _revealedLaneId;
    if (revealed == null) return;
    if (revealed == state.activeLaneId) return;
    _restoreDwell.enter(
      'restore',
      nowMs: _nowMs,
      delayMs: state.interaction.edgeRevealRestoreDelayMs,
    );
    _ensureTicker();
  }

  /// 泳道内容上的指针按下。
  ///
  /// 两件事一起做：**激活这条泳道**，以及把待发的驻留全部作废
  /// （用户已经用一次点击明确表达了他的意图，不该再过一会儿又自己动一下）。
  void _handleLanePointerDown(String laneId) {
    final cubit = context.read<WorkspaceCubit>();
    _pointerDown = true;
    _hoverDwell.cancel();
    _edgeDwell.cancel();
    _restoreDwell.cancel();
    _stopTickerIfIdle();

    if (laneId == _revealedLaneId) {
      // 在被揭示的泳道里交互 ⇒ 它变成真正的激活，揭示结束（条带留在原地）。
      setState(() => _revealedLaneId = null);
    }
    cubit.activateLane(laneId);
  }

  void _handlePointerUp() {
    _pointerDown = false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorkspaceCubit, WorkspaceState>(
      listenWhen: (previous, next) =>
          previous.activeLaneId != next.activeLaneId ||
          previous.layout.soloLaneId != next.layout.soloLaneId ||
          previous.layout.laneOrder != next.layout.laneOrder ||
          previous.layout.lanes != next.layout.lanes,
      listener: (context, state) => _scheduleFocus(),
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            // 两个宽度各有各的用处，别合并：
            // - `viewportWidth`：阅读器泳道的**比例**要乘它（乘可用宽会把比例算歪）；
            // - `availableWidth`：条带实际能摆多宽 = 富余 / 滚动的判断基准。
            final viewportWidth = constraints.maxWidth;
            final availableWidth = math.max(
              0.0,
              viewportWidth - SwimlaneWorkspace._stripPadding * 2,
            );
            _viewportWidth = viewportWidth;
            _availableWidth = availableWidth;
            _availableHeight = math.max(
              0.0,
              constraints.maxHeight - SwimlaneWorkspace._stripPadding * 2,
            );

            final metrics = WorkspaceStripMetrics.resolve(
              layout: state.layout,
              viewportWidth: viewportWidth,
              availableWidth: availableWidth,
              resizerWidth: LaneResizer.width,
              // solo 的生效宽度以「它同时是激活泳道」为前提。
              soloLaneId: state.effectiveSoloLaneId,
            );
            final geometry = WorkspaceLaneFocusGeometry.fromMetrics(metrics);
            _geometry = geometry;

            return MouseRegion(
              onHover: _handleStripHover,
              onExit: (_) => _handleStripExit(),
              child: Listener(
                onPointerUp: (_) => _handlePointerUp(),
                onPointerCancel: (_) => _handlePointerUp(),
                child: Padding(
                  padding: const EdgeInsets.all(
                    SwimlaneWorkspace._stripPadding,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: _buildStrip(context, state, viewportWidth, metrics),
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
        final after = slot.afterLaneId!;
        children.add(
          LaneResizer(
            onDragDelta: (delta) =>
                cubit.dragLanePair(before, after, delta, viewportWidth),
            onDoubleTapReset: () => cubit.resetLanePair(before, after),
          ),
        );
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
            isActive: activeLaneId == laneId,
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
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: SizedBox(width: metrics.contentWidth, child: strip),
    );
  }

  Widget _buildLane(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    double viewportWidth, {
    required bool isActive,
    double? resolvedWidth,
  }) {
    final cubit = context.read<WorkspaceCubit>();
    final config =
        state.layout.lanes[laneId] ?? LaneConfig(width: 380, title: laneId);
    final laneWidth = resolvedWidth ?? config.resolveWidth(viewportWidth);

    final column = SwimlaneColumn(
      laneId: laneId,
      config: config,
      resolvedWidth: laneWidth,
      isSolo: state.effectiveSoloLaneId == laneId,
      isActive: isActive,
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
      onToggleCollapse: () => cubit.toggleLaneCollapsed(laneId),
      onToggleSolo: () => cubit.toggleSoloLane(laneId),
      onResetWidth: () => cubit.resetLaneWidth(laneId),
      child: _buildAbsorbingContent(context, state, laneId, cubit, isActive),
    );

    return MouseRegion(
      onEnter: (_) => _handleLaneHoverEnter(laneId, state),
      onExit: (_) => _handleLaneHoverExit(laneId),
      child: Listener(
        // 在**整条泳道**上听按下：栏头里的控件（折叠 / 独占 / 宽度）也要算
        // 「用户把交互交给了这条泳道」。被吃掉的只有内容区，见下。
        onPointerDown: (_) => _handleLanePointerDown(laneId),
        child: _buildLaneDragTarget(context, cubit, laneId, column),
      ),
    );
  }

  /// 非激活泳道的**内容**吃掉第一下点击。
  ///
  /// 契约原文：`That click is consumed by the workspace and must not reach
  /// Reader area bindings, page navigation, video controls, or the radial menu`。
  ///
  /// 用 `AbsorbPointer` 而不是在外层拦手势：它让子树的命中测试整个失败，
  /// 于是「是不是被吞了」只有一个是非项，不依赖任何子控件恰好没注册某个
  /// 手势识别器。激活之后立刻恢复派发。
  ///
  /// **只包内容、不包栏头**（这是本方法的全部意义）。
  /// 栏头的按钮是这条泳道**自己的**控件，第一下点击就该生效 —— 用户按
  /// 「折叠」而什么都没发生，比「按了但先激活了泳道」难解释得多。
  /// 两条都靠外层那个 `Listener.onPointerDown` 顺带完成激活，彼此不冲突。
  /// 早先版本把这个 `AbsorbPointer` 包在了**整列**外面（含栏头），
  /// 于是非激活泳道上的折叠 / 独占按钮第一下必然哑掉，而注释还写着
  /// 「只包内容」—— 注释与实现不一致本身就是缺陷。
  Widget _buildAbsorbingContent(
    BuildContext context,
    WorkspaceState state,
    String laneId,
    WorkspaceCubit cubit,
    bool isActive,
  ) {
    return AbsorbPointer(
      absorbing: !isActive,
      child: _buildLaneContent(context, state, laneId, cubit),
    );
  }

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
        icon: Icon(
          isSwimlane ? Icons.fullscreen_rounded : Icons.view_column_rounded,
          size: 18,
        ),
        tooltip: isSwimlane ? '切换为沉浸四边栏 (Edges)' : '切换为多列泳道 (Swimlane)',
        visualDensity: VisualDensity.compact,
        onPressed: () => cubit.toggleMode(),
      ),
      if (state.readerTarget != null)
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: '关闭当前漫画 (回到空态)',
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
