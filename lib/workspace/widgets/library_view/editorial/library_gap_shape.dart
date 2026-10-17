import 'dart:math' as math;

import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';

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

/// 一款随机图形的**轮廓家族**。
///
/// 种子仍然决定具体几何（旋转、撞色贴片、图标），这一层只决定读起来像什么：
/// 有机团 / 星芒 / 四叶草 / 宝石 / 拱门 / 花形 / 圆环 / 波纹。样式只影响轮廓，
/// 不改变尺寸与留白 —— 同一块空隙换一款样式不会把邻居挤走。
///
/// 与「小组件」的关系：小组件装不下或已经用过的槽位会退化成随机图形
/// （见 `library_gap_fill.dart` 的 `both` 口径），所以这里是单一套件，
/// 单项开关放在 `LibraryPresentation.gapShapeStyles`。
enum LibraryGapShapeStyle {
  blob,
  burst,
  clover,
  gem,
  arch,
  flower,
  ring,
  wave;

  const LibraryGapShapeStyle();

  String get label => switch (this) {
    LibraryGapShapeStyle.blob => t.workspace.gapShapeBlob,
    LibraryGapShapeStyle.burst => t.workspace.gapShapeBurst,
    LibraryGapShapeStyle.clover => t.workspace.gapShapeClover,
    LibraryGapShapeStyle.gem => t.workspace.gapShapeGem,
    LibraryGapShapeStyle.arch => t.workspace.gapShapeArch,
    LibraryGapShapeStyle.flower => t.workspace.gapShapeFlower,
    LibraryGapShapeStyle.ring => t.workspace.gapShapeRing,
    LibraryGapShapeStyle.wave => t.workspace.gapShapeWave,
  };
}

const List<LibraryGapShapeStyle> kLibraryGapShapeStyles =
    LibraryGapShapeStyle.values;

/// 单项开关（缺键 = 开）过滤后的图形样式。
///
/// 全关掉时保留「有机团」那一款：设置里可以全关，但**被填的空隙不能变成
/// 一块空白** —— 那与用户关掉整个「随机图形」开关是两件事。
List<LibraryGapShapeStyle> libraryGapShapeStylesFromToggles(
  Map<String, bool> toggles,
) {
  final enabled = [
    for (final style in kLibraryGapShapeStyles)
      if (toggles[style.name] ?? true) style,
  ];
  return enabled.isEmpty ? const [LibraryGapShapeStyle.blob] : enabled;
}

/// 按种子挑一款启用中的样式：同一块空隙每次重排都抽到同一款。
LibraryGapShapeStyle libraryGapShapeStyleFor(
  int seed,
  List<LibraryGapShapeStyle> enabled,
) {
  final pool = enabled.isEmpty ? const [LibraryGapShapeStyle.blob] : enabled;
  return pool[seed.abs() % pool.length];
}

/// 空隙里的 **MD3 Expressive 随机图形**：种子决定的不规则轮廓 + 撞色几何贴片 + 随机图标。
///
/// 轮廓来自 [ExpressiveBlob]（同一 seed 永远同一形状，切回来不跳形），
/// 只在自己的矩形内变形，不会压到相邻卡片。[style] 换的是轮廓家族，
/// 种子、配色与图标池都不变。
class LibraryGapShape extends StatelessWidget {
  const LibraryGapShape({
    super.key,
    required this.seed,
    this.icon,
    this.margin = 4,
    this.style = LibraryGapShapeStyle.blob,
  });

  final int seed;
  final Glyph? icon;
  final LibraryGapShapeStyle style;

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
        label: t.workspace.decorativeShapes,
        child: CustomPaint(
          painter: _GapBlobPainter(
            seed: seed,
            fill: fill,
            accent: content,
            patch: patch,
            style: style,
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
    required this.style,
  });

  final int seed;
  final Color fill;
  final Color accent;
  final Color patch;
  final LibraryGapShapeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final box = Offset.zero & size;
    final inset = math.min(size.shortestSide * .06, 8.0);
    final rect = box.deflate(inset);
    if (rect.isEmpty) return;

