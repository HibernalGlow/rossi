// 弹出面板：**一条弹层，两种出场方式**。
//
// # 尺寸：一律原样，绝不铺满
//
// 弹层**永远**是内容自己那份大小（[`PopupPanel`] 的卡片档，宽度 280..420），
// 不因为屏幕窄、也不因为「这是确认类」就铺满整屏。改造前全仓的弹层都是
// `AlertDialog`（卡片档的上下限与它同一档），所以换过来不会有尺寸跳变。
//
// # 出场方式：两种
//
// - [`PopupPresentation.relative`]：从触发处飞出的托盘卡片（`CommonPopupRoute`
//   那份 FlClash 动画 —— 托盘沿弧线长成卡片、内容由糊变清）。筛选 / 表单
//   这类「随手用一下」的轻面板走它，省掉一次「先找到它从哪儿冒出来」的眼动。
// - [`PopupPresentation.modal`]：全屏遮罩 + 居中卡片，也就是改造前
//   `showDialog` 的样子。警告 / 删除这类「要先看清再决定」的弹层走它 ——
//   分量重的动作不该长得像一次随手点击。
//
// 走哪一条由 [`resolvePopupRelative`] 定，纯函数：**声明为 modal 的**、
// 以及**窄屏上的**一律走 modal（移动端不改），其余相对弹出。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/navigation/navigation_layout.dart';

/// 弹层怎么出场。
enum PopupPresentation {
  /// 从触发处飞出的托盘卡片。轻面板（筛选 / 表单）的常态。
  relative,

  /// 全屏遮罩 + 居中卡片。警告 / 删除 / 确认类用它。
  modal,
}

/// 这一次弹层走不走「相对弹出」。
///
/// 抽成纯函数：判据直接断言真值表，不必起 app（本仓判据一律这么写）。
bool resolvePopupRelative({
  required PopupPresentation presentation,
  required double width,
}) {
  if (presentation == PopupPresentation.modal) {
    return false;
  }
  // 窄屏保持改造前的「全屏遮罩 + 居中」：移动端不必为轻面板学一套新的
  // 出场方式。阈值与导航栏的窄屏口径同源（`kDefaultNarrowNavigationWidth`）
  // —— 「窄屏 = 走移动端导航」与「窄屏 = 弹层照旧居中」是同一件判断的两面。
  return width >= kDefaultNarrowNavigationWidth;
}

/// 最近一次指针落点。
///
/// 托盘要有个「从哪儿长出来」的原点，而**没有触发钮**的调用点（右键菜单项、
/// 长按、服务层弹的确认框）手边一个矩形也没有 —— 那时退回这里。
///
/// 由 `main.dart` 根部那层 `Listener` 记录（与右键返回同一处），
/// 只在 `showPopupPanel` 没拿到 `anchorOf` 时被读到。有触发钮的地方一律
/// 用触发钮自己的矩形 —— 那一条还会把按钮拍成快照随托盘飞（`CommonPopupBox`），
/// 效果比这一点更完整。
abstract final class PopupPointerOrigin {
  static Offset? _last;

  /// 全局坐标。调用方要按当时的 Navigator 换算到局部（见 `_pointerAnchor`）。
  static Offset? get last => _last;

  static void record(Offset position) => _last = position;
}

/// 弹出一条面板。
///
/// 与 [`CommonPopupBox`] 的分工：那一条锚在**我们自己的触发钮**上（按钮会被
/// 拍成快照随托盘飞，观感最完整）；这一条给「触发处不由我们画」的调用点用
/// —— 菜单项、长按、服务层。两者最终都推 [`CommonPopupRoute`]，动画同一份。
///
/// 返回值是这条路由此刻正在弹的那一层被关掉时的结果（`Navigator.pop` 带出来的
/// 那个值），所以「选完再落账」的调用点 await 它即可。
/// **默认 [`PopupPresentation.modal`]**（= 改造前 `showDialog` 的样子）。
/// 「相对弹出」是一次主动选择：只有筛选 / 选择 / 输入这一层随手用一下的轻面板
/// 才该飞出来；警告、删除、进度、须知这些按默认走，就还是原来那张居中的脸。
Future<T?> showPopupPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  PopupPresentation presentation = PopupPresentation.modal,
  PopupAnchorResolver? anchorOf,
}) {
  if (!resolvePopupRelative(
    presentation: presentation,
    width: MediaQuery.sizeOf(context).width,
  )) {
    // 改造前 `showDialog` 的样子：全屏遮罩 + 居中卡片。
    //
    // 内边距用 MD3 对话框那一档（水平 40 / 垂直 24），所以内容的换行位置
    // 与旧弹层一致 —— 「原本是什么大小就什么大小」这条要求落在这一行上。
    return showDialog<T>(
      context: context,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (routeContext) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Center(child: builder(routeContext)),
      ),
    );
  }

  // 有触发钮的调用点把矩形传进来（卡片会贴它的右边、从它那儿长出来）。
  // 没有的就退回指针落点，「点了哪儿就从哪儿长」总比「从屏幕正中长」像话。
  final byTrigger = anchorOf != null;
  final anchor = anchorOf ?? _pointerAnchor(context);
  return Navigator.of(context).push(
    CommonPopupRoute<T>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      anchorOf: () => anchor(),
      placement: byTrigger
          ? PopupPlacement.overAnchorEnd
          : PopupPlacement.belowPoint,
      builder: builder,
    ),
  );
}

