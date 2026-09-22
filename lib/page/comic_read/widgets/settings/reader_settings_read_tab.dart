part of 'reader_settings_sheet.dart';

class _ReaderSettingsReadTab extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;

  const _ReaderSettingsReadTab({
    required this.changePageIndex,
    this.onLandscapeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsTabContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadModeSection(
            changePageIndex: changePageIndex,
            onLandscapeChanged: onLandscapeChanged,
          ),
          const SizedBox(height: 18),
          const _SuperResolutionSection(),
          const SizedBox(height: 18),
          const _ThemeModeSection(),
          const SizedBox(height: 18),
          const _ReadBackgroundSection(),
          const SizedBox(height: 18),
          const _AutoReadSection(),
          const SizedBox(height: 18),
          const _PreloadSection(),
          const SizedBox(height: 18),
          const _ReadExperienceSection(),
          const SizedBox(height: 18),
          const _MediaFormatSection(),
          const SizedBox(height: 18),
          const _VideoSection(),
        ],
      ),
    );
  }
}

/// 「哪些后缀算图片 / 算视频」。
///
/// # 为什么单独一屏而不是塞进上面的视频段
///
/// 这张表判的是**文件管理器列不列一个条目**（`folder_tree::is_recognized_image_ext`
/// 在 Rust 侧），影响面是整库浏览，不是「这一页怎么播」。放错段的代价不是难看而已：
/// 用户要找的是「为什么这个文件看不见」，而它会在播放设置里被划过去。
///
/// # 语义是替换，不是追加
///
/// 照 neoview `media.ts:64-65`：**填了就整体替换内置表**，没列进来的后缀会连页都不算。
/// 留空才继续用内置默认。所以这两颗的提示必须把「填错不是多加一条，而是其余全不见」
/// 说在前面 —— 这是这次改动最容易自我伤害的一处。
/// 上面那段里原有的「自定义视频后缀」是**追加**档，两档并存：替换档定基线，
/// 追加档永远叠在基线之上。
///
/// 存在 `VideoSettingsStore`：两张表要和 `extraVideoExtensions` **同进同出**推给 Rust
/// （见 `VideoSettingsStore._apply`），拆成两个存储就会有一张表被推漏的那天。
class _MediaFormatSection extends StatefulWidget {
  const _MediaFormatSection();

  @override
  State<_MediaFormatSection> createState() => _MediaFormatSectionState();
}

