import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';

export 'package:zephyr/widgets/expressive/expressive_shape.dart'
    show ExpressiveButtonShape;

/// 顶栏二级面板的名单。
///
/// neoview 的 `ExpandedPanel` 有六档（sort / zoom / rotate / hover-scroll /
/// slideshow / magnifier）。顺序照那边排，**做出来一档就点亮一档**，
/// 没做出来的那几颗仍然住在主行末尾的「更多」菜单里（见 `app_bar.dart` 的
/// `_buildOverflowItems`），点它们会给一句话，不静默失效。
enum ReaderToolbarPanel { sort, zoom, rotate, layout, slideshow, magnifier }

/// 主行「视图」那一组里真的摆出来的几颗。
///
/// 六颗全摆会把这条 48 高度带顶到第二行去（`Wrap` 把整组推下去，实测中心线偏 54，
/// 钉这条不列的 `reader_top_bar_layout_test` 就是这么红的）。
/// 其余三颗不住主行，但**不是没有入口**：主行末尾「更多」里每颗都带文字同名项
/// （见 `app_bar.dart` 里 `for (final panel in ReaderToolbarPanel.values)`），
/// 与主行那颗共用同一个 `_togglePanel` 入口，所以点下去是同一件事。
const List<ReaderToolbarPanel> kReaderPrimaryToolbarPanels = [
  ReaderToolbarPanel.zoom,
  ReaderToolbarPanel.rotate,
  ReaderToolbarPanel.layout,
];

/// 顶栏的度量档：**画图与排布判断读同一份常数**。
///
/// 为什么要有这么一类东西：改造前每一颗控件各自写死自己的边长（30 圆钮 /
/// 40 方钮 / 36 自绘框）与各自的 4~12px 间距，视觉上就是「一坨挤在一起的图标」。
/// 尺寸与间距收进一处之后，主行的宽度预算才算得清。
abstract final class ReaderToolbarMetrics {
  /// 主行高度（含上下内边距由外层给）。
  static const double rowHeight = 56;

  /// 图标按钮的见方边长 —— MD3 图标按钮的规范尺寸。
  static const double buttonSize = 48;

  /// 图标本身的边长。MD3 的图标按钮缺省是 24，但顶栏压在漫画上、一行要塞
  /// 十几颗控件，24 会把整条拉得比内容还抢眼，所以统一按 20 走。
  static const double iconSize = 20;

  /// 同一组之内的间距。
  static const double gapWithinGroup = 4;

  /// 相邻两组之间的间距（不放分隔线时用）。
  static const double gapBetweenGroups = 12;

  /// 组间竖分隔线：线宽 1、长 20、左右各 6 的呼吸。
  static const double separatorThickness = 1;
  static const double separatorHeight = 20;
  static const double separatorMargin = 6;

  /// 胶囊容器（一组紧贴合的控件）的内边距。
  ///
  /// **0**：容器与里面的圆钮同高（40），整条主行才是**一个 40 的高度带**。
  /// 留 2 会让胶囊变成 44、芯片 32、按钮 40 —— 三种高度并排就是「错位」。
  static const double pillPadding = 0;

  /// 芯片（带文字的开关）与状态芯片的高度：与 [buttonSize] 同档。
  static const double chipHeight = 48;

  /// 顶栏自身的圆角：贴边浮层组件的造型，**不走主题圆角**
  /// （见 `lib/config/global/theme_shape.dart` 里那条「组件自身造型不该被主题拉走」）。
  static const double barRadius = 28;

  /// 全圆角（胶囊 / 圆钮）。
  static const double fullRadius = 999;
}

/// 一组紧密贴合的图标按钮/控件（外壳 = MD3 的容器色，不描边）。
class ReaderToolbarGroup extends StatelessWidget {
  final List<Widget> children;

  const ReaderToolbarGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, child) in children.indexed)
          if (index == 0)
            child
          else if (children[index - 1] is ReaderToolbarOptionalSlot)
            // 上一颗自己带了间距（而且只在真的画出来时带），这里再加就成两份。
            child
          else ...[
            const SizedBox(width: ReaderToolbarMetrics.gapWithinGroup),
            child,
          ],
      ],
    );
  }
}

