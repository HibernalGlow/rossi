import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 给 plat 的一条标签套上「右键 / 长按 → 在上/下/左/右再开一条 + 关闭」。
///
/// # 为什么算通用件
///
/// 里面**没有一行**认识「发现页」「插件」这些概念：它只拿
/// ① 一个 [PlatController]、② 一条标签的 id、③ 一个「怎么造同内容的新标签」的回调、
/// ④ 一个「关掉这条」的回调。别处（书架、工具、以后任何标签面）要同样的右键分屏，
/// 直接套这一层即可。
///
/// # 语义：复制，不是移动
///
/// 「在右侧打开」= 同一条页面在两个窗格里各有一份（各自可读、互不影响滚动位置），
/// 与 dockview / VS Code 的 Split Right 同义，也正是 plat `insertTabBeside` 的原生语义。
/// 想把标签**挪**过去，拖它就行（plat 的轨内拖拽本来就通）。
///
/// # 摆不下就不给点
///
/// 分屏会把这一格切成两半，于是每一半都可能窄到让**标签内容**布局溢出。那类溢出异常
/// 发生在设备更新相里会跳过 `MouseTracker` 的复位标志，表现是「每帧刷
/// `!_debugDuringDeviceUpdate` 直到卡死」—— 本应用已经为它付过一次学费。
/// 所以这里按 [paneSize] 与 [minPaneWidth] / [minPaneHeight] 把摆不下的方向**置灰**，
/// 而不是让用户点出一个必炸的布局。
class RossiPlatTabMenuRegion extends StatelessWidget {
  const RossiPlatTabMenuRegion({
    super.key,
    required this.controller,
    required this.tabId,
    required this.duplicateTab,
    required this.child,
    this.onClose,
    this.duplicable = true,
    this.paneSize,
    this.minPaneWidth = rossiPlatMinPaneWidth,
    this.minPaneHeight = rossiPlatMinPaneHeight,
  });

  final PlatController controller;

  /// 这条标签的 id（菜单所有动作的目标）。
  final String tabId;

  /// 造一条与当前标签**同内容**的新标签（新 id，标题自己带序号）。
  ///
  /// 只在用户真的点了某个方向时才调 —— 它通常会分配一个新 id，
  /// 拿来当「能不能分屏」的判断会把序号烧掉一串。
  final PlatTab? Function() duplicateTab;

  /// 这一条能不能复制（宿主按 locked 之类给）。false ⇒ 四个方向全部置灰。
  final bool duplicable;

  /// 关掉这条标签；`null` = 菜单里不给「关闭」那一项。
  final VoidCallback? onClose;

  /// 这一格现在多大。`null` = 不知道（不做置灰判断，四个方向都给）。
  final Size? paneSize;

  /// 切一半之后单侧的最小可用宽高。
  final double minPaneWidth;
  final double minPaneHeight;

  final Widget child;

  /// 单侧最小可用宽：与发现页量出来的内容硬下限同一条数（见
  /// `DiscoverPlatView.contentMinWidth`）。
  static const double rossiPlatMinPaneWidth = 280;

  /// 单侧最小可用高：标签内容那一页自带 AppBar + 一行操作，再矮就没意义了。
  static const double rossiPlatMinPaneHeight = 200;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      // 桌面右键 + 触摸长按，两个都挂、不按平台分叉：
      // 分叉会在「带触摸屏的桌面」上错（平台说是桌面，用户却在长按）。
      onSecondaryTapUp: (details) => _open(context, details.globalPosition),
      onLongPressStart: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }

  /// 往这一侧切一半之后，两边还都摆得下吗。
  bool _fits(PlatSide side) {
    if (!duplicable) return false;
    final size = paneSize;
    if (size == null) return true;
    return switch (side) {
      PlatSide.left || PlatSide.right => size.width / 2 >= minPaneWidth,
      PlatSide.top || PlatSide.bottom => size.height / 2 >= minPaneHeight,
    };
  }

  Future<void> _open(BuildContext context, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final close = onClose;
    final entries = <PopupMenuEntry<_RossiPlatMenuChoice>>[
      for (final entry in rossiPlatSplitSides.entries)
        PopupMenuItem(
          value: _RossiPlatMenuChoice.split(entry.value),
          enabled: _fits(entry.value),
          child: Text(rossiPlatMenuLabel(entry.key)),
        ),
      if (close != null) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: const _RossiPlatMenuChoice.close(),
          child: Text(t.plat.closeTab),
        ),
      ],
    ];

    final choice = await showMenu<_RossiPlatMenuChoice>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: entries,
    );
    if (choice == null || !context.mounted) return;

    final side = choice.side;
    if (side != null) {
      final tab = duplicateTab();
      if (tab == null) return;
      // 分屏的目标是**装这条标签的那个组**，不是标签自己：
      // plat 的 `split` 拿 leaf id 会返回 true 却什么也不改（实测树仍是
      // TabGroupSnapshot），只有喂组 id 才真的切出第二个窗格。
      controller.insertTabBeside(
        targetId: controller.tabGroupContaining(tabId) ?? tabId,
        side: side,
        tab: tab,
      );
      return;
    }
    close?.call();
  }
}

/// 菜单里被选中的那一项：要么「分屏到某侧」，要么「关闭」。
@immutable
class _RossiPlatMenuChoice {
  const _RossiPlatMenuChoice.split(PlatSide this.side) : isClose = false;

  const _RossiPlatMenuChoice.close() : side = null, isClose = true;

  final PlatSide? side;
  final bool isClose;
}

/// 四个方向的菜单项，顺序即菜单顺序（上 / 下 / 左 / 右）。
///
/// 只在这里定义一遍：判据与置灰判断都读这一份，免得菜单和判断各数各的。
const Map<RossiPlatMenuLabel, PlatSide> rossiPlatSplitSides =
    <RossiPlatMenuLabel, PlatSide>{
      RossiPlatMenuLabel.above: PlatSide.top,
      RossiPlatMenuLabel.below: PlatSide.bottom,
      RossiPlatMenuLabel.leftOf: PlatSide.left,
      RossiPlatMenuLabel.rightOf: PlatSide.right,
    };

/// 菜单四项的名字。**只有四个方向**，不含 plat 的枚举值本身 ——
/// 方向是给 plat 用的，名字是给人看的，两件事不该混在一个枚举里。
enum RossiPlatMenuLabel { above, below, leftOf, rightOf }

/// 菜单标题走 i18n（枚举是 const，拿不到 `t`，所以做成函数）。
String rossiPlatMenuLabel(RossiPlatMenuLabel label) => switch (label) {
  RossiPlatMenuLabel.above => t.plat.openAbove,
  RossiPlatMenuLabel.below => t.plat.openBelow,
  RossiPlatMenuLabel.leftOf => t.plat.openLeft,
  RossiPlatMenuLabel.rightOf => t.plat.openRight,
};
