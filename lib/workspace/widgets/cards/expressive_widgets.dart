import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_control_kit.dart';
import 'package:zephyr/workspace/widgets/insights/insight_components.dart';

export 'package:zephyr/workspace/widgets/cards/expressive_control_kit.dart';

/// 面板卡片的 **MD3 Expressive 小组件库**。
///
/// 洞察面板先按这套语言重做过一轮（非对称圆角、cookie 形图标座、弹簧驱动的
/// 数值与进度、可点选条目），信息 / 控制 / 发现三个面板此前仍是「一行行纯文本」。
/// 这里把那套语言里**与图表无关**的部分抽成通用件，供三个面板共用：
/// 卡片外壳继续用 [CollapsibleCard] 的 `expressive: true`，卡片内容用本文件的件。
///
/// 三条纪律：
/// - **数值不编**：`null` 一律画成 `—`，不 fallback 成 0，也不换个说法猜；
/// - **窄卡先活**：每个件都在 `LayoutBuilder` 里自选档，2×1 槽位与全宽槽位都不溢出；
/// - **动效可关**：`eInkInstantRoutes` 与「减少动态效果」下弹簧直接落位。

/// Expressive 的非对称圆角：三圆一尖，视线从尖角那侧进数值。
///
/// 与 [InsightMetric] 用的是同一组数（22 / 22 / 6 / 22），所以洞察卡与信息卡
/// 并排时看不出是两套东西。
const BorderRadius expressiveCornerSm = BorderRadius.only(
  topLeft: Radius.circular(18),
  topRight: Radius.circular(18),
  bottomLeft: Radius.circular(6),
  bottomRight: Radius.circular(18),
);

const BorderRadius expressiveCornerMd = BorderRadius.only(
  topLeft: Radius.circular(22),
  topRight: Radius.circular(22),
  bottomLeft: Radius.circular(6),
  bottomRight: Radius.circular(22),
);

const BorderRadius expressiveCornerLg = BorderRadius.only(
  topLeft: Radius.circular(28),
  topRight: Radius.circular(28),
  bottomLeft: Radius.circular(8),
  bottomRight: Radius.circular(28),
);

/// 小组件的容器色档。
///
/// 只有这几档，且全部走 `ColorScheme` 的 container 对 —— Expressive 的分层靠
/// 容器色而不是描边/投影，自己挑 `Colors.xxx` 会在暗色主题下立刻散架。
enum ExpressiveTone {
  /// 卡片内的一层浅底（默认）。
  neutral,

  /// 比卡片本身更浅的一层，用于「这块是原始数据」。
  sunken,

  /// 主色高亮：当前值 / 被选中 / 需要一眼看到的那格。
  primary,

  secondary,
  tertiary,

  /// 出错、不可用这类需要警示但不打断阅读的那档。
  warning,
}

/// 一档 tone 对应的（容器色, 前景色）。
({Color container, Color onContainer}) expressiveToneColors(
  ColorScheme scheme,
  ExpressiveTone tone,
) {
  return switch (tone) {
    ExpressiveTone.neutral => (
      container: scheme.surfaceContainerHighest,
      onContainer: scheme.onSurface,
    ),
    ExpressiveTone.sunken => (
      container: scheme.surfaceContainerLow,
      onContainer: scheme.onSurface,
    ),
    ExpressiveTone.primary => (
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
    ),
    ExpressiveTone.secondary => (
      container: scheme.secondaryContainer,
      onContainer: scheme.onSecondaryContainer,
    ),
    ExpressiveTone.tertiary => (
      container: scheme.tertiaryContainer,
      onContainer: scheme.onTertiaryContainer,
    ),
    ExpressiveTone.warning => (
      container: scheme.errorContainer,
      onContainer: scheme.onErrorContainer,
    ),
  };
}

/// Expressive 图标座：cookie 形容器 + 居中字形。
///
/// 洞察那边是 36×36 的 `cookie4Sided`；这里把尺寸与边数开放出来，
/// 让「卡片标题的图标」和「一行事实的图标」能用不同重量而不必各写一份。
class ExpressiveIconBadge extends StatelessWidget {
  const ExpressiveIconBadge({
    super.key,
    required this.icon,
    this.size = 36,
    this.glyphSize,
    this.tone = ExpressiveTone.primary,
    this.color,
    this.foreground,
    this.sided,
  });

  final Glyph icon;
  final double size;
  final double? glyphSize;

  /// [color] 为 null 时用它取色。
  final ExpressiveTone tone;

  /// 覆盖容器色（例如按图源取色）。
  final Color? color;
  final Color? foreground;

  /// 覆盖形状（null = 按尺寸自选：小的一颗用 6 边，大的用 4 边）。
  final M3EShapeKind? sided;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    return SizedBox(
      width: size,
      height: size,
      child: M3EShapeContainer(
        kind:
            sided ??
            (size <= 28
                ? M3EShapeKind.cookie6Sided
                : M3EShapeKind.cookie4Sided),
        color: color ?? tones.container,
        child: Center(
          child: GlyphIcon(
            icon,
            size: glyphSize ?? (size * .56).roundToDouble(),
            color: foreground ?? tones.onContainer,
          ),
        ),
      ),
    );
  }
}

