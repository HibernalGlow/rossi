part of 'spring_lens_bar.dart';

Path _lensPath(Rect rect, double? corner) =>
    ControlShape.path(rect, corner: corner);

/// 画选中态那颗lens。只画不布局。
///
/// **公开**是为了让判据能读它身上的 [slots] / [position] 重算一遍落点：
/// painter 只在 `paint(canvas, size)` 里作画，从外面量不到那颗矩形
/// （见 `test/widgets/spring_lens_bar_test.dart` 的 `_lensRect`）。
class SpringLensPainter extends CustomPainter {
  const SpringLensPainter({
    required this.slots,
    required double position,
    required double velocity,
    required double lift,
    required this.color,
    required this.corner,
    required this.axis,
    this.shadow,
  }) : _snapshot = (position: position, velocity: velocity, lift: lift),
       lensValue = null,
       liftValue = null;

  /// 弹簧直接驱动绘制，动画帧不重建 CustomPaint 和页签子树。
  SpringLensPainter.animated({
    required Listenable repaint,
    required this.lensValue,
    required this.liftValue,
    required this.slots,
    required this.color,
    required this.corner,
    required this.axis,
    this.shadow,
  }) : _snapshot = (position: 0, velocity: 0, lift: 0),
       super(repaint: repaint);

  final LensSlots slots;
  final ({double position, double velocity, double lift}) _snapshot;
  final SpringLensValue? lensValue;
  final ValueListenable<double>? liftValue;
  double get position => lensValue?.value ?? _snapshot.position;
  double get velocity => lensValue?.velocity ?? _snapshot.velocity;
  double get lift => liftValue?.value ?? _snapshot.lift;
  final Color color;
  final double? corner;
  final Axis axis;

  /// 那颗块自己的投影。不给就不画。
  final Shadow? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty || size.isEmpty) return;
    final real = slots.resolvedTo(size);
    if (real == null || real.isEmpty) return;
    final rect = lensRect(
      slots: real,
      position: position,
      velocity: velocity,
      lift: lift,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final path = _lensPath(rect, corner);
    // 投影先画 —— 它是「浮起」那一层，要压在块底下而不是盖在上面。
    // 用 `Shadow.blurSigma`（`blurRadius * 0.57735 + 0.5`）：`BoxShadow` 走的是
    // 同一条换算，所以从 `BoxShadow` 搬过来的数值不会变胖。
    final shadow = this.shadow;
    if (shadow != null) {
      canvas.drawPath(
        path.shift(shadow.offset),
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(SpringLensPainter old) =>
      old.slots != slots ||
      old.axis != axis ||
      old.lensValue != lensValue ||
      old.liftValue != liftValue ||
      old.position != position ||
      old.velocity != velocity ||
      old.lift != lift ||
      old.color != color ||
      old.corner != corner ||
      old.shadow != shadow;
}

/// 画鼠标悬停那层高亮（跟着指针磁吸）。
class _HoverPainter extends CustomPainter {
  _HoverPainter({
    required Listenable repaint,
    required this.slots,
    required this.position,
    required this.opacity,
    required this.color,
    required this.axis,
    required this.corner,
  }) : super(repaint: repaint);

  final LensSlots slots;
  final ValueListenable<double> position;
  final ValueListenable<double> opacity;
  final double? corner;
  final Color color;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = LensMetrics.hoverAlpha * opacity.value.clamp(0.0, 1.0);
    if (alpha == 0 || slots.isEmpty || size.isEmpty) return;
    final real = slots.resolvedTo(size);
    if (real == null || real.isEmpty) return;
    final index = real.indexAt(position.value);
    final rect = lensRect(
      slots: real,
      position: position.value,
      velocity: 0,
      lift: 0,
    );
    final band = axis == Axis.horizontal
        ? Rect.fromLTWH(
            rect.left,
            real.crossStart,
            real.spanOf(index),
            real.crossSize,
          )
        : Rect.fromLTWH(
            real.crossStart,
            rect.top,
            real.crossSize,
            real.spanOf(index),
          );
    if (band.width <= 0 || band.height <= 0) return;
    canvas.drawPath(
      _lensPath(band, corner),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_HoverPainter old) =>
      old.slots != slots ||
      old.axis != axis ||
      old.position != position ||
      old.opacity != opacity ||
      old.corner != corner ||
      old.color != color;
}
