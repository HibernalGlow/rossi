import 'dart:async';
import 'dart:convert';
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
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/util/input/binding_pointer_tracker.dart';
import 'package:zephyr/video/view/active_video_scope.dart';
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
    this.onSwitchBook,
  });

  final BuildContext context;
  final ReaderCubit readerCubit;
  late ReaderActionController actionController;
  final PageController pageController;
  final TransformationController transformationController;
  final VoidCallback onToggleMenu;
  final Future<void> Function(bool forward)? onSwitchBook;
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
  bool _customTouchDrag = false;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 动作派发器（绑定表解析出的 action id → 本仓的执行体）。
  ///
  /// 懒建：它要握着 [actionController]，而后者是 `setActionController` 之后才有的。
  /// 第一次有输入进来时必然已经设好了。
  ReaderActionDispatcher? _dispatcher;
  ReaderActionDispatcher get _actionDispatcher =>
      _dispatcher ??= ReaderActionDispatcher(
        context: context,
        actions: actionController,
        onToggleMenu: onToggleMenu,
        onToggleFullscreen: toggleReaderFullscreen,
        onOpenSettings: () => unawaited(showReaderSettingsSheet(context)),
        onResetView: resetViewerTransformIfNeeded,
        onOpenRadialMenu: openRadialMenu,
        onConfirmRadialMenu: ReaderRadialMenu.confirm,
        onBeforePageTurn: restoreScaleForPageTurnAction,
        onSwitchBook: onSwitchBook,
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

  final _keyHolds = <PhysicalKeyboardKey, Timer>{};
  Size _inputSize = Size.zero;
  late final _pointerBindings = BindingPointerTracker(
    deferAreaClicks: true,
    lookup: (input) {
      final bindings = _runtimeBindings;
      return bindings == null
          ? null
          : _actionDispatcher.resolveInput(input, bindings);
    },
    dispatch: (input) {
      if (!context.mounted) return false;
      final bindings = _runtimeBindings;
      return bindings != null &&
          _actionDispatcher.dispatchInput(
            jsonEncode(input),
            bindings,
            fromKeyboard: false,
          );
    },
  );

  String? _areaAt(Offset point) {
    if (_runtimeBindings == null) return null;
    return OperationBindingStore.areaAtPoint(
      x: point.dx,
      y: point.dy,
      width: _inputSize.width,
      height: _inputSize.height,
    );
  }

  // ── 轮盘：一条输入把它开出来 ────────────────────────────────────────────────

  /// 轮盘文档 JSON（形状）；`null` = 轮盘这条通道不走（总开关关着、轮盘自己关着、
  /// 或文档读不出）。
  String? get _radialConfigJson => OperationBindingStore.runtimeRadialJson(
    context.read<GlobalSettingCubit>().state.operationBindingSetting,
  );

  /// 最近一次按下的全局坐标 —— 轮盘开在这里（neoview 的 `lastInputPoint` 同一件事）。
  Offset? _lastPointerGlobal;

  /// 这次按下把轮盘开出来了 ⇒ 它的抬起要转交给浮层。
  ///
  /// 需要转交是因为 Flutter 对**进行中的指针**复用按下时的命中结果：浮层是按下之后
  /// 才插进 Overlay 的，于是同一次手势的抬起事件根本到不了它，只会回到阅读器。
  int? _radialOpeningPointer;

  /// 一次按下 → 问引擎「这一按是什么动作」→ 派发。
  ///
  /// 用 `Listener` 而不是 `GestureDetector.onSecondaryTap`：neoview 的出厂绑法是
  /// **右键按下**开轮盘（按下即出、拖到某一格松手即执行），而 tap 要等到抬起才成立。
  /// 走绑定表意味着用户可以把轮盘改绑到中键、某个修饰键组合，或者干脆不绑。
  /// 在 [globalCenter]（全局坐标）处开出轮盘。
  ///
  /// 浮层只拿到**形状**与**绑定表**：每一格是什么动作由引擎回答，所以「设置页改完
  /// 不用重启」这条判据在轮盘上同样成立。
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
      openingPointer: _radialOpeningPointer,
    );
  }

  /// 唤出轮盘：知道指针在哪就开在那儿，否则开在阅读区正中。
  ///
  /// 两个入口共用它（`radial.open-default` 的执行体）：鼠标按下时指针位置是准的，
  /// 而键盘（出厂 `Enter`）没有指针参与 —— 那时「正中间」是唯一不让人意外的落点。
  void openRadialMenu() {
    final at = _lastPointerGlobal;
    if (at != null) {
      showRadialMenu(at);
      return;
    }
    _openRadialMenuAtCenter();
  }

  void _openRadialMenuAtCenter() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    showRadialMenu(
      renderObject.localToGlobal(renderObject.size.center(Offset.zero)),
    );
  }

  /// 轮盘开着时，**唤出那次手势**的后续事件转交给浮层。
  ///
  /// 转交成功就不再让阅读器的手势采集器看见这一拖 —— 否则松手还会被当成滑动/点击。
  /// 阅读器看得见这根指针的每一次 move/up/cancel：Flutter 对进行中的指针复用按下时的
  /// 命中结果，而按下那一刻浮层还没插进 Overlay，所以那次手势整段都回到阅读器。
  bool _forwardToRadialMenu(PointerEvent event) {
    final opening = _radialOpeningPointer;
    return opening != null && ReaderRadialMenu.forwardPointer(event, opening);
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
    // 阅读器整棵拆掉时轮盘还开着，会留下一层没人收的遮罩。
    ReaderRadialMenu.dismiss();
    for (final timer in _keyHolds.values) {
      timer.cancel();
    }
    _keyHolds.clear();
    _pointerBindings.dispose();
    transformationController.removeListener(_onTransformationChanged);
    focusNode.dispose();
  }

  /// 构建阅读核心交互层：键盘、手势、缩放、多指锁滚动。
  Widget buildInteractiveViewer() {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final readSetting = globalSettingState.readSetting;
    final isDoubleTapActionEnabled =
        readSetting.doubleTapZoom ||
        readSetting.doubleTapOpenMenu ||
        (parseBindings(
              globalSettingState.operationBindingSetting.bindingsJson,
            )?.any(
              (row) =>
                  row['enabled'] == true &&
                  (row['input'] as Map)['action'] == 'double-click',
            ) ??
            false);

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: (event) {
          if (_forwardToRadialMenu(event)) {
            _pointerBindings.cancel();
          } else if (ReaderRadialMenu.isOpen) {
            _pointerBindings.cancel();
          } else {
            _pointerBindings.move(event);
          }
        },
        onPointerUp: _onPointerUpOrCancel,
        onPointerCancel: _onPointerUpOrCancel,
        // `LayoutBuilder` 紧贴 `GestureDetector` 外沿：它拿到的 `constraints.biggest`
        // 就是那个盒子的尺寸，于是与 `onTapDown` 给的 `localPosition` **同一个
        // 坐标系**。点击分区要的正是这两样东西，而它们只在这一层能成对拿到 ——
        // 于是把尺寸**捕获在这个闭包里**、和落点一起做成 [ReaderTapSample]：
        // 落点来自哪个盒子，尺码就必然是那个盒子的。
        child: BindingPointerSignalRegion(
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPointerPanZoomStart,
          onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
          onPointerPanZoomEnd: _onPointerPanZoomEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final surface = constraints.biggest;
              _inputSize = surface;
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
    if (event is KeyUpEvent) {
      _keyHolds.remove(event.physicalKey)?.cancel();
      return KeyEventResult.ignored;
    }
    if (bindings != null) {
      if (event is KeyDownEvent) {
        final json = keyboardInputJsonOf(event);
        if (json != null) {
          final holdInput = {
            ...Map<String, dynamic>.from(jsonDecode(json) as Map),
            'trigger': 'hold',
          };
          final hold = _actionDispatcher.resolveInput(holdInput, bindings);
          if (hold != null) {
            final input = hold['input'] as Map;
            _keyHolds[event.physicalKey]?.cancel();
            _keyHolds[event.physicalKey] = Timer(
              Duration(
                milliseconds: (input['durationMs'] as num? ?? 450)
                    .toInt()
                    .clamp(100, 5000),
              ),
              () {
                if (!context.mounted ||
                    !HardwareKeyboard.instance.physicalKeysPressed.contains(
                      event.physicalKey,
                    )) {
                  return;
                }
                final current = _runtimeBindings;
                if (current != null) {
                  _actionDispatcher.dispatchInput(
                    jsonEncode(holdInput),
                    current,
                    fromKeyboard: true,
                  );
                }
              },
            );
            return KeyEventResult.handled;
          }
        }
      }
      if (event is KeyRepeatEvent && _keyHolds.containsKey(event.physicalKey)) {
        return KeyEventResult.handled;
      }
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
    final bindings = _runtimeBindings;
    if (bindings != null) {
      // 手势竞争胜出后，执行指针采集器记录的真实格子。视频子控件赢得点击时
      // 不会走到这里，避免它自己的暂停/跳转与外层重复触发。未绑定格子也到此结束，
      // 不能再回退到旧三分区，否则 Neo 留空的左上格会被当成左中格翻页。
      _tap = null;
      final input = _pointerBindings.deferredAreaClick;
      if (!_pointerBindings.claimed && input != null) {
        _actionDispatcher.dispatchInput(
          jsonEncode(input),
          bindings,
          fromKeyboard: false,
        );
      }
      return;
    }
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
    if (_runtimeBindings != null && _pointerBindings.claimed) return;
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
    _radialOpeningPointer = event.pointer;
    _lastPointerGlobal = event.position;
    _pointerBindings.down(event, _areaAt(event.localPosition));

    if (!_isTouchPointer(event.kind)) return;
    _activeTouchPointers.add(event.pointer);
    final bindings = _runtimeBindings;
    _customTouchDrag =
        bindings != null &&
        ['left', 'right', 'up', 'down'].any(
          (direction) =>
              _actionDispatcher.resolveInput({
                'device': 'touch',
                'gesture': 'swipe-$direction',
                'fingers': _activeTouchPointers.length,
              }, bindings) !=
              null,
        );
    _updateMultiTouchScrollLock();
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    // 先转交再清：轮盘要用这个「唤出指针」认出这次抬起是不是它那一根。
    final forwarded = _forwardToRadialMenu(event);
    _radialOpeningPointer = null;
    if (event is PointerCancelEvent || forwarded || ReaderRadialMenu.isOpen) {
      // 轮盘接住了这次抬起，避免同时触发阅读器 click 绑定。
      _pointerBindings.cancel();
    } else if (event is PointerUpEvent) {
      _pointerBindings.up(event);
    }
    if (!_isTouchPointer(event.kind)) return;
    _activeTouchPointers.remove(event.pointer);
    if (_activeTouchPointers.isEmpty) _customTouchDrag = false;
    _updateMultiTouchScrollLock();
  }

  bool _isTouchPointer(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  double _trackpadPanAccumulator = 0;
  DateTime? _lastTrackpadWheelTime;

  bool _dispatchWheelDelta(double dy, {PointerSignalEvent? signalEvent}) {
    if (!_isDesktopPlatform || dy == 0) return false;
    final bindings = _runtimeBindings;
    if (bindings == null) return false;
    final input = bindingWheelInput(dy);
    // 滚轮由命中测试送到阅读区，不依赖键盘焦点。右侧设置页可能把桥的上下文
    // 留在 panel；复用它会使 reader 绑定失配，必须按当前内容采集本次上下文。
    final contexts = [
      'reader',
      if (ActiveVideoScope.instance.hasTarget) 'video',
    ];
    if (_actionDispatcher.resolveInput(input, bindings, contexts: contexts) ==
        null) {
      return false;
    }
    final before = transformationController.value.clone();
    void execute() {
      transformationController.value = before;
      _actionDispatcher.dispatchInput(
        jsonEncode(input),
        bindings,
        fromKeyboard: false,
        contexts: contexts,
      );
    }

    if (signalEvent != null) {
      // InteractiveViewer 直接处理缩放信号；消费绑定输入时复原它的本次变换。
      GestureBinding.instance.pointerSignalResolver.register(signalEvent, (_) {
        execute();
      });
    } else {
      execute();
    }
    return true;
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadPanAccumulator = 0;
    _lastTrackpadWheelTime = null;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_isDesktopPlatform) return;
    final dy = event.panDelta.dy;
    if (dy == 0) return;
    if ((_trackpadPanAccumulator > 0 && dy < 0) ||
        (_trackpadPanAccumulator < 0 && dy > 0)) {
      _trackpadPanAccumulator = 0;
    }
    _trackpadPanAccumulator += dy;
    // 触控板滑动累计超过 24px 时触发一次滚轮动作并步进防抖
    if (_trackpadPanAccumulator.abs() >= 24) {
      final now = DateTime.now();
      if (_lastTrackpadWheelTime == null ||
          now.difference(_lastTrackpadWheelTime!).inMilliseconds >= 120) {
        final consumed = _dispatchWheelDelta(_trackpadPanAccumulator);
        if (consumed) {
          _lastTrackpadWheelTime = now;
        }
      }
      _trackpadPanAccumulator = 0;
    }
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadPanAccumulator = 0;
    _lastTrackpadWheelTime = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isDesktopPlatform) return;
    if (_dispatchWheelDelta(event.scrollDelta.dy, signalEvent: event)) {
      return;
    }

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

    // 绑定表在位时，未命中的输入留给 Scrollable / 缩放；不再执行旧翻页规则。
    // 否则删除、停用或改绑滚轮之后，它仍会绕过配置翻页。
    if (_runtimeBindings != null) return;

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
        _customTouchDrag ||
        _activeTouchPointers.length >= 2 ||
        currentScale > kScaleLockThreshold;
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
