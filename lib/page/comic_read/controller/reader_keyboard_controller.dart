import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/page/comic_read/controller/reader_keyboard_repeat_timing.dart';
import 'package:zephyr/page/comic_read/method/key.dart';
import 'package:zephyr/page/comic_read/widgets/radial/reader_radial_menu_overlay.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/util/input/reader_input_bridge.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

/// 输入绑定仍由现有引擎解析；这里只控制横翻键盘长按的节奏。
class ReaderKeyboardController with WidgetsBindingObserver {
  ReaderKeyboardController({
    required this.context,
    required this.actions,
    required this.dispatcher,
    required this.runtimeBindings,
    required this.onToggleFullscreen,
  }) {
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(cancel);
    ReaderInputBridge.instance.addListener(_cancelIfBlocked);
  }

  final BuildContext context;
  final ReaderActionController actions;
  final ReaderActionDispatcher dispatcher;
  final String? Function() runtimeBindings;
  final Future<void> Function() onToggleFullscreen;
  final _customHolds = <PhysicalKeyboardKey, Timer>{};
  // 旧方向键即使还按着，也不能被系统重复事件重新激活。
  final _managedKeys = <PhysicalKeyboardKey>{};
  PhysicalKeyboardKey? _activeKey;
  Timer? _repeatTimer;

  bool get _allowed =>
      context.mounted &&
      ReaderInputBridge.instance.acceptsReaderKeyboard &&
      !ReaderRadialMenu.isOpen;

  ReaderKeyboardRepeatTiming get _timing {
    final setting = context.readEffectiveReadSetting();
    return ReaderKeyboardRepeatTiming(
      pagesPerSecond: setting.keyboardPageTurnPagesPerSecond,
      holdDelayMs: setting.keyboardPageTurnHoldDelayMs,
    );
  }

  List<String> get _contexts => ReaderInputBridge.instance.activeContexts
      .map((context) => context.name)
      .toList(growable: false);

  Map<String, dynamic>? _resolve(KeyEvent event) {
    final reverse = context
        .readEffectiveReadSetting()
        .reverseHorizontalPageTurn;
    final bindings = runtimeBindings();
    if (bindings == null) {
      final action = resolveGlobalPageKeyAction(
        event,
        reverseHorizontal: reverse,
      );
      return action == null ? null : {'action': action};
    }
    final input = keyboardInputJsonOf(event, swapHorizontal: reverse);
    return input == null
        ? null
        : dispatcher.resolveInput(
            Map<String, dynamic>.from(jsonDecode(input) as Map),
            bindings,
            contexts: _contexts,
          );
  }

  bool _isPageTurn(Map<String, dynamic>? binding) =>
      binding != null &&
      BindingAction.pageTurnFamily.contains(binding['action']) &&
      context.readEffectiveReadSetting().readMode != 0 &&
      !ActiveVideoScope.instance.seekModeActive;

  bool _dispatch(
    Map<String, dynamic> binding,
    KeyEvent event, {
    required bool repeat,
  }) {
    if (runtimeBindings() == null) {
      return handleGlobalKeyEvent(
        event,
        actions,
        reverseHorizontal: context
            .readEffectiveReadSetting()
            .reverseHorizontalPageTurn,
      );
    }
    return dispatchBindingActions(
      binding,
      isRepeat: repeat,
      execute: (action) => dispatcher.dispatch(action, fromKeyboard: true),
    );
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      _customHolds.remove(event.physicalKey)?.cancel();
      final managed = _managedKeys.remove(event.physicalKey);
      if (_activeKey == event.physicalKey) _stopRepeat();
      return managed ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (!_allowed) {
      cancel();
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent &&
        (_managedKeys.contains(event.physicalKey) ||
            _customHolds.containsKey(event.physicalKey))) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 用户显式配置的 hold 绑定优先于连续翻页，与原行为一致。
    final bindings = runtimeBindings();
    if (event is KeyDownEvent && bindings != null) {
      final json = keyboardInputJsonOf(
        event,
        swapHorizontal: context
            .readEffectiveReadSetting()
            .reverseHorizontalPageTurn,
      );
      if (json != null) {
        final holdInput = {
          ...Map<String, dynamic>.from(jsonDecode(json) as Map),
          'trigger': 'hold',
        };
        final hold = dispatcher.resolveInput(
          holdInput,
          bindings,
          contexts: _contexts,
        );
        if (hold != null) {
          _stopRepeat();
          _managedKeys.add(event.physicalKey);
          _customHolds[event.physicalKey]?.cancel();
          _customHolds[event.physicalKey] = Timer(
            Duration(
              milliseconds:
                  ((hold['input'] as Map)['durationMs'] as num? ?? 450)
                      .toInt()
                      .clamp(100, 5000),
            ),
            () {
              if (!_allowed ||
                  !HardwareKeyboard.instance.physicalKeysPressed.contains(
                    event.physicalKey,
                  )) {
                return;
              }
              final current = runtimeBindings();
              if (current != null) {
                dispatcher.dispatchInput(
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
    if (bindings == null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(onToggleFullscreen());
      return KeyEventResult.handled;
    }

    final binding = _resolve(event);
    if (binding == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent && _isPageTurn(binding)) {
      _stopRepeat();
      _managedKeys.add(event.physicalKey);
      actions.withKeyboardPageTurnDuration(
        _timing.firstAnimationDuration,
        () => _dispatch(binding, event, repeat: false),
      );
      if (binding['ignoreRepeat'] != true && _allowed) {
        _activeKey = event.physicalKey;
        _repeatTimer = Timer(_timing.holdDelay, () => _repeat(event));
      }
      return KeyEventResult.handled;
    }
    return _dispatch(binding, event, repeat: event is KeyRepeatEvent)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _repeat(KeyEvent event) {
    if (!_allowed ||
        _activeKey != event.physicalKey ||
        !HardwareKeyboard.instance.physicalKeysPressed.contains(
          event.physicalKey,
        )) {
      _stopRepeat();
      return;
    }
    // 每次重新解析：设置/方向/绑定/视频上下文变化后不执行旧动作。
    final binding = _resolve(event);
    if (!_isPageTurn(binding) || binding!['ignoreRepeat'] == true) {
      _stopRepeat();
      return;
    }
    final timing = _timing;
    actions.withKeyboardPageTurnDuration(
      timing.animationDuration,
      () => _dispatch(binding, event, repeat: true),
    );
    if (_activeKey == event.physicalKey && _allowed) {
      // 单次计时器不补发错过的 tick，卡帧后不会积压翻页。
      _repeatTimer = Timer(timing.interval, () => _repeat(event));
    }
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _activeKey = null;
  }

  void _cancelIfBlocked() {
    if (!_allowed) cancel();
  }

  void cancel() {
    _stopRepeat();
    for (final timer in _customHolds.values) {
      timer.cancel();
    }
    _customHolds.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) cancel();
  }

  void dispose() {
    cancel();
    _managedKeys.clear();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(cancel);
    ReaderInputBridge.instance.removeListener(_cancelIfBlocked);
  }
}
