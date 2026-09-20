import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/page/setting/operation_binding/binding_editor_labels.dart';

class BindingInputRecorder extends StatefulWidget {
  const BindingInputRecorder({super.key, required this.input});
  final Map<String, dynamic> input;

  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    Map<String, dynamic> input,
  ) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => BindingInputRecorder(input: input),
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
    if (_device != InputDevice.keyboard || isBindingModifier(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    final json = keyboardInputJsonOf(event);
    if (json != null) {
      setState(
        () => _captured = {
          ...widget.input,
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
    if (_device == InputDevice.mouseGesture && _last != null) {
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
    if (_device == InputDevice.mouse) {
      result = {...widget.input, 'button': _button};
    } else if (_device == InputDevice.mouseGesture && _directions.isNotEmpty) {
      result = {
        ...widget.input,
        'button': _button,
        'directions': [..._directions],
      };
    } else if (_device == InputDevice.touch &&
        event.kind == PointerDeviceKind.touch) {
      final delta = event.localPosition - start;
      result = {
        ...widget.input,
        'fingers': _fingers.clamp(1, 3),
        'gesture': delta.distance >= 40
            ? 'swipe-${bindingDirection(delta)}'
            : elapsed >= 500
            ? 'long-press'
            : 'tap',
      };
    }
    if (result != null) setState(() => _captured = result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${t.bindingEditor.record} · ${bindingDeviceLabels[_device]}'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.bindingEditor.recordHint),
          const SizedBox(height: 16),
          Focus(
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
                if (_device == InputDevice.wheel &&
                    event is PointerScrollEvent &&
                    event.scrollDelta.dy != 0) {
                  setState(
                    () => _captured = bindingWheelInput(event.scrollDelta.dy),
                  );
                }
              },
              child: Container(
                height: 180,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _captured == null
                      ? t.bindingEditor.recordWaiting
                      : bindingInputSummary(_captured!),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
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
