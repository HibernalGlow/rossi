/// 就地编辑菜单时的卡片：标题 + 恢复默认 + 完成，下面是分段编辑器。
///
/// 两个入口共用：
/// - 右键菜单里点「自定义此菜单…」→ 当前这份菜单**原地**变成编辑器；
/// - 设置页 → 个性化 → 右键菜单 → 弹窗里也是这张卡。
///
/// 没有预览：编辑的就是菜单本身（同一个 [ContextMenuScopeEditor]），
/// 改动即时落账，点「完成」回到菜单形态。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/context_menu/context_menu_scope_editor.dart';

class ContextMenuInlineEditor extends StatelessWidget {
  const ContextMenuInlineEditor({
    super.key,
    required this.definition,
    required this.labelOf,
    required this.onDone,
    this.glyphOf,
    this.maxWidth = 380,
    this.maxHeight = 520,
  });

  final ContextMenuDefinition definition;
  final String Function(ContextMenuEntryDefinition entry) labelOf;
  final Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf;

  /// 退出编辑（回到菜单形态，或关闭设置弹窗）。
  final VoidCallback onDone;

  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: CommonPopupSurface(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.contextMenu.customizeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final cubit = context.read<GlobalSettingCubit>();
                    cubit.updateContextMenuSetting((settings) {
                      final scopes = Map<String, ContextMenuScopeLayout>.of(
                        settings.scopes,
                      )..remove(definition.scope);
                      return settings.copyWith(scopes: scopes);
                    });
                  },
                  child: Text(t.contextMenu.resetScope),
                ),
                IconButton(
                  tooltip: t.common.done,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDone,
                  icon: const GlyphIcon(AppGlyphs.check, size: 18),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                t.contextMenu.dragHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ContextMenuScopeEditor(
                definition: definition,
                labelOf: labelOf,
                glyphOf: glyphOf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