/// 没有触发钮时的兜底锚点：最近一次指针落点（换算到 Navigator 局部坐标）。
///
/// 一次都没记到（键盘触发的弹层、测试里直接 pump）就退回屏幕中心 ——
/// 那是唯一不需要任何上下文就成立的「用户大概在看的地方」。
Rect Function() _pointerAnchor(BuildContext context) {
  final position = PopupPointerOrigin.last;
  final size = MediaQuery.sizeOf(context);
  if (position == null) {
    return () =>
        Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
  }
  final renderObject = Navigator.maybeOf(context)?.context.findRenderObject();
  return () {
    final local = renderObject is RenderBox && renderObject.attached
        ? renderObject.globalToLocal(position)
        : position;
    return local & Size.zero;
  };
}

/// 面板本体：标题 / 内容 / 动作三槽。
///
/// 只有**一种样子** —— 卡片。出场方式（相对弹出还是全屏遮罩居中）由
/// 推出它的那条路决定，这里不掺和。
///
/// 参数刻意与 `AlertDialog` 对齐（`title` / `content` / `actions` /
/// `actionsAlignment` / `scrollable`）：全仓那几十处「选完 取消/应用」的弹层
/// 因此是一次**改名**（`AlertDialog` → `PopupPanel`、`showDialog` →
/// `showPopupPanel`）就能换过来，不必逐处重排内容。
class PopupPanel extends StatelessWidget {
  const PopupPanel({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment = MainAxisAlignment.end,
    this.scrollable = false,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// 动作条的对齐。与 `AlertDialog.actionsAlignment` 同义。
  final MainAxisAlignment actionsAlignment;

  /// 内容超高时可滚。与 `AlertDialog.scrollable` 同义（内容自己已经是
  /// 滚动视图时不用它）。
  final bool scrollable;

  /// 卡片形态的宽度档。
  ///
  /// 上限 420 与改造前的 `AlertDialog`（`SizedBox(width: 420)`）同一档，
  /// 所以从旧弹层换过来时内容的换行位置不会跳。下限 280 是 MD3 对话框的
  /// 最小宽 —— 一排短按钮的确认框不至于缩成一条。
  static const double cardMaxWidth = 420;
  static const double cardMinWidth = 280;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = this.content;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: cardMinWidth,
        maxWidth: cardMaxWidth,
      ),
      child: CommonPopupSurface(
        // 表面是 `CommonPopupSurface` 管的（底色 / 圆角 / 阴影与托盘同源），
        // 这里只定**内容**与卡片边之间的那圈留白。
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              DefaultTextStyle.merge(
                style: theme.textTheme.titleMedium,
                child: title!,
              ),
              const SizedBox(height: 12),
            ],
            if (content != null)
              Flexible(
                child: scrollable
                    ? SingleChildScrollView(child: content)
                    : content,
              ),
            if (actions != null) ...[
              const SizedBox(height: 12),
              _actions(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 动作条。
  ///
  /// 用 [OverflowBar] 而不是 `Row`：这正是 `AlertDialog` 的取法 —— 一排按钮
  /// 放不下时**折成一列**，而不是溢出。窄屏 + 长标签（「导出后删除原下载」那类）
  /// 在 `Row` 上会直接画黄黑斜纹，那是改造前不存在的问题。
  Widget _actions(BuildContext context) {
    return OverflowBar(
      alignment: actionsAlignment,
      spacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      children: actions!,
    );
  }
}
