import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';

/// 收藏 / 历史卡片里**一个条目**的右键菜单宿主。
///
/// 两件事分开：
///
/// - **有哪些项、哪一项可用** —— 纯函数 [buildShelfEntryMenuItems]
///   （`lib/workspace/model/shelf_entry_menu_spec.dart`，判据 `dart run
///   test/workspace/shelf_entry_menu_check.dart`）；
/// - **长什么样、在哪儿弹** —— 本文件。
///
/// # 触发方式：桌面右键 + 触摸长按
///
/// 两个手势都挂，不按平台分叉。理由：桌面端长按也弹菜单无害（用户只是在按住
/// 卡片看封面，松手即散），而**按平台分叉会在「带触摸屏的桌面」上错**——
/// `defaultTargetPlatform` 说 desktop、用户却用触控笔长按，于是菜单永远出不来。
///
/// 与卡片自己的 `InkWell(onTap:)` 不冲突：那个只认主键单击，这里认的是次键与长按，
/// 三种手势在 arena 里各走各的。
///
/// # 为什么不包 `PopupMenuButton`
///
/// 那个组件要的是「自己就是那个按钮」，而这里整行已经是可点的 `InkWell`；
/// 再套一层按钮会让「点一下」与「右键一下」落到两个不同的响应区。
class ShelfEntryContextMenuRegion extends StatelessWidget {
  const ShelfEntryContextMenuRegion({
    super.key,
    required this.child,
    required this.inputBuilder,
    required this.onAction,
    this.enabled = true,
  });

  final Widget child;

  /// **菜单真正弹出来的那一刻**才调用它。
  ///
  /// 不提前算：`isFavorite` 要查一次 ObjectBox，而列表里每一条都查一遍属于
  /// 「为了一个可能永远不打开的菜单，把整张列表过一遍数据库」。
  final ShelfEntryMenuInput Function() inputBuilder;

  /// 用户选了一个动作。选中后菜单已经关掉了，这里只负责执行。
  final void Function(BuildContext context, ShelfEntryAction action) onAction;

  /// 全局开关关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得"有反应"，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) => _open(context, details.globalPosition),
      onLongPressStart: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }

  Future<void> _open(BuildContext context, Offset globalPosition) async {
    final action = await showShelfEntryMenu(
      context,
      position: globalPosition,
      input: inputBuilder(),
    );
    if (action == null || !context.mounted) return;
    onAction(context, action);
  }
}

/// 在 [position]（全局坐标）弹出菜单并等用户选一个。
///
/// 返回 `null` = 点空白关掉了 / 选了灰掉的那一项 —— 两种都不该有动作。
Future<ShelfEntryAction?> showShelfEntryMenu(
  BuildContext context, {
  required Offset position,
  required ShelfEntryMenuInput input,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  // 两条分隔线把菜单切成「打开类 / 复制类 / 破坏性」三段：挨在一起最容易点错，
  // 而破坏性那一段必须与上面隔开（neoview 的两份菜单也是这么分组的）。
  final items = <PopupMenuEntry<ShelfEntryAction>>[];
  for (final spec in buildShelfEntryMenuItems(input)) {
    if (spec.action == ShelfEntryAction.copyTitle ||
        spec.action == ShelfEntryAction.remove) {
      items.add(const PopupMenuDivider());
    }
    items.add(
      PopupMenuItem<ShelfEntryAction>(
        value: spec.action,
        enabled: spec.enabled,
        child: _MenuRow(
          spec: spec,
          kind: input.kind,
          isFavorite: input.isFavorite,
        ),
      ),
    );
  }

  return showMenu<ShelfEntryAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.spec,
    required this.kind,
    required this.isFavorite,
  });

  final ShelfEntryMenuItemSpec spec;
  final ShelfEntryKind kind;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = spec.destructive ? theme.colorScheme.error : null;
    final label = shelfEntryActionLabel(
      spec.action,
      kind: kind,
      isFavorite: isFavorite,
    );

    return Row(
      children: [
        Icon(
          shelfEntryActionIcon(spec.action, kind: kind),
          size: 18,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            // MD3 菜单项正文是 labelLarge（14/500），与卡片位置菜单同一口径。
            style: theme.textTheme.labelLarge?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

IconData shelfEntryActionIcon(
  ShelfEntryAction action, {
  required ShelfEntryKind kind,
}) {
  switch (action) {
    case ShelfEntryAction.open:
      return Icons.menu_book_rounded;
    case ShelfEntryAction.openInFileManagerTab:
      return Icons.folder_open_rounded;
    case ShelfEntryAction.copyTitle:
      return Icons.text_fields_rounded;
    case ShelfEntryAction.copyLink:
      return Icons.link_rounded;
    case ShelfEntryAction.toggleFavorite:
      return Icons.star_border_rounded;
    case ShelfEntryAction.remove:
      return kind == ShelfEntryKind.favorite
          ? Icons.star_outline_rounded
          : Icons.delete_outline_rounded;
  }
}
