part of '../video_control_overlay.dart';

/// 波浪已播放轨道与 MD3 间隔滑块；交互、键盘和语义仍由 Slider 提供。
class _ExpressiveVideoTrackShape extends GappedSliderTrackShape {
  const _ExpressiveVideoTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme.copyWith(
        activeTrackColor: Colors.transparent,
        disabledActiveTrackColor: Colors.transparent,
      ),
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final rtl = textDirection == TextDirection.rtl;
    final start = rtl ? rect.right : rect.left;
    final end = rtl
        ? math.min(start, thumbCenter.dx + (sliderTheme.trackGap ?? 4))
        : math.max(start, thumbCenter.dx - (sliderTheme.trackGap ?? 4));
    final length = (end - start).abs();
    if (length <= 2) return;
    final direction = rtl ? -1.0 : 1.0;
    final path = Path();
    // 两端平滑收幅，进度很短时也不会突然出现一段陡折线。
    for (var distance = 0.0; distance <= length; distance += 0.5) {
      final taper = math.min(1.0, math.min(distance, length - distance) / 8);
      final y = rect.center.dy + math.sin(distance * math.pi / 12) * 3 * taper;
      final x = start + distance * direction;
      if (distance == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    context.canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(
          sliderTheme.disabledActiveTrackColor,
          sliderTheme.activeTrackColor,
          enableAnimation.value,
        )!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }
}
