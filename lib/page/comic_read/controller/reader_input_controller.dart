import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/key.dart';
import 'package:zephyr/page/comic_read/method/reader_gesture_logic.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/page/comic_read/widgets/radial/reader_radial_menu_overlay.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_fullscreen_scope.dart';

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

  /// 动作派发器（绑定表解析出的 action id → 本仓的执行体）。
  ///
  /// 懒建：它要握着 [actionController]，而后者是 `setActionController` 之后才有的。
  /// 第一次有输入进来时必然已经设好了。
  ReaderActionDispatcher? _dispatcher;
  ReaderActionDispatcher get _actionDispatcher => _dispatcher ??= ReaderActionDispatcher(
    context: context,
    actions: actionController,
    onToggleMenu: onToggleMenu,
    onToggleFullscreen: toggleReaderFullscreen,
    onOpenSettings: () => unawaited(showReaderSettingsSheet(context)),
    onResetView: resetViewerTransformIfNeeded,
    onOpenRadialMenu: openRadialMenuAtCenter,
    onBeforePageTurn: restoreScaleForPageTurnAction,
  );

  /// 当前可用的绑定表（裸数组 JSON）。`null` = 不走绑定表：
  /// 开关关着，或者表还没播种 / 被导坏 —— 那种情况下回退到改造前的硬编码判断，
  /// 而不是「什么都不做」。
  String? get _runtimeBindings {
    final setting = context.read<GlobalSettingCubit>().state;
    return OperationBindingStore.runtimeBindingsJson(
      setting.operationBindingSetting,
    );
  }

  // ── 轮盘：按住唤出 ──────────────────────────────────────────────────────────

  /// 按住多久唤出轮盘。
  ///
  /// 这里**不用** `GestureDetector.onLongPress`：那会和 `InteractiveViewer` 的缩放
  /// 识别器抢手势竞技场，表现为「按住想放大时突然弹出轮盘」。`Listener` 自己计时
  /// 不参与竞技场，两条路互不干扰 —— 代价是要自己管位移阈值（[kRadialHoldSlop]）。
  static const int kRadialHoldMilliseconds = 450;

  /// 超过这个位移就认为用户在拖动/缩放，不该开轮盘。
  static const double kRadialHoldSlop = 14.0;

  Timer? _radialHoldTimer;
  Offset? _radialHoldFrom;

  /// 最近一次抬起的全局坐标 —— 轮盘浮层要用它决定「松在哪一格」。
  Offset? _radialReleasePosition;

  /// 这次手势已经用「按住」开出了轮盘：随后的单击不该再被当成翻页点击。
  bool _radialOpenedByHold = false;

  /// 运行时可用的轮盘文档 JSON（`null` = 轮盘这条通道不走：总开关关着、轮盘自己关着、
  /// 或文档读不出）。
  String? get _radialConfigJson => OperationBindingStore.runtimeRadialJson(
    context.read<GlobalSettingCubit>().state.operationBindingSetting,
  );

  void _armRadialHold(PointerDownEvent event) {
    // 只认主键：右键/中键的按下本来就不该开出轮盘（那是另一族输入，将来单独绑）。
    if (event.buttons != kPrimaryButton) return;
    if (_radialConfigJson == null || _runtimeBindings == null) return;
    _radialOpenedByHold = false;
    _radialHoldFrom = event.position;
    _radialHoldTimer?.cancel();
    _radialHoldTimer = Timer(
      const Duration(milliseconds: kRadialHoldMilliseconds),
      () {
        _radialHoldTimer = null;
        final from = _radialHoldFrom;
        _radialHoldFrom = null;
        if (from == null || !context.mounted) return;
        _radialOpenedByHold = true;
        showRadialMenu(from);
      },
    );
  }

  /// 按住期间的位移检查（同时也是浮层要用的「指针现在在哪」）。
  void _trackRadialHold(PointerEvent event) {
    final from = _radialHoldFrom;
    if (from == null) return;
    const slop2 = kRadialHoldSlop * kRadialHoldSlop;
    if ((event.position - from).distanceSquared > slop2) _cancelRadialHold();
  }

  void _cancelRadialHold() {
    _radialHoldTimer?.cancel();
    _radialHoldTimer = null;
    _radialHoldFrom = null;
  }

  /// 在 [globalCenter]（全局坐标）处开出轮盘。
  ///
  /// 浮层只拿到**形状**（configJson）与**绑定表**（bindingsArrayJson）：每一格是什么
  /// 动作由引擎回答，所以「设置页改完不用重启」这条判据在轮盘上同样成立。
  void showRadialMenu(Offset globalCenter) {
    if (!context.mounted) return;
    final bindings = _runtimeBindings;
    final config = _radialConfigJson;
    if (bindings == null || config == null) return;
    ReaderRadialMenu.show(
      context,
      globalCenter: globalCenter,
      configJson: config,
      bindingsArrayJson: bindings,
      dispatcher: _actionDispatcher,
    );
  }

  /// 键盘 / 点击绑定的 `reader.open-radial-menu` 走这里：落在阅读区正中。
  void openRadialMenuAtCenter() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    showRadialMenu(
      renderObject.localToGlobal(renderObject.size.center(Offset.zero)),
    );
  }

  /// 阅读器全屏切换：工作台泳道里交给宿主，独立阅读器自己切。
  ///
  /// 按键（F11）与 `reader.fullscreen` 动作共用这一处 —— 两条路必须落同一个实现，
  /// 否则「同一个动作按来源有两种结果」会在某个布局下诡异地不一致。
  Future<void> toggleReaderFullscreen() async {
    final fullscreenScope = ReaderFullscreenScope.maybeOf(context);
    if (fullscreenScope != null) {
      fullscreenScope.onToggleFullscreen();
      return;
    }
    await _onToggleDesktopFullscreen();
  }

  void setActionController(ReaderActionController controller) {
    actionController = controller;
  }

  void init() {
    transformationController.addListener(_onTransformationChanged);
  }

  void dispose() {
    _radialHoldTimer?.cancel();
    // 阅读器整棵拆掉时轮盘还开着，会留下一层没人收的遮罩。
    ReaderRadialMenu.dismiss();
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
        onPointerMove: _trackRadialHold,
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) =>
      handleKeyEvent(event);

  /// 阅读器的按键处理入口。
  ///
  /// 它有两个入口，逻辑**只有这一处**：① 挂在本子树的 `Focus` 上
  /// （见 [buildInteractiveViewer]）；② 经 `ReaderInputBridge` 登记给工作台 ——
  /// 当焦点离开阅读器子树时（例如打开阅读设置面板，模态路由会把主焦点拿走），
  /// 由工作台把冒泡上来的按键转交到这里。于是「左右键被设置面板吃掉」不再发生。
  ///
  /// 「这个键是什么动作」的判断有两份，按开关切换：绑定表在位时是 **Rust 引擎**
  /// （`operation_binding`，改绑定不重新编译即生效）；表不可用时是 `key.dart` 里
  /// 改造前的硬编码名单。两份**不叠加**：表在位时没人认的键一律放行，
  /// 不回落名单 —— 回落等于「把一条绑定删掉它还在生效」。
  KeyEventResult handleKeyEvent(KeyEvent event) {
    final bindings = _runtimeBindings;
    if (bindings != null) {
      // 只处理按下与长按重复：抬起/修饰键独立事件不该触发动作（与旧名单同一口径）。
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      return _actionDispatcher.dispatchKeyEvent(event, bindings)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(toggleReaderFullscreen());
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

    // 这次「单击」其实是按住唤出轮盘之后的那一次**松手**：进行中的指针不会命中刚插入的
    // 浮层，所以抬起落回这里。转交给浮层，松在哪一格就执行那一格。
    if (_radialOpenedByHold) {
      _radialOpenedByHold = false;
      final release = _radialReleasePosition;
      if (release != null) {
        ReaderRadialMenu.commitAt(release, keepOpenOnMiss: true);
      } else {
        ReaderRadialMenu.dismiss();
      }
      return;
    }

    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    // 落点与尺码都取这次点击**自己**那一对（[ReaderTapSample]）：前者相对接收手势的
    // 那个盒子，后者是那个盒子量出来的尺寸。它们同一个坐标系，分区才分得对；
    // 换成 `details.globalPosition`（窗口坐标）会让分区整体平移「泳道左边缘」
    // 那么多，表现为泳道模式下**点哪儿都翻下一页**。
    ReaderGestureLogic.handleTap(
      actionController: actionController,
      context: context,
      sample: tap,
      dispatcher: _actionDispatcher,
      bindingsArrayJson: _runtimeBindings,
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
    _armRadialHold(event);
    if (!_isTouchPointer(event.kind)) return;
    _activeTouchPointers.add(event.pointer);
    _updateMultiTouchScrollLock();
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    // 抬起的位置要留给轮盘浮层：进行中的指针不会命中刚插入的浮层，
    // 所以「按住拖到某一格再松手」得由这里把坐标转交过去（见 `_onTap` 的轮盘分支）。
    _radialReleasePosition = event.position;
    _cancelRadialHold();
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
