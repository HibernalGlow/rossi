import 'package:flutter/widgets.dart';
import 'package:zephyr/page/comic_read/model/page_trim.dart';

/// 位图、GPU 纹理与译文叠层使用完全相同的 contain 裁边变换。
class PageTrimTransform extends StatelessWidget {
  const PageTrimTransform({
    super.key,
    required this.boxSize,
    required this.imageSize,
    required this.contentRect,
    required this.child,
  });
  final Size boxSize;
  final Size imageSize;
  final Rect? contentRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rect = contentRect;
    final geometry = rect == null
        ? null
        : computePageTrim(
            boxSize: boxSize,
            imageSize: imageSize,
            contentRect: rect,
          );
    if (geometry == null) return child;
    return ClipRect(
      child: SizedBox.fromSize(
        size: boxSize,
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(0, 0, geometry.scale)
            ..setEntry(1, 1, geometry.scale)
            ..setEntry(0, 3, geometry.dx)
            ..setEntry(1, 3, geometry.dy),
          child: child,
        ),
      ),
    );
  }
}
