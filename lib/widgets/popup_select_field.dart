// 设置页里「字段形状的选择器」：外壳是一颗填充输入框，点开走全仓统一的
// 托盘弹出器（`common_popup.dart`）。
//
// 为什么要有这一份：原来只有操作绑定那一页在用 Material 的 `DropdownMenu`，
// 弹层是 SDK 默认的淡入缩放，与工作台「更多」、书架右键那一批托盘动画不是同一套；
// 而 `DropdownMenuEntry` 也没有本仓的 `Glyph` 槽，图标只能往 `child` 里手塞 `Row`。
// 文件管理器的「新页签启动选项」是同一形状的第二个用户 —— 两处共用这一份，
// 别再写第二套平行实现。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';

/// 填充字段的装饰：文本框与选择器共用一份，两者并排时高度与圆角才对得齐。
InputDecoration popupFieldDecoration(BuildContext context, String label) {
  final colorScheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: UnderlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: UnderlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: UnderlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
  );
}

/// 从 [options] 里选一个值。[glyphOf] 只给**已经存在图标映射**的那几组用；
/// 没有图标家族的（按钮序号、九宫格区域、手指数这类）就留空 ——
/// 菜单项允许纯文字，为它们现画图形才是「同一语义长出第二颗」的来源。
class PopupSelectField<T> extends StatelessWidget {
  const PopupSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.glyphOf,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Glyph? Function(T value)? glyphOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = options[value] ?? '$value';
    return CommonPopupBox<void>(
      targetBuilder: (open) => Material(
        // 不假设自己在哪张卡里：文本框那一侧有 Scaffold 的 Material 托底。
        type: MaterialType.transparency,
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: popupFieldDecoration(context, label),
            child: Row(
              children: [
                if (glyphOf?.call(value) case final glyph?) ...[
                  GlyphIcon(
                    glyph,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const GlyphIcon(AppGlyphs.chevronDown, size: 18),
              ],
            ),
          ),
        ),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          for (final item in options.entries)
            CommonPopupMenuItem(
              label: item.value,
              glyph: glyphOf?.call(item.key),
              checked: item.key == value,
              onPressed: () => onChanged(item.key),
            ),
          // 存着一个目录里已经没有的值：不能藏起来，否则用户点开读不到
          // 自己当前是什么，也就没法改。
          if (!options.containsKey(value))
            CommonPopupMenuItem(
              label: '$value',
              glyph: glyphOf?.call(value),
              checked: true,
              onPressed: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}
