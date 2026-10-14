import 'dart:math' as math;

import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';

/// 图形池：语义中性、在一面藏书墙上读得通的符号。
///
/// 刻意不放「关闭 / 删除」这类动作符号 —— 空隙是装饰，不能长得像按钮。
const List<Glyph> kLibraryGapGlyphs = [
  AppGlyphs.sparkle,
  AppGlyphs.star,
  AppGlyphs.bolt,
  AppGlyphs.sun,
  AppGlyphs.moon,
  AppGlyphs.donut,
  AppGlyphs.compass,
  AppGlyphs.puzzle,
  AppGlyphs.wand,
  AppGlyphs.palette,
  AppGlyphs.gradient,
  AppGlyphs.ring,
  AppGlyphs.dot,
  AppGlyphs.trophy,
  AppGlyphs.fire,
  AppGlyphs.rocket,
  AppGlyphs.target,
  AppGlyphs.shuffle,
  AppGlyphs.globe,
  AppGlyphs.music,
  AppGlyphs.category,
  AppGlyphs.highlight,
  AppGlyphs.dice,
  AppGlyphs.quality,
  AppGlyphs.openBook,
  AppGlyphs.bookmark,
  AppGlyphs.history,
  AppGlyphs.hourglass,
];

/// 种子 → 图标。取的是种子里的高位，与图形轮廓用的低位互不相关，
/// 于是「同一个位置」不会永远配「同一类形状 + 同一枚图标」的固定组合。
Glyph libraryGapGlyph(int seed) =>
    kLibraryGapGlyphs[(seed >> 5) % kLibraryGapGlyphs.length];

const List<ExpressiveButtonShape> _kShapeAccents = [
  ExpressiveButtonShape.sunny,
  ExpressiveButtonShape.clover4Leaf,
  ExpressiveButtonShape.softBurst,
  ExpressiveButtonShape.puffyDiamond,
  ExpressiveButtonShape.cookie4Sided,
  ExpressiveButtonShape.cookie6Sided,
  ExpressiveButtonShape.flower,
  ExpressiveButtonShape.gem,
  ExpressiveButtonShape.pentagon,
];

/// 空隙里的 **MD3 Expressive 随机图形**：种子决定的不规则轮廓 + 撞色几何贴片 + 随机图标。
///
/// 轮廓来自 [ExpressiveBlob]（同一 seed 永远同一形状，切回来不跳形），
/// 只在自己的矩形内变形，不会压到相邻卡片。
class LibraryGapShape extends StatelessWidget {
  const LibraryGapShape({
    super.key,
    required this.seed,
    this.icon,
    this.margin = 4,
  });

  final int seed;
  final Glyph? icon;

  /// 轮廓与图标的留白；空隙越小留得越少。
  final double margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = <(Color, Color, Color)>[
      (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.tertiaryContainer,
      ),
      (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.primaryContainer,
      ),
      (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        scheme.secondaryContainer,
      ),
      (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
        scheme.primaryContainer,
      ),
      (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        scheme.tertiaryContainer,
      ),
    ];
    final (fill, content, patch) = tones[seed.abs() % tones.length];
    return IgnorePointer(
      child: Semantics(
        label: '装饰图形',
        child: CustomPaint(
          painter: _GapBlobPainter(
            seed: seed,
            fill: fill,
            accent: content,
            patch: patch,
          ),
          child: Padding(
            padding: EdgeInsets.all(margin),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Center(
                  child: GlyphIcon(
                    icon ?? libraryGapGlyph(seed),
                    size: (side * .42).clamp(16.0, 56.0),
                    color: content.withValues(alpha: .78),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GapBlobPainter extends CustomPainter {
  const _GapBlobPainter({
    required this.seed,
    required this.fill,
    required this.accent,
    required this.patch,
  });

  final int seed;
  final Color fill;
  final Color accent;
  final Color patch;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final box = Offset.zero & size;
    final inset = math.min(size.shortestSide * .06, 8.0);
    final rect = box.deflate(inset);
    final mainPath = ExpressiveBlob.ofSeed(
      seed,
    ).path(rect: rect, progress: 0, safeInset: size.shortestSide * .22);
    canvas.drawPath(mainPath, Paint()..color = fill.withValues(alpha: .88));

    // 对角处的 M3E 有机多边形撞色贴片（裁切在主轮廓内，小槽位里也不越界）。
    if (size.shortestSide >= 48) {
      canvas.save();
      canvas.clipPath(mainPath);
      final s = seed.abs();
      final poly = _kShapeAccents[s % _kShapeAccents.length].polygon;
      final d = size.shortestSide * .56;
      final top = (s & 2) == 0;
      final left = (s & 4) == 0;
      final cx = left ? rect.left + d * .2 : rect.right - d * .2;
      final cy = top ? rect.top + d * .2 : rect.bottom - d * .2;
      final matrix = Matrix4.identity()
        ..translateByDouble(cx, cy, 0, 1)
        ..rotateZ((s % 7) * 0.2)
        ..scaleByDouble(d, d, 1, 1)
        ..translateByDouble(-.5, -.5, 0, 1);
      canvas.drawPath(
        poly.toPath().transform(matrix.storage),
        Paint()..color = patch.withValues(alpha: .48),
      );
      canvas.restore();
    }

    // 一枚描边小图形压在角上：空隙大时它落在轮廓外，小时叠在上面，
    // 两种情况都只是让这块不显得「一块纯色」。
    final side = size.shortestSide * .3;
    final corner = (seed >> 3) % 4;
    final dx = corner == 0 || corner == 3
        ? box.left + inset * 2
        : box.right - side - inset * 2;
    final dy = corner < 2 ? box.top + inset * 2 : box.bottom - side - inset * 2;
    canvas.drawPath(
      ExpressiveBlob.ofSeed(seed ^ 0x9e3779b9).path(
        rect: Rect.fromLTWH(
          dx.clamp(box.left, box.right - side),
          dy.clamp(box.top, box.bottom - side),
          side,
          side,
        ),
        progress: 0,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: .36),
    );
  }

  @override
  bool shouldRepaint(covariant _GapBlobPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.fill != fill ||
      oldDelegate.accent != accent ||
      oldDelegate.patch != patch;
}
