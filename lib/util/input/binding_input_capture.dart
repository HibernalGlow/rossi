import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 透明覆盖层先登记已绑定滚轮的处理器，未绑定时仍交给内部 Scrollable。
/// hitTest 的顺序是最上层到最下层；translucent 不阻断按下、拖动与点击。
class BindingPointerSignalRegion extends StatelessWidget {
  const BindingPointerSignalRegion({
    super.key,
    required this.onPointerSignal,
    this.onPointerPanZoomStart,
    this.onPointerPanZoomUpdate,
    this.onPointerPanZoomEnd,
    required this.child,
  });
  final void Function(PointerSignalEvent) onPointerSignal;
  final void Function(PointerPanZoomStartEvent)? onPointerPanZoomStart;
  final void Function(PointerPanZoomUpdateEvent)? onPointerPanZoomUpdate;
  final void Function(PointerPanZoomEndEvent)? onPointerPanZoomEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: onPointerSignal,
          onPointerPanZoomStart: onPointerPanZoomStart,
          onPointerPanZoomUpdate: onPointerPanZoomUpdate,
          onPointerPanZoomEnd: onPointerPanZoomEnd,
          child: const SizedBox.expand(),
        ),
      ),
    ],
  );
}

/// 录制器与运行时共用平台事件到 Neo 描述符的翻译。
int? bindingMouseButton(int buttons) {
  for (final entry in const {
    kPrimaryButton: 0,
    kTertiaryButton: 1,
    kSecondaryButton: 2,
    kBackMouseButton: 3,
    kForwardMouseButton: 4,
  }.entries) {
    if (buttons & entry.key != 0) return entry.value;
  }
  return null;
}

String bindingDirection(Offset delta) => delta.dx.abs() > delta.dy.abs()
    ? (delta.dx < 0 ? 'left' : 'right')
    : (delta.dy < 0 ? 'up' : 'down');

Map<String, dynamic> bindingWheelInput(double dy) => {
  'device': 'wheel',
  'direction': dy < 0 ? 'up' : 'down',
  'ctrl': HardwareKeyboard.instance.isControlPressed,
  'alt': HardwareKeyboard.instance.isAltPressed,
  'shift': HardwareKeyboard.instance.isShiftPressed,
  'meta': HardwareKeyboard.instance.isMetaPressed,
};

bool isBindingModifier(LogicalKeyboardKey key) => {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
}.contains(key);
