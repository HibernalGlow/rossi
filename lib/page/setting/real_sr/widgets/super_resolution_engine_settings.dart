import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/mimage_model_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';
import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/util/coreml_model_loader.dart';

/// 阅读器与全局设置共用；两个引擎各自保留模型选择。
class SuperResolutionEngineSettings extends StatefulWidget {
  final bool isReaderCompact;

  const SuperResolutionEngineSettings({
    super.key,
    this.isReaderCompact = false,
  });

  @override
  State<SuperResolutionEngineSettings> createState() =>
      _SuperResolutionEngineSettingsState();
}

class _SuperResolutionEngineSettingsState
    extends State<SuperResolutionEngineSettings> {
  SuperResolutionEngine? _engine;
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
      final engine = await RealSrSettings.loadEngine();
      final (forward, back) = await RealSrSettings.loadPrefetch();
      final family = await RealSrSettings.loadCoreMLFamily();
      final variant = await RealSrSettings.loadCoreMLVariant(family);
      final available = supportsCoreML
          ? await CoreMLModelLoader.isModelAvailable(variant.fileName)
          : false;
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final engineCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SuperResolutionEngine>(
          key: const ValueKey('apple-sr-engine'),
          value: _engine,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: [
            for (final engine in availableEngines)
              DropdownMenuItem(
                value: engine,
                child: Text(
                  engine.label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
          ],
          onChanged: (engine) {
            if (engine != null) {
              _change(() => RealSrSettings.saveEngine(engine));
            }
          },
        ),
      ),
    );

    final advancedSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预超分（当前页优先）',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('后续页：', style: TextStyle(fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('sr-prefetch-forward'),
                      value: _forward,
                      isDense: true,
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
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('之前页：', style: TextStyle(fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('sr-prefetch-back'),
                      value: _back,
                      isDense: true,
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
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '一次处理一页，避免争抢内存；都设为 0 可关闭预超分。',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        const SuperResolutionLogControls(),
      ],
    );

    return Padding(
      padding: EdgeInsets.all(widget.isReaderCompact ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isReaderCompact) ...[
            Text('超分引擎', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
          ],
          if (_engine == null && _error == null)
            const LinearProgressIndicator()
          else ...[
            engineCard,
            const SizedBox(height: 6),
            Text(
              '切换后当前页自动重新处理，两套模型选择分别保留。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_engine == SuperResolutionEngine.mimageOnnx)
              const MImageModelSettings(showLogControls: false)
            else if (_engine == SuperResolutionEngine.breezeCoreML) ...[
              Text(
                'Rossi 原生模型',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CoreMLModelFamily>(
                    key: const ValueKey('breeze-coreml-model'),
                    value: _family,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: [
                      for (final family in CoreMLModelConfig.families)
                        DropdownMenuItem(
                          value: family,
                          child: Text(
                            switch (family.id) {
                              'waifu2x' => 'waifu2x · 速度优先',
                              'realcugan' => 'Real-CUGAN · 质量优先',
                              _ => family.label,
                            },
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                    onChanged: _downloading
                        ? null
                        : (family) {
                            if (family != null) {
                              _change(
                                () => RealSrSettings.saveCoreMLFamily(family),
                              );
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '原生 ${_variant.config['scale']}×',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _variant.localizedDisplayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _available
                          ? Colors.green.withValues(alpha: 0.15)
                          : colorScheme.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _available ? '已安装' : '未安装',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _available ? Colors.green : colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Swift 直接调用 Apple CoreML，复用已加载模型。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (!_available) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('下载 Rossi 原生模型'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
              ],
            ] else if (_engine == SuperResolutionEngine.desktopNcnn)
              Text(
                '调用 waifu2x / Real-CUGAN 的 ncnn-vulkan 可执行文件；'
                '模式、倍率、并发与分块在「图片超分」设置页下方调整。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
          ],
          const SizedBox(height: 12),
          if (widget.isReaderCompact)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '高级超分选项 (预超分 / 日志)',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [advancedSection],
              ),
            )
          else
            advancedSection,
        ],
      ),
    );
  }
}
