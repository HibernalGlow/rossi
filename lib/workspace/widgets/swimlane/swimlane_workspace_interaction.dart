part of 'swimlane_workspace.dart';

/// 输入归属、驻留与定位活动。内容构造留在 workspace，避免交互更新重建 Reader。
mixin _SwimlaneWorkspaceInteraction on State<SwimlaneWorkspace> {
  WorkspaceLaneFocusGeometry? get _geometry;
  double get _availableWidth;
  double get _viewportWidth;
  double get _viewportHeight;

  late final WorkspaceLaneInputRouter _inputRouter;
  ModalRoute<dynamic>? _route;
  bool _visualRequestPending = false;
  bool _focusScheduled = false;
  bool _activatingFromHover = false;
  String? _activationAfterGesture;
  bool _hoveredIsRail = false;
  bool _wasBlocked = false;

  final WorkspaceLaneScrollController _scroll = WorkspaceLaneScrollController();

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

  /// **预备态**高亮落在哪条泳道（驻留已「停住」、最后那段延时还没走完）。
  ///
  /// 它只是边框颜色，不改几何、不改记账，也不进 cubit —— 一次 hover 就把整份
  /// 状态 emit 一遍，等于把「预备」做成「已经换了人」。
  String? _armedHoverLaneId;

  @override
  void initState() {
    super.initState();
    _inputRouter = WorkspaceLaneInputRouter(
      hasLane: (laneId) =>
          context.read<WorkspaceCubit>().state.layout.lanes.containsKey(laneId),
      interactionOwned: () =>
          ReaderRadialMenu.isOpen || (_route != null && !_route!.isCurrent),
      initialLaneId: context.read<WorkspaceCubit>().state.activeLaneId,
    )..addListener(_onInputChanged);
    ReaderRadialMenu.openState.addListener(_inputRouter.refreshOwnership);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    ReaderRadialMenu.openState.removeListener(_inputRouter.refreshOwnership);
    _inputRouter.removeListener(_onInputChanged);
    _inputRouter.dispose();
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
    _visualRequestPending = true;
    if (_focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted) return;
      _applyOffset();
    });
  }

  /// 把条带滚到「当前该在的位置」。
  void _applyOffset() {
    if (_inputRouter.blocksAutomatic) {
      _visualRequestPending = true;
      return;
    }
    _visualRequestPending = false;
    final geometry = _geometry;
    if (geometry == null || !_scroll.hasClients || _availableWidth <= 0) return;
    final state = context.read<WorkspaceCubit>().state;
    final target = _targetOffset(state, geometry);
    if ((_scroll.offset - target).abs() < 0.5) return;
    _scroll.positionTo(target);
  }

  /// 当前该停在哪：揭示优先于激活泳道。
  double _targetOffset(
    WorkspaceState state,
    WorkspaceLaneFocusGeometry geometry,
  ) {
    final revealed = _revealedLaneId;
    if (revealed != null && revealed != state.activeLaneId) {
      return geometry.revealOffset(
        laneId: revealed,
        viewportWidth: _availableWidth,
      );
    }

    final active = state.activeLaneId;
    if (active == null || !geometry.containsLane(active)) {
      return geometry.clampOffset(_scroll.offset, _availableWidth);
    }

    return geometry.focusOffset(
      laneId: active,
      viewportWidth: _availableWidth,
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
    if (_hoverDwell.isPending ||
        _edgeDwell.isPending ||
        _restoreDwell.isPending) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
  }

  void _pollDwells() {
    if (!mounted) return;
    if (_inputRouter.blocksAutomatic) {
      _cancelDwells();
      return;
    }
    final now = _nowMs;
    final cubit = context.read<WorkspaceCubit>();

    final hoveredLane = _hoverDwell.takeDue(now);
    if (hoveredLane != null) {
      _activateVisually(hoveredLane);
      _scheduleFocus();
    }
    _syncHoverHighlight(now);

    final revealSide = _edgeDwell.takeDue(now);
    if (revealSide != null) {
      if (cubit.state.interaction.revealFocusesLane) {
        // 揭示即聚焦：交互交给被揭示的泳道，揭示这个**瞬态**当场结束。
        // 不自己算落点 —— `activateLane` 会经 `BlocListener` 走 post-frame 的
        // `_scheduleFocus`，那条路径用的是**聚焦**几何（最小移动 + 给 Reader
        // 留一条缝），而不是揭示几何（整条推进视口、Reader 该挤多少挤多少）。
        // 留着那条缝才谈得上「点一下回独占」，否则自动聚焦等于把独占弄丢。
        _inputRouter.selectExplicitly(revealSide);
        _activateVisually(revealSide);
        if (_revealedLaneId != null) setState(() => _revealedLaneId = null);
      } else {
        // 契约的原味：揭示只是看清楚，不动激活泳道。
        setState(() => _revealedLaneId = revealSide);
        _applyOffset();
      }
    }

    if (_restoreDwell.takeDue(now) != null) {
      setState(() => _revealedLaneId = null);
      _applyOffset();
    }

    _stopTickerIfIdle();
  }

  /// 把「已经停住了」这件事翻译成边框上的预备态。
  ///
  /// 指针还在动时 [WorkspaceDwell.isArmed] 恒为假 ⇒ 路过一条泳道**不会闪任何东西**；
  /// 只有真停下来，才先亮边框、再进行定位。输入目标已在进入时更新，不需要等这段驻留。
  void _syncHoverHighlight(int now) {
    final armed = _hoverDwell.isArmed(now) ? _hoverDwell.pendingId : null;
    if (armed == _armedHoverLaneId) return;
    setState(() => _armedHoverLaneId = armed);
  }

  /// 预备态要**当场**撤掉：轮询定时器一停就没人再算了，留着它就是一道赖在边框上的
  /// 高亮（指针都走了，那条泳道还像是「正准备被激活」）。
  void _clearHoverHighlight() {
    if (_armedHoverLaneId == null) return;
    setState(() => _armedHoverLaneId = null);
  }

  // ── 指针 ───────────────────────────────────────────────────────────────

  /// 悬停驻留定位：输入目标立即更新，停够久再激活视觉位置。
  ///
  /// 每泳道可覆写定位开关与延迟，未配置时继承 Reader/面板全局偏好。
  /// 键盘目标跟随和视觉定位各自独立。
  ///
  /// [isRail] 的泳道**一律跳过**：44px 的紧凑轨（用户折叠的、或 Reader 独占时
  /// 的切换栏轨）已经在当「切换把手」用了，读数时指针扫过去是常事，
  /// 停一下就跳焦点会把这条把手变成陷阱。
  void _handleLaneHoverEnter(
    String laneId,
    WorkspaceState state, {
    required bool isRail,
  }) {
    _hoveredLaneId = laneId;
    _hoveredIsRail = isRail;
    // 进了被揭示的那条泳道 ⇒ 取消「回到 Reader」的计时（用户在看它）。
    if (laneId == _revealedLaneId) {
      _restoreDwell.cancel();
    }

    if (isRail) return;
    final preference = state.interaction.interactionForLane(laneId);
    _inputRouter.hover(laneId, follows: preference.inputTargetOnHover);
    _armHoverPositioning(laneId, state);
  }

  void _armHoverPositioning(
    String laneId,
    WorkspaceState state, {
    bool pointerMoved = false,
  }) {
    final preference = state.interaction.interactionForLane(laneId);
    if (!preference.autoReveal ||
        _inputRouter.blocksAutomatic ||
        (_scroll.hasClients &&
            _scroll.position.isScrollingNotifier.value &&
            !(pointerMoved && _scroll.isPositioning))) {
      return;
    }
    _hoverDwell.enter(
      laneId,
      nowMs: _nowMs,
      delayMs: state.interaction.hoverDelayForLane(laneId),
    );
    _ensureTicker();
  }

  void _handleLaneHoverExit(String laneId) {
    _inputRouter.leave(laneId);
    if (_hoveredLaneId == laneId) _hoveredLaneId = null;
    _hoverDwell.leave(laneId);
    _syncHoverHighlight(_nowMs);
    if (laneId == _revealedLaneId) {
      _maybeScheduleRestore(context.read<WorkspaceCubit>().state);
    }
    _stopTickerIfIdle();
  }

  /// 条带范围内的悬停：判定「指针是否停在视口边缘」。
  void _handleStripHover(PointerHoverEvent event) {
    // **动了就是还没停**。两个驻留的到期点跟着最后一次运动往后推，路过哪条泳道
    // 都轮不到触发；「延时」于是只承担「停住之后再看一会儿」这一件事。
    // 揭示也要走这条：契约那句是「指针**停**在视口左右边缘」，横扫过边缘不该把它呼出来。
    final now = _nowMs;
    _hoverDwell.noteMotion(now);
    _edgeDwell.noteMotion(now);
    _syncHoverHighlight(now);

    final state = context.read<WorkspaceCubit>().state;
    final hovered = _hoveredLaneId;
    if (hovered != null && !_hoveredIsRail) {
      final preference = state.interaction.interactionForLane(hovered);
      _inputRouter.hover(hovered, follows: preference.inputTargetOnHover);
      if (_hoverDwell.pendingId != hovered) {
        // 实际鼠标移动可以换定位目标；条带移动造成的合成 enter 不再连锁定位。
        _armHoverPositioning(hovered, state, pointerMoved: true);
      }
    }
    final soloArmed =
        state.layout.soloLaneId == LaneId.reader &&
        state.activeLaneId == LaneId.reader;

    // 编辑、弹层、轮盘、滚轮序列及按下都显式保护，不能靠之前是否点过来推断。
    if (!soloArmed || _inputRouter.blocksAutomatic || _availableWidth <= 0) {
      _edgeDwell.cancel();
      _maybeScheduleRestore(state);
      _stopTickerIfIdle();
      return;
    }

    final x = event.localPosition.dx;
    final y = event.localPosition.dy;
    // 命中判定交给**唤出区自己**（「设置 → 布局」里画的那几块）：
    // 指针落在左右哪一块里，就为揭示那一条泳道开始计时。
    // 上下两条边不归这里 —— 它们管的是顶栏与阅读器底栏的悬停唤出。
    final hit = state.interaction.revealZones.edgeAt(
      xPercent: _percentOf(x, _viewportWidth),
      yPercent: _percentOf(y, _viewportHeight),
    );
    String? candidate = switch (hit) {
      RevealEdge.left => LaneId.left,
      RevealEdge.right => LaneId.right,
      _ => null,
    };
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
    if (_hoveredLaneId != null) _inputRouter.leave(_hoveredLaneId!);
    _hoveredLaneId = null;
    _clearHoverHighlight();
    _maybeScheduleRestore(context.read<WorkspaceCubit>().state);
    _stopTickerIfIdle();
  }

  /// 离开一条**未被激活**的揭示 ⇒ 延时回到 Reader。
  ///
  /// `revealFocusesLane` 打开时这条路径基本走不到（揭示到点就被激活了，
  /// 于是 `revealed == activeLaneId` 的守卫直接返回）—— 那是自洽的：
  /// 「收回 Reader」是为了不留下一个没人认领的瞬态，而它现在已经是激活泳道了。
  /// 回 Reader 改由悬停聚焦或点那条 Reader 窄缝负责。
  void _maybeScheduleRestore(WorkspaceState state) {
    final revealed = _revealedLaneId;
    if (revealed == null || _inputRouter.blocksAutomatic) return;
    if (revealed == state.activeLaneId) return;
    _restoreDwell.enter(
      'restore',
      nowMs: _nowMs,
      delayMs: state.interaction.edgeRevealRestoreDelayMs,
    );
    _ensureTicker();
  }

  /// 按下时停止移动；抬起后的下一帧再确认视觉激活，保持手势命中坐标稳定。
  void _handleLanePointerDown(String laneId, int pointer) {
    _activationAfterGesture = laneId;
    _inputRouter.pointerDown(laneId, pointer);
    _cancelDwells();
    _pauseScroll();
    _claimReveal(laneId);
  }

  bool _handleLaneWheel(String laneId) {
    final accepted = _inputRouter.acceptWheel(laneId);
    if (accepted) {
      _activationAfterGesture = laneId;
      _claimReveal(laneId);
      _cancelDwells();
      _pauseScroll();
    }
    return accepted;
  }

  void _claimReveal(String laneId) {
    if (_revealedLaneId == laneId) setState(() => _revealedLaneId = null);
  }

  void _handlePointerUp(int pointer) => _inputRouter.pointerUp(pointer);

  void _cancelDwells() {
    _hoverDwell.cancel();
    _edgeDwell.cancel();
    _restoreDwell.cancel();
    _clearHoverHighlight();
    _stopTickerIfIdle();
  }

  void _pauseScroll() {
    if (_scroll.hasClients && _scroll.position.isScrollingNotifier.value) {
      _scroll.jumpTo(_scroll.offset);
      _visualRequestPending = true;
    }
  }

  void _onInputChanged() {
    if (!mounted) return;
    final wasBlocked = _wasBlocked;
    _wasBlocked = _inputRouter.blocksAutomatic;
    if (_wasBlocked) {
      _cancelDwells();
      _pauseScroll();
    } else {
      final activation = _activationAfterGesture;
      _activationAfterGesture = null;
      if (activation != null && activation == _inputRouter.targetLaneId) {
        _activationAfterGesture = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _inputRouter.blocksAutomatic) {
            _activationAfterGesture = activation;
            return;
          }
          _activateVisually(activation);
          _scheduleFocus();
        });
      } else if (_visualRequestPending) {
        _scheduleFocus();
      }
      if (wasBlocked && _hoveredLaneId != null && !_hoveredIsRail) {
        _armHoverPositioning(
          _hoveredLaneId!,
          context.read<WorkspaceCubit>().state,
        );
      }
    }
    // 目标只重建外壳；泳道内容始终交出缓存实例。
    setState(() {});
  }

  void _activateVisually(String laneId) {
    _activatingFromHover = true;
    context.read<WorkspaceCubit>().activateLane(laneId);
    // cubit stream 异步通知，在其投递之后解除，避免视觉 dwell 改写键盘目标。
    scheduleMicrotask(() => _activatingFromHover = false);
  }
}
