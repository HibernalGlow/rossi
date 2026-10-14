import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

/// 控制面板专用的 **MD3 Expressive 撞色几何贴片与多态控件套件**。
///
/// 解决控制面板原先「只有普通圆角盒子 + 干巴巴纯文字列表」的问题：
/// 1. **多态几何徽章 ([ExpressiveShapeBadge])**：使用 `material_new_shapes` 的
///    有机多边形（星芒、四叶草、八叶花、曲边钻、扇面、超椭圆等），支持按种子随机挑选，
///    并在激活/按压时平滑形变（Morph）。
/// 2. **色彩鲜明的 M3E 撞色几何贴片 ([ExpressivePatchBackdrop] / [ExpressiveHeroBanner])**：
///    在卡片或组块内绘制高饱和对比度的 `primaryContainer` / `secondaryContainer` /
///    `tertiaryContainer` 几何图形拼贴（Collage Patches），同一 seed 形状稳定，
///    不同小组件各自呈现独特的几何构图。
/// 3. **响应式开关磁贴 ([ExpressiveToggleTile])**：带多态图标座、撞色几何贴片角标、
///    状态胶囊与弹簧开关的卡片化控件，在宽面板下自动分列。

/// 适合做图标座与撞色几何贴片的 M3 Expressive 形状池。
const List<ExpressiveButtonShape> kExpressiveBadgeShapes = [
  ExpressiveButtonShape.sunny,
  ExpressiveButtonShape.clover4Leaf,
  ExpressiveButtonShape.softBurst,
  ExpressiveButtonShape.puffyDiamond,
  ExpressiveButtonShape.cookie4Sided,
  ExpressiveButtonShape.cookie6Sided,
  ExpressiveButtonShape.cookie7Sided,
  ExpressiveButtonShape.cookie9Sided,
  ExpressiveButtonShape.flower,
  ExpressiveButtonShape.gem,
  ExpressiveButtonShape.pentagon,
  ExpressiveButtonShape.clamShell,
  ExpressiveButtonShape.puffy,
  ExpressiveButtonShape.arch,
  ExpressiveButtonShape.slanted,
  ExpressiveButtonShape.clover8Leaf,
  ExpressiveButtonShape.verySunny,
  ExpressiveButtonShape.softBoom,
];

/// 按稳定字符串或整数种子挑选一枚 M3E 几何形状。
ExpressiveButtonShape expressiveShapeForSeed(int seed) =>
    kExpressiveBadgeShapes[seed.abs() % kExpressiveBadgeShapes.length];

/// 按稳定标识挑选色档（在 primary / secondary / tertiary 之间错落轮转）。
ExpressiveTone expressiveAccentToneForSeed(int seed) {
  const tones = [
    ExpressiveTone.primary,
    ExpressiveTone.secondary,
    ExpressiveTone.tertiary,
  ];
  return tones[(seed.abs() >> 3) % tones.length];
}

/// 多态几何图标座：比固定 4/6 边 cookie 更丰富的 M3E 形状容器，
/// 且支持随 [active] 状态在静止轮廓与展开轮廓之间连续形变。
class ExpressiveShapeBadge extends StatelessWidget {
  const ExpressiveShapeBadge({
    super.key,
    required this.icon,
    this.shape,
    this.seed,
    this.size = 38,
    this.glyphSize,
    this.tone = ExpressiveTone.primary,
    this.active = false,
    this.color,
    this.foreground,
  });

