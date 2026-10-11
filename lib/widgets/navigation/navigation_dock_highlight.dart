part of 'navigation_dock.dart';

/// The pointer's highlight, drawn to the destination under it and leaning a
/// little toward the cursor, as iPadOS highlights a tab bar item; the item
/// under it follows the cursor half as far.
class _HoverHighlight extends StatelessWidget {
  const _HoverHighlight({
    required this.position,
    required this.extent,
    required this.opacity,
  });

  final double position;
  final double extent;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final alpha = _hoverAlpha * opacity.clamp(0.0, 1.0);
    if (alpha == 0) {
      return const SizedBox.shrink();
    }
    return Positioned.directional(
      textDirection: Directionality.of(context),
      start: position * extent,
      top: 0,
      bottom: 0,
      width: extent,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.colorScheme.onSurface.withValues(alpha: alpha),
          shape: ControlShape.rounded,
        ),
      ),
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens({
    required this.position,
    required this.velocity,
    required this.extent,
    required this.height,
    required this.lift,
  });

  final double position;
  final double velocity;
  final double extent;
  final double height;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final rect = _lensRect(
      position: position,
      velocity: velocity,
      extent: extent,
      height: height,
      lift: lift,
    );
    return PositionedDirectional(
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.alphaBlend(
            colorScheme.onSecondaryContainer.withValues(
              alpha: 0.08 * lift.clamp(0.0, 1.0),
            ),
            colorScheme.secondaryContainer,
          ),
          shape: ControlShape.rounded,
        ),
      ),
    );
  }
}
