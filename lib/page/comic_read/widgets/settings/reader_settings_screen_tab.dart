part of 'reader_settings_sheet.dart';

class _BottomProgressBarSection extends StatelessWidget {
  const _BottomProgressBarSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return SettingsSection(
      title: t.reader.bottomProgressBar,
      icon: AppGlyphs.linearScale,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.bottomProgressBar,
              subtitle: t.reader.bottomProgressBarSubtitle,
              value: readSetting.showBottomProgressBar,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(showBottomProgressBar: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.showBottomProgressBar,
              child: SettingsSwitchTile(
                title: t.reader.bottomProgressBarGlow,
                subtitle: t.reader.bottomProgressBarGlowSubtitle,
                value: readSetting.bottomProgressBarGlow,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(bottomProgressBarGlow: value),
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

class _ReaderChromeSection extends StatelessWidget {
  const _ReaderChromeSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;

    return SettingsSection(
      title: t.reader.chromeSection,
      icon: AppGlyphs.cropSquare,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.thumbnailStrip,
              subtitle: t.reader.thumbnailStripSubtitle,
              value: readSetting.showThumbnailStrip,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(showThumbnailStrip: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.showThumbnailStrip,
              child: SettingsSwitchTile(
                title: t.reader.thumbnailStripOriginalAspectRatio,
                subtitle: t.reader.thumbnailStripOriginalAspectRatioSubtitle,
                value: readSetting.thumbnailStripOriginalAspectRatio,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(
                      thumbnailStripOriginalAspectRatio: value,
                    ),
                  );
                },
              ),
            ),
            // 顶栏「透明」档：跳过玻璃，只留一层半透明蒙层。
            // 住在全局设置里，换书 / 换章 / 重启都保持。
            SettingsSwitchTile(
              title: t.reader.transparentTopBar,
              subtitle: t.reader.transparentTopBarSubtitle,
              value: readSetting.transparentTopBar,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(transparentTopBar: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.transparentTopBar,
              child: SettingsSliderCard(
                title: t.reader.transparentTopBarOpacity,
                value: clampReaderTopBarOpacityPercent(
                  readSetting.topBarScrimOpacityPercent,
                ),
                min: ReaderTopBarStyleLimits.minOpacityPercent,
                max: ReaderTopBarStyleLimits.maxOpacityPercent,
                divisions: 100,
                suffix: t.reader.percent,
                onChanged: (value) {
                  final percent = clampReaderTopBarOpacityPercent(value);
                  globalSettingCubit.updateReadSetting(
                    (current) =>
                        current.copyWith(topBarScrimOpacityPercent: percent),
                  );
                },
              ),
            ),
            SettingsSwitchTile(
              title: t.reader.sidePadding,
              subtitle: t.reader.sidePaddingSubtitle,
              value: readSetting.sidePaddingEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(sidePaddingEnabled: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.sidePaddingEnabled,
              child: SettingsSliderCard(
                title: t.reader.sidePaddingPercent,
                value: readSetting.sidePaddingPercent.clamp(0, 30),
                min: 0,
                max: 30,
                divisions: 30,
                suffix: t.reader.percent,
                onChanged: (value) {
                  final percent = value.clamp(0, 30);
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(sidePaddingPercent: percent),
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