  final Glyph icon;
  final ExpressiveButtonShape? shape;
  final int? seed;
  final double size;
  final double? glyphSize;
  final ExpressiveTone tone;
  final bool active;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    final effectiveSeed = seed ?? icon.hashCode;
    final baseShape = shape ?? expressiveShapeForSeed(effectiveSeed);
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);
    final fill =
        color ??
        (active
            ? switch (tone) {
                ExpressiveTone.primary => scheme.primary,
                ExpressiveTone.secondary => scheme.secondary,
                ExpressiveTone.tertiary => scheme.tertiary,
                ExpressiveTone.warning => scheme.error,
                _ => scheme.primaryContainer,
              }
            : tones.container);
    final fg =
        foreground ??
        (active
            ? switch (tone) {
                ExpressiveTone.primary => scheme.onPrimary,
                ExpressiveTone.secondary => scheme.onSecondary,
                ExpressiveTone.tertiary => scheme.onTertiary,
                ExpressiveTone.warning => scheme.onError,
                _ => scheme.onPrimaryContainer,
              }
            : tones.onContainer);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: active ? 1 : 0, end: active ? 1 : 0),
      duration: animate
          ? ExpressiveMotion.duration(context, ExpressiveMotion.spatialDuration)
          : Duration.zero,
      curve: ExpressiveMotion.spatialCurve,
      builder: (context, progress, child) {
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: fill,
              shape: ExpressiveMorphBorder(
                from: baseShape,
                to: baseShape.pressedShape,
                progress: progress,
              ),
            ),
            child: Center(
              child: GlyphIcon(
                icon,
                size: glyphSize ?? (size * .52).roundToDouble(),
                color: fg,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 色彩鲜明的 M3E 撞色几何贴片背景层。
///
/// 底色直接落在 [Material] 上（避免 `DecoratedBox` 遮挡内部 `ListTile` 的水波断言），
/// 并在边角绘制 2~3 枚由 `seed` 决定的高对比度有机多边形与不规则 Blob 贴片。
class ExpressivePatchBackdrop extends StatelessWidget {
  const ExpressivePatchBackdrop({
    super.key,
    required this.seed,
    required this.child,
    this.tone = ExpressiveTone.neutral,
    this.active = false,
    this.intensity = 1.0,
    this.borderRadius = expressiveCornerMd,
    this.padding = EdgeInsets.zero,
    this.borderSide,
    this.onTap,
  });

  final int seed;
  final Widget child;
  final ExpressiveTone tone;
  final bool active;

  /// 撞色贴片鲜明度（0.5 柔和 ~ 1.2 鲜明）。
  final double intensity;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final BorderSide? borderSide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final baseTones = expressiveToneColors(scheme, tone);

    // 撞色组合：特意避开底色自身，形成鲜明的 M3E 几何贴片对比。
    final patches = switch (tone) {
      ExpressiveTone.primary => (
        primaryPatch: scheme.tertiaryContainer,
        secondaryPatch: scheme.secondaryContainer,
        strokeColor: scheme.primary,
      ),
      ExpressiveTone.secondary => (
        primaryPatch: scheme.primaryContainer,
        secondaryPatch: scheme.tertiaryContainer,
        strokeColor: scheme.secondary,
      ),
      ExpressiveTone.tertiary => (
        primaryPatch: scheme.primaryContainer,
        secondaryPatch: scheme.secondaryContainer,
        strokeColor: scheme.tertiary,
      ),
      _ => (
        primaryPatch: scheme.primaryContainer,
        secondaryPatch: scheme.tertiaryContainer,
        strokeColor: scheme.tertiary,
      ),
    };

    final effectiveBorder =
        borderSide ??
        BorderSide(
          color: active
              ? patches.strokeColor.withValues(alpha: .65)
              : scheme.outlineVariant.withValues(alpha: .32),
          width: active ? 1.4 : .8,
        );

    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: body,
      );
    }

    return Material(
      color: baseTones.container,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: effectiveBorder,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _M3ECollagePatchPainter(
          seed: seed,
          primaryPatch: patches.primaryPatch,
          secondaryPatch: patches.secondaryPatch,
          strokeColor: patches.strokeColor,
          active: active,
          isDark: isDark,
          intensity: intensity,
        ),
        child: body,
      ),
    );
  }
}

class _M3ECollagePatchPainter extends CustomPainter {
  const _M3ECollagePatchPainter({
    required this.seed,
    required this.primaryPatch,
    required this.secondaryPatch,
    required this.strokeColor,
    required this.active,
    required this.isDark,
    required this.intensity,
  });

  final int seed;
  final Color primaryPatch;
  final Color secondaryPatch;
  final Color strokeColor;
  final bool active;
  final bool isDark;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = seed.abs();
    final baseAlpha = (isDark ? 0.42 : 0.62) * intensity * (active ? 1.2 : 1.0);
    final secondaryAlpha =
        (isDark ? 0.34 : 0.52) * intensity * (active ? 1.2 : 1.0);
    final strokeAlpha = (isDark ? 0.40 : 0.48) * intensity;

    final shapeA = kExpressiveBadgeShapes[s % kExpressiveBadgeShapes.length];
    final shapeB =
        kExpressiveBadgeShapes[(s >> 4) % kExpressiveBadgeShapes.length];

    // 1. 右上或右下大号撞色多边形贴片
    final patchSizeA = (size.shortestSide * .78).clamp(44.0, 108.0);
    final topAnchor = (s & 1) == 0;
    final centerA = Offset(
      size.width - patchSizeA * .22,
      topAnchor ? patchSizeA * .18 : size.height - patchSizeA * .18,
    );
    final angleA = ((s % 12) - 6) * 0.12 + (active ? 0.22 : 0.0);
    _drawPolygonPatch(
      canvas,
      polygon: shapeA.polygon,
      center: centerA,
      diameter: patchSizeA,
      angle: angleA,
      paint: Paint()
        ..style = PaintingStyle.fill
        ..color = primaryPatch.withValues(alpha: baseAlpha.clamp(0.0, 0.88)),
    );

    // 2. 第二枚错位撞色几何贴片（与第一枚形成叠印拼贴感）
    final patchSizeB = (size.shortestSide * .52).clamp(28.0, 72.0);
    final centerB = Offset(
      size.width - patchSizeA * .68,
      topAnchor ? size.height - patchSizeB * .15 : patchSizeB * .22,
    );
    final angleB = -((s >> 3) % 10) * 0.15 - (active ? 0.18 : 0.0);
    _drawPolygonPatch(
      canvas,
      polygon: shapeB.polygon,
      center: centerB,
      diameter: patchSizeB,
      angle: angleB,
      paint: Paint()
        ..style = PaintingStyle.fill
        ..color = secondaryPatch.withValues(
          alpha: secondaryAlpha.clamp(0.0, 0.85),
        ),
    );

