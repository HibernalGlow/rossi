/// 顶部图标条 —— 菜单里那排「常用动作」的小图标（Win11 的做法）。
///
/// 只负责画：排几格、哪些能点、点了执行什么，全由调用方（`showContextMenu`）
/// 依据解析计划决定。这里不读设置、不判断显隐。
///
/// 宽度上限由解析器（`kMaxContextMenuStripItems`）控制：菜单用 `IntrinsicWidth`
/// 量宽，`Wrap` 的 intrinsic 宽度会把菜单撑过 280，所以这里**不能**用
/// `LayoutBuilder`，格数与格宽都必须是常量。
library;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

/// 图标条里的一格。
class ContextMenuIconAction {
  const ContextMenuIconAction({
    required this.label,
    required this.glyph,
    this.dangerous = false,
    this.enabled = true,
    this.onPressed,
  });

  /// 悬停提示，也是无障碍标签。
  final String label;

  final Glyph glyph;

  /// 用危险色画（删除、移入回收站之类）。
  final bool dangerous;

  /// 不可点时仍然画出来（置灰）—— 与菜单项的「不隐藏只置灰」同一条口径。
  final bool enabled;

  final VoidCallback? onPressed;
}

/// 一排固定尺寸的图标格，底部带一条与菜单分节线同高的分隔线。
class CommonPopupMenuIconStrip extends StatelessWidget {
  const CommonPopupMenuIconStrip({
    super.key,
    required this.actions,
    this.cellSize = 34,
    this.gap = 2,
  });

  final List<ContextMenuIconAction> actions;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              _IconActionCell(action: action, size: cellSize),
          ],
        ),
        // 与 `CommonPopupMenu` 的 `_dividerHeight`（8 * 2 + 1）同高，
        // 这样图标条与下方列表之间的留白和普通分节线一致。
        const Divider(height: 17, thickness: 1),
      ],
    );
  }
}

class _IconActionCell extends StatelessWidget {
  const _IconActionCell({required this.action, required this.size});

  final ContextMenuIconAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = action.dangerous ? colorScheme.error : colorScheme.onSurface;
    final color = action.enabled ? base : base.withValues(alpha: 0.3);
    final enabled = action.enabled && action.onPressed != null;

    return Tooltip(
      message: action.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: action.label,
        child: SizedBox(
          width: size,
          height: size,
          child: InkWell(
            customBorder: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            onTap: enabled
                ? () {
                    // 与 `CommonPopupMenu._select` 同序：先关菜单再执行，
                    // 回调闭包的是调用点的 context，不依赖菜单路由还活着。
                    Navigator.of(context).pop();
                    action.onPressed!();
                  }
                : null,
            splashColor: Colors.transparent,
            hoverColor: action.dangerous
                ? colorScheme.error.withValues(alpha: 0.1)
                : null,
            child: Center(
              child: GlyphIcon(action.glyph, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
