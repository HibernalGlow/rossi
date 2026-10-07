import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/widgets/cards/file_manager_entry_context_menu.dart'
    show md3MenuStyle;
import 'package:zephyr/workspace/widgets/cards/file_manager_toolbar.dart';

/// 工具栏里的一颗「按下弹菜单」的键，菜单面按 Material Design 3 规格画。
///
/// 为什么不用 `FluentPopupMenuButton`：那一套是本仓自己搓的浮层，菜单面走
/// Fluent 的底色与圆角。MD3 的菜单面是 **`surfaceContainer` 底色 + 2dp 高度 +
/// 4dp 圆角 + 上下 8dp 内边距**，规格收在 [md3MenuStyle] 一份。
///
/// 也不用 `PopupMenuButton`：这个版本的 `material_ui` 里它仍然走 M2 的
/// `PopupMenuTheme` 那条路（源码注释自己写着「配置为 Material 3 时推荐改用
/// [MenuAnchor]」），换不到 MD3 的菜单面。
///
/// 触发键本身的几何不另立口径，直接用文件管理器工具栏那一份
/// （[FileManagerToolbarIconButton.style]：图标钮 40 见方、图标 20），
/// 否则同一条带上会同时出现 40 和 32 两种高度。
class ShelfMenuButton extends StatefulWidget {
  const ShelfMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.menuChildren,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;

  /// 菜单项。
  ///
  /// 这一层每次重建都会**构造**这些 widget 对象（构造不等于布局，
  /// `MenuAnchor` 只在菜单真的弹出来时才摆它们），所以内容只许读调用方
  /// 手里已经有的状态，不许在这里查库或发桥调用。
  final List<Widget> menuChildren;
  final bool enabled;

  @override
  State<ShelfMenuButton> createState() => _ShelfMenuButtonState();
}

class _ShelfMenuButtonState extends State<ShelfMenuButton> {
  /// `MenuController` 只能由 State 持有（在 `attach` 之前调 `open()` 会断言失败），
  /// 所以触发键是有状态的。这个版本的 `material_ui` 没有 `MenuAnchor.builder`，
  /// 拿不到 `controller.isOpen` —— 但也不需要：菜单在外面盖了一层 barrier，
  /// 第二次点触发键先被 barrier 吃掉并关掉菜单，「再点一次收起」是白拿的。
  final MenuController _controller = MenuController();

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      style: md3MenuStyle(context),
      menuChildren: widget.menuChildren,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.enabled ? () => _controller.open() : null,
        style: FileManagerToolbarIconButton.style(context),
        icon: Icon(widget.icon),
      ),
    );
  }
}

/// [ShelfMenuButton] 里的一项，按 MD3 菜单项规格画。
///
/// 规格里的一条硬约定：**这一项永远在场，只是有时不可点**。`onPressed: null`
/// 就是 MD3 的禁用态（置灰、不可聚焦、点了不响应），而不是把项藏起来 ——
/// 用户得看得见「有这件事，只是现在做不了」。
class ShelfMenuItem extends StatelessWidget {
  const ShelfMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.destructive = false,
  });

  final String label;

  /// `null` = 灰掉。
  final VoidCallback? onPressed;

  /// 前置图标，MD3 的 24dp。不给就没有这一列。
  final IconData? icon;

  /// 单选菜单里当前选中的那一项。勾一律画在**右侧**：这一层只有一条规则，
  /// 「有勾的就是当前值」，不需要按有没有前置图标换位置。
  final bool selected;

  /// 破坏性动作，整项走 `error` 色。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: icon == null ? null : Icon(icon, size: 24, color: color),
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 24, color: color)
          : null,
      child: Text(label, style: TextStyle(color: color)),
    );
  }
}

/// 菜单里的分组线。
///
/// MD3 说菜单里相关动作成组、组间分隔 —— 挨在一起最容易点错，破坏性那一段
/// 必须与上面隔开。
class ShelfMenuDivider extends StatelessWidget {
  const ShelfMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 9, thickness: 1);
  }
}
