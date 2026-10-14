import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/auto_trim_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/icons/icons.dart';

/// 滤镜 / 墨水屏 / 禁用动画：三颗都会让画面和原图不一样。
///
/// 读写都走 `GlobalSettingCubit.state.readSetting`，与阅读设置面板那一排是
/// **同一个 cubit 的同一份状态**，所以两边不需要任何同步。
class ImageTuningSection extends StatelessWidget {
  const ImageTuningSection({super.key});

  @override
  Widget build(BuildContext context) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;

    return SettingsSection(
      title: t.reader.tuningSection,
      icon: AppGlyphs.wand,
      children: [
        const AutoTrimSection(),
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.disableAnimation,
              subtitle: t.reader.disableAnimationSubtitle,
              value: readSetting.noAnimation,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(noAnimation: value),
                );
              },
            ),
            SettingsSwitchTile(
              title: t.reader.readFilter,
              subtitle: t.reader.readFilterSubtitle,
              value: readSetting.readFilterEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readFilterEnabled: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.readFilterEnabled,
              child: SettingsSliderCard(
                title: t.reader.filterIntensity,
                value: readSetting.readFilterOpacityPercent.clamp(0, 100),
                min: 0,
                max: 100,
                divisions: 100,
                suffix: t.reader.percent,
                onChanged: (value) {
                  final percent = value.clamp(0, 100);
                  globalSettingCubit.updateReadSetting(
                    (current) =>
                        current.copyWith(readFilterOpacityPercent: percent),
                  );
                },
              ),
            ),
            SettingsSwitchTile(
              title: t.reader.einkOptimization,
              subtitle: t.reader.einkOptimizationSubtitle,
              value: readSetting.einkOptimization,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(einkOptimization: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.einkOptimization,
              child: SettingsSliderCard(
                title: t.reader.einkDelay,
                value: readSetting.einkDelayMs.clamp(50, 500),
                min: 50,
                max: 500,
                divisions: 45,
                suffix: t.reader.milliseconds,
                onChanged: (value) {
                  final delayMs = value.clamp(50, 500);
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(einkDelayMs: delayMs),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
