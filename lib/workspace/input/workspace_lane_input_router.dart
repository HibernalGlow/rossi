import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/widgets.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/util/input/reader_input_context.dart';
import 'package:zephyr/util/input/reader_input_guard.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';

/// 泳道只报告目标与交互归属；动作解析仍归 operation_binding。
/// 不写入布局快照，也不申请 FocusNode，所以悬停不会抢走编辑器。
class WorkspaceLaneInputRouter extends ChangeNotifier
    with WidgetsBindingObserver {
  WorkspaceLaneInputRouter({
    required this.hasLane,
    required this.interactionOwned,
    String? initialLaneId,
  }) : _target = initialLaneId {
    FocusManager.instance.addListener(refreshOwnership);
    WidgetsBinding.instance.addObserver(this);
    ReaderInputBridge.instance.attachContextSource(this, contexts);
  }

  final bool Function(String) hasLane;
  final bool Function() interactionOwned;
  String? _target;
  String? _hovered;
  bool _hoverFollows = true;
  final Set<int> _pointers = {};
  String? _wheelLane;
  Timer? _wheelEnd;
  bool _windowFocused = true;
  bool _disposed = false;

  String? get targetLaneId => _target;
  bool get hasGesture => _pointers.isNotEmpty || _wheelLane != null;
  bool get ownsOverlay => ReaderInputGuard.blocksKeyboard || interactionOwned();
  bool get blocksAutomatic => !_windowFocused || ownsOverlay || hasGesture;

  Set<ReaderInputContext> contexts() {
    if (ReaderInputGuard.isEditing) return const {ReaderInputContext.editor};
    if (!_windowFocused || ownsOverlay) return const {ReaderInputContext.modal};
    if (_target != null && hasLane(_target!) && _target != LaneId.reader) {
      return const {ReaderInputContext.panel};
    }
    return ActiveVideoScope.instance.hasTarget
        ? const {ReaderInputContext.reader, ReaderInputContext.video}
        : const {ReaderInputContext.reader};
  }

  void _select(String laneId) {
    if (!hasLane(laneId) || _target == laneId) return;
    _target = laneId;
    notifyListeners();
  }

  void hover(String laneId, {required bool follows}) {
    _hovered = laneId;
    _hoverFollows = follows;
    if (!blocksAutomatic && follows) _select(laneId);
  }

  void leave(String laneId) {
    if (_hovered == laneId) _hovered = null;
    // 空白/离窗保留最近目标。
  }

  /// 导航/键盘显式切换，包括旧的触屏轨入口。
  void selectExplicitly(String laneId) {
    if (!ownsOverlay && !hasGesture) _select(laneId);
  }

  void pointerDown(String laneId, int pointer) {
    if (_pointers.isEmpty && !interactionOwned()) _select(laneId);
    trackPointer(pointer);
  }

  /// 条带把手等没有泳道内容目标的拖动也暂停自动定位。
  void trackPointer(int pointer) {
    if (_pointers.add(pointer)) notifyListeners();
  }

  void pointerUp(int pointer) {
    if (!_pointers.remove(pointer)) return;
    refreshOwnership();
  }

  /// 每次 wheel burst 固定首个命中泳道。跨泳道的剩余信号由采集层消费，
  /// 原泳道内的信号仍交原有绑定/Scrollable 仲裁，不复制或重发信号。
  bool acceptWheel(String laneId) {
    if (!_windowFocused || ReaderInputGuard.isModal || interactionOwned()) {
      return false;
    }
    final first = _wheelLane == null;
    _wheelLane ??= laneId;
    _wheelEnd?.cancel();
    _wheelEnd = Timer(const Duration(milliseconds: 180), () {
      _wheelLane = null;
      _wheelEnd = null;
      if (!_disposed) refreshOwnership();
    });
    if (first) {
      // 文本编辑只拥有键盘；命中本泳道的原生滚动仍可使用。
      if (!ReaderInputGuard.isEditing) _select(laneId);
      notifyListeners();
    }
    return _wheelLane == laneId;
  }

  void refreshOwnership() {
    if (_disposed) return;
    if (!blocksAutomatic && _hovered != null && _hoverFollows) {
      _select(_hovered!);
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setWindowFocused(state == AppLifecycleState.resumed);
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _setWindowFocused(event.state == ViewFocusState.focused);
  }

  void _setWindowFocused(bool value) {
    _windowFocused = value;
    ReaderInputBridge.instance.windowFocused = value;
    refreshOwnership();
  }

  @override
  void dispose() {
    _disposed = true;
    _wheelEnd?.cancel();
    FocusManager.instance.removeListener(refreshOwnership);
    WidgetsBinding.instance.removeObserver(this);
    ReaderInputBridge.instance.detachContextSource(this);
    ReaderInputBridge.instance.windowFocused = true;
    super.dispose();
  }
}
