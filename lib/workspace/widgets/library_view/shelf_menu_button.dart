import 'package:material_ui/material_ui.dart';

import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// Expressive 操作菜单：形变入口、连续圆角容器和分组操作面。
class ShelfMenuButton extends StatefulWidget {
  const ShelfMenuButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.menuChildren,
    this.enabled = true,
    this.size = 40,
    this.shape = ExpressiveButtonShape.cookie4Sided,
  });

  /// 触发键的图标：本仓自绘 glyph（`lib/icons/`），与侧栏、文件管理器工具条
  /// 同一套形状语言。
  final Glyph glyph;
  final String tooltip;

  /// 菜单项。
  ///
  /// 这一层每次重建都会**构造**这些 widget 对象（构造不等于布局，
  /// `MenuAnchor` 只在菜单真的弹出来时才摆它们），所以内容只许读调用方
  /// 手里已经有的状态，不许在这里查库或发桥调用。
  final List<Widget> menuChildren;
  final bool enabled;
  final double size;
  final ExpressiveButtonShape shape;

  @override
  State<ShelfMenuButton> createState() => _ShelfMenuButtonState();
}

class _ShelfMenuButtonState extends State<ShelfMenuButton> {
  final MenuController _controller = MenuController();
  bool _open = false;

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 300.0);
    return MenuAnchor(
      controller: _controller,
      animated: !MediaQuery.disableAnimationsOf(context),
      consumeOutsideTap: true,
      onOpen: () => setState(() => _open = true),
      onClose: () {
        if (mounted) setState(() => _open = false);
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll(AppShape.xxl),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        maximumSize: WidgetStatePropertyAll(Size(maxWidth, double.infinity)),
      ),
      menuChildren: widget.menuChildren,
      child: ExpressiveIconButton(
        tooltip: widget.tooltip,
        glyph: widget.glyph,
        active: _open,
        activeGlyph: AppGlyphs.close,
        activeTurns: .5,
        size: widget.size,
        shape: widget.shape,
        onPressed: widget.enabled
            ? () {
                if (_controller.isOpen) {
                  _controller.close();
                } else {
                  _controller.open();
                }
              }
            : null,
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
    this.glyph,
    this.icon,
    this.selected = false,
    this.destructive = false,
  }) : assert(
         glyph == null || icon == null,
         '图标只给一个：glyph（Glyph）或 icon（Glyph）',
       );

  final String label;

  /// `null` = 灰掉。
  final VoidCallback? onPressed;

  /// 前置图标，MD3 的 24dp。glyph 是本仓自绘那套（`lib/icons/`），icon 是
  /// Material 的兜底 —— glyph 词表里没有对应符号的动作（如「打开」的书）
  /// 暂走 icon，等词表补齐再换。不给就没有这一列。
  final Glyph? glyph;
  final Glyph? icon;

  /// 单选菜单里当前选中的那一项。勾一律画在**右侧**：这一层只有一条规则，
  /// 「有勾的就是当前值」，不需要按有没有前置图标换位置。
  final bool selected;

  /// 破坏性动作，整项走 `error` 色。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = onPressed == null
        ? scheme.onSurface.withValues(alpha: .38)
        : destructive
        ? scheme.error
        : selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return ElasticButton(
      enabled: onPressed != null && !MediaQuery.disableAnimationsOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MenuItemButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            shape: WidgetStateProperty.resolveWith(
              (states) => AppShape.all(
                states.contains(WidgetState.pressed)
                    ? 12
                    : states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)
                    ? 24
                    : 16,
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (onPressed == null) return Colors.transparent;
              if (destructive) {
                return scheme.errorContainer.withValues(alpha: .5);
              }
              if (selected ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return scheme.secondaryContainer;
              }
              return scheme.surfaceContainerHigh;
            }),
            foregroundColor: WidgetStatePropertyAll(color),
          ),
          leadingIcon: glyph != null || icon != null
              ? GlyphIcon((glyph ?? icon)!, size: 20, color: color)
              : null,
          trailingIcon: selected
              ? GlyphIcon(AppGlyphs.check, size: 20, color: color)
              : null,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
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
