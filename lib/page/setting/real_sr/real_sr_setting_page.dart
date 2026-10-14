import 'package:zephyr/page/comic_read/widgets/settings/sections/image_denoise_section.dart';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/real_sr_model_management_section.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_engine_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/upscale_conditions_card.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/icons/icons.dart';

final Map<int, String> _concurrencyLabels = {
  1: '1',
  2: '2',
  4: '4',
  6: '6',
  8: '8',
  0: t.realSr.unlimited,
};

final List<int> _concurrencyOptions = _concurrencyLabels.keys.toList()..sort();

@RoutePage()
class RealSrSettingPage extends StatefulWidget {
  const RealSrSettingPage({super.key});

  @override
  State<RealSrSettingPage> createState() => _RealSrSettingPageState();
}

class _RealSrSettingPageState extends State<RealSrSettingPage> {
  bool _loading = true;
  bool _autoUpscale = false;
  RealSrResolutionThreshold _resolutionThreshold =
      RealSrResolutionThreshold.p720;
  int _concurrency = 2;
  int _tileSize = 0;
  AndroidNcnnMode _desktopNcnnMode = DesktopNcnnModelConfig.defaultMode;
  AndroidNcnnNoise _desktopNcnnNoise = DesktopNcnnModelConfig.defaultNoise;
  RealSrScale _scale = RealSrScale.x2;
  bool _isAvailable = false;
  SuperResolutionEngine _engine = defaultEngine;

  // 可用档位与夹取规则统一由 RealSrSettings 提供 —— 阅读器面板用同一份，
  // 两处各写一遍就会漂移（见 effectiveThreshold 的注释）。
  List<RealSrResolutionThreshold> get _availableThresholds =>
      RealSrSettings.availableThresholds;

  RealSrResolutionThreshold get _effectiveThreshold =>
      RealSrSettings.effectiveThreshold(_resolutionThreshold);

