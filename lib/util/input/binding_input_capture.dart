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

/// 一次滚轮/双指平移 → 滚轮 descriptor。
///
/// [invert] 把方向词从「内容往哪走」换成「手往哪推」：macOS 的 `scrollDelta.dy` 已经含了
/// 系统「自然滚动」那一次反转，见 `OperationBindingSettingState.invertWheelDirection`。
/// **录制与运行时必须传同一个值**，否则会出现「录进去是 up、触发时算 down」的错位 ——
/// 所以取反只可能落在这一个函数里。`bindingDirection`（鼠标轨迹的拖动方向）不吃这个：
/// 指针位移没有系统反转那一层。
Map<String, dynamic> bindingWheelInput(double dy, {bool invert = false}) => {
  'device': 'wheel',
  'direction': (invert ? -dy : dy) < 0 ? 'up' : 'down',
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
