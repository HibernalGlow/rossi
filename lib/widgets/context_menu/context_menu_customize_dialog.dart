/// 「自定义此菜单…」在**没有卡片宿主**时的入口（设置页）。
///
/// 右键菜单自己走的是 ContextMenuHost 的原地编辑，不经过这里；
/// 设置页需要一个能单独弹出来的容器，于是复用同一张编辑卡
/// [ContextMenuInlineEditor]（没有预览、没有第二套 UI）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/context_menu/context_menu_catalog.dart';
import 'package:zephyr/widgets/context_menu/context_menu_inline_editor.dart';

Future<void> showContextMenuCustomizeDialog(
  BuildContext context, {
  required ContextMenuDefinition definition,
  String Function(ContextMenuEntryDefinition entry)? labelOf,
  Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf,
}) {
  final descriptor = contextMenuScopeOf(definition.scope);
  final labels = labelOf ?? descriptor?.labelOf ?? (entry) => entry.id;
  final glyphs = glyphOf ?? descriptor?.glyphOf;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ContextMenuInlineEditor(
        definition: definition,
        labelOf: labels,
        glyphOf: glyphs,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}