/// 条件可见控件的槽位：**内容不画，间距跟着一起不占**。
///
/// 顶栏增强那三颗芯片各自在自己的 `ListenableBuilder` 里判画不画（父层判不了：
/// 父层要判就得订阅译文/呈现器状态，整条顶栏会跟着翻页重建）。用固定的组内
/// 间距时，隐藏那颗仍然留下 4 —— 于是同一条图标带上出现两种间距，症状就是
/// 「某一处比别处宽」。这里把间距挂在**子节点量出来的实际宽度**上：宽 0 则整槽 0。
class ReaderToolbarOptionalSlot extends SingleChildRenderObjectWidget {
  const ReaderToolbarOptionalSlot({
    super.key,
    required this.gap,
    required super.child,
  });

  /// 内容可见时补在**右侧**的间距。放右侧是因为隐藏的那颗可能正好是组里最后一颗
  /// 有内容的控件之外的位置，而组的左边缘不该被一颗可见性未知的控件推走。
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderToolbarOptionalSlot(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    // `RenderProxyBox` 而不是那个私有子类：`library_private_types_in_public_api`
    // 不许把私有的东西摆进公开签名里，而协变收窄本身要的就是这个父类型。
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _RenderToolbarOptionalSlot).gap = gap;
  }
}

class _RenderToolbarOptionalSlot extends RenderProxyBox {
  _RenderToolbarOptionalSlot(this._gap);

  double _gap;

  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  Size _slotSize(Size childSize) => childSize.width == 0
      ? Size.zero
      : Size(childSize.width + _gap, childSize.height);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(_slotSize(child.size));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _slotSize(child?.getDryLayout(constraints) ?? Size.zero);
}

/// 一组紧密贴合的按钮/控件的外壳（带一层容器底色）。
class ReaderToolbarPill extends StatelessWidget {
  final List<Widget> children;

  /// 内底色再深一档 —— 面板里滑条那种「容器里的容器」。
  final bool emphasized;

  const ReaderToolbarPill({
    super.key,
    required this.children,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(ReaderToolbarMetrics.pillPadding),
      decoration: BoxDecoration(
        // MD3 的容器角色本就是给「一层叠一层」用的，直接取实色，
        // 不再 `withValues` 自己调一档透明度。
        color: emphasized
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
      ),
      child: ReaderToolbarGroup(children: children),
    );
  }
}

/// 组间竖分隔线（MD3 divider：`outlineVariant`，实色不透明）。
class ReaderToolbarSeparator extends StatelessWidget {
  const ReaderToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ReaderToolbarMetrics.separatorThickness,
      height: ReaderToolbarMetrics.separatorHeight,
      margin: const EdgeInsets.symmetric(
        horizontal: ReaderToolbarMetrics.separatorMargin,
      ),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// 组前的小标签（MD3 `labelSmall`，次要色）。
class ReaderToolbarLabel extends StatelessWidget {
  final String text;

  const ReaderToolbarLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 顶栏/面板里的一颗图标按钮，统一走 MD3 `IconButton` 的状态层。
///
/// 三种态各用一处角色，不自己叠透明度：
/// - 常态：`onSurfaceVariant` 图标 + 无底
/// - 按下（选中 / 展开 / 开关开着）：`secondaryContainer` 底 + `onSecondaryContainer`
/// - 禁用：`onSurfaceVariant` 38%（MD3 的禁用档就是这个数）
///
/// 悬停/按压的水波纹由 `IconButton` 按角色自己算，之前手写 `InkWell` 时
/// 这层是没有的。
class ReaderToolbarIconButton extends StatelessWidget {
  final Glyph icon;
  final String tooltip;
  final bool selected;
  final bool enabled;

  /// null = 只按下不响应（配合 [enabled] 用于置灰态）。
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// null = 按 [selected] 那两档配色。状态芯片（下载失败要红、暂停要三级色）
  /// 需要自己指定图标颜色时才传，且**只传角色色**。
  final Color? tint;
  final ExpressiveButtonShape? expressiveShape;

  const ReaderToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.onLongPress,
    this.tint,
    this.expressiveShape,
  });

