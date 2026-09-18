import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/key.dart';
import 'package:zephyr/page/comic_read/method/reader_gesture_logic.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 阅读器输入控制器。
///
/// 负责键盘、手势、滚轮、缩放交互的识别与分发，
/// 把具体动作委托给 [ReaderActionController]，把页面级回调交回 State。
class ReaderInputController {
  ReaderInputController({
    required this.context,
    required this.readerCubit,
    required this.pageController,
    required this.transformationController,
    required this.onToggleMenu,
    required this._onToggleDesktopFullscreen,
    required this.onRefreshState,
    required this.isScrollLockedByMultiTouch,
    required this.onUpdateScrollLock,
    required this.buildColumnMode,
    required this.buildRowMode,
  });

  final BuildContext context;
  final ReaderCubit readerCubit;
  late ReaderActionController actionController;
  final PageController pageController;
  final TransformationController transformationController;
  final VoidCallback onToggleMenu;
  final Future<void> Function() _onToggleDesktopFullscreen;
  final VoidCallback onRefreshState;
  final bool Function() isScrollLockedByMultiTouch;
  final void Function(bool locked) onUpdateScrollLock;
  final Widget Function(bool enableDoublePage) buildColumnMode;
  final Widget Function() buildRowMode;

  final FocusNode focusNode = FocusNode();
  final Set<int> _activeTouchPointers = <int>{};

  /// 最近一次点击的**成对样本**（落点 + 接收它的那个盒子量出来的尺寸）。
  ///
  /// 两样必须同时记、同时用（见 [ReaderTapSample]）：分区算的是「落点落在这块面的
  /// 哪个三分之一里」，把尺寸换到别的坐标系就等于把整条分区平移。早先这两样分别
  /// 住在两个字段里（落点来自 `onTapDown`、尺寸来自 `LayoutBuilder` 的**每次** build），
  /// 而「这一刻的落点」只跟「这一块面的尺寸」成对 —— 分开存就允许配出
  /// 「窗口坐标的落点 × 泳道的尺寸」，那正是工作台里**点哪儿都翻下一页、
  /// 中间唤不出上下栏、左边点不出上一页**的原因。现在它们被同一个不可变值绑在一起，
  /// 落点与尺码不可能来自不同的两次时机。
  ReaderTapSample? _tap;
  TapDownDetails? _doubleTapDownDetails;
  bool _isCtrlPressed = false;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void setActionController(ReaderActionController controller) {
    actionController = controller;
  }

  void init() {
    transformationController.addListener(_onTransformationChanged);
  }

  void dispose() {
    focusNode.dispose();
  }

