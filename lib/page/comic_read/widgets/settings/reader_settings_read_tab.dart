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
          const _ThemeModeSection(),
          const SizedBox(height: 18),
          const _ReadBackgroundSection(),
          if (GpuPresentBridge.isPlatformSupported) ...[
            const SizedBox(height: 18),
            const _HdrSection(),
          ],
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
              title: t.reader.singlePageLtr,
              selected: globalSettingState.readSetting.readMode == 1,
              onTap: () {
                if (globalSettingState.readSetting.readMode == 1) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readMode: 1),
                );
                changePageIndex(0);
              },
            ),
            _SettingsChoiceChip(
              title: t.reader.singlePageRtl,
              selected: globalSettingState.readSetting.readMode == 2,
              onTap: () {
                if (globalSettingState.readSetting.readMode == 2) {
                  return;
                }
                globalSettingCubit.updateReadSetting(
                  (current) => current.copyWith(readMode: 2),
                );
                changePageIndex(0);
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
            globalSettingCubit.updateReadSetting(
              (current) => current.copyWith(doublePageMode: value),
            );
            changePageIndex(0);
          },
        ),
        if (globalSettingState.readSetting.doublePageMode &&
            globalSettingState.readSetting.readMode != 0)
          _SettingsSwitchTile(
            title: t.reader.doublePageSeamless,
            subtitle: t.reader.doublePageSeamlessSubtitle,
            value: globalSettingState.readSetting.doublePageSeamless,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(doublePageSeamless: value),
              );
              changePageIndex(0);
            },
          ),
        if (globalSettingState.readSetting.doublePageMode)
          _SettingsSwitchTile(
            title: t.reader.doublePageLeadingBlank,
            subtitle: t.reader.doublePageLeadingBlankSubtitle,
            value: globalSettingState.readSetting.doublePageLeadingBlank,
            onChanged: (value) {
              globalSettingCubit.updateReadSetting(
                (current) => current.copyWith(doublePageLeadingBlank: value),
              );
              changePageIndex(0);
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
      ],
    );
  }
}

class _HdrSection extends StatefulWidget {
  const _HdrSection();

  @override
  State<_HdrSection> createState() => _HdrSectionState();
}