    // 3. 种子驱动的不规则 Blob 描边贴片，增加线条层次
    final blobSide = (size.shortestSide * .46).clamp(24.0, 62.0);
    final blobRect = Rect.fromCenter(
      center: Offset(
        size.width - patchSizeA * .36,
        size.height * (topAnchor ? .68 : .32),
      ),
      width: blobSide * 1.25,
      height: blobSide,
    );
    final blobPath = ExpressiveBlob.ofSeed(
      s ^ 0x5bd1e995,
    ).path(rect: blobRect, progress: active ? 0.45 : 0.0, safeInset: 6);
    canvas.drawPath(
      blobPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = strokeColor.withValues(alpha: strokeAlpha.clamp(0.0, 0.75)),
    );
  }

  void _drawPolygonPatch(
    Canvas canvas, {
    required RoundedPolygon polygon,
    required Offset center,
    required double diameter,
    required double angle,
    required Paint paint,
  }) {
    var path = polygon.toPath();
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(diameter, diameter, 1, 1)
      ..translateByDouble(-.5, -.5, 0, 1);
    path = path.transform(matrix.storage);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _M3ECollagePatchPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.primaryPatch != primaryPatch ||
      oldDelegate.secondaryPatch != secondaryPatch ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.active != active ||
      oldDelegate.isDark != isDark ||
      oldDelegate.intensity != intensity;
}

/// 控制面板小组件顶部的 **MD3 Expressive 撞色几何横幅**。
///
/// 用于承载小组件的核心说明、汇总状态胶囊与快捷动作按钮，替掉原先孤零零的一行小字。
class ExpressiveHeroBanner extends StatelessWidget {
  const ExpressiveHeroBanner({
    super.key,
    required this.seed,
    required this.icon,
    required this.title,
    this.subtitle,
    this.shape,
    this.tone = ExpressiveTone.secondary,
    this.active = false,
    this.pills = const [],
    this.trailing,
  });

  final int seed;
  final Glyph icon;
  final String title;
  final String? subtitle;
  final ExpressiveButtonShape? shape;
  final ExpressiveTone tone;
  final bool active;
  final List<Widget> pills;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = expressiveToneColors(scheme, tone);

    return ExpressivePatchBackdrop(
      seed: seed,
      tone: tone,
      active: active,
      intensity: 1.05,
      borderRadius: expressiveCornerMd,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExpressiveShapeBadge(
                icon: icon,
                shape: shape,
                seed: seed,
                size: 40,
                tone: tone == ExpressiveTone.primary
                    ? ExpressiveTone.tertiary
                    : ExpressiveTone.primary,
                active: active,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: tones.onContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tones.onContainer.withValues(alpha: .82),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: pills),
          ],
        ],
      ),
    );
  }
}

/// 响应式 **MD3 Expressive 开关磁贴**。
///
/// 带有：
/// - 左侧多态几何图标座（开启时自动形变并切换高亮主色）；
/// - 右侧撞色几何贴片背景装饰；
/// - 整格可点 + 弹簧缩放反馈 + [M3ESwitch]。
class ExpressiveToggleTile extends StatelessWidget {
  const ExpressiveToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.subtitle,
    this.shape,
    this.activeTone = ExpressiveTone.primary,
    this.seed,
    this.disabled = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Glyph icon;
  final ExpressiveButtonShape? shape;
  final ExpressiveTone activeTone;
  final int? seed;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tileSeed = seed ?? expressiveBlobSeed(title);
    final effectiveTone = value ? activeTone : ExpressiveTone.sunken;
    final tones = expressiveToneColors(scheme, effectiveTone);
    final animate =
        !disabled &&
        !eInkInstantRoutes &&
        !MediaQuery.disableAnimationsOf(context);

    final card = ExpressivePatchBackdrop(
      seed: tileSeed,
      tone: effectiveTone,
      active: value,
      intensity: value ? 1.05 : 0.72,
      borderRadius: value
          ? const BorderRadius.all(Radius.circular(20))
          : expressiveCornerSm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: disabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged(!value);
            },
      child: Row(
        children: [
          ExpressiveShapeBadge(
            icon: icon,
            shape: shape,
            seed: tileSeed,
            size: 36,
            tone: activeTone,
            active: value,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: value ? FontWeight.w700 : FontWeight.w600,
                    color: tones.onContainer,
                    fontSize: 12.5,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: value
                          ? tones.onContainer.withValues(alpha: .82)
                          : scheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          M3ESwitch(
            semanticLabel: title,
            value: value,
            selectedIcon: const Icon(Icons.check, size: 16),
            onChanged: disabled
                ? null
                : (next) {
                    HapticFeedback.selectionClick();
                    onChanged(next);
                  },
          ),
        ],
      ),
    );

    if (disabled) {
      return Opacity(opacity: 0.55, child: card);
    }

    return ActionBubbleTarget(
      enabled: !eInkInstantRoutes,
      corner: 18,
      child: ElasticPress(enabled: animate, child: card),
    );
  }
}