  @override
  Widget build(BuildContext context) {
    if (expressiveShape != null) {
      return ActionBubbleTarget(
        enabled: enabled && onPressed != null,
        child: GestureDetector(
          onLongPress: enabled ? onLongPress : null,
          child: ExpressiveIconButton(
            glyph: icon,
            tooltip: tooltip,
            onPressed: enabled ? onPressed : null,
            active: selected,
            activeTurns: 0,
            size: ReaderToolbarMetrics.buttonSize,
            shape: expressiveShape!,
          ),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final fg =
        tint ??
        (selected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant);
    final bg = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHigh;

    return ActionBubbleTarget(
      enabled: enabled && onPressed != null,
      child: ElasticButton(
        enabled:
            enabled &&
            onPressed != null &&
            !MediaQuery.disableAnimationsOf(context),
        child: GestureDetector(
          onLongPress: enabled ? onLongPress : null,
          child: IconButton(
            isSelected: selected,
            tooltip: tooltip,
            onPressed: enabled ? onPressed : null,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(ReaderToolbarMetrics.buttonSize),
              minimumSize: const Size.square(ReaderToolbarMetrics.buttonSize),
              padding: EdgeInsets.zero,
              backgroundColor: bg,
              foregroundColor: fg,
              disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
                alpha: .38,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(selected ? 16 : 24),
              ),
            ).merge(ElasticPress.buttonStyle),
            icon: AnimatedGlyph(glyph: icon, filled: selected),
          ),
        ),
      ),
    );
  }
}

/// neo 主行上有、本仓还没有对应能力的那几颗占位按钮。
class ReaderToolbarComingSoonButton extends StatelessWidget {
  final Glyph icon;
  final String name;

  const ReaderToolbarComingSoonButton({
    super.key,
    required this.icon,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return ReaderToolbarIconButton(
      icon: icon,
      tooltip: '$name（本仓尚未实现）',
      onPressed: () => showReaderToolbarComingSoon(context, name),
    );
  }
}

/// 一颗「图标 +（可选）文字」的开关芯片：MD3 filter chip 的那套配色。
///
/// 开 = `secondaryContainer` 实色底；关 = 只描一条 `outline`。
/// 两态只差**一处**（底色 vs 描边），不要既填主色又描主色。
class ReaderToolbarToggleChip extends StatelessWidget {
  final Glyph icon;
  final String tooltip;

  /// null 或空串 = 只画图标（窄档把文字收成图标）。
  final String? label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ReaderToolbarToggleChip({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.selected = false,
    this.enabled = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasLabel = label != null && label!.isNotEmpty;

    final fg = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
        : selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final border = !enabled
        ? colorScheme.outlineVariant
        : selected
        ? Colors.transparent
        : colorScheme.outline;

    return Tooltip(
      message: tooltip,
      child: ActionBubbleTarget(
        enabled: enabled,
        corner: 24,
        child: ElasticButton(
          enabled: enabled,
          child: InkWell(
            onTap: enabled ? onTap : null,
            onLongPress: enabled ? onLongPress : null,
            borderRadius: BorderRadius.circular(
              ReaderToolbarMetrics.fullRadius,
            ),
            customBorder: const StadiumBorder(),
            // 约束两态必须**同一形状**：写 `width: hasLabel ? null : 40` 会从
            // `maxWidth: Infinity` 插值到一个有限值，AnimatedContainer 直接抛
            // 「Cannot interpolate between finite and unbounded constraints」——
            // 窗口拖过标签阈值那一下顶栏整条停止布局。所以宽度只给下限，
            // 让内容自己撑：图标态落在 40，带字态按文字走。
            child: AnimatedContainer(
              duration: ExpressiveMotion.duration(
                context,
                ExpressiveMotion.effectDuration,
              ),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(
                minWidth: ReaderToolbarMetrics.buttonSize,
                minHeight: ReaderToolbarMetrics.chipHeight,
                maxHeight: ReaderToolbarMetrics.chipHeight,
              ),
              padding: EdgeInsets.symmetric(horizontal: hasLabel ? 12 : 0),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(
                  ReaderToolbarMetrics.fullRadius,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    icon,
                    size: ReaderToolbarMetrics.iconSize,
                    color: fg,
                  ),
                  if (hasLabel) ...[
                    const SizedBox(width: 6),
                    Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(color: fg),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「本仓还没接进阅读器」的那几颗共用的提示。
///
/// 保留占位是**刻意的**：顶栏的形状与 neo 对齐，将来做出一块就点亮一块。
/// 但它不能是静默失效的一颗 —— 点了要给一句话，否则人只会以为是自己点歪了。
void showReaderToolbarComingSoon(BuildContext context, String name) {
  showInfoToast(
    '$name 还没接进本仓的阅读器',
    duration: const Duration(milliseconds: 1800),
    context: context,
  );
}

/// 二级工具栏与展开面板采用居中的紧凑停靠容器，窄屏自动换行。
class ReaderToolbarPanelRow extends StatelessWidget {
  final List<Widget> children;
  final bool floating;

  const ReaderToolbarPanelRow({
    super.key,
    required this.children,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, floating ? 10 : 6, 8, 0),
      child: Center(
        child: Material(
          color: floating
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: floating ? 3 : 0,
          borderRadius: BorderRadius.circular(28),
          child: ActionBubbleRegion(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 4,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
