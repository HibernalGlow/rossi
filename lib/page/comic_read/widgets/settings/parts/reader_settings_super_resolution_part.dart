part of '../reader_settings_sheet.dart';
// rossi


/// 阅读器设置里的「AI 超分辨率」。
///
/// 面板里是**两条**开关，作用域不同，别混：
/// - 「本书」：写这本书自己的覆盖（`RealSrBookScope`），关掉只影响这本书，
///   别的书仍按全局走；重开这本书仍是你上次的选择。
/// - 「全局」：与设置页「自动超分」同一条（`realsr_auto_upscale`），所有书的默认。
class _SuperResolutionSection extends StatefulWidget {
  const _SuperResolutionSection();

  @override
  State<_SuperResolutionSection> createState() =>
      _SuperResolutionSectionState();
}


class _SuperResolutionSectionState extends State<_SuperResolutionSection> {
  bool _loading = true;

  /// 这本书最终是否超分（覆盖 ?? 全局）。本地书以呈现器的实时值为准。
  bool _bookEnabled = false;

  /// 全局那条总闸（所有书的默认）。
  bool _globalEnabled = false;

  RealSrResolutionThreshold _threshold = RealSrResolutionThreshold.p720;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // 另一处拨了同一条（顶栏芯片 / 全局设置）要跟着刷新，别两颗控件各说各话。
    RealSrBookScope.changes.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    RealSrBookScope.changes.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (mounted) unawaited(_load());
  }

  /// 当前这本书的身份：本地书用读会话登记的那条路径，在线书用 `插件id:漫画id`。
  String? get _bookKey =>
      RealSrBookScope.activeLocalBook ??
      RealSrBookScope.keyFor(
        from: ReaderSessionCoordinator.instance.from,
        comicId: ReaderSessionCoordinator.instance.comicId,
      );

  Future<void> _load() async {
    try {
      final global = await RealSrSettings.loadAutoUpscale();
      final book = await RealSrBookScope.enabledFor(_bookKey);
      final threshold = await RealSrSettings.loadResolutionThreshold();
      final modelReady = await RealSrSuperResolution.isAvailable;
      if (!mounted) return;
      setState(() {
        _globalEnabled = global;
        _bookEnabled = book;
        _threshold = threshold;
        _modelReady = modelReady;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setBookUpscale(bool value) async {
    setState(() => _bookEnabled = value);
    try {
      await RealSrBookScope.save(_bookKey, value);
      // 本地书：呈现器立刻跟随（写覆盖那条链也会通知，但带着明确的值更直接）。
      final presenter = LocalReadSession.instance.presenter;
      if (presenter != null) await presenter.setUpscaleEnabled(value);
    } catch (_) {}
  }

  Future<void> _setGlobalUpscale(bool value) async {
    setState(() => _globalEnabled = value);
    try {
      await RealSrSettings.saveAutoUpscale(value);
      // 本书没有自己的覆盖时，呈现器会经 `RealSrBookScope.changes` 当场跟随；
      // 有覆盖的书不受影响 —— 这正是「本书」与「全局」的区分。
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
    final presenterReady = presenter != null && presenter.canPresent;
    final hasEngineChoice = hasSuperResolutionEngineChoice;

    Widget section() {
      final cardItems = <Widget>[
        if (!_loading)
          _SettingsSwitchTile(
            title: '本书：启用 AI 超分辨率',
            subtitle: _modelReady
                ? '只影响这本书，其它书仍按全局设置'
                : '只影响这本书；模型未下载，开启时会先问一句',
            value: presenterReady ? presenter.isUpscaleEnabled : _bookEnabled,
            onChanged: _setBookUpscale,
          ),
        if (presenterReady) ...[
          _SettingsAnimatedCollapse(
            isExpanded: presenter.isUpscaleEnabled,
            child: _SettingsSwitchTile(
              title: '对比原图',
              subtitle: '临时查看原图，关闭后恢复超分图',
              value: presenter.isOriginalPreview,
              onChanged: presenter.setOriginalPreview,
            ),
          ),
        ],
        if (!_loading)
          _SettingsSwitchTile(
            title: t.realSr.autoUpscale,
            subtitle: _globalEnabled
                ? '所有书的默认（与设置页那条同一条）'
                : '所有书的默认，现在关着；打开后没有单独设置的书都会跟着开',
            value: _globalEnabled,
            onChanged: _setGlobalUpscale,
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
