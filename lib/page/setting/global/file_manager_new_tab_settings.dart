import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/popup_select_field.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 默认值与继承策略只用于未来页签；改设置时不覆盖已经打开的页签。
class FileManagerNewTabSettings extends StatelessWidget {
  const FileManagerNewTabSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.fileManagerSetting;
    Widget select<T>(
      String label,
      T value,
      Map<T, String> choices,
      ValueChanged<T> change, {
      Glyph? Function(T value)? glyphOf,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: PopupSelectField<T>(
        label: label,
        value: value,
        options: choices,
        glyphOf: glyphOf,
        onChanged: change,
      ),
    );
    return SettingSectionCard(
      title: t.settings.fmNewTabStartup,
      icon: AppGlyphs.layoutTabs,
      children: [
        select(
          t.settings.fmTabPolicySource,
          setting.newTabPolicy,
          {
            for (final policy in FileManagerTabStartupPolicy.values)
              policy: policy.label,
          },
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabPolicy: value),
          ),
          // 预设 = 「回到默认」那一颗（与泳道的恢复默认宽度同一语义）；
          // 继承最近 / 继承触发页签分别是历史与定位。
          glyphOf: (policy) => switch (policy) {
            FileManagerTabStartupPolicy.defaults => AppGlyphs.reset,
            FileManagerTabStartupPolicy.recent => AppGlyphs.history,
            FileManagerTabStartupPolicy.triggering => AppGlyphs.target,
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(t.settings.fmTabPolicyHint),
        ),
        select(
          t.settings.fmDefaultEntryStyle,
          LibraryViewMode.values.any((m) => m.name == setting.newTabViewMode)
              ? setting.newTabViewMode
              : 'compact',
          {for (final mode in LibraryViewMode.values) mode.name: mode.label},
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabViewMode: value),
          ),
          // 图标只有一份：直接取 `LibraryViewMode.icon`，与文件卡工具栏
          // 「视图模式：$label」那六颗同一套，这里不再另画。
          glyphOf: (name) => LibraryViewMode.values.asNameMap()[name]?.icon,
        ),
        select(
          t.settings.fmDefaultContentLayout,
          const [
                'content',
                'tree',
                'columns',
              ].contains(setting.newTabLayoutMode)
              ? setting.newTabLayoutMode
              : 'content',
          {
            'content': t.settings.fmViewContent,
            'tree': t.settings.fmViewTree,
            'columns': t.settings.fmViewColumns,
          },
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabLayoutMode: value),
          ),
          // 树形 / 分栏沿用工具栏上那两颗（文件树开关、目录列开关），
          // 内容视图是「只有条目列表」，取列表那一颗。
          glyphOf: (name) => switch (name) {
            'tree' => AppGlyphs.tree,
            'columns' => AppGlyphs.columnsTwo,
            'content' => AppGlyphs.appsList,
            _ => null,
          },
        ),
        SettingGroup.switchTile(
          title: Text(t.settings.fmNewTabPassthrough),
          value: setting.newTabPenetration,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabPenetration: v),
          ),
        ),
        SettingGroup.switchTile(
          title: Text(t.settings.fmNewTabShowHidden),
          value: setting.newTabShowHidden,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabShowHidden: v),
          ),
        ),
        SettingGroup.switchTile(
          title: Text(t.settings.fmNewTabShowInternal),
          value: setting.newTabShowChildNames,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabShowChildNames: v),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(t.settings.fmNewTabPresetHint),
        ),
      ],
    );
  }
}
