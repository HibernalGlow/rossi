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
        ],
      ),
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

    return _SettingsSection(
      title: t.reader.readingMode,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SettingsChoiceChip(
              title: t.reader.webtoon,
              selected: globalSettingState.readSetting.readMode == 0,
              onTap: () {
                if (globalSettingState.readSetting.readMode == 0) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readMode: 0),
                );
                changePageIndex(0);
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.readingDirectionRightOpen,
              selected: globalSettingState.readSetting.readMode == 1,
              onTap: () {
                final previousMode = globalSettingState.readSetting.readMode;
                if (previousMode == 1) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readMode: 1),
                );
                // 右开 ⇄ 左开（1↔2）同属 RowModeWidget，槽位含义不变，
                // 不清零位置 —— 以前这里跟着 `changePageIndex(0)`，等于
                // 切个方向就跳回第一页。只有条漫↔横向（0↔1/2）是重建式
                // 切换，需要归位。
                if (previousMode == 0) {
                  changePageIndex(0);
                }
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.readingDirectionLeftOpen,
              selected: globalSettingState.readSetting.readMode == 2,
              onTap: () {
                final previousMode = globalSettingState.readSetting.readMode;
                if (previousMode == 2) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readMode: 2),
                );
                if (previousMode == 0) {
                  changePageIndex(0);
                }
              },
            ),
          ],
        ),
        if (isMobilePlatform && onLandscapeChanged != null)
          _SettingsSwitchTile(
            title: t.reader.landscapeReader,
            subtitle: t.reader.landscapeReaderSubtitle,
            value: globalSettingState.readSetting.landscapeReader,
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
          value: globalSettingState.readSetting.doublePageMode,
          onChanged: (value) {
            // 单/双页换的是槽位切法，不换「看的是哪张图」：位置由阅读器按同一张
            // 图重算（`_syncPairingLayoutChange`），不在这里清零 —— 以前这里跟一句
            // `changePageIndex(0)`，就是「切一下单双页，页数跳回开头」。
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(doublePageMode: value),
            );
          },
        ),
        if (globalSettingState.readSetting.doublePageMode &&
            globalSettingState.readSetting.readMode != 0)
          _SettingsSwitchTile(
            title: t.reader.doublePageSeamless,
            subtitle: t.reader.doublePageSeamlessSubtitle,
            value: globalSettingState.readSetting.doublePageSeamless,
            onChanged: (value) {
              // 无缝只改两张图之间留不留缝，配对与槽位都不变。
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(doublePageSeamless: value),
              );
            },
          ),
        if (globalSettingState.readSetting.doublePageMode)
          _SettingsSwitchTile(
            title: t.reader.doublePageLeadingBlank,
            subtitle: t.reader.doublePageLeadingBlankSubtitle,
            value: globalSettingState.readSetting.doublePageLeadingBlank,
            onChanged: (value) {
              // 首页留白会让每段图片整体错一位（配对变了），同样交给阅读器重算位置。
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(doublePageLeadingBlank: value),
              );
            },
          ),
        _SettingsSwitchTile(
          title: t.reader.readingDirectionToggleSetting,
          subtitle: t.reader.readingDirectionToggle,
          value: globalSettingState.readSetting.readingDirectionToggle,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(readingDirectionToggle: value),
            );
          },
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
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SettingsChoiceChip(
              title: t.common.lightMode,
              selected: globalSettingState.themeMode == ThemeMode.light,
              onTap: () {
                if (globalSettingState.themeMode == ThemeMode.light) {
                  return;
                }
                globalSettingCubit.updateState(
                  (current) => current.copyWith(themeMode: ThemeMode.light),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.common.darkMode,
              selected: globalSettingState.themeMode == ThemeMode.dark,
              onTap: () {
                if (globalSettingState.themeMode == ThemeMode.dark) {
                  return;
                }
                globalSettingCubit.updateState(
                  (current) => current.copyWith(themeMode: ThemeMode.dark),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.common.followSystem,
              selected: globalSettingState.themeMode == ThemeMode.system,
              onTap: () {
                if (globalSettingState.themeMode == ThemeMode.system) {
                  return;
                }
                globalSettingCubit.updateState(
                  (current) => current.copyWith(themeMode: ThemeMode.system),
                );
              },
            ),
          ],
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
        if (readSetting.autoScroll)
          _SettingsSwitchTile(
            title: t.reader.autoReadHidePauseButton,
            subtitle: t.reader.autoReadHidePauseButtonSubtitle,
            value: readSetting.autoScrollHidePauseButton,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(autoScrollHidePauseButton: value),
              );
            },
          ),
        if (readSetting.autoScroll)
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
        if (readSetting.autoScroll)
          _SettingsSliderCard(
            title: t.reader.webtoonScrollDistance,
            value: readSetting.autoScrollColumnDistancePercent.clamp(10, 100),
            min: 10,
            max: 100,
            divisions: 90,
            suffix: t.reader.screenHeightPercent,
            onChanged: (value) {
              final percent = value.clamp(10, 100);
              globalSettingCubit.updateReadSetting(
                (current) =>
                    current.copyWith(autoScrollColumnDistancePercent: percent),
              );
            },
          ),
        if (readSetting.autoScroll)
          _SettingsSliderCard(
            title: t.reader.webtoonScrollInterval,
            value: readSetting.autoScrollColumnIntervalMs.clamp(300, 5000),
            min: 300,
            max: 5000,
            divisions: 47,
            suffix: t.reader.milliseconds,
            onChanged: (value) {
              final intervalMs = value.clamp(300, 5000);
              globalSettingCubit.updateReadSetting(
                (current) =>
                    current.copyWith(autoScrollColumnIntervalMs: intervalMs),
              );
            },
          ),
        if (readSetting.autoScroll)
          _SettingsSliderCard(
            title: t.reader.singlePageScrollInterval,
            value: readSetting.autoScrollPageIntervalMs.clamp(800, 10000),
            min: 800,
            max: 10000,
            divisions: 92,
            suffix: t.reader.milliseconds,
            onChanged: (value) {
              final intervalMs = value.clamp(800, 10000);
              globalSettingCubit.updateReadSetting(
                (current) =>
                    current.copyWith(autoScrollPageIntervalMs: intervalMs),
              );
            },
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
    );
  }
}