  /// 构建阅读核心交互层：键盘、手势、缩放、多指锁滚动。
  Widget buildInteractiveViewer() {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final readSetting = globalSettingState.readSetting;
    final isDoubleTapActionEnabled =
        readSetting.doubleTapZoom || readSetting.doubleTapOpenMenu;

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUpOrCancel,
        onPointerCancel: _onPointerUpOrCancel,
        onPointerSignal: _onPointerSignal,
        // `LayoutBuilder` 紧贴 `GestureDetector` 外沿：它拿到的 `constraints.biggest`
        // 就是那个盒子的尺寸，于是与 `onTapDown` 给的 `localPosition` **同一个
        // 坐标系**。点击分区要的正是这两样东西，而它们只在这一层能成对拿到 ——
        // 于是把尺寸**捕获在这个闭包里**、和落点一起做成 [ReaderTapSample]：
        // 落点来自哪个盒子，尺码就必然是那个盒子的。
        child: LayoutBuilder(
          builder: (context, constraints) {
            final surface = constraints.biggest;
            return GestureDetector(
              onTap: _onTap,
              onTapDown: (details) => _tap = ReaderTapSample(
                localPosition: details.localPosition,
                viewportSize: surface,
              ),
              onDoubleTapDown: isDoubleTapActionEnabled
                  ? (details) => _doubleTapDownDetails = details
                  : null,
              onDoubleTap: isDoubleTapActionEnabled ? _onDoubleTap : null,
              child: InteractiveViewer(
                transformationController: transformationController,
                boundaryMargin: EdgeInsets.zero,
                minScale: kMinReaderScale,
                maxScale: kMaxReaderScale,
                scaleEnabled:
                    !_isDesktopPlatform ||
                    _isCtrlPressed ||
                    _activeTouchPointers.length >= 2 ||
                    transformationController.value.getMaxScaleOnAxis() >
                        kScaleLockThreshold,
                interactionEndFrictionCoefficient: kReaderPanFriction,
                onInteractionUpdate: (_) => _updateMultiTouchScrollLock(),
                onInteractionEnd: (_) => _updateMultiTouchScrollLock(),
                child: isColumnReadMode(readSetting.readMode)
                    ? buildColumnMode(readSetting.doublePageMode)
                    : buildRowMode(),
              ),
            );
          },
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(_onToggleDesktopFullscreen());
      return KeyEventResult.handled;
    }
    final handled = handleGlobalKeyEvent(event, actionController);
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Future<void> _onTap() async {
    // 延迟一帧处理，减少单击和双击的手势竞争。
    await Future.delayed(Duration.zero);
    final tap = _tap;
    if (tap == null || !context.mounted) return;
    _tap = null;

    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    // 落点与尺码都取这次点击**自己**那一对（[ReaderTapSample]）：前者相对接收手势的
    // 那个盒子，后者是那个盒子量出来的尺寸。它们同一个坐标系，分区才分得对；
    // 换成 `details.globalPosition`（窗口坐标）会让分区整体平移「泳道左边缘」
    // 那么多，表现为泳道模式下**点哪儿都翻下一页**。
    ReaderGestureLogic.handleTap(
      actionController: actionController,
      context: context,
      sample: tap,
      onToggleMenu: readSetting.doubleTapOpenMenu
          ? () {
              final cubit = context.read<ReaderCubit>();
              if (cubit.state.isMenuVisible) {
                onToggleMenu();
              }
            }
          : onToggleMenu,
      onBeforePageTurn: restoreScaleForPageTurnAction,
    );
  }

  void _onDoubleTap() {
    if (!context.mounted) return;
    _tap = null;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    if (readSetting.doubleTapZoom) {
      _onDoubleTapZoom();
      return;
    }
    if (readSetting.doubleTapOpenMenu) {
      _onDoubleTapOpenMenu();
    }
  }

  void _onDoubleTapOpenMenu() {
    onToggleMenu();
    _doubleTapDownDetails = null;
  }

  void _onDoubleTapZoom() {
    final details = _doubleTapDownDetails;
    if (details == null) return;

    if (resetViewerTransformIfNeeded()) {
      _doubleTapDownDetails = null;
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      _doubleTapDownDetails = null;
      return;
    }

    // 以双击点为锚点放大，手感更自然。
    final localPosition = renderObject.globalToLocal(details.globalPosition);
    const targetScale = kDoubleTapZoomScale;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        renderObject.size.width / 2 - localPosition.dx * targetScale,
        renderObject.size.height / 2 - localPosition.dy * targetScale,
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, 1, 1);

    transformationController.value = matrix;
    _updateMultiTouchScrollLock();
    _doubleTapDownDetails = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_isTouchPointer(event.kind)) return;
    _activeTouchPointers.add(event.pointer);
    _updateMultiTouchScrollLock();
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (!_isTouchPointer(event.kind)) return;
    _activeTouchPointers.remove(event.pointer);
    _updateMultiTouchScrollLock();
  }

  bool _isTouchPointer(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isDesktopPlatform) return;

    final newCtrlPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.controlLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.controlRight,
        );

    if (_isCtrlPressed != newCtrlPressed) {
      _isCtrlPressed = newCtrlPressed;
      onRefreshState();
    }

    final readMode = context
        .read<GlobalSettingCubit>()
        .state
        .readSetting
        .readMode;
    if (!newCtrlPressed && readMode != 0) {
      if (event.scrollDelta.dy > 0) {
        actionController.onPageActionNext();
      } else if (event.scrollDelta.dy < 0) {
        actionController.onPageActionPrev();
      }
    }
  }

  void _onTransformationChanged() {
    _updateMultiTouchScrollLock();
  }

  // 多指触控或放大状态下锁定滚动，减少与翻页手势互相干扰。
  void _updateMultiTouchScrollLock() {
    final currentScale = transformationController.value.getMaxScaleOnAxis();
    final shouldLock =
        _activeTouchPointers.length >= 2 || currentScale > kScaleLockThreshold;
    if (isScrollLockedByMultiTouch() == shouldLock || !context.mounted) return;
    onUpdateScrollLock(shouldLock);
  }

  /// 翻页前统一归位缩放与位移，避免跨页后仍停留在局部放大状态。
  bool resetViewerTransformIfNeeded() {
    final matrix = transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final tx = matrix.storage[12].abs();
    final ty = matrix.storage[13].abs();
    final shouldReset = scale > kScaleLockThreshold || tx > 0.5 || ty > 0.5;
    if (!shouldReset) return false;

    transformationController.value = Matrix4.identity();
    _activeTouchPointers.clear();
    _updateMultiTouchScrollLock();
    return true;
  }

  /// 供 [ReaderActionController] 翻页前调用。
  bool restoreScaleBeforeTurnPage(bool _) {
    resetViewerTransformIfNeeded();
    return false;
  }

  /// 供 State 在点击翻页前调用。
  void restoreScaleForPageTurnAction() {
    resetViewerTransformIfNeeded();
  }

  /// 供 State 在拖拽翻页前调用。
  void restoreScaleForPageDrag() {
    resetViewerTransformIfNeeded();
  }
}
