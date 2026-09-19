import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/mimage_model_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';
import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/util/coreml_model_loader.dart';

/// 阅读器与全局设置共用；两个引擎各自保留模型选择。
class AppleSuperResolutionSettings extends StatefulWidget {
  const AppleSuperResolutionSettings({super.key});

  @override
  State<AppleSuperResolutionSettings> createState() =>
      _AppleSuperResolutionSettingsState();
}

class _AppleSuperResolutionSettingsState
    extends State<AppleSuperResolutionSettings> {
  AppleSuperResolutionEngine? _engine;
  CoreMLModelFamily _family = CoreMLModelConfig.defaultFamily;
  CoreMLModelVariant _variant = CoreMLModelConfig.defaultVariant;
  bool _available = false;
  bool _downloading = false;
  double? _progress;
  String? _error;
  int _generation = 0;
  int _forward = 2;
  int _back = 1;

  @override
  void initState() {
    super.initState();
    RealSrSettings.modelChanges.addListener(_reload);
    RealSrSettings.prefetchChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_reload);
    RealSrSettings.prefetchChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final engine = await RealSrSettings.loadAppleEngine();
      final (forward, back) = await RealSrSettings.loadPrefetch();
      final family = await RealSrSettings.loadCoreMLFamily();
      final variant = await RealSrSettings.loadCoreMLVariant(family);
      final available = await CoreMLModelLoader.isModelAvailable(
        variant.fileName,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _engine = engine;
        _forward = forward;
        _back = back;
        _family = family;
        _variant = variant;
        _available = available;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    }
  }

  Future<void> _download() async {
    final variant = _variant;
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      await CoreMLModelLoader.prepareModel(
        variant.fileName,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      RealSrSettings.notifyChanges();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _downloading = false);
      await _reload();
    }
  }

  Future<void> _change(Future<void> Function() save) async {
    try {
      await save();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('超分引擎', style: Theme.of(context).textTheme.titleSmall),
        if (_engine == null && _error == null)
          const LinearProgressIndicator()
        else ...[
          DropdownButton<AppleSuperResolutionEngine>(
            key: const ValueKey('apple-sr-engine'),
            value: _engine,
            isExpanded: true,
            items: [
              for (final engine in AppleSuperResolutionEngine.values)
                DropdownMenuItem(value: engine, child: Text(engine.label)),
            ],
            onChanged: (engine) {
              if (engine != null) {
                _change(() => RealSrSettings.saveAppleEngine(engine));
              }
            },
          ),
          const Text('切换后当前页自动重新处理，两套模型选择分别保留。'),
          const SizedBox(height: 12),
          if (_engine == AppleSuperResolutionEngine.mimageOnnx)
            const MImageModelSettings(showLogControls: false)
          else if (_engine == AppleSuperResolutionEngine.breezeCoreML) ...[
            const Text('Breeze 原生模型'),
            DropdownButton<CoreMLModelFamily>(
              key: const ValueKey('breeze-coreml-model'),
              value: _family,
              isExpanded: true,
              items: [
                for (final family in CoreMLModelConfig.families)
                  DropdownMenuItem(
                    value: family,
                    child: Text(switch (family.id) {
                      'waifu2x' => 'waifu2x · 速度优先',
                      'realcugan' => 'Real-CUGAN · 质量优先',
                      _ => family.label,
                    }),
                  ),
              ],
              onChanged: _downloading
                  ? null
                  : (family) {
                      if (family != null) {
                        _change(() => RealSrSettings.saveCoreMLFamily(family));
                      }
                    },
            ),
            Text('倍率：原生 ${_variant.config['scale']}×（由模型决定）'),
            const SizedBox(height: 6),
            Text('降噪：${_variant.localizedDisplayName}'),
            const SizedBox(height: 6),
            const Text('Swift 直接调用 Apple CoreML，复用已加载模型。'),
            const SizedBox(height: 8),
            Text(_available ? '当前模型已安装' : '下载原生模型后即可使用'),
            SelectableText(
              _variant.fileName,
              style: const TextStyle(fontSize: 12),
            ),
            if (!_available)
              OutlinedButton.icon(
                onPressed: _downloading ? null : _download,
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载 Breeze 原生模型'),
              ),
            if (_downloading) LinearProgressIndicator(value: _progress),
          ],
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        const Text('预超分（当前页优先）'),
        Wrap(
          spacing: 16,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('后续页：'),
                DropdownButton<int>(
                  key: const ValueKey('sr-prefetch-forward'),
                  value: _forward,
                  items: [
                    for (var n = 0; n <= 5; n++)
                      DropdownMenuItem(value: n, child: Text('$n 页')),
                  ],
                  onChanged: (n) {
                    if (n != null) {
                      _change(
                        () => RealSrSettings.savePrefetch(
                          forward: n,
                          back: _back,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('之前页：'),
                DropdownButton<int>(
                  key: const ValueKey('sr-prefetch-back'),
                  value: _back,
                  items: [
                    for (var n = 0; n <= 5; n++)
                      DropdownMenuItem(value: n, child: Text('$n 页')),
                  ],
                  onChanged: (n) {
                    if (n != null) {
                      _change(
                        () => RealSrSettings.savePrefetch(
                          forward: _forward,
                          back: n,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        const Text(
          '一次处理一页，避免争抢内存；都设为 0 可关闭预超分。',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        const SuperResolutionLogControls(),
      ],
    ),
  );
}
