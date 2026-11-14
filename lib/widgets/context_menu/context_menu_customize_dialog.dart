/// 「自定义此菜单…」的弹窗外壳。
///
/// 内容由 [ContextMenuScopeEditor] 提供；这里只负责标题、恢复默认与关闭。
/// 改动是**即时落账**的（编辑器每次操作直接写全局设置），所以没有「保存」
/// 按钮，只有「完成」。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/context_menu/context_menu_catalog.dart';
import 'package:zephyr/widgets/context_menu/context_menu_scope_editor.dart';

Future<void> showContextMenuCustomizeDialog(
  BuildContext context, {
  required ContextMenuDefinition definition,
  String Function(ContextMenuEntryDefinition entry)? labelOf,
}) {
  final descriptor = contextMenuScopeOf(definition.scope);
  final labels = labelOf ?? descriptor?.labelOf ?? (entry) => entry.id;
  return showDialog<void>(
    context: context,
    builder: (_) => _ContextMenuCustomizeDialog(
      definition: definition,
      labelOf: labels,
      title: descriptor?.title ?? definition.scope,
    ),
  );
}

class _ContextMenuCustomizeDialog extends StatelessWidget {
  const _ContextMenuCustomizeDialog({
    required this.definition,
    required this.labelOf,
    required this.title,
  });

  final ContextMenuDefinition definition;
  final String Function(ContextMenuEntryDefinition entry) labelOf;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          t.contextMenu.settingsSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
                    tooltip: t.common.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const GlyphIcon(AppGlyphs.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ContextMenuScopeEditor(
                  definition: definition,
                  labelOf: labelOf,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.contextMenu.dragHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.common.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
