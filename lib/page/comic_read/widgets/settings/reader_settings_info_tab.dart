part of 'reader_settings_sheet.dart';

class _ReaderSettingsInfoTab extends StatelessWidget {
  const _ReaderSettingsInfoTab();

  @override
  Widget build(BuildContext context) {
    return const _SettingsTabContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageInfoVisibilitySection(),
          SizedBox(height: 14),
          _PageInfoPlacementSection(),
          SizedBox(height: 14),
          _PageInfoAppearanceSection(),
          SizedBox(height: 14),
          _BottomProgressBarSection(),
        ],
      ),
    );
  }
}

/// 底边常驻进度条
class _BottomProgressBarSection extends StatelessWidget {
  const _BottomProgressBarSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.bottomProgressBar,
      icon: Icons.linear_scale_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSwitchTile(
              title: t.reader.bottomProgressBar,
              subtitle: t.reader.bottomProgressBarSubtitle,
              value: readSetting.showBottomProgressBar,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(showBottomProgressBar: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.showBottomProgressBar,
              child: _SettingsSwitchTile(
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

class _PageInfoVisibilitySection extends StatelessWidget {
  const _PageInfoVisibilitySection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;
    final allHidden =
        !readSetting.pageInfoShowPage &&
        !readSetting.pageInfoShowNetwork &&
        !readSetting.pageInfoShowBattery &&
        !readSetting.pageInfoShowTime;

    return _SettingsSection(
      title: t.reader.infoDisplay,
      icon: Icons.info_outline_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSwitchTile(
              title: t.reader.pageNumber,
              subtitle: t.reader.pageNumberSubtitle,
              value: readSetting.pageInfoShowPage,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowPage: value),
                );
              },
            ),
            _SettingsSwitchTile(
              title: t.reader.networkStatus,
              subtitle: t.reader.networkStatusSubtitle,
              value: readSetting.pageInfoShowNetwork,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowNetwork: value),
                );
              },
            ),
            _SettingsSwitchTile(
              title: t.reader.battery,
              subtitle: t.reader.batterySubtitle,
              value: readSetting.pageInfoShowBattery,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowBattery: value),
                );
              },
            ),
            _SettingsSwitchTile(
              title: t.reader.time,
              subtitle: t.reader.timeSubtitle,
              value: readSetting.pageInfoShowTime,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowTime: value),
                );
              },
            ),
          ],
        ),
        if (allHidden) _SettingsNoticeCard(text: t.reader.allHiddenNotice),
      ],
    );
  }
}

class _PageInfoPlacementSection extends StatelessWidget {
  const _PageInfoPlacementSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;
    final isHorizontalCenter =
        readSetting.pageInfoHorizontalPosition ==
        ReaderInfoHorizontalPosition.center;

    return _SettingsSection(
      title: t.reader.infoBarPosition,
      icon: Icons.place_outlined,
      children: [
        _SettingsSegmentedTile<ReaderInfoVerticalPosition>(
          selected: readSetting.pageInfoVerticalPosition,
          segments: [
            ButtonSegment<ReaderInfoVerticalPosition>(
              value: ReaderInfoVerticalPosition.top,
              icon: const Icon(Icons.vertical_align_top_rounded, size: 18),
              label: Text(t.reader.verticalPositionTop),
            ),
            ButtonSegment<ReaderInfoVerticalPosition>(
              value: ReaderInfoVerticalPosition.bottom,
              icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
              label: Text(t.reader.verticalPositionBottom),
            ),
          ],
          onSelectionChanged: (pos) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(pageInfoVerticalPosition: pos),
            );
          },
        ),
        _SettingsAnimatedCollapse(
          isExpanded:
              readSetting.pageInfoVerticalPosition ==
              ReaderInfoVerticalPosition.top,
          showDivider: false,
          child: _SettingsCardGroup(
            children: [
              _SettingsSwitchTile(
                title: t.reader.showInStatusBar,
                subtitle: t.reader.showInStatusBarSubtitle,
                value: readSetting.pageInfoTopInStatusBar,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) =>
                        current.copyWith(pageInfoTopInStatusBar: value),
                  );
                },
              ),
            ],
          ),
        ),
        _SettingsSegmentedTile<ReaderInfoHorizontalPosition>(
          selected: readSetting.pageInfoHorizontalPosition,
          segments: [
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.left,
              icon: const Icon(Icons.format_align_left_rounded, size: 18),
              label: Text(t.reader.horizontalPositionLeft),
            ),
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.center,
              icon: const Icon(Icons.format_align_center_rounded, size: 18),
              label: Text(t.reader.horizontalPositionCenter),
            ),
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.right,
              icon: const Icon(Icons.format_align_right_rounded, size: 18),
              label: Text(t.reader.horizontalPositionRight),
            ),
          ],
          onSelectionChanged: (pos) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(pageInfoHorizontalPosition: pos),
            );
          },
        ),
        _SettingsCardGroup(
          children: [
            _SettingsSliderCard(
              title: t.reader.edgePadding,
              value: readSetting.pageInfoEdgePadding.clamp(0, 48),
              min: 0,
              max: 48,
              divisions: 48,
              suffix: t.reader.pixels,
              enabled: !isHorizontalCenter,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoEdgePadding: value),
                );
              },
            ),
          ],
        ),
        if (isHorizontalCenter)
          _SettingsNoticeCard(text: t.reader.edgePaddingDisabled),
      ],
    );
  }
}

class _PageInfoAppearanceSection extends StatelessWidget {
  const _PageInfoAppearanceSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.infoBarStyle,
      icon: Icons.format_size_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSliderCard(
              title: t.reader.backgroundOpacity,
              value: readSetting.pageInfoOpacityPercent.clamp(20, 100),
              min: 20,
              max: 100,
              divisions: 80,
              suffix: t.reader.percent,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoOpacityPercent: value),
                );
              },
            ),
            _SettingsSliderCard(
              title: t.reader.fontSize,
              value: readSetting.pageInfoFontSize.clamp(10, 20),
              min: 10,
              max: 20,
              divisions: 10,
              suffix: t.reader.pixels,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoFontSize: value),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
