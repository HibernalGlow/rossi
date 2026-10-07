import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_entry_context_menu.dart'
    show md3MenuStyle;
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 收藏 / 历史卡片里**一个条目**的右键菜单宿主，菜单面按 Material Design 3 规格实现。
///
/// 三件事分开：
///
/// - **有哪些项、哪一项可用** —— 纯函数 [buildShelfEntryMenuItems]
///   （`lib/workspace/model/shelf_entry_menu_spec.dart`，判据 `dart run
///   test/workspace/shelf_entry_menu_check.dart`）；
/// - **长什么样、在哪儿弹** —— 本文件；
/// - **动作怎么落地** —— 卡片里的 `_onMenuAction`。
///
/// # 为什么用 `MenuAnchor` 而不是 `showMenu`
///
/// `showMenu` 走的是 M2 的 `PopupMenuTheme`：`surface` 底色、2dp 圆角、8dp 高度。
/// MD3 的菜单面是 `surfaceContainer` + 2dp 高度 + 4dp 圆角 + 上下 8dp 内边距，
/// 条目 48dp 高、24dp 前置图标 —— 规格与文件管理器那一份共用 [md3MenuStyle]，
/// 不再有两套菜单长得不一样。
///
/// 也**不用** `PopupMenuButton`：那个组件要的是「自己就是那个按钮」，而这里整行
/// 已经是可点的 `InkWell`，再套一层按钮会让「点一下」与「右键一下」落到两个
/// 不同的响应区。
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
  /// 「为了一个可能永远不打开的菜单，把整张列表过一遍数据库」。所以
  /// [MenuAnchor.menuChildren] 在菜单关着的时候是空表，只有 [_openAt] 先把
  /// 输入算出来存进 State、重建一次，才交给菜单。
  final ShelfEntryMenuInput Function() inputBuilder;

  /// 用户选了一个动作。选中后菜单已经关掉了，这里只负责执行。
  final void Function(BuildContext context, ShelfEntryAction action) onAction;

  /// 全局开关关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得"有反应"，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return _ShelfEntryMenuAnchor(
      inputBuilder: inputBuilder,
      onAction: onAction,
      child: child,
    );
  }
}

/// `MenuAnchor` 需要 `MenuController`，而 `MenuController` 只能在 State 里持有一个
/// （它在 `attach` 之前调 `open()` 会断言失败）。所以外壳是 Stateless、内核是 Stateful。
class _ShelfEntryMenuAnchor extends StatefulWidget {
  const _ShelfEntryMenuAnchor({
    required this.child,
    required this.inputBuilder,
    required this.onAction,
  });

  final Widget child;
  final ShelfEntryMenuInput Function() inputBuilder;
  final void Function(BuildContext context, ShelfEntryAction action) onAction;

  @override
  State<_ShelfEntryMenuAnchor> createState() => _ShelfEntryMenuAnchorState();
}

class _ShelfEntryMenuAnchorState extends State<_ShelfEntryMenuAnchor> {
  final MenuController _controller = MenuController();

  /// 这一次菜单的输入；`null` = 菜单没在弹，也就一项都不必构造。
  ShelfEntryMenuInput? _input;

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  void _openAt(Offset localPosition) {
    // 查库（`isFavorite`）只发生在这一行被右键/长按的时候。
    setState(() => _input = widget.inputBuilder());
    // MD3 的惯例是菜单左上角落在指针处。`MenuAnchor` 的 `position` 用的是
    // 锚点自己的坐标系，所以直接用 `localPosition`，不要换算全局坐标。
    _controller.open(position: localPosition);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      style: md3MenuStyle(context),
      menuChildren: _buildItems(context),
      child: GestureDetector(
        // `deferToChild`：手势只在这一行本身吃掉了事件时才认，不抢上层滚动的。
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapUp: (details) => _openAt(details.localPosition),
        onLongPressStart: (details) => _openAt(details.localPosition),
        child: widget.child,
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final input = _input;
    if (input == null) return const [];
    final items = <Widget>[];
    for (final spec in buildShelfEntryMenuItems(input)) {
      // 两条分隔线把菜单切成「打开类 / 复制类 / 破坏性」三段：挨在一起最容易点错，
      // 而破坏性那一段必须与上面隔开（neoview 的两份菜单也是这么分组的）。
      if (spec.action == ShelfEntryAction.copyTitle ||
          spec.action == ShelfEntryAction.remove) {
        items.add(const ShelfMenuDivider());
      }
      items.add(
        ShelfMenuItem(
          // 动作挂在 key 上：判据按「这是哪一项」找，不按文案找 —— 文案收进
          // slang 之后会随语言变。
          key: ValueKey(spec.action),
          label: shelfEntryActionLabel(
            spec.action,
            kind: input.kind,
            isFavorite: input.isFavorite,
          ),
          icon: shelfEntryActionIcon(spec.action, kind: input.kind),
          // `onPressed: null` 就是 MD3 的禁用态：菜单项**永远在场**，
          // 只是有的不可点。
          onPressed: spec.enabled
              ? () {
                  _controller.close();
                  widget.onAction(context, spec.action);
                }
              : null,
          destructive: spec.destructive,
        ),
      );
    }
    return items;
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
