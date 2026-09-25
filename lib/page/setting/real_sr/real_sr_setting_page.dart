import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_engine_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/upscale_conditions_card.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

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
  bool _downloading = false;
  bool _importing = false;
  double _downloadProgress = 0;

  /// 「桌面 NCNN 专属」的那几块（模型管理 / 手动下载 / 导入）要不要画。
  ///
  /// Apple 没有 NCNN 这条引擎，永远不画；Windows / Linux 只在选中桌面 NCNN 时画 ——
  /// 切到 mImage ONNX 之后，模型的下载/导入由 ONNX 面板自己管，这里再摆一份就会
  /// 出现「按了下载却去拉 7z」的错路。
  /// 「分块大小」不在这一组里：ONNX 也读那个值，门禁见 [RealSrSettings.tileSizeRowApplies]。
  bool get _showsDesktopNcnnBlocks =>
      supportsDesktopNcnn && _engine != SuperResolutionEngine.mimageOnnx;

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

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      await RealSrSuperResolution.downloadModel(
        force: _isAvailable,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress = received / total);
        },
      );
    } catch (e, s) {
      logger.e('模型下载失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDownloadFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _refreshAvailability();
      }
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.realSr.deleteModel),
        content: Text(t.realSr.deleteModelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.common.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await RealSrSuperResolution.deleteModel();
      showSuccessToast(t.realSr.modelDeleted);
    } catch (e, s) {
      logger.e('模型删除失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDeleteFailed}: $e');
    } finally {
      if (mounted) await _refreshAvailability();
    }
  }

  Future<void> _openManualDownloadUrl() async {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      showErrorToast(t.realSr.manualDownloadUnsupported);
      return;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      showErrorToast(t.realSr.openDownloadUrlFailed);
    }
  }

  Future<void> _importModel() async {
    // iOS 没有系统声明的 7z UTI，使用通用数据类型后由导入逻辑校验 7z 魔数。
    final typeGroup = Platform.isIOS
        ? const XTypeGroup(label: '7z')
        : const XTypeGroup(label: '7z', extensions: ['7z']);
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (e) {
      showErrorToast('${t.realSr.modelImportFailed}: $e');
      return;
    }
    if (file == null) return;

    setState(() => _importing = true);
    try {
      await RealSrSuperResolution.importModelArchive(file.path);
      if (mounted) showSuccessToast(t.realSr.modelImportSuccess);
    } catch (e, s) {
      logger.e('模型导入失败', error: e, stackTrace: s);
      if (mounted) {
        showErrorToast('${t.realSr.modelImportFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        await _refreshAvailability();
      }
    }
  }

  List<Widget> _buildModelItems() {
    if (supportsCoreML) {
      return const [SuperResolutionEngineSettings()];
    }

    if (Platform.isAndroid) {
      return [
        ListTile(
          leading: const Icon(Icons.info_outline),
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
        leading: const Icon(Icons.zoom_out_map_outlined),
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
        leading: const Icon(Icons.speed_outlined),
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
        leading: const Icon(Icons.healing_outlined),
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

  Widget _buildModelManagementTile() {
    if (_downloading) {
      return ListTile(
        leading: const Icon(Icons.downloading_outlined),
        title: Text(t.realSr.downloadingModel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 4),
            Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
          ],
        ),
      );
    }

    if (_isAvailable) {
      return ListTile(
        leading: Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(t.realSr.modelReady),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _deleteModel,
              child: Text(t.realSr.deleteModel),
            ),
            TextButton(
              onPressed: _downloadModel,
              child: Text(t.realSr.redownload),
            ),
          ],
        ),
      );
    }

    return ListTile(
      leading: const Icon(Icons.warning_amber_rounded),
      title: Text(t.realSr.modelNotDownloaded),
      subtitle: Text(t.realSr.modelNotDownloadedSubtitle),
      trailing: ElevatedButton(
        onPressed: _downloadModel,
        child: Text(t.realSr.downloadModel),
      ),
    );
  }

  Widget _buildManualDownloadTile() {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      return ListTile(
        leading: const Icon(Icons.open_in_browser_outlined),
        title: Text(t.realSr.manualDownload),
        subtitle: Text(t.realSr.manualDownloadUnsupported),
      );
    }
    return ListTile(
      leading: const Icon(Icons.open_in_browser_outlined),
      title: Text(t.realSr.manualDownload),
      subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: _openManualDownloadUrl,
        child: Text(t.realSr.openDownloadUrl),
      ),
    );
  }

  Widget _buildImportModelTile() {
    return ListTile(
      leading: const Icon(Icons.file_open_outlined),
      title: Text(t.realSr.importModel),
      subtitle: Text(t.realSr.importModelSubtitle),
      trailing: _importing
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _importModel,
              child: Text(t.realSr.importModelAction),
            ),
    );
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
                settingSectionTitle(context, t.realSr.autoUpscaleSection),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_fix_high_outlined),
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
                  leading: const Icon(Icons.hd_outlined),
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
                      leading: const Icon(Icons.speed_outlined),
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
                        leading: const Icon(Icons.grid_on_outlined),
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

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                if (_showsDesktopNcnnBlocks) ...[
                  settingSectionTitle(context, t.realSr.modelManagementSection),
                  _buildModelManagementTile(),
                  _buildManualDownloadTile(),
                  _buildImportModelTile(),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
