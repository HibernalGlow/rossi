/// 设置 → 个性化 → 右键菜单。
///
/// 这里只做总览与全局开关；单个菜单的顺序/显隐/pin 在弹窗里改
/// （[showContextMenuCustomizeDialog]），与右键菜单底部那条入口共用同一份编辑器。
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/context_menu/context_menu_catalog.dart';
import 'package:zephyr/widgets/context_menu/context_menu_customize_dialog.dart';

@RoutePage()
class ContextMenuSettingPage extends StatelessWidget {
  const ContextMenuSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state.contextMenuSetting;
    final colorScheme = Theme.of(context).colorScheme;
    final catalog = contextMenuScopeCatalog();
    final customized = catalog
        .where(
          (descriptor) =>
              !(state.scopes[descriptor.definition.scope]?.isPristine ?? true),
        )
        .length;

    return SettingPageShell(
      title: t.contextMenu.customizeTitle,
      description: customized == 0
          ? t.contextMenu.nothingCustomized
          : t.contextMenu.customizedCount(count: customized),
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingSectionCard(
            title: t.contextMenu.customizeTitle,
            icon: AppGlyphs.sliders,
            children: [
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.vAlignTop),
                title: Text(t.contextMenu.topStripEnabled),
                subtitle: Text(t.contextMenu.topStripEnabledHint),
                value: state.topStripEnabled,
                onChanged: (value) => cubit.updateContextMenuSetting(
                  (current) => current.copyWith(topStripEnabled: value),
                ),
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.sliders),
                title: Text(t.contextMenu.customizeEntryVisible),
                value: state.customizeEntryVisible,
                onChanged: (value) => cubit.updateContextMenuSetting(
                  (current) => current.copyWith(customizeEntryVisible: value),
                ),
              ),
            ],
          ),
          SettingSectionCard(
            title: t.contextMenu.settingsSubtitle,
            icon: AppGlyphs.more,
            children: [
              for (final descriptor in catalog)
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.more, size: 20),
                  title: Text(descriptor.title),
                  subtitle: Text(_scopeSummary(state, descriptor)),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                  onTap: () => showContextMenuCustomizeDialog(
                    context,
                    definition: descriptor.definition,
                    labelOf: descriptor.labelOf,
                  ),
                ),
            ],
          ),
          SettingSectionCard(
            children: [
              ListTile(
                leading: GlyphIcon(
                  AppGlyphs.delete,
                  size: 20,
                  color: colorScheme.error,
                ),
                title: Text(
                  t.contextMenu.resetAll,
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () => _confirmResetAll(context, cubit),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _scopeSummary(
    ContextMenuSettingState state,
    ContextMenuScopeDescriptor descriptor,
  ) {
    final layout = state.scopes[descriptor.definition.scope];
    if (layout == null || layout.isPristine) {
      return t.contextMenu.scopeDefault;
    }
    return t.contextMenu.scopeCustomized;
  }

  Future<void> _confirmResetAll(
    BuildContext context,
    GlobalSettingCubit cubit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.contextMenu.resetAll),
        content: Text(t.contextMenu.settingsSubtitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.common.ok),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    cubit.updateContextMenuSetting(
      (current) =>
          current.copyWith(scopes: const <String, ContextMenuScopeLayout>{}),
    );
  }
}
