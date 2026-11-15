/// 「自定义此菜单…」的弹窗外壳。
///
/// 内容由 [ContextMenuScopeEditor] 提供，右侧是一面 [ContextMenuPreview]
/// **实时预览**（与真实菜单同一套渲染，改一下立刻变）。
///
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
import 'package:zephyr/widgets/context_menu/context_menu_preview.dart';
import 'package:zephyr/widgets/context_menu/context_menu_scope_editor.dart';

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
    builder: (_) => _ContextMenuCustomizeDialog(
      definition: definition,
      labelOf: labels,
      glyphOf: glyphs,
      title: descriptor?.title ?? definition.scope,
    ),
  );
}

class _ContextMenuCustomizeDialog extends StatelessWidget {
  const _ContextMenuCustomizeDialog({
    required this.definition,
    required this.labelOf,
    required this.glyphOf,
    required this.title,
  });

  final ContextMenuDefinition definition;
  final String Function(ContextMenuEntryDefinition entry) labelOf;
  final Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final editor = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ContextMenuScopeEditor(
        definition: definition,
        labelOf: labelOf,
        glyphOf: glyphOf,
      ),
    );
    final preview = _PreviewPane(
      definition: definition,
      labelOf: labelOf,
      glyphOf: glyphOf,
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 980,
          maxHeight: 720,
          minWidth: 320,
        ),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 宽窗口左右分栏（编辑 + 预览）；窄窗口上下排，预览在上。
                  if (constraints.maxWidth >= 760) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: editor),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 320, child: preview),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 240, child: preview),
                      const Divider(height: 1),
                      Expanded(child: editor),
                    ],
                  );
                },
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

/// 预览那一栏：一层浅底 + 标题 + 居中的真实菜单卡片。
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.definition,
    required this.labelOf,
    required this.glyphOf,
  });

  final ContextMenuDefinition definition;
  final String Function(ContextMenuEntryDefinition entry) labelOf;
  final Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.contextMenu.previewTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  t.contextMenu.previewHint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ContextMenuPreview(
                  definition: definition,
                  labelOf: labelOf,
                  glyphOf: glyphOf,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
