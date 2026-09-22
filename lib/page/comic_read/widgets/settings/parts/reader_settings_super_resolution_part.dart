part of '../reader_settings_sheet.dart';
// rossi


/// 阅读器设置里的「AI 超分辨率」。
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAutoUpscale(bool value) async {
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
    final hasEngineChoice = hasSuperResolutionEngineChoice;

    Widget section() {
      final cardItems = <Widget>[
        if (presenterReady) ...[
          _SettingsSwitchTile(
            title: '启用 AI 超分辨率',
            subtitle: '后台处理当前页，完成后替换画面',
            value: presenter.isUpscaleEnabled,
            onChanged: presenter.setUpscaleEnabled,
          ),
          _SettingsAnimatedCollapse(
            isExpanded: presenter.isUpscaleEnabled,
            child: _SettingsSwitchTile(
              title: '对比原图',
              subtitle: '临时查看原图，关闭后恢复超分图',
              value: presenter.isOriginalPreview,
              onChanged: presenter.setOriginalPreview,
            ),
          ),
        ] else if (!hasPresenter && !_loading)
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
      ];

      if (cardItems.isEmpty && !hasEngineChoice) return const SizedBox.shrink();

      final colorScheme = Theme.of(context).colorScheme;

      return _SettingsSection(
        title: 'AI 超分辨率',
        icon: Icons.auto_awesome_outlined,
        children: [
          _SettingsCardGroup(children: cardItems),
          if (hasEngineChoice) ...[
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: const SuperResolutionEngineSettings(isReaderCompact: true),
            ),
          ],
          const UpscaleConditionsCard(isReaderCompact: true),
        ],
      );
    }

    if (!presenterReady) return section();
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, _) => section(),
    );
  }
}
