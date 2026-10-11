import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';

/// 标签保持在原位；输入区域向下展开，搜索入口就地切换为关闭入口。
class ShelfSearchHeader extends StatelessWidget {
  const ShelfSearchHeader({
    super.key,
    required this.expanded,
    required this.tabs,
    required this.filter,
    this.searchField,
    required this.onExpand,
    required this.onClose,
  });

  final bool expanded;
  final Widget tabs;
  final Widget filter;
  final Widget? searchField;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tabs,
            ),
          ),
          const SizedBox(width: 8),
          ExpressiveIconButton(
            glyph: AppGlyphs.search,
            activeGlyph: AppGlyphs.close,
            active: expanded,
            activeTurns: .25,
            tooltip: expanded ? t.common.close : t.common.search,
            onPressed: expanded ? onClose : onExpand,
          ),
          const SizedBox(width: 4),
          filter,
        ],
      ),
      if (searchField != null)
        ShelfSearchRegion(expanded: expanded, child: searchField!),
    ],
  );
}

/// 在工具栏下方按内容高度展开；可放在正文顶部，避开 AppBar 固定高度约束。
class ShelfSearchRegion extends StatelessWidget {
  const ShelfSearchRegion({
    super.key,
    required this.expanded,
    required this.child,
    this.padding = const EdgeInsets.only(top: 12),
  });

  final bool expanded;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !expanded,
    child: IgnorePointer(
      ignoring: !expanded,
      child: ExpressiveReveal(
        visible: expanded,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