class _ReadBackgroundSection extends StatelessWidget {
  const _ReadBackgroundSection();

  @override
  Widget build(BuildContext context) {
    final readSetting = context.watch<GlobalSettingCubit>().state.readSetting;
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: t.reader.background,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SettingsChoiceChip(
              title: t.reader.auto,
              selected:
                  readSetting.readerBackgroundMode == ReaderBackgroundMode.auto,
              onTap: () {
                if (readSetting.readerBackgroundMode ==
                    ReaderBackgroundMode.auto) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    readerBackgroundMode: ReaderBackgroundMode.auto,
                  ),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.black,
              selected:
                  readSetting.readerBackgroundMode ==
                  ReaderBackgroundMode.black,
              onTap: () {
                if (readSetting.readerBackgroundMode ==
                    ReaderBackgroundMode.black) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    readerBackgroundMode: ReaderBackgroundMode.black,
                  ),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.white,
              selected:
                  readSetting.readerBackgroundMode ==
                  ReaderBackgroundMode.white,
              onTap: () {
                if (readSetting.readerBackgroundMode ==
                    ReaderBackgroundMode.white) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    readerBackgroundMode: ReaderBackgroundMode.white,
                  ),
                );
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.grey,
              selected:
                  readSetting.readerBackgroundMode == ReaderBackgroundMode.grey,
              onTap: () {
                if (readSetting.readerBackgroundMode ==
                    ReaderBackgroundMode.grey) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(
                    readerBackgroundMode: ReaderBackgroundMode.grey,
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
        if (readSetting.readFilterEnabled)
          _SettingsSliderCard(
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
        if (readSetting.einkOptimization)
          _SettingsSliderCard(
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
        if (readSetting.sidePaddingEnabled)
          _SettingsSliderCard(
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
        _SettingsSwitchTile(
          title: t.reader.hoverRevealEnabled,
          subtitle:
              '${t.reader.hoverRevealEnabledSubtitle}（前往「${t.reader.gesture}」标签可微调感应区与延时）',
          value: readSetting.hoverRevealEnabled,
          onChanged: (value) {
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(hoverRevealEnabled: value),
            );
          },
        ),
        // 和底栏那个相册按钮是同一个开关：开关状态住在全局设置里，
        // 所以换书 / 换章 / 重启都保持，不会再「开一本新的就收起」。
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
      ],
    );
  }
}

/// 阅读器设置里的「AI 超分辨率」。
///
/// **两条来源的控件不是同一套，不能合成一个：**
///
/// - **本地归档 / 文件夹**（GPU 呈现会话）：超分的开关是**呈现器**自己的
///   `GpuPresentController.isUpscaleEnabled`（启动时从持久化的「自动超分」初始化，
///   见 `_initUpscaleSetting`）。也只有这条有「对比原图」可言 —— 呈现器同时握着
///   原图与超分图两张纹理。
/// - **网络来源**（插件漫画）：**没有呈现器**，超分发生在图片文件的下载/缓存层
///   （`getCachePicture` → `RealSrSuperResolution.upscaleAndConvertToWebp`），
///   唯一的总闸是全局设置里的「自动超分」。这一路原先在阅读器里**一个控件都没有**，
///   于是出现「日志明明在超分，开关却哪儿都找不到」。
///
/// **超分条件（分辨率阈值）两条路都吃**：呈现器在 `gpu_present_controller.dart`
/// 调 `shouldUpscale`，文件层在 `upscaleAndConvertToWebp` 里也调它，二者最终都读
/// `RealSrSettings.loadResolutionThreshold()`。所以它**不分来源**，一直是显示的。
///
/// 判「当前是哪条」用 `LocalReadSession`：本地阅读器 `dispose()` 时会连会话一起释放
/// （`comic_read.dart`），所以**根本没有呈现器**就是网络来源。三种状态分开处理：
///
/// | 状态 | 显示什么 |
/// |---|---|
/// | 有呈现器且就绪 | 呈现器开关 + 对比原图 |
/// | **没有呈现器**（网络来源） | 全局「自动超分」开关 |
/// | 有呈现器但未就绪 | **不给全局开关** —— 那条开关管不到呈现器这条路，放上去等于撒谎 |
///
/// 分辨率阈值在前三种状态下都显示（两条执行路都读它）。
/// 代价是工作台里两条泳道各开一本书（一本地一网络）时会话是共用的，会退化成
/// 「按先打开的那条算」—— 那是既有全局单例的遗留问题，不在本次范围。
class _SuperResolutionSection extends StatefulWidget {
  const _SuperResolutionSection();

  @override
  State<_SuperResolutionSection> createState() =>
      _SuperResolutionSectionState();
}

class _SuperResolutionSectionState extends State<_SuperResolutionSection> {
  bool _loading = true;
  bool _autoUpscale = false;
  RealSrResolutionThreshold _threshold = RealSrResolutionThreshold.p720;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final auto = await RealSrSettings.loadAutoUpscale();
      final threshold = await RealSrSettings.loadResolutionThreshold();
      final modelReady = await RealSrSuperResolution.isAvailable;
      if (!mounted) return;
      setState(() {
        _autoUpscale = auto;
        _threshold = threshold;
        _modelReady = modelReady;
        _loading = false;
      });
    } catch (_) {
      // 读设置失败也要落地：否则这块永远停在未加载态，用户看到的是「控件不见了」。
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAutoUpscale(bool value) async {
    // 先动 UI 再落盘：写盘失败也不至于点了没反应。
    setState(() => _autoUpscale = value);
    try {
      await RealSrSettings.saveAutoUpscale(value);
    } catch (_) {}
  }

  Future<void> _setThreshold(RealSrResolutionThreshold value) async {
    setState(() => _threshold = value);
    try {
      await RealSrSettings.saveResolutionThreshold(value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final presenter = LocalReadSession.instance.presenter;
    final hasPresenter = presenter != null;
    final presenterReady = presenter != null && presenter.canPresent;
    final apple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    Widget section() {
      final children = <Widget>[
        if (presenterReady) ...[
          _SettingsSwitchTile(
            title: '启用 AI 超分辨率',
            subtitle: '后台处理当前页，完成后替换画面',
            value: presenter.isUpscaleEnabled,
            onChanged: presenter.setUpscaleEnabled,
          ),
          if (presenter.isUpscaleEnabled)
            _SettingsSwitchTile(
              title: '对比原图',
              subtitle: '临时查看原图，关闭后恢复超分图',
              value: presenter.isOriginalPreview,
              onChanged: presenter.setOriginalPreview,
            ),
        ] else if (!hasPresenter && !_loading)
          // 网络来源：超分只受全局设置驱动，这里给它一个入口。
          _SettingsSwitchTile(
            title: t.realSr.autoUpscale,
            subtitle: _modelReady
                ? t.realSr.autoUpscaleSubtitleAvailable
                : t.realSr.autoUpscaleSubtitleUnavailable,
            value: _autoUpscale,
            onChanged: _setAutoUpscale,
          ),
        if (!_loading)
          _SettingsDropdownTile<RealSrResolutionThreshold>(
            title: t.realSr.resolutionThreshold,
            subtitle: t.realSr.resolutionThresholdSubtitle,
            value: RealSrSettings.effectiveThreshold(_threshold),
            values: RealSrSettings.availableThresholds,
            labelOf: (threshold) => threshold.label,
            onChanged: _setThreshold,
          ),
        if (apple) const AppleSuperResolutionSettings(),
      ];

      if (children.isEmpty) return const SizedBox.shrink();
      return _SettingsSection(title: 'AI 超分辨率', children: children);
    }

    // 呈现器在跑时才需要跟着它重建（开关状态由它持有）。
    if (!presenterReady) return section();
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, _) => section(),
    );
  }
}
