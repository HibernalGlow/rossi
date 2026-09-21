import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 给 plat 的一条标签套上「右键 / 长按 → 换边打开 + 关闭」。
///
/// # 换边是**移动**，不是复制
///
/// 「在右侧打开」= 这条标签离开原来那一格、单独成一格摆在右边，原来那一格少一条。
/// 与 dockview / VS Code 的 Move Editor into … 同义，走的是 plat 的 `moveTabBeside`。
/// 复制一份出来没有意义：两条一样的页面占两格，用户要的是把眼前这条挪个位置。
///
/// # 竖向轨那一档不出新窗格
///
/// plat 的每一个窗格都自带一条自己的标签条。竖轨下那条新标签条会画在**内容中间**
/// （一格变两格，中间凭空多一根轨），而且新组的朝向永远是 `top`，跟全页唯一的轨厚
/// 混在一起就是一根「有轨那么高的横条」。用户 2026-09-21 看过实机后的口径是：
/// 「纵向的时候这个标签页就该直接在标签页区域打开」。
///
/// 所以竖向档这里只有「在上方 / 在下方」，含义是在**轨里**这条的前后各多开一条同
/// 内容的标签（那一步仍然是复制：轨里多一条才是这一档能给的「换个地方看同一页」）。
///
/// # 为什么算通用件
///
/// 里面**没有一行**认识「发现页」「插件」这些概念：它只拿
/// ① 一个 [PlatController]、② 一条标签的 id、③ 一个「怎么造同内容的新标签」的回调、
/// ④ 一个「关掉这条」的回调。朝向、组、序号全从快照上现读，别处（书架、工具、
/// 以后任何标签面）要同样的右键，直接套这一层即可。
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
    this.detachable = true,
    this.paneSize,
    this.minPaneWidth = rossiPlatMinPaneWidth,
    this.minPaneHeight = rossiPlatMinPaneHeight,
  });

  final PlatController controller;

  /// 这条标签的 id（菜单所有动作的目标）。
  final String tabId;

  /// 造一条与当前标签**同内容**的新标签（新 id，标题自己带序号）。
  ///
  /// 只有竖向档那一档会用到它（横向档是移动，不需要造新的）。它通常会分配一个
  /// 新 id，所以拿来当「能不能分屏」的判断会把序号烧掉一串 —— 只在用户真的点了
  /// 某一项时才调。
  final PlatTab? Function() duplicateTab;

  /// 这条标签能不能被拆出去（宿主按 locked 之类给）。false ⇒ 方向项全部置灰。
  final bool detachable;

  /// 关掉这条标签；`null` = 菜单里不给「关闭」那一项。
  final VoidCallback? onClose;

  /// 现问「这一格现在多大」。**是个回调而不是一个值**：菜单项的 enabled 在 build
  /// 时就定下了，而格子的真实大小要到布局之后才知道 —— 等到用户右键那一下再问，
  /// 拿到的才是眼前这一格。`null` = 宿主不知道（不做置灰判断，方向项都给）。
  final Size? Function()? paneSize;

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
  bool _fits(PlatSide side, Size? size) {
    if (size == null) return true;
    return switch (side) {
      PlatSide.left || PlatSide.right => size.width / 2 >= minPaneWidth,
      PlatSide.top || PlatSide.bottom => size.height / 2 >= minPaneHeight,
    };
  }

  /// 能不能把这条标签挪到 [side] 那一格。
  bool _canMove(PlatSide side, TabGroupSnapshot group) {
    // 源组至少留两条：只剩一条时那一格会跟着消失，而它正是这次分屏的落点。
    // plat 自己的 Cmd + \ 也是这条判据（`splitActiveTab` 里 `tabs.length < 2` 直接 return）。
    if (!detachable || group.tabs.length < 2) return false;
    return _fits(side, paneSize?.call());
  }

  Future<void> _open(BuildContext context, Offset globalPosition) async {
    final groupId = controller.tabGroupContaining(tabId);
    if (groupId == null) return;
    final snapshot = controller.snapshot(groupId);
    if (snapshot is! TabGroupSnapshot) return;
    final group = snapshot;
    final index = group.tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final rail = group.side != TabBarSide.top;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final close = onClose;
    final entries = <PopupMenuEntry<_RossiPlatMenuChoice>>[
      if (rail)
        for (final (label, at) in [
          (RossiPlatMenuLabel.above, index),
          (RossiPlatMenuLabel.below, index + 1),
        ])
          PopupMenuItem(
            value: _RossiPlatMenuChoice.insertRail(at),
            enabled: detachable,
            child: Text(rossiPlatMenuLabel(label)),
          )
      else
        for (final entry in rossiPlatSplitSides.entries)
          PopupMenuItem(
            value: _RossiPlatMenuChoice.move(entry.value),
            enabled: _canMove(entry.value, group),
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
      // 目标是**装这条标签的那个组**，不是标签自己：plat 的 `split` 拿 leaf id
      // 会返回 true 却什么也不改（实测树仍是 TabGroupSnapshot）。
      controller.moveTabBeside(tabId: tabId, targetId: groupId, side: side);
      return;
    }
    final at = choice.railIndex;
    if (at != null) {
      final tab = duplicateTab();
      if (tab == null) return;
      controller.insertTab(tabGroupId: groupId, tab: tab, index: at);
      return;
    }
    close?.call();
  }
}

/// 菜单里被选中的那一项：挪到某侧 / 在轨里第 [railIndex] 位多开一条 / 关闭。
@immutable
class _RossiPlatMenuChoice {
  const _RossiPlatMenuChoice.move(PlatSide this.side)
    : railIndex = null,
      isClose = false;

  const _RossiPlatMenuChoice.insertRail(int this.railIndex) : side = null, isClose = false;

  const _RossiPlatMenuChoice.close() : side = null, railIndex = null, isClose = true;

  final PlatSide? side;
  final int? railIndex;
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

/// 菜单项的名字。**只有四个方向**，不含 plat 的枚举值本身 ——
/// 方向是给 plat 用的，名字是给人看的，两件事不该混在一个枚举里。
enum RossiPlatMenuLabel { above, below, leftOf, rightOf }

/// 菜单标题走 i18n（枚举是 const，拿不到 `t`，所以做成函数）。
///
/// 竖向档只用到「上方 / 下方」那两条：轨里上下插一条，标签仍然说得上话。
String rossiPlatMenuLabel(RossiPlatMenuLabel label) => switch (label) {
  RossiPlatMenuLabel.above => t.plat.openAbove,
  RossiPlatMenuLabel.below => t.plat.openBelow,
  RossiPlatMenuLabel.leftOf => t.plat.openLeft,
  RossiPlatMenuLabel.rightOf => t.plat.openRight,
};