    final mainPath = _outline(rect, size);
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

    _paintAccent(canvas, size, box, rect, mainPath);
  }

  /// 轮廓：样式决定家族，种子决定细节。
  Path _outline(Rect rect, Size size) {
    switch (style) {
      case LibraryGapShapeStyle.blob:
        return ExpressiveBlob.ofSeed(
          seed,
        ).path(rect: rect, progress: 0, safeInset: size.shortestSide * .22);
      case LibraryGapShapeStyle.ring:
        final outer = Path()..addOval(rect);
        final inner = Path()
          ..addOval(
            Rect.fromCenter(
              center: rect.center,
              width: rect.width * .52,
              height: rect.height * .52,
            ),
          );
        return Path.combine(PathOperation.difference, outer, inner);
      case LibraryGapShapeStyle.wave:
        return _waveBand(rect);
      case LibraryGapShapeStyle.burst:
        return _polygon(ExpressiveButtonShape.softBurst, rect);
      case LibraryGapShapeStyle.clover:
        return _polygon(ExpressiveButtonShape.clover4Leaf, rect);
      case LibraryGapShapeStyle.gem:
        return _polygon(ExpressiveButtonShape.puffyDiamond, rect);
      case LibraryGapShapeStyle.arch:
        return _polygon(ExpressiveButtonShape.arch, rect);
      case LibraryGapShapeStyle.flower:
        return _polygon(ExpressiveButtonShape.flower, rect);
    }
  }

  Path _polygon(ExpressiveButtonShape shape, Rect rect) {
    final matrix = Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(rect.width, rect.height, 1, 1);
    return shape.polygon.toPath().transform(matrix.storage);
  }

  /// 一条从左侧中线出发的正弦带，底边拉平 —— 读作「波浪」而不是一团色块。
  Path _waveBand(Rect rect) {
    const steps = 36;
    final path = Path();
    final mid = rect.center.dy;
    final amp = rect.height * .16;
    final phase = (seed.abs() % 7) * .7;
    path.moveTo(rect.left, mid);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      path.lineTo(
        rect.left + rect.width * t,
        mid + math.sin(t * math.pi * 2 + phase) * amp,
      );
    }
    path.lineTo(rect.right, rect.bottom);
    path.lineTo(rect.left, rect.bottom);
    path.close();
    return path;
  }

  /// 角上的那一笔：有机团沿用描边小图形，其余样式改画轮廓线/内圈，
  /// 让「这块是装饰」这件事在不同家族里都成立。
  void _paintAccent(Canvas canvas, Size size, Rect box, Rect rect, Path main) {
    if (style == LibraryGapShapeStyle.blob) {
      final side = size.shortestSide * .3;
      final corner = (seed >> 3) % 4;
      final inset = math.min(size.shortestSide * .06, 8.0);
      final dx = corner == 0 || corner == 3
          ? box.left + inset * 2
          : box.right - side - inset * 2;
      final dy = corner < 2
          ? box.top + inset * 2
          : box.bottom - side - inset * 2;
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
      return;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: .3);
    canvas.drawPath(main, stroke);

    if (style == LibraryGapShapeStyle.ring) {
      // 圆环再补一圈细内环：只描外轮廓时，中间那枚图标读起来像浮在色块上。
      canvas.drawOval(
        Rect.fromCenter(
          center: rect.center,
          width: rect.width * .64,
          height: rect.height * .64,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent.withValues(alpha: .26),
      );
    } else if (style == LibraryGapShapeStyle.wave) {
      final second = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: .22);
      for (var line = 1; line <= 2; line++) {
        final y = rect.top + rect.height * (.78 - line * .16);
        final path = Path()..moveTo(rect.left, y);
        for (var i = 1; i <= 18; i++) {
          final t = i / 18;
          path.lineTo(
            rect.left + rect.width * t,
            y + math.sin(t * math.pi * 2 + line) * rect.height * .07,
          );
        }
        canvas.drawPath(path, second);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GapBlobPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.fill != fill ||
      oldDelegate.accent != accent ||
      oldDelegate.patch != patch ||
      oldDelegate.style != style;
}
