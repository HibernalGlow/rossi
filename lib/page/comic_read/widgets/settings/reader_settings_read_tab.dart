part of 'reader_settings_sheet.dart';

/// 「阅读」这一排：这一本怎么翻、底色是什么、不想动手时让它自己走、
/// 下一张图从哪儿来。
class _ReaderSettingsReadTab extends StatelessWidget {
  final _ReaderSettingsArgs args;

  const _ReaderSettingsReadTab({required this.args});

  @override
  Widget build(BuildContext context) {
    return _SettingsTabContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadModeSection(args: args),
          const SizedBox(height: 18),
          const _ThemeModeSection(),
          const SizedBox(height: 18),
          const _ReadBackgroundSection(),
          const SizedBox(height: 18),
          const _AutoReadSection(),
          const SizedBox(height: 18),
          const _PreloadSection(),
        ],
      ),
    );
  }
}

class _ReadModeSection extends StatelessWidget {
  final _ReaderSettingsArgs args;

  const _ReadModeSection({required this.args});

  @override
  Widget build(BuildContext context) {
    final changePageIndex = args.changePageIndex;
    final onLandscapeChanged = args.onLandscapeChanged;
    final perComicAvailable = args.perComicAvailable;
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final isMobilePlatform =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !isTablet(context);
    final readSetting = globalSettingState.readSetting;
    // 本漫特定设置仅在阅读页入口（带 source/comicId）可用，全局设置页隐藏。
    final perComicState = perComicAvailable
        ? context.watch<ComicReadPreferenceCubit>().state
        : const ComicReadPreferenceState();
    final perComicEnabled = perComicAvailable && perComicState.hasOverride;
    // 有效阅读模式：启用本漫设置时用覆盖值，否则跟随全局。
    final effectiveReadMode =
        perComicState.overrideReadMode ??
        globalSettingState.readSetting.readMode;

    Future<void> selectPerComicReadMode(int mode) async {
      if (perComicState.overrideReadMode == mode) return;
      HapticFeedback.selectionClick();
      await context.read<ComicReadPreferenceCubit>().setOverride(mode);
      changePageIndex(0);
    }

    return SettingsSection(
      title: t.reader.readingMode,
      icon: AppGlyphs.openBook,
      children: [
        // 上游的「本漫独立阅读模式」：开关 + 展开的本漫选项，只在阅读页入口出现。
        if (perComicAvailable) ...[
          SettingsSwitchTile(
            title: t.reader.perComicReadMode,
            subtitle: t.reader.perComicReadModeSubtitle,
            value: perComicEnabled,
            onChanged: (value) async {
              HapticFeedback.selectionClick();
              final cubit = context.read<ComicReadPreferenceCubit>();
              if (value) {
                await cubit.setOverride(
                  globalSettingState.readSetting.readMode,
                );
              } else {
                await cubit.clearOverride();
              }
              changePageIndex(0);
            },
          ),
          // 开关打开后展开本漫独立选项，给出明确的展开/收起动效。
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: perComicEnabled
                ? _PerComicReadModeOptions(
                    overrideReadMode:
                        perComicState.overrideReadMode ??
                        globalSettingState.readSetting.readMode,
                    onSelect: selectPerComicReadMode,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        // 全局阅读模式：本仓沿用分段控件，改这里始终改全局。
        SettingsSegmentedTile<int>(
          selected: readSetting.readMode,
          segments: [
            ButtonSegment<int>(
              value: 0,
              icon: const GlyphIcon(AppGlyphs.viewAgenda, size: 18),
              label: Text(t.reader.webtoon),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: const GlyphIcon(AppGlyphs.arrowBack, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t.reader.readingDirectionRightOpen),
              ),
              tooltip: t.reader.readingDirectionRightOpen,
            ),
            ButtonSegment<int>(
              value: 2,
              icon: const GlyphIcon(AppGlyphs.arrowForward, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t.reader.readingDirectionLeftOpen),
              ),
              tooltip: t.reader.readingDirectionLeftOpen,
            ),
          ],
          onSelectionChanged: (mode) {
            final previousMode = readSetting.readMode;
            if (previousMode == mode) return;
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(readMode: mode),
            );
            if (previousMode == 0 || mode == 0) {
              changePageIndex(0);
            }
          },
        ),
        SettingsCardGroup(
          children: [
            if (isMobilePlatform && onLandscapeChanged != null)
              SettingsSwitchTile(
                title: t.reader.landscapeReader,
                subtitle: t.reader.landscapeReaderSubtitle,
                value: readSetting.landscapeReader,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(landscapeReader: value),
                  );
                  onLandscapeChanged(value);
                },
              ),
            SettingsSwitchTile(
              title: t.reader.doublePage,
              subtitle: t.reader.doublePageSubtitle,
              value: readSetting.doublePageMode,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(doublePageMode: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.doublePageMode && effectiveReadMode != 0,
              child: SettingsSwitchTile(
                title: t.reader.doublePageSeamless,
                subtitle: t.reader.doublePageSeamlessSubtitle,
                value: readSetting.doublePageSeamless,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(doublePageSeamless: value),
                  );
                  // 上游口径：拼缝改变页宽，得重算当前页索引。
                  changePageIndex(0);
                },
              ),
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.doublePageMode,
              child: SettingsSwitchTile(
                title: t.reader.doublePageLeadingBlank,
                subtitle: t.reader.doublePageLeadingBlankSubtitle,
                value: readSetting.doublePageLeadingBlank,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) =>
                        current.copyWith(doublePageLeadingBlank: value),
                  );
                  // 上游口径：首部空白格改变槽位，得重算当前页索引。
                  changePageIndex(0);
                },
              ),
            ),
            SettingsSwitchTile(
              title: t.reader.readingDirectionToggleSetting,
              subtitle: effectiveReadMode == 0
                  ? t.reader.readingDirectionToggleDisabled
                  : (effectiveReadMode == 2
                        ? t.reader.readingDirectionToggleLeftOpen
                        : t.reader.readingDirectionToggleRightOpen),
              value: readSetting.readingDirectionToggle,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readingDirectionToggle: value),
                );
              },
            ),
            // 条漫（readMode 0）里没有"翻页"这个动作，开关对它没有意义。
            // 判据用**有效**模式：这本开了独立模式时，跟着这本走。
            if (effectiveReadMode != 0)
              SettingsSwitchTile(
                title: t.reader.swipePreview,
                subtitle: t.reader.swipePreviewSubtitle,
                value: readSetting.swipePreviewEnabled,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(swipePreviewEnabled: value),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// 开关打开后展开的本漫独立选项卡。
///
/// 用高亮边框 + 全局对照文案明确告知用户“现在改的是本漫，不是全局”，
/// 配合外层 [AnimatedSize] 实现展开/收起动效。
class _PerComicReadModeOptions extends StatelessWidget {
  final int overrideReadMode;
  final Future<void> Function(int mode) onSelect;

  const _PerComicReadModeOptions({
    required this.overrideReadMode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(overrideReadMode),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SettingsChoiceChip(
                  title: t.reader.webtoon,
                  selected: overrideReadMode == 0,
                  onTap: () => onSelect(0),
                ),
                SettingsChoiceChip(
                  // 文案沿用本仓分段控件的那一份（上游的 singlePageLtr/Rtl 键
                  // 在本仓已被 readingDirection* 取代，这里不再新增键）。
                  title: t.reader.readingDirectionRightOpen,
                  selected: overrideReadMode == 1,
                  onTap: () => onSelect(1),
                ),
                SettingsChoiceChip(
                  title: t.reader.readingDirectionLeftOpen,
                  selected: overrideReadMode == 2,
                  onTap: () => onSelect(2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSection extends StatelessWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return SettingsSection(
      title: t.reader.themeMode,
      icon: AppGlyphs.sun,
      children: [
        SettingsSegmentedTile<ThemeMode>(
          selected: globalSettingState.themeMode,
          segments: [
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              icon: const GlyphIcon(AppGlyphs.sun, size: 18),
              label: Text(t.common.lightMode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              icon: const GlyphIcon(AppGlyphs.moon, size: 18),
              label: Text(t.common.darkMode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              icon: const GlyphIcon(AppGlyphs.brightnessAuto, size: 18),
              label: Text(t.common.followSystem),
            ),
          ],
          onSelectionChanged: (mode) {
            globalSettingCubit.updateState(
              (current) => current.copyWith(themeMode: mode),
            );
          },
        ),
      ],
    );
  }
}

class _AutoReadSection extends StatelessWidget {
  const _AutoReadSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return SettingsSection(
      title: t.reader.autoRead,
      icon: AppGlyphs.playCircle,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSwitchTile(
              title: t.reader.autoRead,
              subtitle: t.reader.autoReadSubtitle,
              value: readSetting.autoScroll,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(autoScroll: value),
                );
              },
            ),
            SettingsAnimatedCollapse(
              isExpanded: readSetting.autoScroll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSwitchTile(
                    title: t.reader.autoReadHidePauseButton,
                    subtitle: t.reader.autoReadHidePauseButtonSubtitle,
                    value: readSetting.autoScrollHidePauseButton,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) =>
                            current.copyWith(autoScrollHidePauseButton: value),
                      );
                    },
                  ),
                  SettingsSwitchTile(
                    title: t.reader.autoReadSmooth,
                    subtitle: t.reader.autoReadSmoothSubtitle,
                    value: readSetting.autoScrollSmooth,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(autoScrollSmooth: value),
                      );
                    },
                  ),
                  SettingsSliderCard(
                    title: t.reader.webtoonScrollDistance,
                    value: readSetting.autoScrollColumnDistancePercent.clamp(
                      10,
                      100,
                    ),
                    min: 10,
                    max: 100,
                    divisions: 90,
                    suffix: t.reader.screenHeightPercent,
                    onChanged: (value) {
                      final percent = value.clamp(10, 100);
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(
                          autoScrollColumnDistancePercent: percent,
                        ),
                      );
                    },
                  ),
                  SettingsSliderCard(
                    title: t.reader.webtoonScrollInterval,
                    value: readSetting.autoScrollColumnIntervalMs.clamp(
                      300,
                      5000,
                    ),
                    min: 300,
                    max: 5000,
                    divisions: 47,
                    suffix: t.reader.milliseconds,
                    onChanged: (value) {
                      final intervalMs = value.clamp(300, 5000);
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(
                          autoScrollColumnIntervalMs: intervalMs,
                        ),
                      );
                    },
                  ),
                  SettingsSliderCard(
                    title: t.reader.singlePageScrollInterval,
                    value: readSetting.autoScrollPageIntervalMs.clamp(
                      800,
                      10000,
                    ),
                    min: 800,
                    max: 10000,
                    divisions: 92,
                    suffix: t.reader.milliseconds,
                    onChanged: (value) {
                      final intervalMs = value.clamp(800, 10000);
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(
                          autoScrollPageIntervalMs: intervalMs,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreloadSection extends StatelessWidget {
  const _PreloadSection();

  @override
  Widget build(BuildContext context) {
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return SettingsSection(
      title: t.reader.preload,
      icon: AppGlyphs.downloading,
      children: [
        SettingsCardGroup(
          children: [
            SettingsDropdownTile(
              title: t.reader.preloadImageCount,
              subtitle: t.reader.preloadImageCountSubtitle,
              value: readSetting.preloadImageCount.clamp(2, 10).toInt(),
              values: List<int>.generate(9, (index) => index + 2),
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(preloadImageCount: value),
                );
              },
            ),
            SettingsDropdownTile(
              title: t.reader.preloadChapterCount,
              subtitle: t.reader.preloadChapterCountSubtitle,
              value: readSetting.preloadChapterCount.clamp(1, 3).toInt(),
              values: List<int>.generate(3, (index) => index + 1),
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(preloadChapterCount: value),
                );
              },
            ),
            SettingsSwitchTile(
              title: t.reader.readWhileDownloading,
              subtitle: t.reader.readWhileDownloadingSubtitle,
              value: readSetting.readWhileDownloading,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readWhileDownloading: value),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadBackgroundSection extends StatelessWidget {
  const _ReadBackgroundSection();

  @override
  Widget build(BuildContext context) {
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    // 自适应档位下，下面这条「底色」选段显示的是**兜底色** —— 也就是取色还没到、
    // 或这一本不是本地漫画时看到的那个颜色。显示成 `auto` 与
    // `resolveReaderBackgroundColor` 对自适应档位的返回值一致，不是随便挑的。
    final ReaderBackgroundMode baseMode = readSetting.readerAmbientEnabled
        ? ReaderBackgroundMode.auto
        : readSetting.readerBackgroundMode;

    return SettingsSection(
      title: t.reader.background,
      icon: AppGlyphs.palette,
      children: [
        SettingsSegmentedTile<ReaderBackgroundMode>(
          selected: baseMode,
          segments: [
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.auto,
              icon: const GlyphIcon(AppGlyphs.brightnessAuto, size: 18),
              label: Text(t.reader.auto),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.black,
              icon: const GlyphIcon(AppGlyphs.dot, size: 12, color: Colors.black),
              label: Text(t.reader.black),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.white,
              icon: const GlyphIcon(AppGlyphs.dot, size: 12, color: Colors.white),
              label: Text(t.reader.white),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.grey,
              icon: const GlyphIcon(AppGlyphs.dot, size: 12, color: Colors.grey),
              label: Text(t.reader.grey),
            ),
          ],
          onSelectionChanged: (mode) {
            // 选固定底色**同时**关掉自适应：两者是互斥的一档，
            // 让它们同时"开着"会让用户看到一条选了却没生效的设置。
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(readerBackgroundMode: mode),
            );
          },
        ),
        SettingsSwitchTile(
          title: t.reader.adaptive,
          subtitle: t.reader.ambientDimSubtitle,
          value: readSetting.readerAmbientEnabled,
          onChanged: (enabled) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(
                readerBackgroundMode: enabled
                    ? ReaderBackgroundMode.adaptive
                    : ReaderBackgroundMode.auto,
              ),
            );
          },
        ),
        if (readSetting.readerAmbientEnabled)
          SettingsCardGroup(
            children: [
              SettingsSegmentedTile<ReaderBackgroundMode>(
                selected: readSetting.readerBackgroundMode,
                segments: [
                  ButtonSegment<ReaderBackgroundMode>(
                    value: ReaderBackgroundMode.adaptive,
                    icon: const GlyphIcon(AppGlyphs.gradient, size: 18),
                    label: Text(t.reader.adaptive),
                  ),
                  ButtonSegment<ReaderBackgroundMode>(
                    value: ReaderBackgroundMode.adaptiveEdge,
                    icon: const GlyphIcon(AppGlyphs.gradient, size: 18),
                    label: Text(t.reader.adaptiveEdge),
                  ),
                ],
                onSelectionChanged: (mode) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(readerBackgroundMode: mode),
                  );
                },
              ),
              SettingsSliderCard(
                title: t.reader.ambientDim,
                value: readSetting.readerAmbientDimPercent.clamp(
                  readerAmbientDimPercentMin,
                  readerAmbientDimPercentMax,
                ),
                min: readerAmbientDimPercentMin,
                max: readerAmbientDimPercentMax,
                divisions:
                    readerAmbientDimPercentMax - readerAmbientDimPercentMin,
                suffix: '%',
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(
                      readerAmbientDimPercent: value.clamp(
                        readerAmbientDimPercentMin,
                        readerAmbientDimPercentMax,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }
}
