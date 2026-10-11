import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';
import 'package:zephyr/util/input/binding_pointer_signal_guard.dart';

/// 信号层先于内容的 Scrollable 命中，用同一个 pointerSignalResolver 仲裁。
/// 首个有效信号原样放行；持续滚轮跨泳道时消费一次，避免误翻 Reader。
class WorkspaceLaneInputRegion extends StatelessWidget {
  const WorkspaceLaneInputRegion({
    super.key,
    required this.child,
    required this.acceptWheel,
    required this.onPanZoomStart,
    required this.onPanZoomEnd,
  });

  final Widget child;
  final bool Function() acceptWheel;
  final void Function(int) onPanZoomStart;
  final void Function(int) onPanZoomEnd;

  @override
  Widget build(BuildContext context) => BindingPointerSignalRegion(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent && !acceptWheel()) {
        BindingPointerSignalGuard.reject(event);
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          BindingPointerSignalGuard.finishRejected(event);
        });
      }
    },
    onPointerPanZoomStart: (event) => onPanZoomStart(event.pointer),
    onPointerPanZoomEnd: (event) => onPanZoomEnd(event.pointer),
    child: child,
  );
}
