import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 复用 Flutter 的手势竞争；只有当前输入能匹配双击时才让双击识别器参赛。
///
/// 把双击挂满阅读区会让无关区域的单击也等待 kDoubleTapTimeout。按下时筛选
/// 能保留原生的单击/双击互斥、拖动取消及子控件优先级，不直接从 Listener 翻页。
class BindingTapRegion extends StatelessWidget {
  const BindingTapRegion({
    super.key,
    required this.acceptsDoubleTap,
    required this.onTap,
    required this.onTapDown,
    required this.onDoubleTap,
    required this.onDoubleTapDown,
    required this.child,
  });

  final bool Function(PointerDownEvent event) acceptsDoubleTap;
  final GestureTapCallback onTap;
  final GestureTapDownCallback onTapDown;
  final GestureDoubleTapCallback onDoubleTap;
  final GestureTapDownCallback onDoubleTapDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    return RawGestureDetector(
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (instance) => instance
                ..gestureSettings = gestureSettings
                ..onTap = onTap
                ..onTapDown = onTapDown,
            ),
        _BindingDoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _BindingDoubleTapGestureRecognizer
            >(
              () => _BindingDoubleTapGestureRecognizer(debugOwner: this),
              (instance) => instance
                ..gestureSettings = gestureSettings
                ..accepts = acceptsDoubleTap
                ..onDoubleTap = onDoubleTap
                ..onDoubleTapDown = onDoubleTapDown,
            ),
      },
      child: child,
    );
  }
}

class _BindingDoubleTapGestureRecognizer extends DoubleTapGestureRecognizer {
  _BindingDoubleTapGestureRecognizer({super.debugOwner});

  late bool Function(PointerDownEvent event) accepts;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && accepts(event);
}
