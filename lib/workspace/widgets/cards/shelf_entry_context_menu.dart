import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/context_menu/context_menu_entry_view.dart';
import 'package:zephyr/widgets/context_menu/context_menu_region.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_definition.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';

/// 收藏 / 历史卡片里**一个条目**的右键菜单宿主。
///
/// 三件事分开：
///
/// - **有哪些项、哪一项可用** —— 纯函数 [buildShelfEntryMenuItems]
///   （`lib/workspace/model/shelf_entry_menu_spec.dart`，判据 `dart run
///   test/workspace/shelf_entry_menu_check.dart`）；
/// - **用户能怎么摆它** —— [buildShelfMenuDefinition]（同一个目录下的
///   `shelf_entry_menu_definition.dart`）；
/// - **长什么样、在哪儿弹** —— 本文件 + `showContextMenu`；
/// - **动作怎么落地** —— 卡片里的 `_onMenuAction`。
///
/// # 弹出动画与工作台那排「更多」同源
///
/// 统一走 `showCommonPopupMenu`：托盘从右键 / 长按那一点长出来、放不下时自己
/// 朝上翻，全仓菜单只有一份弹出动画。顺序 / 折叠 / 隐藏 / pin / 顶部图标条
/// 由 `lib/model/context_menu/` 的解析器决定，这里不再自己拼分隔线。
///
/// # 触发方式：桌面右键 + 触摸长按
///
/// 两个手势都挂，不按平台分叉（理由见 `ContextMenuRegion` 顶部注释）：
/// 按 `defaultTargetPlatform` 分叉会在「带触摸屏的桌面」上错。
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
    final definition = buildShelfMenuDefinition(input);
    unawaited(
      showContextMenu(
        context: context,
        position: globalPosition,
        definition: definition,
        viewOf: (entry) {
          final action = shelfEntryActionOfId(entry.id);
          return ContextMenuEntryView(
            label: shelfEntryActionLabel(
              action,
              kind: input.kind,
              isFavorite: input.isFavorite,
            ),
            glyph: shelfEntryActionIcon(action, kind: input.kind),
            onPressed: () => onAction(context, action),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(enabled: enabled, onOpen: _openAt, child: child);
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

/// 一个动作对应哪一个符号。
///
/// 收藏卡上的「收藏 / 移除」共用星标（那个动作就是取消收藏），历史卡的
/// 「收藏」没有符号 —— 与迁移前那张 switch 表逐条一致。
Glyph? shelfEntryActionIcon(
  ShelfEntryAction action, {
  required ShelfEntryKind kind,
}) {
  switch (action) {
    case ShelfEntryAction.open:
      return AppGlyphs.book;
    case ShelfEntryAction.openInFileManagerTab:
      return AppGlyphs.folder;
    case ShelfEntryAction.copyTitle:
      return AppGlyphs.copy;
    case ShelfEntryAction.copyLink:
      return AppGlyphs.link;
    case ShelfEntryAction.toggleFavorite:
      return kind == ShelfEntryKind.favorite ? AppGlyphs.star : null;
    case ShelfEntryAction.remove:
      return kind == ShelfEntryKind.favorite
          ? AppGlyphs.star
          : AppGlyphs.delete;
  }
}