/// 一块 Expressive 底面：非对称圆角 + 容器色分层 + 可选点击。
///
/// 卡片内容里几乎所有「格子」都是它；[ExpressiveFactTile]、
/// [ExpressiveStatTile] 等是在它上面排好的具体版式。
class ExpressiveTile extends StatelessWidget {
  const ExpressiveTile({
    super.key,
    required this.child,
    this.tone = ExpressiveTone.neutral,
    this.color,
    this.radius = expressiveCornerSm,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  final Widget child;
  final ExpressiveTone tone;
  final Color? color;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;

  /// 可点（选中 / 复制 / 打开详情）。为 null 时不吃点击，也不画按压反馈。
  final VoidCallback? onTap;

  /// 选中态：换成主色容器并描一圈主色，替旧实现里那种「换个背景色」。
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    final animate =
        onTap != null &&
        !eInkInstantRoutes &&
        !MediaQuery.disableAnimationsOf(context);

    final body = AnimatedContainer(
      // 换色也要吃「减少动态效果」与墨水屏：本文件的第三条纪律不是只说弹簧。
      duration: animate
          ? ExpressiveMotion.duration(context, ExpressiveMotion.effectDuration)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : (color ?? tones.container),
        borderRadius: radius,
        border: selected
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(
                color: scheme.outlineVariant.withValues(alpha: .28),
                width: .5,
              ),
      ),
      child: child,
    );

    if (onTap == null) return body;
    return ActionBubbleTarget(
      enabled: !eInkInstantRoutes,
      corner: 18,
      child: ElasticPress(
        enabled: animate,
        child: Semantics(
          button: true,
          selected: selected,
          label: semanticLabel,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              radius: 90,
              borderRadius: radius,
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行「标签 + 值」的 Expressive 事实格。
///
/// 取代信息面板原来的裸 [InfoRow]：值仍然可选中复制（路径 / ID 不用截屏），
/// 但窄卡里标签与值上下排，宽卡里左右排，并且高亮那一格用主色容器而不是加粗。
class ExpressiveFactTile extends StatelessWidget {
  const ExpressiveFactTile({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.tone = ExpressiveTone.sunken,
    this.emphasis = false,
    this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Glyph? icon;
  final ExpressiveTone tone;

  /// 「这一格是当前值」：主色容器 + 更重的字重。
  final bool emphasis;
  final VoidCallback? onTap;
  final bool selected;

  /// 值右侧的次要信息（单位、百分比、状态点）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    final foreground = emphasis ? scheme.onPrimaryContainer : tones.onContainer;

    final labelText = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: emphasis
            ? scheme.onPrimaryContainer.withValues(alpha: .85)
            : scheme.onSurfaceVariant,
        letterSpacing: .3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final valueText = Text(
      value ?? '—',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: foreground,
        fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    // 可点的格子**不套** SelectionArea：SelectableRegion 自己的 tap 识别器会在
    // 竞技场里赢过外层 InkWell，于是点在值上（格子最大部分面积）静默丢点击。
    // 实测：label 上点得到、value 上点不到。
    // 二者只能选一个 —— 可点的格子是控件，不可点的才是用来复制路径 / ID 的数据。
    final content =
        valueWidget ??
        (onTap == null ? SelectionArea(child: valueText) : valueText);

    return ExpressiveTile(
      tone: emphasis ? ExpressiveTone.primary : tone,
      selected: selected,
      onTap: onTap,
      semanticLabel: '$label ${value ?? ''}',
      radius: expressiveCornerSm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 200 ||
              MediaQuery.textScalerOf(context).scale(12) > 20;
          final iconSlot = icon == null
              ? const SizedBox.shrink()
              : ExpressiveIconBadge(
                  icon: icon!,
                  size: 26,
                  tone: emphasis ? ExpressiveTone.primary : tone,
                  color: emphasis
                      ? scheme.primary.withValues(alpha: .18)
                      : null,
                  foreground: foreground,
                );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[iconSlot, const SizedBox(width: 8)],
                    Expanded(child: labelText),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: content),
                    ?trailing,
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[iconSlot, const SizedBox(width: 10)],
              SizedBox(width: 74, child: labelText),
              const SizedBox(width: 8),
              Expanded(child: content),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          );
        },
      ),
    );
  }
}

/// 大数字格：一个值得被读出来的数 + 它的名字。
///
/// 与 [InsightMetric] 同形（同一组圆角与字号），差别是这里允许可点与
/// 一条底部进度 —— 信息面板的「已用 / 总量」、控制面板的「当前档位」用的是它。
class ExpressiveStatTile extends StatelessWidget {
  const ExpressiveStatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.highlight = false,
    this.caption,
    this.gauge,
    this.onTap,
    this.selected = false,
    this.maxValueLines = 1,
  });

  final String value;
  final String label;
  final Glyph? icon;
  final bool highlight;
  final String? caption;

  /// 底部那条进度（0..1）；null = 不画。
  final double? gauge;

  final VoidCallback? onTap;
  final bool selected;
  final int maxValueLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = highlight ? scheme.onPrimaryContainer : scheme.onSurface;

    return ExpressiveTile(
      tone: highlight ? ExpressiveTone.primary : ExpressiveTone.neutral,
      radius: expressiveCornerMd,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      onTap: onTap,
      selected: selected,
      semanticLabel: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExpressiveIconBadge(
              icon: icon!,
              size: 32,
              tone: highlight ? ExpressiveTone.primary : ExpressiveTone.neutral,
              color: highlight
                  ? scheme.primary.withValues(alpha: .16)
                  : scheme.primary.withValues(alpha: .12),
              foreground: highlight
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: maxValueLines,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground.withValues(alpha: .75),
              ),
            ),
          ],
          if (gauge != null) ...[
            const SizedBox(height: 10),
            ExpressiveGauge(
              value: gauge!,
              color: highlight ? scheme.onPrimaryContainer : scheme.primary,
              trackColor: highlight
                  ? scheme.primaryContainer.withValues(alpha: .45)
                  : scheme.surfaceContainerHighest,
            ),
          ],
        ],
      ),
    );
  }
}

