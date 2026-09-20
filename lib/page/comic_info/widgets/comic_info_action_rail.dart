import 'package:flutter/material.dart';

import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';

/// 详情页的竖向操作栏（桌面）。移动端那条底部条见 `comic_info_action_bar.dart`（车道 G）。
///
/// 为什么要有这个东西：返回只能点左上角、开始阅读只能点特定那一颗，鼠标在宽窗口上要走
/// 一整条对角线（`docs/comic-info-action-rail.md` §1）。
///
/// 它**不持有状态**：条目由页面现造（[ComicInfoActionScope.comicInfoActionItems]），
/// 与封面下方那横排操作行同源。执行一律走 [dispatchComicInfoAction] —— 这里不出现
/// 「这一条该调哪个方法」的判断，否则派发点就有了第二份。
class ComicInfoActionRail extends StatelessWidget {
  const ComicInfoActionRail({
    super.key,
    required this.scope,
    required this.items,
  });

  final ComicInfoActionScope scope;
  final List<ComicInfoActionEntry> items;

  /// 一列的占宽。图标按钮本身是 [_iconSize] + 四周留白，这里只多不少 —— rail 站在
  /// `_constrainedSliver` 那 1120 之外的余量里，宽窗口下不吃正文宽度。
  static const double width = 52;

  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 一条都没有就不占位：rail 是加速层，不该为了自己把正文挤窄。
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: width,
      child: SafeArea(
        child: SingleChildScrollView(
          // 顶栏下面、滚到内容底部之前都点得到；条目多到一屏放不下时能滚，
          // 而不是把最后几颗裁掉（那是「看不见」，比「放不下」更难发现）。
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              for (final item in items)
                _RailButton(
                  item: item,
                  scope: scope,
                  iconColor: item.selected
                      ? (item.accentColor ?? theme.colorScheme.primary)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.scope, this.iconColor});

  final ComicInfoActionEntry item;
  final ComicInfoActionScope scope;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = item.enabled && item.onTap != null;
    final child = IconButton(
      // 与阅读器顶栏那条口径一致：整列同尺寸，rail 才看得出是一组。
      iconSize: ComicInfoActionRail._iconSize,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: item.selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
      ),
      onPressed: enabled
          ? () => dispatchComicInfoAction(scope, item.actionId, context)
          // 不可用要**看得见**：置灰而不是藏掉，也不是画一颗点了没反应的。
          : null,
      icon: Icon(item.icon, color: enabled ? iconColor : null),
    );
    return Tooltip(
      // triggerMode 用默认值：有指针时悬停出提示，触屏上长按出提示。写死 manual
      // 等于「提示永远不出现」，而 rail 上只有图标，提示就是它的文字。
      message: item.tooltip ?? item.label,
      child: item.onLongPress == null
          ? child
          : GestureDetector(
              // 下载那颗的「长按挑章节」在 rail 上要保得住（口径 5：行为不变）。
              onLongPress: enabled ? item.onLongPress : null,
              child: child,
            ),
    );
  }
}
