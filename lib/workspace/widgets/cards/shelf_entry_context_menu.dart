import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';

/// 收藏 / 历史卡片里**一个条目**的右键菜单宿主。
///
/// 三件事分开：
///
/// - **有哪些项、哪一项可用** —— 纯函数 [buildShelfEntryMenuItems]
///   （`lib/workspace/model/shelf_entry_menu_spec.dart`，判据 `dart run
///   test/workspace/shelf_entry_menu_check.dart`）；
/// - **长什么样、在哪儿弹** —— 本文件；
/// - **动作怎么落地** —— 卡片里的 `_onMenuAction`。
///
/// # 弹出动画与工作台那排「更多」同源
///
/// 这一份曾经走 MD3 的 `MenuAnchor`（Material 自己的淡入缩放），与栏头 ⋮、
/// 文件管理器「更多」的 FlClash 托盘动画不是一套。现在统一走
/// [showCommonPopupMenu]：托盘从右键 / 长按那一点长出来、放不下时自己朝上翻，
/// 全仓菜单只有一份弹出动画。菜单面也随之换成 [CommonPopupSurface]
/// （superellipse 卡片），与工作台其余菜单同貌。
///
/// # 触发方式：桌面右键 + 触摸长按
///
/// 两个手势都挂，不按平台分叉。理由：桌面端长按也弹菜单无害（用户只是在按住
/// 卡片看封面，松手即散），而**按平台分叉会在「带触摸屏的桌面」上错**——
/// `defaultTargetPlatform` 说 desktop、用户却用触控笔长按，于是菜单永远出不来。
///
/// 与卡片自己的 `InkWell(onTap:)` 不冲突：那个只认主键单击，这里认的是次键与长按，
/// 三种手势在 arena 里各走各的。
class ShelfEntryContextMenuRegion extends StatelessWidget {
  const ShelfEntryContextMenuRegion({
    super.key,
    required this.child,
    required this.inputBuilder,
    required this.onAction,
    this.enabled = true,
  });

  final Widget child;

  /// **菜单要弹出来的那一刻**才调用它。
  ///
  /// 不提前算：`isFavorite` 要查一次 ObjectBox，而列表里每一条都查一遍属于
  /// 「为了一个可能永远不打开的菜单，把整张列表过一遍数据库」。所以它只在
  /// 真的右键 / 长按那一下被调一次。
  final ShelfEntryMenuInput Function() inputBuilder;

  /// 用户选了一个动作。选中后菜单已经关掉了，这里只负责执行。
  final void Function(BuildContext context, ShelfEntryAction action) onAction;

  /// 全局开关关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得"有反应"，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  void _openAt(BuildContext context, Offset globalPosition) {
    final input = inputBuilder();
    final items = <CommonPopupMenuItem>[];
    for (final spec in buildShelfEntryMenuItems(input)) {
      // 两条分隔线把菜单切成「打开类 / 复制类 / 破坏性」三段：挨在一起最容易点错，
      // 而破坏性那一段必须与上面隔开（neoview 的两份菜单也是这么分组的）。
      if (spec.action == ShelfEntryAction.copyTitle ||
          spec.action == ShelfEntryAction.remove) {
        items.add(const CommonPopupMenuItem.divider());
      }
      items.add(
        CommonPopupMenuItem(
          label: shelfEntryActionLabel(
            spec.action,
            kind: input.kind,
            isFavorite: input.isFavorite,
          ),
          // 动作 → glyph 一张表拍平：词表（含本仓补的 book / folder）里
          // 每个动作都有符号，不再留 Material `icon:` 兜底 —— 图标语汇只有一份。
          glyph: switch (spec.action) {
            ShelfEntryAction.open => AppGlyphs.book,
            ShelfEntryAction.openInFileManagerTab => AppGlyphs.folder,
            ShelfEntryAction.copyTitle => AppGlyphs.copy,
            ShelfEntryAction.copyLink => AppGlyphs.link,
            ShelfEntryAction.toggleFavorite || ShelfEntryAction.remove
                when input.kind == ShelfEntryKind.favorite =>
              AppGlyphs.star,
            ShelfEntryAction.remove => AppGlyphs.delete,
            _ => null,
          },
          // `onPressed: null` 就是禁用态：菜单项**永远在场**，只是有的不可点。
          // 破坏性那一项按 `danger` 上一档色（与工作台「退出」类同一读法）。
          danger: spec.destructive,
          onPressed: spec.enabled ? () => onAction(context, spec.action) : null,
        ),
      );
    }
    // 路由自己会在选中 / 点空白时关掉，不必等它。
    unawaited(
      showCommonPopupMenu(
        context: context,
        position: globalPosition,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      // `deferToChild`：手势只在这一行本身吃掉了事件时才认，不抢上层滚动的。
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) => _openAt(context, details.globalPosition),
      onLongPressStart: (details) => _openAt(context, details.globalPosition),
      child: child,
    );
  }
}

/// 一个动作、一个条目类型 —— 对应哪一句文案。
///
/// 收藏卡与历史卡的「打开」不是同一句话：历史卡上它是「继续阅读」（带进度），
/// 收藏卡上它就是「打开」。抽成一个函数的价值在于**两处口径不会再分叉**。
String shelfEntryActionLabel(
  ShelfEntryAction action, {
  required ShelfEntryKind kind,
  required bool isFavorite,
}) {
  switch (action) {
    case ShelfEntryAction.open:
      return kind == ShelfEntryKind.history
          ? t.shelfMenu.resumeReading
          : t.shelfMenu.open;
    case ShelfEntryAction.openInFileManagerTab:
      return t.shelfMenu.openInFileManagerTab;
    case ShelfEntryAction.copyTitle:
      return t.shelfMenu.copyTitle;
    case ShelfEntryAction.copyLink:
      return t.shelfMenu.copyLink;
    case ShelfEntryAction.toggleFavorite:
      return isFavorite ? t.shelfMenu.alreadyFavorite : t.shelfMenu.addFavorite;
    case ShelfEntryAction.remove:
      return kind == ShelfEntryKind.favorite
          ? t.shelfMenu.removeFavorite
          : t.shelfMenu.removeHistory;
  }
}
