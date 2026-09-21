import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/page/setting/operation_binding/binding_editor_labels.dart';

class BindingInputRecorder extends StatefulWidget {
  const BindingInputRecorder({
    super.key,
    required this.input,
    this.wheelFollowsHand = false,
  });

  final Map<String, dynamic> input;

  /// 滚轮方向词按手推的方向还是按内容走的方向算（见
  /// `OperationBindingStore.wheelDirectionFollowsHand`）。由持有设置的调用方传进来，
  /// 这个组件自己不去读 `GlobalSettingCubit` —— 录键框要能在隔离的夹具里跑。
  final bool wheelFollowsHand;

  /// 方向判定由**持有设置的调用方**传进来：这个组件自己不看 `GlobalSettingCubit`，
  /// 录键框因此能在任何宿主里打开，也不会因为缺一层 provider 而 behaves 不同。
  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    Map<String, dynamic> input, {
    bool wheelFollowsHand = false,
  }) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => BindingInputRecorder(
      input: input,
      wheelFollowsHand: wheelFollowsHand,
    ),
  );

  @override
  State<BindingInputRecorder> createState() => _BindingInputRecorderState();
}

class _BindingInputRecorderState extends State<BindingInputRecorder> {
  final _focus = FocusNode();
  final _starts = <int, Offset>{};
  final _ends = <int, Offset>{};
  final _directions = <String>[];
  Offset? _last;
  Duration? _pressedAt;
  int _button = 0;
  int _fingers = 0;
  double _panZoomDyAccumulator = 0;
  Map<String, dynamic>? _captured;
  String get _device => widget.input['device'] as String;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (isBindingModifier(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    final json = keyboardInputJsonOf(event);
    if (json != null) {
      setState(
        () => _captured = {
          'device': InputDevice.keyboard,
          ...Map<String, dynamic>.from(jsonDecode(json) as Map),
          'trigger': widget.input['trigger'] ?? 'down',
        },
      );
    }
    return KeyEventResult.handled;
  }

  void _down(PointerDownEvent event) {
    _focus.requestFocus();
    if (_starts.isEmpty) {
      _directions.clear();
      _ends.clear();
      _fingers = 0;
      _pressedAt = event.timeStamp;
      _last = event.localPosition;
      _button = bindingMouseButton(event.buttons) ?? 0;
    }
    _starts[event.pointer] = event.localPosition;
    _ends[event.pointer] = event.localPosition;
    if (_starts.length > _fingers) _fingers = _starts.length;
  }

  void _move(PointerMoveEvent event) {
    if (!_starts.containsKey(event.pointer)) return;
    _ends[event.pointer] = event.localPosition;
    if (_last != null) {
      final delta = event.localPosition - _last!;
      if (delta.distance >= 16) {
        final direction = bindingDirection(delta);
        if (_directions.lastOrNull != direction && _directions.length < 16) {
          _directions.add(direction);
        }
        _last = event.localPosition;
      }
    }
  }

  void _up(PointerUpEvent event) {
    final start = _starts.remove(event.pointer);
    if (start == null || _starts.isNotEmpty) return;
    final elapsed =
        (event.timeStamp - (_pressedAt ?? event.timeStamp)).inMilliseconds;
    Map<String, dynamic>? result;
    if (_directions.isNotEmpty) {
      result = {
        'device': InputDevice.mouseGesture,
        'button': _button,
        'directions': [..._directions],
        'trigger': widget.input['trigger'] ?? 'instant',
      };
    } else if (event.kind == PointerDeviceKind.touch) {
      final delta = event.localPosition - start;
      result = {
        'device': InputDevice.touch,
        'fingers': _fingers.clamp(1, 3),
        'gesture': delta.distance >= 40
            ? 'swipe-${bindingDirection(delta)}'
            : elapsed >= 500
            ? 'long-press'
            : 'tap',
      };
    } else {
      result = {
        'device': InputDevice.mouse,
        'button': _button,
        'action': widget.input['action'] ?? 'click',
      };
    }
    setState(() => _captured = result);
  }

  /// 录制与运行时共用同一个滚轮方向判定（macOS 的系统反转滚动已在 dy 里翻过一次）。
  /// 两边不一致就会出现「录进去是 up、触发时算 down」的错位。
  bool get _wheelFollowsHand => widget.wheelFollowsHand;

  void _onScroll(PointerScrollEvent event) {
    if (event.scrollDelta.dy != 0) {
      setState(
        () => _captured = bindingWheelInput(
          event.scrollDelta.dy,
          invert: _wheelFollowsHand,
        ),
      );
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _panZoomDyAccumulator += event.panDelta.dy;
    if (_panZoomDyAccumulator.abs() >= 10) {
      setState(
        () => _captured = bindingWheelInput(
          _panZoomDyAccumulator,
          invert: _wheelFollowsHand,
        ),
      );
      _panZoomDyAccumulator = 0;
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomDyAccumulator = 0;
  }

  @override
  Widget build(BuildContext context) {
    final activeDevice = _captured?['device'] as String? ?? _device;
    return AlertDialog(
      title: Text(
        '${t.bindingEditor.record} · ${bindingDeviceLabels[activeDevice] ?? activeDevice}',
      ),
      content: SizedBox(
        width: 500,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: (_) {
              _starts.clear();
              _ends.clear();
            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _onScroll(event);
              }
            },
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            onPointerPanZoomEnd: _onPanZoomEnd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.bindingEditor.recordHint),
                const SizedBox(height: 16),
                Container(
                  height: 180,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _captured == null
                        ? t.bindingEditor.recordWaiting
                        : bindingInputSummary(_captured!),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: _captured == null
              ? null
              : () => Navigator.of(context).pop(_captured),
          child: Text(t.common.confirm),
        ),
      ],
    );
  }
}