class _HdrSectionState extends State<_HdrSection> {
  int _mode = LocalReadSession.instance.hdrMode;
  double _boost = LocalReadSession.instance.hdrBoost;
  Map<String, dynamic>? _hdrStatus;
  Map<String, dynamic>? _diag;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      await LocalReadSession.instance.ensurePrefsLoaded();
      if (mounted) {
        setState(() {
          _mode = LocalReadSession.instance.hdrMode;
          _boost = LocalReadSession.instance.hdrBoost;
        });
      }
      await _queryStatus();
    }());
  }

  Future<void> _queryStatus() async {
    final status = await const GpuPresentBridge().getHdrStatus();
    final diag = await const GpuPresentBridge().getHdrDiagnostics();
    if (mounted && status != null) {
      setState(() {
        _hdrStatus = status;
        if (diag != null) _diag = diag;
      });
    }
  }

  Future<void> _apply(int mode, {double? boost}) async {
    setState(() {
      _mode = mode;
      if (boost != null) _boost = boost;
    });
    await LocalReadSession.instance.setHdr(mode: _mode, boost: _boost);
    // 参数推下去之后重新读一次：输出通路的字节数是「真 HDR 到底有没有生效」
    // 唯一能从外部看到的硬证据（4 = 8 位 SDR，8 = 半精度浮点）。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _queryStatus();
  }

  /// 一键自检：把这条通路上每一步的实际状态摊开，并写进 /tmp/breeze_gpu.log。
  ///
  /// 存在的理由很具体：这条通路的失败模式都是「画面就是黑的，没别的线索」。
  /// 自检把「平台视图建没建、图层接没接管、输出是 4 字节还是 8 字节」一次问清，
  /// 而不是靠猜。
  Future<void> _selfCheck() async {
    final presenter = LocalReadSession.instance.presenter;
    if (presenter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('呈现器尚未创建（先打开一本本地漫画）')),
        );
      }
      return;
    }
    final report = await HdrImageSurface.selfCheck(
      presenter: presenter,
      path: LocalReadSession.instance.currentSource?.path,
    );
    await _queryStatus();
    if (!mounted) return;
    final diag = report['hdrDiagnostics'] as Map<dynamic, dynamic>?;
    final int bpp = (diag?['outputBpp'] as num?)?.toInt() ?? 4;
    final lines = <String>[
      '平台: ${report['platform']}（桥可用: ${report['bridgeSupported']}）',
      'HDR 模式: ${report['hdrMode']}  启用: ${report['hdrEnabled']}',
      '呈现器: ${report['presenterState']}  canPresent: ${report['canPresent']}',
      'EDR 自检: ${report['edrVerified'] ?? '尚未验证'}',
      if ((report['edrFailureReason'] as String? ?? '').isNotEmpty)
        '失败原因: ${report['edrFailureReason']}',
      '屏幕 EDR: ${(report['hdrStatus'] as Map?)?['maxEdrHeadroom'] ?? '-'}',
      '图层接管: ${diag?['attached'] ?? '-'}',
      '输出每像素字节: $bpp ${bpp == 8 ? '(真 HDR)' : '(8 位 SDR)'}',
      if (report['openedPages'] != null) 'native 侧页数: ${report['openedPages']}',
      if (report['openError'] != null) '打开失败: ${report['openError']}',
      '',
      '明细已写入 /tmp/breeze_gpu.log',
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('HDR 自检'),
        content: SingleChildScrollView(
          child: SelectableText(lines.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 把「现在到底走的是哪条输出通路」说清楚。
  String get _pathLabel {
    final int bpp = (_diag?['outputBpp'] as num?)?.toInt() ?? 4;
    if (bpp == 8) {
      return 'RGBA16F 线性浮点（真 HDR）';
    }
    if (_mode == 0) {
      return 'BGRA8（未开启）';
    }
    return 'BGRA8（8 位通路，只能 SDR 增强）';
  }

  @override
  Widget build(BuildContext context) {
    final bool isHdrSupported = _hdrStatus?['hdrSupported'] == true;
    final double maxEdr = (_hdrStatus?['maxEdrHeadroom'] as num?)?.toDouble() ?? 1.0;
    final bool floatOutput = ((_diag?['outputBpp'] as num?)?.toInt() ?? 4) == 8;

    return _SettingsSection(
      title: 'HDR 与画质增强 (GPU 逆色调映射)',
      children: [
        if (_hdrStatus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              isHdrSupported
                  ? '🍎 屏幕支持 EDR，当前头顶空间 ${maxEdr.toStringAsFixed(2)}x（约 ${(maxEdr * 100).round()} nit）'
                  : '当前屏幕未报告 EDR 头顶空间，只能做 SDR 增强',
              style: TextStyle(
                fontSize: 12,
                color: isHdrSupported ? const Color(0xFF34D399) : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '输出通路: $_pathLabel',
            style: TextStyle(
              fontSize: 12,
              color: floatOutput ? const Color(0xFF34D399) : const Color(0xFF9CA3AF),
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SettingsChoiceChip(
              title: '关闭',
              selected: _mode == 0,
              onTap: () => _apply(0),
            ),
            _SettingsChoiceChip(
              title: 'SDR 增强',
              selected: _mode == 2,
              onTap: () => _apply(2),
            ),
            _SettingsChoiceChip(
              title: '真 HDR',
              selected: _mode == 1,
              onTap: () => _apply(1),
            ),
          ],
        ),
        if (_mode != 0) ...[
          const SizedBox(height: 12),
          _SettingsSliderCard(
            title: '高光与白点提升倍率',
            value: (_boost * 10).round().clamp(10, 40),
            min: 10,
            max: 40,
            divisions: 30,
            suffix: 'x',
            onChanged: (val) {
              final newBoost = val / 10.0;
              _apply(_mode, boost: newBoost);
            },
          ),
        ],
        if (_mode == 1 && !floatOutput)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '提示：真 HDR 需要原生 EDR 图层接管。若输出仍为 BGRA8，点下方自检看哪一步断了。',
              style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: _selfCheck,
            icon: const Icon(Icons.health_and_safety_outlined, size: 16),
            label: const Text('运行 HDR 自检'),
          ),
        ),
      ],
    );
  }
}
