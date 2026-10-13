part of 'path_breadcrumb.dart';

/// 起伏保持在紧凑的轮廓带内，按钮装饰与文字留在平稳的内部区域。
class _BreadcrumbWaveBorder extends OutlinedBorder {
  const _BreadcrumbWaveBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  OutlinedBorder copyWith({BorderSide? side}) => this;

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(24.0, rect.height / 2);
    final path = Path()..moveTo(rect.left + r, rect.top + 2);
    final span = math.max(0.0, rect.width - 2 * r);
    final lobes = math.max(1, (span / 90).round());
    final step = span / lobes;
    for (var i = 0; i < lobes; i++) {
      final x = rect.left + r + step * i;
      path.cubicTo(
        x + step * .3,
        rect.top,
        x + step * .7,
        rect.top + 5,
        x + step,
        rect.top + 2,
      );
    }
    path.quadraticBezierTo(rect.right, rect.top + 2, rect.right, rect.top + r);
    path.lineTo(rect.right, rect.bottom - r);
    path.quadraticBezierTo(
      rect.right,
      rect.bottom - 2,
      rect.right - r,
      rect.bottom - 2,
    );
    for (var i = lobes - 1; i >= 0; i--) {
      final x = rect.left + r + step * i;
      path.cubicTo(
        x + step * .7,
        rect.bottom,
        x + step * .3,
        rect.bottom - 5,
        x,
        rect.bottom - 2,
      );
    }
    path.quadraticBezierTo(
      rect.left,
      rect.bottom - 2,
      rect.left,
      rect.bottom - r,
    );
    path.lineTo(rect.left, rect.top + r);
    path.quadraticBezierTo(
      rect.left,
      rect.top + 2,
      rect.left + r,
      rect.top + 2,
    );
    return path..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