class _MediaFormatSectionState extends State<_MediaFormatSection> {
  VideoSettings _settings = const VideoSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await VideoSettingsStore.instance.load();
    if (!mounted) return;
    setState(() => _settings = loaded);
  }

  Future<void> _write(VideoSettings next) async {
    setState(() => _settings = next);
    await VideoSettingsStore.instance.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: t.video.mediaSection,
      icon: Icons.folder_copy_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _StringListTile(
              title: t.video.imageFormats,
              hint: t.video.formatsHint,
              dialogHint: t.video.aliasesDialogHint,
              values: _settings.imageFormats,
              validate: (next) => mediaFormatTableProblems(
                image: next,
                video: _settings.videoFormats,
              ),
              onChanged: (next) =>
                  _write(_settings.copyWith(imageFormats: next)),
            ),
            _StringListTile(
              title: t.video.videoFormats,
              hint: t.video.formatsHint,
              dialogHint: t.video.aliasesDialogHint,
              values: _settings.videoFormats,
              validate: (next) => mediaFormatTableProblems(
                image: _settings.imageFormats,
                video: next,
              ),
              onChanged: (next) =>
                  _write(_settings.copyWith(videoFormats: next)),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadModeSection extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;

  const _ReadModeSection({
    required this.changePageIndex,
    this.onLandscapeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final isMobilePlatform =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !isTablet(context);
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.readingMode,
      icon: Icons.auto_stories_outlined,
      children: [
        _SettingsSegmentedTile<int>(
          selected: readSetting.readMode,
          segments: [
            ButtonSegment<int>(
              value: 0,
              icon: const Icon(Icons.view_agenda_outlined, size: 18),
              label: Text(t.reader.webtoon),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t.reader.readingDirectionRightOpen),
              ),
              tooltip: t.reader.readingDirectionRightOpen,
            ),
            ButtonSegment<int>(
              value: 2,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
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
        _SettingsCardGroup(
          children: [
            if (isMobilePlatform && onLandscapeChanged != null)
              _SettingsSwitchTile(
                title: t.reader.landscapeReader,
                subtitle: t.reader.landscapeReaderSubtitle,
                value: readSetting.landscapeReader,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(landscapeReader: value),
                  );
                  onLandscapeChanged!(value);
                },
              ),
            _SettingsSwitchTile(
              title: t.reader.doublePage,
              subtitle: t.reader.doublePageSubtitle,
              value: readSetting.doublePageMode,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(doublePageMode: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded:
                  readSetting.doublePageMode && readSetting.readMode != 0,
              child: _SettingsSwitchTile(
                title: t.reader.doublePageSeamless,
                subtitle: t.reader.doublePageSeamlessSubtitle,
                value: readSetting.doublePageSeamless,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(doublePageSeamless: value),
                  );
                },
              ),
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.doublePageMode,
              child: _SettingsSwitchTile(
                title: t.reader.doublePageLeadingBlank,
                subtitle: t.reader.doublePageLeadingBlankSubtitle,
                value: readSetting.doublePageLeadingBlank,
                onChanged: (value) {
                  globalSettingCubit.updateReadSetting(
                    (current) =>
                        current.copyWith(doublePageLeadingBlank: value),
                  );
                },
              ),
            ),
            _SettingsSwitchTile(
              title: t.reader.readingDirectionToggleSetting,
              subtitle: readSetting.readMode == 0
                  ? t.reader.readingDirectionToggleDisabled
                  : (readSetting.readMode == 2
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
            if (readSetting.readMode != 0)
              _SettingsSwitchTile(
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

class _ThemeModeSection extends StatelessWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: t.reader.themeMode,
      icon: Icons.light_mode_outlined,
      children: [
        _SettingsSegmentedTile<ThemeMode>(
          selected: globalSettingState.themeMode,
          segments: [
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined, size: 18),
              label: Text(t.common.lightMode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined, size: 18),
              label: Text(t.common.darkMode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_outlined, size: 18),
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

    return _SettingsSection(
      title: t.reader.autoRead,
      icon: Icons.play_circle_outline_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSwitchTile(
              title: t.reader.autoRead,
              subtitle: t.reader.autoReadSubtitle,
              value: readSetting.autoScroll,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(autoScroll: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.autoScroll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SettingsSwitchTile(
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
                  _SettingsSwitchTile(
                    title: t.reader.autoReadSmooth,
                    subtitle: t.reader.autoReadSmoothSubtitle,
                    value: readSetting.autoScrollSmooth,
                    onChanged: (value) {
                      globalSettingCubit.updateReadSetting(
                        (current) => current.copyWith(autoScrollSmooth: value),
                      );
                    },
                  ),
                  _SettingsSliderCard(
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
                  _SettingsSliderCard(
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
                  _SettingsSliderCard(
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

    return _SettingsSection(
      title: t.reader.preload,
      icon: Icons.downloading_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsDropdownTile(
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
            _SettingsDropdownTile(
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
            _SettingsSwitchTile(
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

    return _SettingsSection(
      title: t.reader.background,
      icon: Icons.palette_outlined,
      children: [
        _SettingsSegmentedTile<ReaderBackgroundMode>(
          selected: baseMode,
          segments: [
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.auto,
              icon: const Icon(Icons.brightness_auto_outlined, size: 18),
              label: Text(t.reader.auto),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.black,
              icon: const Icon(Icons.circle, size: 12, color: Colors.black),
              label: Text(t.reader.black),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.white,
              icon: const Icon(Icons.circle, size: 12, color: Colors.white),
              label: Text(t.reader.white),
            ),
            ButtonSegment<ReaderBackgroundMode>(
              value: ReaderBackgroundMode.grey,
              icon: const Icon(Icons.circle, size: 12, color: Colors.grey),
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
        _SettingsSwitchTile(
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
          _SettingsCardGroup(
            children: [
              _SettingsSegmentedTile<ReaderBackgroundMode>(
                selected: readSetting.readerBackgroundMode,
                segments: [
                  ButtonSegment<ReaderBackgroundMode>(
                    value: ReaderBackgroundMode.adaptive,
                    icon: const Icon(Icons.gradient_outlined, size: 18),
                    label: Text(t.reader.adaptive),
                  ),
                  ButtonSegment<ReaderBackgroundMode>(
                    value: ReaderBackgroundMode.adaptiveEdge,
                    icon: const Icon(Icons.gradient, size: 18),
                    label: Text(t.reader.adaptiveEdge),
                  ),
                ],
                onSelectionChanged: (mode) {
                  globalSettingCubit.updateReadSetting(
                    (current) => current.copyWith(readerBackgroundMode: mode),
                  );
                },
              ),
              _SettingsSliderCard(
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

class _ReadExperienceSection extends StatelessWidget {
  const _ReadExperienceSection();

  @override
  Widget build(BuildContext context) {
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final readSetting = globalSettingState.readSetting;

    return _SettingsSection(
      title: t.reader.readingExperience,
      icon: Icons.tune_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSwitchTile(
              title: t.reader.disableAnimation,
              subtitle: t.reader.disableAnimationSubtitle,
              value: readSetting.noAnimation,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(noAnimation: value),
                );
              },
            ),
            _SettingsSwitchTile(
              title: t.reader.readFilter,
              subtitle: t.reader.readFilterSubtitle,
              value: readSetting.readFilterEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readFilterEnabled: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.readFilterEnabled,
              child: _SettingsSliderCard(
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
            _SettingsSwitchTile(
              title: t.reader.einkOptimization,
              subtitle: t.reader.einkOptimizationSubtitle,
              value: readSetting.einkOptimization,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(einkOptimization: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.einkOptimization,
              child: _SettingsSliderCard(
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
            _SettingsSwitchTile(
              title: t.reader.sidePadding,
              subtitle: t.reader.sidePaddingSubtitle,
              value: readSetting.sidePaddingEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(sidePaddingEnabled: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.sidePaddingEnabled,
              child: _SettingsSliderCard(
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
            _SettingsSwitchTile(
              title: t.reader.hoverRevealEnabled,
              subtitle:
                  '${t.reader.hoverRevealEnabledSubtitle}（前往「${t.reader.gesture}」标签可微调）',
              value: readSetting.hoverRevealEnabled,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(hoverRevealEnabled: value),
                );
              },
            ),
            _SettingsSwitchTile(
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
            // 住在全局设置里，换书 / 换章 / 重启都保持（与上面两条同一口径）。
            _SettingsSwitchTile(
              title: t.reader.transparentTopBar,
              subtitle: t.reader.transparentTopBarSubtitle,
              value: readSetting.transparentTopBar,
              onChanged: (value) {
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(transparentTopBar: value),
                );
              },
            ),
            _SettingsAnimatedCollapse(
              isExpanded: readSetting.transparentTopBar,
              child: _SettingsSliderCard(
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
          ],
        ),
      ],
    );
  }
}

