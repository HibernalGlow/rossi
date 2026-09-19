// 液态玻璃（Liquid Glass）材质基元 —— **全仓唯一的玻璃实现**。
//
// 苹果把这块材质拆成四层：折射/透镜 → 着色 → 高光 → 阴影。
// Flutter 拿不到逐层合成信息（整个 UI 对系统合成器只是一张纹理，
// 它不知道玻璃后面是图片还是文字），所以只能按能做的近似：
//
//   · 折射层 → `BackdropFilter` 的「模糊 + **饱和增强**」。
//     饱和增强是分水岭：苹果说的是「弯曲并汇聚光线」(lensing)，
//     只做高斯模糊那是 iOS 7 时代的磨砂玻璃，看起来就是一层灰雾。
//   · 着色层 → **中性**半透明填充（白/黑），不掺 `colorScheme.surface`，
//     且深浅模式各取一套值。掺主题色会让玻璃在两种模式下各偏一边，
//     这是「不像苹果」的主因之一。着色还要保证纯黑背景上面板仍可见。
//   · 高光层 → 沿光照角（默认 315°，苹果的基准光）的渐变描边，
//     模拟 Fresnel 边缘反射（掠射角反射率趋近 100%，所以边缘比中间亮）
//     + 同方向的顶部反光。
//   · 阴影层 → 大半径、低不透明度的外阴影，把面板从背景里托起来。
//
// 各处**按档位取用**（`LiquidGlassThickness`），不要再一个组件写一套
// blur / alpha ——「一致」指的是共用同一套材质语言，不是所有面板同一个数值；
// 苹果自己也是导航栏、弹窗、警报各用不同 weight。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 材质权重。
///
/// 对应苹果给开发者的四档里的三档（`ultraThinMaterial` 只用于整屏环境叠层，
/// 本仓没有那种用法，先不留）。
enum LiquidGlassThickness {
  /// 导航栏 / 标签栏：轻着色，背景内容可见但被柔化。
  thin,

  /// 卡片 / 弹窗 / 提示条：中等着色，层级分离明确。
  regular,

  /// 警报 / 关键对话框，以及**压在内容上的阅读器浮层**：
  /// 重着色、接近不透明，保证前景永远读得清。
  thick,
}

/// 光源与几何的基准值。
abstract final class LiquidGlassDefaults {
  /// 基准光照角（度）。从正上方顺时针量，315° 即苹果的左上打光，
  /// 高光落在左上、右下最弱。改这个值等于把「灯」挪个位置。
  static const double lightAngle = 315;

  /// 描边宽度。苹果是 1px 极细高光，粗了就成描框了。
  static const double bezelWidth = 1;
}

/// 一套材质参数（已解析成可直接渲染的值）。
@immutable
class LiquidGlassSpec {
  const LiquidGlassSpec({
    required this.blur,
    required this.saturation,
    required this.tint,
    required this.bezel,
    required this.sheen,
    required this.shadow,
    required this.shadowBlur,
    required this.shadowOffset,
  });

  /// 背景模糊 sigma。
  final double blur;

  /// 饱和度倍数（1.0 = 不增强）。
  final double saturation;

  /// 面板着色（含 alpha）。
  final Color tint;

  /// Fresnel 边缘高光的峰值色（含 alpha），沿光照角渐隐。
  final Color bezel;

  /// 顶部反光的峰值色（含 alpha）。
  final Color sheen;

  final Color shadow;
  final double shadowBlur;
  final Offset shadowOffset;

