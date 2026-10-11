import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';

/// 页签的业务内容。选中背景、手势和滚动由 [PanelSwitcherTabs] 统一处理。
class PanelSwitcherItem {
  const PanelSwitcherItem({
    required this.label,
    this.child,
    this.tooltip,
    this.onSecondaryTap,
  });

  final String label;
  final Widget? child;
  final String? tooltip;
  final VoidCallback? onSecondaryTap;
}

enum PanelSwitcherAppearance { labels, icons }

/// 书架与泳道共用的面板切换条。
///
/// 文字和图标只改变尺寸、颜色与圆角；两种外观共用滚动、点击、拖动及弹簧动画。
class PanelSwitcherTabs extends StatelessWidget {
  const PanelSwitcherTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.appearance = PanelSwitcherAppearance.labels,
    this.axis = Axis.horizontal,
    this.iconExtent = defaultIconExtent,
  });

  static const double iconSize = 28;
  static const double iconPadding = 1.5;
  static const double defaultIconExtent = iconSize + iconPadding * 2;

  final List<PanelSwitcherItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final PanelSwitcherAppearance appearance;
  final Axis axis;
  final double iconExtent;

  static const _labelPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 6,
  );

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final textTabs = appearance == PanelSwitcherAppearance.labels;
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(Theme.of(context).textTheme.titleSmall);
    final sizes = [
      for (final item in items)
        if (textTabs) _labelExtent(context, item.label, style) else iconExtent,
    ];
    final bar = SpringLensBar(
      tabs: [
        for (var i = 0; i < items.length; i++)
          SpringLensTab(
            semanticLabel: items[i].label,
            tooltip: items[i].tooltip,
            child: GestureDetector(
              onSecondaryTap: items[i].onSecondaryTap,
              child:
                  items[i].child ??
                  Padding(
                    padding: _labelPadding,
                    child: Text(
                      items[i].label,
                      style: style.copyWith(
                        fontWeight: i == selectedIndex
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: i == selectedIndex
                            ? colors.onSurface
                            : colors.onSurface.withValues(alpha: .6),
                      ),
                    ),
                  ),
            ),
          ),
      ],
      axis: axis,
      tabSizes: sizes,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      draggable: true,
      lensCorner: textTabs
          ? ControlShape.labelCorner
          : ControlShape.compactCorner,
      lensColor: textTabs ? colors.surface : colors.primary,
      tintColor: textTabs ? null : colors.onPrimary,
      lensShadow: textTabs
          ? Shadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            )
          : null,
    );
    final scroller = SingleChildScrollView(scrollDirection: axis, child: bar);
    if (!textTabs) return scroller;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(ControlShape.trackCorner),
      ),
      padding: const EdgeInsets.all(4),
      child: scroller,
    );
  }

  double _labelExtent(BuildContext context, String label, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(fontWeight: FontWeight.bold),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final extent = axis == Axis.horizontal ? painter.width : painter.height;
    painter.dispose();
    return extent +
        (axis == Axis.horizontal
            ? _labelPadding.horizontal
            : _labelPadding.vertical);
  }
}
