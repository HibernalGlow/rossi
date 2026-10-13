import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

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
      ValueChanged<T> change,
    ) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final choice in choices.entries)
            DropdownMenuItem(value: choice.key, child: Text(choice.value)),
        ],
        onChanged: (value) {
          if (value != null) change(value);
        },
      ),
    );
    return SettingSectionCard(
      title: '新页签启动选项',
      icon: AppGlyphs.layoutTabs,
      children: [
        select(
          '选项来源',
          setting.newTabPolicy,
          {
            for (final policy in FileManagerTabStartupPolicy.values)
              policy: policy.label,
          },
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabPolicy: value),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '“最近使用”跟随当前活跃页签；“触发页签”跟随发起动作的页签。只继承浏览与搜索选项，查询、结果、历史和选中项各自独立。首次打开没有继承来源时使用预设。',
          ),
        ),
        select(
          '默认条目样式',
          LibraryViewMode.values.any((m) => m.name == setting.newTabViewMode)
              ? setting.newTabViewMode
              : 'compact',
          {for (final mode in LibraryViewMode.values) mode.name: mode.label},
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabViewMode: value),
          ),
        ),
        select(
          '默认内容布局',
          const [
                'content',
                'tree',
                'columns',
              ].contains(setting.newTabLayoutMode)
              ? setting.newTabLayoutMode
              : 'content',
          const {'content': '内容视图', 'tree': '树形视图', 'columns': '分栏视图'},
          (value) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabLayoutMode: value),
          ),
        ),
        SwitchListTile(
          title: const Text('默认启用穿透'),
          thumbIcon: kSettingSwitchThumbIcon,
          value: setting.newTabPenetration,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabPenetration: v),
          ),
        ),
        SwitchListTile(
          title: const Text('默认显示隐藏项'),
          thumbIcon: kSettingSwitchThumbIcon,
          value: setting.newTabShowHidden,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabShowHidden: v),
          ),
        ),
        SwitchListTile(
          title: const Text('默认显示内部条目'),
          thumbIcon: kSettingSwitchThumbIcon,
          value: setting.newTabShowChildNames,
          onChanged: (v) => cubit.updateFileManagerSetting(
            (s) => s.copyWith(newTabShowChildNames: v),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('预设默认值仅在“使用预设默认值”时采用；默认递归范围沿用下方搜索设置。复制与恢复已关闭页签保留原有设置。'),
        ),
      ],
    );
  }
}
