import 'package:flutter/material.dart';

import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// 详情页的**纵向悬浮胶囊**（桌面）。移动端那条底部条见车道 G。
///
/// 为什么要有这个东西：返回只能点左上角、开始阅读只能点特定那一颗，鼠标在宽窗口上要走
/// 一整条对角线（`docs/comic-info-action-rail.md` §1）。
///
/// 为什么是**悬浮**而不是占一列：第一版把它做成 `Row` 里的一条 52px 列，实机截图（2026-09-21）
/// 里它把漫画正文挤窄了 104px，而那一列除了顶上两颗之外整截是空的 —— 用户口径是
/// 「不能挤占漫画显示空间」。所以它浮在正文之上（见 [ComicInfoActionOverlay]），
/// 胶囊按内容多高就多高，垂直居中贴在左右边缘。
///
/// 造型跟着阅读器顶栏那套已有的悬浮语言（`reader_toolbar_shell.dart`）：
/// `surfaceContainerHigh` 底 + `outlineVariant` 描边 + stadium 圆角 +
/// `secondaryContainer` 选中态。[glass] 打开时换成 [LiquidGlassSurface]（可开关，
/// 与阅读器顶栏、提示条同一套材质），此时本体那层 `Material` 只留着承水波纹、不涂底色
/// —— 否则玻璃被自己那层实底盖掉了。
///
/// 它**不持有状态**：条目由页面现造（[ComicInfoActionScope.comicInfoActionItems]），
/// 与封面下方那横排操作行同源。执行一律走 [dispatchComicInfoAction] —— 这里不出现
/// 「这一条该调哪个方法」的判断，否则派发点就有了第二份。
class ComicInfoActionRail extends StatelessWidget {
  const ComicInfoActionRail({
    super.key,
    required this.scope,
    required this.items,
    this.glass = false,
  });

  final ComicInfoActionScope scope;
  final List<ComicInfoActionEntry> items;

  /// 液态玻璃档（来自设置，可关）。关掉时是 `surfaceContainerHigh` 实底 +  elevation。
  final bool glass;

  /// 图标按钮的见方边长 —— 与阅读器顶栏同一个口径（MD3 图标按钮 40）。
  static const double buttonSize = 40;

  /// 图标本身 20 而不是缺省 24：压在漫画上，24 会比内容还抢眼。同阅读器顶栏。
  static const double iconSize = 20;

  /// 胶囊内边距。上下各 [paddingV] 与 [buttonSize] 一起决定 stadium 的圆角半径。
  static const double paddingV = 6;
  static const double paddingH = 4;

  /// 条目之间的间距。
  static const double gap = 2;

  /// 胶囊的占宽（按钮 40 + 左右内边距 4×2）。
  ///
  /// 描边**不加宽**：`StadiumBorder` 的 `BorderSide` 画在形状内部，不参与布局
  /// （这条是测试当场抓出来的：按 50 算会让外层定宽比胶囊宽 2px）。
  ///
  /// 外层要按这个值给 `Positioned` **定宽**，见 [ComicInfoActionOverlay] 的注释。
  static const double maxWidth = buttonSize + paddingH * 2;

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
        final body = SingleChildScrollView(
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
        );
        // Material 两档都要留着：它是 IconButton 水波纹的宿主。玻璃档涂成透明，
        // 只承墨不填色；实底档才上 surfaceContainerHigh（描边同理，玻璃自带边缘高光）。
        final surface = Material(
          color: glass ? Colors.transparent : colorScheme.surfaceContainerHigh,
          shape: StadiumBorder(
            side: glass
                ? BorderSide.none
                : BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          // 阴影交给 elevation：实底档要能看出浮在内容上；玻璃档的投影由
          // LiquidGlassSurface 自己按材质给，这里再叠一层就糊了。
          elevation: glass ? 0 : 2,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: body,
          ),
        );
        if (!glass) {
          return surface;
        }
        return LiquidGlassSurface(
          // 压在漫画内容上的一小条前景：走 regular 那档（卡片/弹窗档），
          // 不像整屏顶栏那样要 thick —— 它只盖住正文的一小条边。
          thickness: LiquidGlassThickness.regular,
          borderRadius: BorderRadius.circular(pillRadius),
          child: surface,
        );
      },
    );
  }
}

/// 把左右两颗胶囊浮在正文之上，且**不占布局宽度**。
///
/// 为什么单独一个 widget：几何要能被测试钉住。第一版把 `Positioned` 直接写在页面里，
/// 写成 `Positioned(right: 8, child: Center(child: rail))` —— 而**只给 `left`/`right`
/// 之一时子节点拿到的是松约束**，`Align`/`Center` 在没有 `widthFactor` 时又会撑到
/// `constraints.biggest`，于是水平落点根本不是「离边 8px」。实机截图里右边那颗被裁在
/// 窗口外，就是这个原因。
///
/// 定宽之后没有歧义：`Positioned` 的宽就是 [ComicInfoActionRail.maxWidth]，
/// `Align` 在紧约束里只做它该做的那一件事；水平落点由 `left` / `right` 唯一决定。
class ComicInfoActionOverlay extends StatelessWidget {
  const ComicInfoActionOverlay({
    super.key,
    required this.child,
    required this.scope,
    required this.leftItems,
    required this.rightItems,
    this.glass = false,
    this.edgeInset = 8,
  });

  final Widget child;
  final ComicInfoActionScope scope;
  final List<ComicInfoActionEntry> leftItems;
  final List<ComicInfoActionEntry> rightItems;
  final bool glass;

  /// 离屏幕边的留白。
  final double edgeInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        _side(left: true, items: leftItems),
        _side(left: false, items: rightItems),
      ],
    );
  }

  Widget _side({
    required bool left,
    required List<ComicInfoActionEntry> items,
  }) {
    return Positioned(
      left: left ? edgeInset : null,
      right: left ? null : edgeInset,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: ComicInfoActionRail.maxWidth,
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: ComicInfoActionRail(scope: scope, items: items, glass: glass),
        ),
      ),
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
    final enabled = item.enabled && item.onTap != null;
    final selected = item.selected;
    // 前景色自己挑，是因为「已收藏 / 已点赞」这类条目带各自的强调色（金 / 红），
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