  @override
  void initState() {
    super.initState();
    RealSrSettings.modelChanges.addListener(_refreshAvailability);
    _loadSettings();
  }

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_refreshAvailability);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      RealSrSettings.loadAutoUpscale(),
      RealSrSettings.loadResolutionThreshold(),
      RealSrSettings.loadConcurrency(),
      RealSrSettings.loadTileSize(),
      RealSrSettings.loadDesktopNcnnMode(),
      RealSrSettings.loadDesktopNcnnNoise(),
      RealSrSettings.loadScale(),
      RealSrSuperResolution.isAvailable,
      RealSrSettings.loadEngine(),
    ]);

    if (!mounted) return;
    setState(() {
      _autoUpscale = results[0] as bool;
      _resolutionThreshold = results[1] as RealSrResolutionThreshold;
      _concurrency = results[2] as int;
      _tileSize = results[3] as int;
      _desktopNcnnMode = results[4] as AndroidNcnnMode;
      _desktopNcnnNoise = results[5] as AndroidNcnnNoise;
      _scale = results[6] as RealSrScale;
      _isAvailable = results[7] as bool;
      _engine = results[8] as SuperResolutionEngine;
      _loading = false;
    });
  }

  Future<void> _setAutoUpscale(bool value) async {
    await RealSrSettings.saveAutoUpscale(value);
    setState(() => _autoUpscale = value);
  }

  Future<void> _setResolutionThreshold(RealSrResolutionThreshold value) async {
    await RealSrSettings.saveResolutionThreshold(value);
    setState(() => _resolutionThreshold = value);
  }

  Future<void> _setConcurrency(int value) async {
    await RealSrSettings.saveConcurrency(value);
    setState(() => _concurrency = value);
  }

  Future<void> _setTileSize(int value) async {
    await RealSrSettings.saveTileSize(value);
    setState(() => _tileSize = value);
  }

  Future<void> _setDesktopNcnnMode(AndroidNcnnMode value) async {
    await RealSrSettings.saveDesktopNcnnMode(value);
    setState(() => _desktopNcnnMode = value);
  }

  Future<void> _setDesktopNcnnNoise(AndroidNcnnNoise value) async {
    await RealSrSettings.saveDesktopNcnnNoise(value);
    setState(() => _desktopNcnnNoise = value);
  }

  Future<void> _setScale(RealSrScale value) async {
    await RealSrSettings.saveScale(value);
    setState(() => _scale = value);
  }

  /// 切引擎会走 `modelChanges` 通知到这里：可用性与「该画哪几块」都随引擎变，
  /// 所以两处一起刷。
  Future<void> _refreshAvailability() async {
    final results = await Future.wait([
      RealSrSuperResolution.isAvailable,
      RealSrSettings.loadEngine(),
    ]);
    if (!mounted) return;
    setState(() {
      _isAvailable = results[0] as bool;
      _engine = results[1] as SuperResolutionEngine;
    });
  }

  List<Widget> _buildModelItems() {
    if (supportsCoreML) {
      return const [SuperResolutionEngineSettings()];
    }

    if (Platform.isAndroid) {
      return [
        ListTile(
          leading: const GlyphIcon(AppGlyphs.info),
          title: Text(t.realSr.androidSuperResolution),
          subtitle: Text(t.realSr.androidSuperResolutionSubtitle),
        ),
      ];
    }

    // Windows / Linux：选了 mImage ONNX 就只留引擎面板（它自带模型的下载与导入），
    // 下面那批 NCNN 档位不再摆出来，避免「按了下载却去拉 7z」。
    if (_engine == SuperResolutionEngine.mimageOnnx) {
      return const [SuperResolutionEngineSettings()];
    }

    return [
      const SuperResolutionEngineSettings(),
      ListTile(
        leading: const GlyphIcon(AppGlyphs.openInFull),
        title: const Text('输出倍率'),
        subtitle: const Text('桌面 NCNN 模型的实际倍率设置'),
        trailing: FluentDropdown<RealSrScale>(
          value: _scale,
          displayValue: _scale.label,
          items: {for (final scale in RealSrScale.values) scale: scale.label},
          onChanged: _setScale,
        ),
      ),
      ListTile(
        leading: const GlyphIcon(AppGlyphs.speed),
        title: Text(t.realSr.desktopStrategy),
        subtitle: Text(t.realSr.desktopStrategySubtitle),
        trailing: FluentDropdown<AndroidNcnnMode>(
          value: _desktopNcnnMode,
          displayValue: _desktopNcnnMode.label,
          items: {for (final mode in AndroidNcnnMode.values) mode: mode.label},
          onChanged: _setDesktopNcnnMode,
        ),
      ),
      ListTile(
        leading: const GlyphIcon(AppGlyphs.wand),
        title: Text(t.realSr.desktopNoiseLevel),
        subtitle: Text(t.realSr.desktopNoiseLevelSubtitle),
        trailing: FluentDropdown<AndroidNcnnNoise>(
          value: _desktopNcnnNoise,
          displayValue: _desktopNcnnNoise.label,
          items: {
            for (final noise in AndroidNcnnNoise.values) noise: noise.label,
          },
          onChanged: _setDesktopNcnnNoise,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.realSr.title,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: ImageDenoiseSection(globalOnly: true),
                ),
                settingSectionTitle(context, t.realSr.autoUpscaleSection),
                SwitchListTile(
                  secondary: const GlyphIcon(AppGlyphs.wand),
                  title: Text(t.realSr.autoUpscale),
                  subtitle: Text(
                    !_isAvailable
                        ? t.realSr.autoUpscaleSubtitleUnavailable
                        : t.realSr.autoUpscaleSubtitleAvailable,
                  ),
                  thumbIcon: kSettingSwitchThumbIcon,
                  value: _autoUpscale,
                  onChanged: _setAutoUpscale,
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.realSr.conditionSection),
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.quality),
                  title: Text(t.realSr.resolutionThreshold),
                  subtitle: Text(t.realSr.resolutionThresholdSubtitle),
                  trailing: FluentDropdown<RealSrResolutionThreshold>(
                    value: _effectiveThreshold,
                    displayValue: _effectiveThreshold.label,
                    items: {
                      for (final threshold in _availableThresholds)
                        threshold: threshold.label,
                    },
                    onChanged: _setResolutionThreshold,
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: UpscaleConditionsCard(),
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.realSr.performanceSection),
                Builder(
                  builder: (context) {
                    final effective = _concurrencyOptions.contains(_concurrency)
                        ? _concurrency
                        : RealSrSettings.defaultConcurrency;
                    return ListTile(
                      leading: const GlyphIcon(AppGlyphs.speed),
                      title: Text(t.realSr.concurrency),
                      subtitle: Text(t.realSr.concurrencySubtitle),
                      trailing: FluentDropdown<int>(
                        value: effective,
                        displayValue: _concurrencyLabels[effective]!,
                        items: {
                          for (final option in _concurrencyOptions)
                            option: _concurrencyLabels[option]!,
                        },
                        onChanged: _setConcurrency,
                      ),
                    );
                  },
                ),
                if (RealSrSettings.tileSizeRowApplies(
                  engine: _engine,
                  hasEngineChoice: hasSuperResolutionEngineChoice,
                ))
                  Builder(
                    builder: (context) {
                      final labels = RealSrSettings.tileSizeLabelsFor(
                        engine: _engine,
                        hasEngineChoice: hasSuperResolutionEngineChoice,
                      );
                      final options = labels.keys.toList()..sort();
                      final effective = RealSrSettings.effectiveTileSize(
                        engine: _engine,
                        hasEngineChoice: hasSuperResolutionEngineChoice,
                        stored: _tileSize,
                      );
                      final isMImageOnnx =
                          _engine == SuperResolutionEngine.mimageOnnx;
                      return ListTile(
                        leading: const GlyphIcon(AppGlyphs.dashboard),
                        title: Text(t.realSr.tileSize),
                        // ONNX 那侧 0 不是「不分块」，照抄旧文案等于在界面上撒谎。
                        subtitle: Text(
                          isMImageOnnx
                              ? '遇到崩溃可设置较小值；「自动」按模型推荐分块，模型声明固定输入尺寸时以模型为准'
                              : t.realSr.tileSizeSubtitle,
                        ),
                        trailing: FluentDropdown<int>(
                          value: effective,
                          displayValue: labels[effective]!,
                          items: {
                            for (final option in options)
                              option: labels[option]!,
                          },
                          onChanged: _setTileSize,
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.realSr.modelSection),
                ..._buildModelItems(),

                const RealSrModelManagementSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