  /// 按整体不透明度缩放。
  ///
  /// **注意不要用 `Opacity` 包住玻璃**：那等于给整个面板（含已经模糊好的背景）
  /// 再套一层 alpha，玻璃会变成一层白雾，而且白白多一次 `saveLayer`。
  /// 把 alpha 缩进 tint / 高光 / 阴影里，才等价于「这块玻璃更透」。
  LiquidGlassSpec withOpacity(double opacity) {
    final factor = opacity.clamp(0.0, 1.0);
    Color scale(Color color) => color.withValues(alpha: color.a * factor);
    return LiquidGlassSpec(
      blur: blur,
      saturation: saturation,
      tint: scale(tint),
      bezel: scale(bezel),
      sheen: scale(sheen),
      shadow: scale(shadow),
      shadowBlur: shadowBlur,
      shadowOffset: shadowOffset,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSpec &&
      other.blur == blur &&
      other.saturation == saturation &&
      other.tint == tint &&
      other.bezel == bezel &&
      other.sheen == sheen &&
      other.shadow == shadow &&
      other.shadowBlur == shadowBlur &&
      other.shadowOffset == shadowOffset;

  @override
  int get hashCode => Object.hash(
    blur,
    saturation,
    tint,
    bezel,
    sheen,
    shadow,
    shadowBlur,
    shadowOffset,
  );
}

/// 各档位的具体参数。
///
/// 模糊半径与饱和度直接对齐苹果那张材质表：
/// `thin 16pt / 1.4x`、`regular 24pt / 1.6x`、`thick 40pt / 1.8x`。
/// 着色值取苹果 "clear" 与 "regular" 两套实测值
/// （clear 深色 `rgba(28,28,32,.30)` / 浅色 `rgba(255,255,255,.40)`，
/// regular 深色 `rgba(34,34,38,.62)` / 浅色 `rgba(248,248,250,.66)`），
/// thick 再往上压一档到接近不透明。
abstract final class LiquidGlassSpecs {
  static LiquidGlassSpec of(
    LiquidGlassThickness thickness,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    switch (thickness) {
      case LiquidGlassThickness.thin:
        return LiquidGlassSpec(
          blur: 16,
          saturation: 1.4,
          tint: dark ? const Color(0x4D1C1C20) : const Color(0x66FFFFFF),
          bezel: dark ? const Color(0x52FFFFFF) : const Color(0x7AFFFFFF),
          sheen: dark ? const Color(0x1FFFFFFF) : const Color(0x2EFFFFFF),
          // 深色主题下阴影要更重一点才看得出来，不再拘泥于苹果的 8%~15%。
          shadow: dark ? const Color(0x40000000) : const Color(0x14000000),
          shadowBlur: 30,
          shadowOffset: const Offset(0, 8),
        );
      case LiquidGlassThickness.regular:
        return LiquidGlassSpec(
          blur: 24,
          saturation: 1.6,
          tint: dark ? const Color(0x9E222226) : const Color(0xA8F8F8FA),
          bezel: dark ? const Color(0x5CFFFFFF) : const Color(0x8AFFFFFF),
          sheen: dark ? const Color(0x26FFFFFF) : const Color(0x38FFFFFF),
          shadow: dark ? const Color(0x4D000000) : const Color(0x19000000),
          shadowBlur: 36,
          shadowOffset: const Offset(0, 10),
        );
      case LiquidGlassThickness.thick:
        return LiquidGlassSpec(
          blur: 40,
          saturation: 1.8,
          tint: dark ? const Color(0xC728282E) : const Color(0xDBFFFFFF),
          bezel: dark ? const Color(0x66FFFFFF) : const Color(0x99FFFFFF),
          sheen: dark ? const Color(0x2BFFFFFF) : const Color(0x40FFFFFF),
          shadow: dark ? const Color(0x57000000) : const Color(0x1F000000),
          shadowBlur: 40,
          shadowOffset: const Offset(0, 12),
        );
    }
  }
}

/// 液态玻璃面板：把自己的 `child` 放在一块玻璃上。
///
/// ```dart
/// LiquidGlassSurface(
///   thickness: LiquidGlassThickness.regular,
///   borderRadius: BorderRadius.circular(16),
///   child: Padding(padding: ..., child: ...),
/// )
/// ```
///
/// 无障碍与降级（任一命中即换成不透明实色，只留圆角与描边）：
/// 调用方显式 `enabled: false`、系统开了「高对比度」、系统开了「减少动效」。
/// 玻璃本身是层级暗示而不是装饰，看不清背景时它反而是负担。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.thickness = LiquidGlassThickness.regular,
    this.borderRadius,
    this.radius = 16,
    this.lightAngle = LiquidGlassDefaults.lightAngle,
    this.opacity = 1.0,
    this.enabled = true,
    this.spec,
    this.shadowScale = 1.0,
  });

  final Widget child;

  /// 材质档位；给了 [spec] 时以 [spec] 为准。
  final LiquidGlassThickness thickness;

  /// 显式圆角；不传则用 [radius] 生成四角等值圆角。
  final BorderRadius? borderRadius;

  /// [borderRadius] 的简写。
  final double radius;

  /// 光照角（度），见 [LiquidGlassDefaults.lightAngle]。
  final double lightAngle;

  /// 整块玻璃的不透明度（缩进 tint / 高光 / 阴影，不是外层 `Opacity`）。
  final double opacity;

  final bool enabled;

  /// 覆盖档位的默认参数（例如某处想要更实的底色）。
  final LiquidGlassSpec? spec;

  /// 外阴影的缩放（0~1）。
  ///
  /// 档位阴影按「面板」校准；44px 的小圆按钮、贴边顶栏用全套阴影
  /// 会重得像悬浮在半米之外，调用处按体量缩小。
  final double shadowScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.maybeOf(context);
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final degrade =
        !enabled ||
        (media?.highContrast ?? false) ||
        (media?.disableAnimations ?? false);

    if (degrade) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: shape,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: child,
      );
    }

    final resolved = (spec ?? LiquidGlassSpecs.of(thickness, theme.brightness))
        .withOpacity(opacity);
    final scaledShadow = resolved.shadow.withValues(
      alpha: resolved.shadow.a * shadowScale.clamp(0.0, 1.0),
    );

    // 阴影画在裁剪区之外：ClipRRect 会把溢出的阴影一起剪掉。
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: scaledShadow,
            blurRadius: resolved.shadowBlur,
            offset: resolved.shadowOffset,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: _refractionFilter(resolved),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: resolved.tint,
              borderRadius: shape,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _LiquidGlassBezelPainter(
                        radius: shape,
                        lightAngle: lightAngle,
                        color: resolved.bezel,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: shape,
                        gradient: LinearGradient(
                          begin: alignmentOfLightAngle(lightAngle),
                          end: Alignment.center,
                          colors: [resolved.sheen, const Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 光照角（度）→ 对齐方向。
///
/// 角度从正上方起顺时针量（同 CSS `conic-gradient(from ...)` 的约定），
/// 所以 0° 是正上、90° 是正右、315° 是左上 —— 也正是苹果的基准光位。
Alignment alignmentOfLightAngle(double degrees) {
  final radians = degrees * math.pi / 180;
  // cos(90°) 的浮点结果是 ~6e-17 而不是 0，不归零的话轴向角度
  // 得到的 Alignment 永远对不上 topCenter/centerRight 这些常量。
  return Alignment(_snapZero(math.sin(radians)), -_snapZero(math.cos(radians)));
}

double _snapZero(double value) => value.abs() < 1e-9 ? 0 : value;

/// 折射层滤镜：先模糊，再增强饱和度。
///
/// 顺序不能反：饱和度矩阵作用在已经模糊过的背景上，才是「透过玻璃看到的
/// 颜色更浓」；反过来会把噪点一起放大。
ui.ImageFilter _refractionFilter(LiquidGlassSpec spec) {
  final blur = ui.ImageFilter.blur(sigmaX: spec.blur, sigmaY: spec.blur);
  if (spec.saturation <= 1.0) return blur;
  return ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(saturationMatrix(spec.saturation)),
    inner: blur,
  );
}

/// 饱和度矩阵（Rec. 709 亮度权重）。
///
/// 公开出来是为了能被单测直接断言 —— 这是「玻璃」与「磨砂」的分水岭，
/// 数值错了肉眼不一定立刻看出来，但整体会少一层通透感。
List<double> saturationMatrix(double saturation) {
  const lumR = 0.213;
  const lumG = 0.715;
  const lumB = 0.072;
  final inverse = 1 - saturation;
  return <double>[
    lumR * inverse + saturation, lumG * inverse, lumB * inverse, 0, 0, //
    lumR * inverse, lumG * inverse + saturation, lumB * inverse, 0, 0, //
    lumR * inverse, lumG * inverse, lumB * inverse + saturation, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// 沿光照角的渐变描边：光源那侧最亮，正对面最弱。
class _LiquidGlassBezelPainter extends CustomPainter {
  const _LiquidGlassBezelPainter({
    required this.radius,
    required this.lightAngle,
    required this.color,
  });

  final BorderRadius radius;
  final double lightAngle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final rect = Offset.zero & size;
    final rrect = radius
        .toRRect(rect)
        .deflate(LiquidGlassDefaults.bezelWidth / 2);
    final begin = alignmentOfLightAngle(lightAngle);
    final shader = LinearGradient(
      begin: begin,
      end: Alignment(-begin.x, -begin.y),
      colors: [
        color,
        color.withValues(alpha: color.a * 0.45),
        color.withValues(alpha: color.a * 0.18),
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = LiquidGlassDefaults.bezelWidth
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_LiquidGlassBezelPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.lightAngle != lightAngle ||
      oldDelegate.color != color;
}
