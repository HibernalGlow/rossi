import 'package:material_ui/material_ui.dart';
import 'package:path_parsing/path_parsing.dart';

/// 源自 `poc/mask-upright.svg` 的品牌面具矢量路径（`fill-rule="evenodd"`，含双尖角与眼部镂空）。
const String kBrandMaskSvgPath =
    'M 69.89,412.80 '
    'C 52.57,402.92 38.15,384.62 33.10,350.38 '
    'C 25.84,301.47 46.33,259.52 82.49,228.78 '
    'C 108.48,203.59 142.40,185.60 172.80,185.60 '
    'L 403.36,185.60 '
    'L 496.51,32.00 '
    'L 578.98,185.60 '
    'L 675.42,32.00 '
    'C 711.57,127.45 743.51,205.32 761.88,274.57 '
    'C 778.08,326.72 756.63,375.63 730.08,412.80 '
    'Z '
    'M 429.13,237.41 '
    'L 537.20,323.82 '
    'C 534.10,342.39 525.06,355.78 507.11,361.76 '
    'C 474.06,373.93 444.97,363.73 428.51,336.24 '
    'C 417.77,318.50 416.70,277.09 429.13,237.41 '
    'Z '
    'M 591.75,329.47 '
    'L 696.56,246.02 '
    'C 707.80,274.26 708.70,310.21 693.80,338.80 '
    'C 680.41,364.35 655.99,378.17 633.01,372.73 '
    'C 615.68,368.42 602.28,351.78 591.75,329.47 '
    'Z';

/// 跟随全局 MD3 Expressive 主题色动态着色的品牌图标组件。
///
/// 直接绘制 `poc/mask-upright.svg` 的矢量面具与超椭圆（squircle）底板，
/// 替代静态位图 `asset/image/app-icon.png`，使面具图形色与底板容器色随
/// `ColorScheme`（动态取色 / 种子色 / 明暗模式）实时同步。
class BrandAppIcon extends StatelessWidget {
  const BrandAppIcon({
    super.key,
    this.size = 88,
    this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
    this.cornerRadiusRatio = 0.28,
    this.maskWidthRatio = 0.86,
  });

  final double size;

  /// 面具本体颜色，默认取 `colorScheme.primary`。
  final Color? foregroundColor;

  /// 超椭圆底板颜色，默认取 `colorScheme.primaryContainer`。
  final Color? backgroundColor;

  /// 底板描边颜色，默认取 `colorScheme.primary` 的低透明描边。
  final Color? borderColor;

  /// 超椭圆圆角占边长比例。
  final double cornerRadiusRatio;

  /// 面具宽度占底板边长比例（对齐 `script/build_app_icon.py` 的构图重心）。
  final double maskWidthRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedForeground = foregroundColor ?? scheme.primary;
    final resolvedBackground = backgroundColor ?? scheme.primaryContainer;
    final resolvedBorder =
        borderColor ?? resolvedForeground.withValues(alpha: 0.24);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: BrandAppIconPainter(
          foregroundColor: resolvedForeground,
          backgroundColor: resolvedBackground,
          borderColor: resolvedBorder,
          cornerRadiusRatio: cornerRadiusRatio,
          maskWidthRatio: maskWidthRatio,
        ),
      ),
    );
  }
}

class BrandAppIconPainter extends CustomPainter {
  const BrandAppIconPainter({
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    this.cornerRadiusRatio = 0.28,
    this.maskWidthRatio = 0.86,
  });

  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final double cornerRadiusRatio;
  final double maskWidthRatio;

  static Path? _cachedMaskPath;
  static Rect? _cachedMaskBounds;

  static (Path, Rect) _ensureMaskPath() {
    if (_cachedMaskPath != null && _cachedMaskBounds != null) {
      return (_cachedMaskPath!, _cachedMaskBounds!);
    }
    final writer = _SvgPathWriter();
    writeSvgPathDataToPath(kBrandMaskSvgPath, writer);
    final path = writer.path..fillType = PathFillType.evenOdd;
    final bounds = path.getBounds();
    _cachedMaskPath = path;
    _cachedMaskBounds = bounds;
    return (path, bounds);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.shortestSide;
    final rect = Offset.zero & size;
    final radius = Radius.circular(side * cornerRadiusRatio);
    final superellipse = RSuperellipse.fromRectAndRadius(rect, radius);

    // 1. 动态主题色超椭圆底板
    canvas.drawRSuperellipse(superellipse, Paint()..color = backgroundColor);

    // 2. 柔和容器描边
    if (borderColor.a > 0) {
      canvas.drawRSuperellipse(
        superellipse,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 3. 居中绘制 `poc/mask-upright.svg` 面具（保留 2% 视觉重心下移以平衡顶部尖角）
    final (maskPath, bounds) = _ensureMaskPath();
    if (bounds.width <= 0 || bounds.height <= 0) return;

    final scale = (side * maskWidthRatio) / bounds.width;
    final tx = size.width / 2 - scale * bounds.center.dx;
    final ty = size.height / 2 + side * 0.02 - scale * bounds.center.dy;

    canvas.save();
    canvas.clipRSuperellipse(superellipse);
    canvas.translate(tx, ty);
    canvas.scale(scale, scale);
    canvas.drawPath(
      maskPath,
      Paint()
        ..color = foregroundColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandAppIconPainter oldDelegate) =>
      foregroundColor != oldDelegate.foregroundColor ||
      backgroundColor != oldDelegate.backgroundColor ||
      borderColor != oldDelegate.borderColor ||
      cornerRadiusRatio != oldDelegate.cornerRadiusRatio ||
      maskWidthRatio != oldDelegate.maskWidthRatio;
}

class _SvgPathWriter implements PathProxy {
  final Path path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
