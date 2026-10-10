part of 'reader_settings_sheet.dart';

/// 「界面」这一排：画面边上那些**叠加出来的东西** —— 页码信息条、底边进度条、
/// 缩略图条、顶栏玻璃、左右留白。判据是「关掉这一排，漫画本身一个像素都没变」。
class _ReaderSettingsScreenTab extends StatelessWidget {
  final _ReaderSettingsArgs args;

  const _ReaderSettingsScreenTab({required this.args});

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
          SizedBox(height: 14),
          _ReaderChromeSection(),
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

    return SettingsSection(
      title: t.reader.infoDisplay,
      icon: AppGlyphs.info,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.pageNumber,
              subtitle: t.reader.pageNumberSubtitle,
              value: readSetting.pageInfoShowPage,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowPage: value),
                );
              },
            ),
            SettingsSwitchTile(
              title: t.reader.networkStatus,
              subtitle: t.reader.networkStatusSubtitle,
              value: readSetting.pageInfoShowNetwork,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowNetwork: value),
                );
              },
            ),
            SettingsSwitchTile(
              title: t.reader.battery,
              subtitle: t.reader.batterySubtitle,
              value: readSetting.pageInfoShowBattery,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(pageInfoShowBattery: value),
                );
              },
            ),
            SettingsSwitchTile(
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
        if (allHidden) SettingsNoticeCard(text: t.reader.allHiddenNotice),
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

    return SettingsSection(
      title: t.reader.infoBarPosition,
      icon: AppGlyphs.place,
      children: [
        SettingsSegmentedTile<ReaderInfoVerticalPosition>(
          selected: readSetting.pageInfoVerticalPosition,
          segments: [
            ButtonSegment<ReaderInfoVerticalPosition>(
              value: ReaderInfoVerticalPosition.top,
              icon: const GlyphIcon(AppGlyphs.vAlignTop, size: 18),
              label: Text(t.reader.verticalPositionTop),
            ),
            ButtonSegment<ReaderInfoVerticalPosition>(
              value: ReaderInfoVerticalPosition.bottom,
              icon: const GlyphIcon(AppGlyphs.vAlignBottom, size: 18),
              label: Text(t.reader.verticalPositionBottom),
            ),
          ],
          onSelectionChanged: (pos) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(pageInfoVerticalPosition: pos),
            );
          },
        ),
        SettingsAnimatedCollapse(
          isExpanded:
              readSetting.pageInfoVerticalPosition ==
              ReaderInfoVerticalPosition.top,
          showDivider: false,
          child: SettingsCardGroup(
            children: [
              SettingsSwitchTile(
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
        SettingsSegmentedTile<ReaderInfoHorizontalPosition>(
          selected: readSetting.pageInfoHorizontalPosition,
          segments: [
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.left,
              icon: const GlyphIcon(AppGlyphs.alignLeft, size: 18),
              label: Text(t.reader.horizontalPositionLeft),
            ),
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.center,
              icon: const GlyphIcon(AppGlyphs.alignCenter, size: 18),
              label: Text(t.reader.horizontalPositionCenter),
            ),
            ButtonSegment<ReaderInfoHorizontalPosition>(
              value: ReaderInfoHorizontalPosition.right,
              icon: const GlyphIcon(AppGlyphs.alignRight, size: 18),
              label: Text(t.reader.horizontalPositionRight),
            ),
          ],
          onSelectionChanged: (pos) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(pageInfoHorizontalPosition: pos),
            );
          },
        ),
        SettingsCardGroup(
          children: [
            SettingsSliderCard(
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
          SettingsNoticeCard(text: t.reader.edgePaddingDisabled),
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

    return SettingsSection(
      title: t.reader.infoBarStyle,
      icon: AppGlyphs.textSize,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSliderCard(
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
            SettingsSliderCard(
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

/// 阅读器上下栏与画面边距。
///
/// 从原来那一整段「阅读体验」里拆出来的界面那一半：缩略图条、顶栏玻璃、
/// 左右留白。另一半（滤镜 / 墨水屏 / 禁用动画）改的是**像素本身**，去了「画面」排。
/// 混在一排时用户找「顶栏太花」要翻一整屏跟画质无关的开关。
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