/// 弹簧驱动的线性进度条（走 M3E 的 linear 指示器）。
class ExpressiveGauge extends StatelessWidget {
  const ExpressiveGauge({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  final double value;
  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InsightSpringValue(
      value: value.clamp(0, 1),
      builder: (animated) => M3EProgressIndicator.linear(
        value: animated,
        color: color ?? scheme.primary,
        trackColor: trackColor ?? scheme.surfaceContainerHighest,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
      ),
    );
  }
}

/// 状态胶囊：一颗点 + 一个词。
///
/// 用于卡片标题行右侧与「这一项当前是什么状态」。点比图标便宜，
/// 且颜色本身就能承载「就绪 / 进行中 / 失败」三态。
class ExpressiveStatusPill extends StatelessWidget {
  const ExpressiveStatusPill({
    super.key,
    required this.text,
    this.tone = ExpressiveTone.secondary,
    this.icon,
    this.dot = true,
    this.compact = false,
  });

  final String text;
  final ExpressiveTone tone;
  final Glyph? icon;

  /// 画不画那颗状态点（有 [icon] 时默认让位给图标）。
  final bool dot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    final showDot = dot && icon == null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 11,
        vertical: compact ? 3 : 5,
      ),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: tones.container,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: tones.onContainer,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            GlyphIcon(icon!, size: compact ? 12 : 14, color: tones.onContainer),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (compact
                          ? theme.textTheme.labelSmall
                          : theme.textTheme.labelMedium)
                      ?.copyWith(
                        color: tones.onContainer,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态：一颗很轻的 cookie 图标座 + 一句「为什么是空的」。
///
/// 信息面板的空态不是「没做完」，而是「还没打开书」——所以要说清
/// 打开之后这里会出现什么，而不是画一个转圈或留白。
class ExpressiveEmptyState extends StatelessWidget {
  const ExpressiveEmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.hint,
  });

  final Glyph icon;
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpressiveIconBadge(
            icon: icon,
            size: 32,
            color: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小组件网格：按可用宽度决定几列，列宽相等。
///
/// 槽位尺寸由卡片的跨度决定，内容不能反过来把格子撑大（洞察那轮踩过的坑），
/// 所以这里用 `SizedBox(width:)` 而不是 `Flexible`。
class ExpressiveTileGrid extends StatelessWidget {
  const ExpressiveTileGrid({
    super.key,
    required this.children,
    this.spacing = 8,
    this.minTileWidth = 150,
  });

  final List<Widget> children;
  final double spacing;

  /// 低于这个宽度就少排一列（最终可以退到单列）。
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (children.isEmpty) return const SizedBox.shrink();
        final count = (constraints.maxWidth / (minTileWidth * scale))
            .floor()
            .clamp(1, children.length);
        final width = (constraints.maxWidth - (count - 1) * spacing) / count;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// 卡内的一节：一个小标题 + 若干内容，用于把长事实区分组。
///
/// 控制面板的多节设置与信息面板的多组事实都用它，替掉原先手写的
/// 「图标 + 主色 12px 文本」——那行字既没有 Expressive 的形状，
/// 也没有随主题走的对比度。
class ExpressiveSection extends StatelessWidget {
  const ExpressiveSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Glyph? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seed = title.codeUnits.fold<int>(0, (a, b) => a * 31 + b);
    final tone = expressiveAccentToneForSeed(seed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                ExpressiveShapeBadge(
                  icon: icon!,
                  seed: seed,
                  size: 26,
                  glyphSize: 14,
                  tone: tone,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        for (final child in children) child,
      ],
    );
  }
}
