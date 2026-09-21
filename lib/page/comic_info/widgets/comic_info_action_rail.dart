import 'package:flutter/material.dart';

import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';

/// 详情页的**纵向悬浮胶囊**（桌面）。移动端那条底部条见车道 G。
///
/// 为什么要有这个东西：返回只能点左上角、开始阅读只能点特定那一颗，鼠标在宽窗口上要走
/// 一整条对角线（`docs/comic-info-action-rail.md` §1）。
///
/// 为什么是**悬浮**而不是占一列：第一版把它做成 `Row` 里的一条 52px 列，实机截图（2026-09-21）
/// 里它把漫画正文挤窄了 104px，而那一列除了顶上两颗之外整截是空的 —— 用户口径是
/// 「不能挤占漫画显示空间」。所以它浮在正文之上（外层 `Stack` + `Positioned`），
/// 胶囊按内容多高就多高，垂直居中贴在左右边缘。
///
/// 造型跟着阅读器顶栏那套已有的悬浮语言（`reader_toolbar_shell.dart`）：
/// `surfaceContainerHigh` 底 + `outlineVariant` 描边 + stadium 圆角 +
/// `secondaryContainer` 选中态。用 [Material] 承底而不是自己画 `BoxDecoration`，
/// 是为了让 `IconButton` 的水波纹落在这颗胶囊上、而不是落在它背后的页面上。
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

  /// 图标按钮的见方边长 —— 与阅读器顶栏同一个口径（MD3 图标按钮 40）。
  static const double buttonSize = 40;

  /// 图标本身 20 而不是缺省 24：压在漫画上，24 会比内容还抢眼。同阅读器顶栏。
  static const double iconSize = 20;

  /// 胶囊内边距。上下各 [paddingV] 与 [buttonSize] 一起决定 stadium 的圆角半径。
  static const double paddingV = 6;
  static const double paddingH = 4;

  /// 与阅读器的 `ReaderToolbarMetrics` 数值一致，但**不 import 它**：那个类是阅读器
  /// chrome 的度量，详情页去依赖它等于把两个界面的改期绑在一起。对齐靠注释，不靠引用。
  static const double gap = 2;

  static double get pillRadius => buttonSize / 2 + paddingV;

  @override
  Widget build(BuildContext context) {
    // 一条都没有就不占位：rail 是加速层，不该为了自己挡正文。
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 条目多到一屏放不下时让胶囊自己滚，而不是把最后几颗裁掉 ——
        // 「看不见」比「放不下」更难发现。
        final maxHeight = (constraints.maxHeight - 24).clamp(
          0.0,
          double.infinity,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            // 描边是 MD3 悬浮面在深色主题下唯一还能看出边界的东西。
            shape: StadiumBorder(
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: paddingV,
                horizontal: paddingH,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, item) in items.indexed) ...[
                    if (index > 0) const SizedBox(height: gap),
                    _PillButton(item: item, scope: scope),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.item, required this.scope});

  final ComicInfoActionEntry item;
  final ComicInfoActionScope scope;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = item.enabled;
    final selected = item.selected;
    // 前景色自己挑，是因为「已收藏/已点赞」这类条目带各自的强调色（金/红），
    // 而选中态的底是统一的 secondaryContainer。
    final foreground = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
        : selected
        ? (item.accentColor ?? colorScheme.onSecondaryContainer)
        : colorScheme.onSurfaceVariant;
    final child = IconButton(
      iconSize: ComicInfoActionRail.iconSize,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: ComicInfoActionRail.buttonSize,
        height: ComicInfoActionRail.buttonSize,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: selected ? colorScheme.secondaryContainer : null,
        shape: const CircleBorder(),
      ),
      // 不可用要**看得见**：置灰而不是藏掉，也不是画一颗点了没反应的。
      onPressed: enabled
          ? () => dispatchComicInfoAction(scope, item.actionId, context)
          : null,
      icon: Icon(item.icon),
    );
    return Tooltip(
      // triggerMode 用默认值：有指针时悬停出提示，触屏上长按出提示。rail 上只有图标，
      // 提示就是它的文字。
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
