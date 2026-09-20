import 'package:material_ui/material_ui.dart';

/// 顶栏二级面板的名单。
///
/// neoview 的 `ExpandedPanel` 有六档（sort / zoom / rotate / hover-scroll /
/// slideshow / magnifier），本仓目前只有真做得起来的这三档 —— **刻意不给
/// 做不出来的那几档留主行占位按钮**：那五颗现在住在主行末尾的「更多」菜单里
/// （见 `app_bar.dart` 的 `_buildOverflowItems`），点它们仍然会给一句话，
/// 不静默失效。哪一块接进了本仓，就从菜单里搬回主行对应的那一组。
enum ReaderToolbarPanel { zoom, rotate, layout }

/// 顶栏的度量档：**画图与排布判断读同一份常数**。
///
/// 为什么要有这么一类东西：改造前每一颗控件各自写死自己的边长（30 圆钮 /
/// 40 方钮 / 36 自绘框）与各自的 4~12px 间距，视觉上就是「一坨挤在一起的图标」。
/// 尺寸与间距收进一处之后，主行的宽度预算才算得清。
abstract final class ReaderToolbarMetrics {
  /// 主行高度（含上下内边距由外层给）。
  static const double rowHeight = 48;

  /// 图标按钮的见方边长 —— MD3 图标按钮的规范尺寸。
  static const double buttonSize = 40;

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
  static const double pillPadding = 2;

  /// 芯片（带文字的开关）高度 —— MD3 chip 的规范档。
  static const double chipHeight = 32;

  /// 芯片里的图标边长（MD3 chip 规范是 18，比主行那颗小一档）。
  static const double chipIconSize = 18;

  /// 顶栏自身的圆角：贴边浮层组件的造型，**不走主题圆角**
  /// （见 `lib/config/global/theme_shape.dart` 里那条「组件自身造型不该被主题拉走」）。
  static const double barRadius = 16;

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
          else ...[
            const SizedBox(width: ReaderToolbarMetrics.gapWithinGroup),
            child,
          ],
      ],
    );
  }
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
  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool enabled;

  /// null = 只按下不响应（配合 [enabled] 用于置灰态）。
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// null = 按 [selected] 那两档配色。状态芯片（下载失败要红、暂停要三级色）
  /// 需要自己指定图标颜色时才传，且**只传角色色**。
  final Color? tint;

  const ReaderToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.onLongPress,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg =
        tint ??
        (selected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant);
    final bg = selected ? colorScheme.secondaryContainer : Colors.transparent;

    return IconButton(
      isSelected: selected,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      onLongPress: enabled ? onLongPress : null,
      iconSize: ReaderToolbarMetrics.iconSize,
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll(
          const Size.square(ReaderToolbarMetrics.buttonSize),
        ),
        minimumSize: WidgetStatePropertyAll(
          const Size.square(ReaderToolbarMetrics.buttonSize),
        ),
        maximumSize: WidgetStatePropertyAll(
          const Size.square(ReaderToolbarMetrics.buttonSize),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        // 见方的可点区缩到画出来的这一圈：顶栏一行要塞十几颗，
        // MD3 的 48 触摸外扩留给正文里的按钮，不留在这条带上。
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(
          CircleBorder(side: BorderSide.none),
        ),
        backgroundColor: WidgetStatePropertyAll(bg),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
          }
          return fg;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return fg.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return fg.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return fg.withValues(alpha: 0.12);
          }
          return Colors.transparent;
        }),
      ),
      icon: Icon(icon),
    );
  }
}

/// neo 主行上有、本仓还没有对应能力的那几颗占位按钮。
class ReaderToolbarComingSoonButton extends StatelessWidget {
  final IconData icon;
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
  final IconData icon;
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
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        customBorder: const StadiumBorder(),
        // 约束两态必须**同一形状**：写 `width: hasLabel ? null : 40` 会从
        // `maxWidth: Infinity` 插值到一个有限值，AnimatedContainer 直接抛
        // 「Cannot interpolate between finite and unbounded constraints」——
        // 窗口拖过标签阈值那一下顶栏整条停止布局。所以宽度只给下限，
        // 让内容自己撑：图标态落在 40，带字态按文字走。
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
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
              Icon(icon, size: ReaderToolbarMetrics.chipIconSize, color: fg),
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
    );
  }
}

/// 「本仓还没接进阅读器」的那几颗共用的提示。
///
/// 保留占位是**刻意的**：顶栏的形状与 neo 对齐，将来做出一块就点亮一块。
/// 但它不能是静默失效的一颗 —— 点了要给一句话，否则人只会以为是自己点歪了。
void showReaderToolbarComingSoon(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$name 还没接进本仓的阅读器'),
      behavior: SnackBarBehavior.floating,
      width: 280,
      duration: const Duration(milliseconds: 1800),
    ),
  );
}

/// 展开区的一行面板（neo 的 `data-reader-toolbar-row="expanded"`：
/// 顶边一条分隔线 + 居中换行排布的控件）。
class ReaderToolbarPanelRow extends StatelessWidget {
  final List<Widget> children;

  const ReaderToolbarPanelRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: ReaderToolbarMetrics.separatorThickness,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // 与 neo 同一处理：窄屏不折叠成溢出菜单，而是**换行摊开**。
      child: Wrap(
        spacing: 2,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
