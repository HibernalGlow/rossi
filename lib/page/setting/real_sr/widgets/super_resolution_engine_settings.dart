import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/mimage_model_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';
import 'package:zephyr/util/coreml_model_config.dart';
import 'package:zephyr/util/coreml_model_loader.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/i18n/strings.g.dart';

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

  /// 当前 CoreML 模型的分块（= 模型输入张量边长）说明。
  String get _coreMLBlockInfo {
    final blockSize = _variant.config['blockSize'] as int? ?? 0;
    final shrinkSize = _variant.config['shrinkSize'] as int? ?? 0;
    final contentSize = CoreMLModelConfig.contentBlockSize(_variant);
    return t.realSr.blockInfoDetail(
      contentSize: contentSize,
      blockSize: blockSize,
      shrink: shrinkSize,
    );
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

  static Glyph _engineGlyph(SuperResolutionEngine engine) => switch (engine) {
    SuperResolutionEngine.breezeCoreML => AppGlyphs.rocket,
    SuperResolutionEngine.mimageOnnx => AppGlyphs.memory,
    SuperResolutionEngine.desktopNcnn => AppGlyphs.speed,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final engineSeed = expressiveBlobSeed('sr_engine_selector');

    final engineCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: ShapeDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        shape: ExpressiveBlobBorder(
          seed: engineSeed,
          progress: 0.55,
          safeInset: 8,
          side: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.38),
            width: 1.2,
          ),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SuperResolutionEngine>(
          key: const ValueKey('apple-sr-engine'),
          value: _engine,
          isExpanded: true,
          icon: const GlyphIcon(AppGlyphs.chevronDown),
          items: [
            for (final engine in availableEngines)
              DropdownMenuItem(
                value: engine,
                child: Row(
                  children: [
                    ExpressiveShapeBadge(
                      icon: _engineGlyph(engine),
                      seed: expressiveBlobSeed(engine.name),
                      size: 26,
                      glyphSize: 14,
                      tone: ExpressiveTone.primary,
                      active: engine == _engine,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        engine.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
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
        Row(
          children: [
            const ExpressiveShapeBadge(
              icon: AppGlyphs.bolt,
              shape: ExpressiveButtonShape.sunny,
              size: 24,
              glyphSize: 13,
              tone: ExpressiveTone.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              t.realSr.preUpscaleCurrentFirst,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: expressiveCornerSm,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    AppGlyphs.skipNext,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(t.realSr.pagesAfter, style: TextStyle(fontSize: 12.5)),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('sr-prefetch-forward'),
                      value: _forward,
                      isDense: true,
                      items: [
                        for (var n = 0; n <= 5; n++)
                          DropdownMenuItem(
                            value: n,
                            child: Text(t.realSr.pageCount(n: n)),
                          ),
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
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: expressiveCornerSm,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    AppGlyphs.skipPrevious,
                    size: 14,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(t.realSr.pagesBefore, style: TextStyle(fontSize: 12.5)),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('sr-prefetch-back'),
                      value: _back,
                      isDense: true,
                      items: [
                        for (var n = 0; n <= 5; n++)
                          DropdownMenuItem(
                            value: n,
                            child: Text(t.realSr.pageCount(n: n)),
                          ),
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
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          t.realSr.preUpscaleHint,
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
          Row(
            children: [
              const ExpressiveShapeBadge(
                icon: AppGlyphs.cpu,
                shape: ExpressiveButtonShape.verySunny,
                size: 28,
                glyphSize: 15,
                tone: ExpressiveTone.primary,
                active: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.realSr.upscaleEngine,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (_engine != null)
                ExpressiveStatusPill(
                  text: _engine == SuperResolutionEngine.breezeCoreML
                      ? 'Apple Neural Engine'
                      : t.realSr.hardwareAcceleration,
                  icon: AppGlyphs.bolt,
                  dot: false,
                  compact: true,
                  tone: ExpressiveTone.tertiary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_engine == null && _error == null)
            const LinearProgressIndicator()
          else ...[
            engineCard,
            const SizedBox(height: 6),
            Text(
              t.realSr.engineSwitchHint,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_engine == SuperResolutionEngine.mimageOnnx)
              const MImageModelSettings(showLogControls: false)
            else if (_engine == SuperResolutionEngine.breezeCoreML) ...[
              Row(
                children: [
                  const ExpressiveShapeBadge(
                    icon: AppGlyphs.sparkle,
                    shape: ExpressiveButtonShape.clover4Leaf,
                    size: 24,
                    glyphSize: 13,
                    tone: ExpressiveTone.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    t.realSr.nativeModel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                decoration: ShapeDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.65,
                  ),
                  shape: ExpressiveBlobBorder(
                    seed: expressiveBlobSeed('breeze-coreml-model'),
                    progress: 0.55,
                    safeInset: 8,
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CoreMLModelFamily>(
                    key: const ValueKey('breeze-coreml-model'),
                    value: _family,
                    isExpanded: true,
                    icon: const GlyphIcon(AppGlyphs.chevronDown),
                    items: [
                      for (final family in CoreMLModelConfig.families)
                        DropdownMenuItem(
                          value: family,
                          child: Row(
                            children: [
                              GlyphIcon(
                                family.id == 'waifu2x'
                                    ? AppGlyphs.bolt
                                    : AppGlyphs.quality,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  switch (family.id) {
                                    'waifu2x' => t.realSr.modeWaifuFast,
                                    'realcugan' => t.realSr.modeCuganQuality,
                                    _ => family.label,
                                  },
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
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
                  ExpressiveStatusPill(
                    text: t.realSr.nativeScaleLabel(
                      x: _variant.config['scale'],
                    ),
                    icon: AppGlyphs.zoomIn,
                    dot: false,
                    compact: true,
                    tone: ExpressiveTone.secondary,
                  ),
                  ExpressiveStatusPill(
                    text: _variant.localizedDisplayName,
                    icon: AppGlyphs.layers,
                    dot: false,
                    compact: true,
                    tone: ExpressiveTone.neutral,
                  ),
                  ExpressiveStatusPill(
                    text: _available ? '已安装' : '未安装',
                    icon: _available
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.warning,
                    dot: false,
                    compact: true,
                    tone: _available
                        ? ExpressiveTone.primary
                        : ExpressiveTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ExpressiveTile(
                tone: ExpressiveTone.neutral,
                radius: expressiveCornerSm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlyphIcon(
                          AppGlyphs.gridPlus,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _coreMLBlockInfo,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlyphIcon(
                          AppGlyphs.bolt,
                          size: 14,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.realSr.coremlDesc,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_available) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const GlyphIcon(AppGlyphs.download, size: 18),
                  label: Text(t.realSr.downloadNativeModel),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
              ],
            ] else if (_engine == SuperResolutionEngine.desktopNcnn)
              Text(
                t.realSr.ncnnCliDesc,
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
                leading: const ExpressiveShapeBadge(
                  icon: AppGlyphs.sliders,
                  shape: ExpressiveButtonShape.puffyDiamond,
                  size: 28,
                  glyphSize: 15,
                  tone: ExpressiveTone.tertiary,
                ),
                title: Text(
                  t.realSr.advancedOptionsTitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
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
