/// 自定义菜单时右侧那面**实时预览**。
///
/// 不是画个示意图：它走的是与真实菜单完全相同的 `buildContextMenuItems` +
/// `CommonPopupMenu`，所以顺序、分组线、折叠、pin、顶部图标条、以及
/// 「自定义此菜单…」那一行，都是最终会长成的样子。
///
/// 只读：外面套 `AbsorbPointer` —— 预览里点一项不能真的执行动作，也不能
/// 把弹窗 pop 掉。改动通过 `context.watch<GlobalSettingCubit>()` 触发重建，
/// 所以编辑器里每一次点击都会立刻反映在这里。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/context_menu/context_menu_entry_view.dart';

class ContextMenuPreview extends StatelessWidget {
  const ContextMenuPreview({
    super.key,
    required this.definition,
    required this.labelOf,
    this.glyphOf,
  });

  final ContextMenuDefinition definition;
  final String Function(ContextMenuEntryDefinition entry) labelOf;

  /// 预览里的图标。设置页拿不到运行时图标时可为 null（行就没有图标）。
  final Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf;

  @override
  Widget build(BuildContext context) {
    // 订阅设置：编辑器里任何一次改动都从这里重建。
    context.watch<GlobalSettingCubit>();

    final resolved = buildContextMenuItems(
      context: context,
      definition: definition,
      viewOf: (entry) => ContextMenuEntryView(
        label: labelOf(entry),
        glyph: glyphOf?.call(entry),
      ),
    );

    if (resolved.items.isEmpty) {
      return Center(
        child: Text(
          t.contextMenu.previewEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: AbsorbPointer(
        // `CommonPopupMenu` 内部有纵向 `SingleChildScrollView`，必须有高度上界，
        // 否则在对话框里会报 unbounded height。
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: CommonPopupMenu(
            items: resolved.items,
            header: resolved.header,
            footer: resolved.footer,
            minWidth: resolved.minWidth,
          ),
        ),
      ),
    );
  }
}
