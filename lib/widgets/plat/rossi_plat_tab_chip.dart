import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';

/// plat 标签 chip 的 rossi 版：与 `PlatTabChip` 视觉同构，但**结构恒定**。
///
/// # 为什么要重写它（按下期间渲染帧 ⇒ 点按必死）
///
/// `PlatTabChip` 的按下/悬停状态层是这么画的：`Container.foregroundDecoration`
/// 在**常态是 null、按下才有值**。而 `Container` 的合成顺序是
/// 「约束 → 前景 DecoratedBox → 背景 DecoratedBox → Padding → Align → 子级」
/// —— `foregroundDecoration` 从 null 翻成有值的那一刻，**同一槽位上的 widget
/// 还是 `DecoratedBox`（旧元素被就地复用成前景盒），原来的背景盒只能作为新的
/// 子级整个重新装配**：Padding 往下的整棵子树（包括关闭按钮的
/// `GestureDetector`）全部重挂，旧 element 连同它手里正在追踪的指针、
/// 手势竞技场成员身份一起消失。
///
/// 于是实机上的现象是：手指按下的瞬间 `_DraggableTab` 的
/// `Listener(onPointerDown: _setPressed)` 触发 setState，下一帧重挂整片，
/// 手指抬起时事件送到已经无人认领的渲染对象上 —— **点 × 十次九空**。
/// 桌面端没人发现，是因为鼠标总是**先悬停再点击**：悬停时翻转已经发生、
/// 结构已稳定；触摸没有悬停，翻转恰好落在按住期间。
///
/// 修法只有一条：**前景层恒在** —— `foregroundDecoration` 永远给一个
/// `BoxDecoration`，未按下/未悬停时颜色取透明。只变色、不变结构，
/// element 全程复用，点按安然无恙。
///
/// 其余各层（取色、字号、指示条、内边距）逐层照抄 `plat-0.1.1`
/// `lib/src/ui/tabs/chip.dart`（MIT），只有上面这一处行为差异 —— 上游若修了
/// 同一个问题，这里可以整体退役换回去。
class RossiPlatTabChip extends StatelessWidget {
  /// Optional widget before the label.
  final Widget? leading;

  /// Optional label widget.
  final Widget? label;

  /// Optional widget after the label.
  final Widget? trailing;

  /// Gap between leading / label / trailing slots.
  final double gap;

  /// Padding around this chip's content. When null, falls back to
  /// [PlatTabBarTheme.labelPadding].
  final EdgeInsetsGeometry? labelPadding;

  /// How to clip this chip's content.
  final Clip clipBehavior;

  /// 这条标签当前的状态集（selected / pressed / hovered / dragged…）。
  ///
  /// `PlatTabChip` 从 `_PlatTabScope`（包私有）里读同一份；这里拿不到 scope，
  /// 由宿主从 `PlatTabDetails.states` 传进来。
  final Set<WidgetState> states;

  /// 这条标签条贴在哪条边上：选中指示条（下划线/描边）的朝向。
  final TabBarSide side;

  const RossiPlatTabChip({
    super.key,
    this.leading,
    this.label,
    this.trailing,
    this.gap = 6,
    this.labelPadding,
    this.clipBehavior = Clip.none,
    this.states = const {},
    this.side = TabBarSide.top,
  });

  @override
  Widget build(BuildContext context) {
    final theme = PlatTheme.of(context).tabBar;
    final materialTabTheme = TabBarTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final selected = states.contains(WidgetState.selected);

    final background =
        theme.chipBackgroundColor?.resolve(states) ??
        _defaultChipBackground(colorScheme, states, selected);
    final foreground =
        theme.chipForegroundColor?.resolve(states) ??
        (selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant);
    final baseStyle =
        _materialLabelStyle(materialTabTheme, selected) ??
        Theme.of(context).textTheme.labelMedium ??
        const TextStyle();
    final stateStyle = selected ? theme.labelStyle : theme.unselectedLabelStyle;
    final style = baseStyle.merge(stateStyle).copyWith(color: foreground);
    final overlay =
        theme.overlayColor?.resolve(states) ??
        materialTabTheme.overlayColor?.resolve(states) ??
        _defaultOverlayColor(colorScheme, states, selected);

    final effectiveLabel =
        label ??
        Text(
          tabTitleFallback(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

    final content = leading == null && trailing == null
        ? effectiveLabel
        : LayoutBuilder(
            builder: (context, constraints) => Row(
              mainAxisSize: constraints.maxWidth.isFinite
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, SizedBox(width: gap)],
                Flexible(
                  fit: constraints.maxWidth.isFinite
                      ? FlexFit.tight
                      : FlexFit.loose,
                  child: effectiveLabel,
                ),
                if (trailing != null) ...[SizedBox(width: gap), trailing!],
              ],
            ),
          );

    final inner = IconTheme.merge(
      data: IconThemeData(color: style.color),
      child: DefaultTextStyle.merge(
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: content,
      ),
    );

    final body = Container(
      alignment: Alignment.center,
      padding: labelPadding ?? theme.labelPadding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: background,
        borderRadius: theme.chipBorderRadius,
        border: _indicatorBorder(context, theme, states),
      ),
      // ★ 本体与上游唯一的差异：恒在（透明也算在），按下/悬停只变色。
      foregroundDecoration: BoxDecoration(
        color: overlay ?? Colors.transparent,
        borderRadius: theme.chipBorderRadius,
      ),
      child: inner,
    );

    return _withStackedIndicator(context, body, theme, states);
  }

  /// 宿主没给 label 时的兜底：没有上下文可读标题，画一段等宽空白。
  static String tabTitleFallback(BuildContext context) => '';

  /// 抄自 plat chip.dart 的默认取色（MIT）。
  static Color? _defaultOverlayColor(
    ColorScheme colors,
    Set<WidgetState> states,
    bool selected,
  ) {
    if (states.contains(WidgetState.pressed)) {
      return colors.primary.withValues(alpha: 0.10);
    }
    if (states.contains(WidgetState.hovered)) {
      return (selected ? colors.primary : colors.onSurface).withValues(
        alpha: 0.08,
      );
    }
    return null;
  }

  static Color _defaultChipBackground(
    ColorScheme colors,
    Set<WidgetState> states,
    bool selected,
  ) {
    if (states.contains(WidgetState.dragged)) {
      return Color.alphaBlend(
        colors.primary.withValues(alpha: 0.26),
        colors.surfaceContainerHigh,
      );
    }
    return selected ? colors.surfaceContainerHigh : colors.surface;
  }

  static TextStyle? _materialLabelStyle(
    TabBarThemeData theme,
    bool selected,
  ) {
    if (selected) return theme.labelStyle;
    return theme.unselectedLabelStyle ?? theme.labelStyle;
  }

  /// 选中项贴边的那条线（上游叫 indicator border）。
  ///
  /// rossi 的两档主题都走不到这里：横向档给了 `indicator`（圆角下划线）、
  /// 竖向档 `indicatorWeight = 0`。保留是为了与上游结构同构。
  BoxBorder? _indicatorBorder(
    BuildContext context,
    PlatTabBarTheme theme,
    Set<WidgetState> states,
  ) {
    if (!states.contains(WidgetState.selected)) return null;
    if (theme.indicator != null || theme.indicatorPadding != EdgeInsets.zero) {
      return null;
    }
    if (theme.indicatorWeight <= 0) return null;

    final borderSide = BorderSide(
      color: theme.indicatorColor ??
          TabBarTheme.of(context).indicatorColor ??
          Theme.of(context).colorScheme.primary,
      width: theme.indicatorWeight,
    );
    return switch (side) {
      TabBarSide.top => Border(bottom: borderSide),
      TabBarSide.bottom => Border(top: borderSide),
      TabBarSide.left => Border(right: borderSide),
      TabBarSide.right => Border(left: borderSide),
    };
  }

  Widget _withStackedIndicator(
    BuildContext context,
    Widget child,
    PlatTabBarTheme theme,
    Set<WidgetState> states,
  ) {
    if (!states.contains(WidgetState.selected)) return child;
    if (theme.indicator == null && theme.indicatorPadding == EdgeInsets.zero) {
      return child;
    }
    if (theme.indicatorWeight <= 0) return child;

    final decoration =
        theme.indicator ??
        BoxDecoration(color: _indicatorColor(context));
    final insets = theme.indicatorPadding.resolve(
      Directionality.maybeOf(context),
    );
    final positioned = switch (side) {
      TabBarSide.top => Positioned(
        left: insets.left,
        right: insets.right,
        bottom: insets.bottom,
        height: theme.indicatorWeight,
        child: DecoratedBox(decoration: decoration),
      ),
      TabBarSide.bottom => Positioned(
        left: insets.left,
        right: insets.right,
        top: insets.top,
        height: theme.indicatorWeight,
        child: DecoratedBox(decoration: decoration),
      ),
      TabBarSide.left => Positioned(
        top: insets.top,
        bottom: insets.bottom,
        right: insets.right,
        width: theme.indicatorWeight,
        child: DecoratedBox(decoration: decoration),
      ),
      TabBarSide.right => Positioned(
        top: insets.top,
        bottom: insets.bottom,
        left: insets.left,
        width: theme.indicatorWeight,
        child: DecoratedBox(decoration: decoration),
      ),
    };

    return Stack(fit: StackFit.passthrough, children: [child, positioned]);
  }

  Color _indicatorColor(BuildContext context) {
    final theme = PlatTheme.of(context).tabBar;
    return theme.indicatorColor ??
        TabBarTheme.of(context).indicatorColor ??
        Theme.of(context).colorScheme.primary;
  }
}
