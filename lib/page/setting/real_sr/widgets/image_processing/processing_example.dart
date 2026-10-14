import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart' show logger;
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/processing_preview_loader.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_disclosure.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/i18n/strings.g.dart';

enum ProcessingExampleKind { autoTrim, denoise }

extension on ProcessingExampleKind {
  String get title => switch (this) {
    ProcessingExampleKind.autoTrim => t.realSr.exampleTrimTitle,
    ProcessingExampleKind.denoise => t.realSr.exampleDenoiseTitle,
  };

  String get staticDescription => switch (this) {
    ProcessingExampleKind.autoTrim => t.realSr.exampleTrimDesc,
    ProcessingExampleKind.denoise => t.realSr.exampleDenoiseDesc,
  };

  String get prefix => switch (this) {
    ProcessingExampleKind.autoTrim => 'trim',
    ProcessingExampleKind.denoise => 'denoise',
  };

  String get beforeLabel => t.realSr.modeOriginal;

  String get afterLabel => switch (this) {
    ProcessingExampleKind.autoTrim => t.realSr.afterTrim,
    ProcessingExampleKind.denoise => t.realSr.afterDenoise,
  };
}

/// 默认折叠、不加载任何图片。用户主动展开后：
/// - 正在阅读时，显示**当前页**的实际处理状态与前后对比；
/// - 没有当前页时，才退回内置静态示例。
/// 收起、换页或离开页面时立刻释放位图与临时文件。
class ProcessingExample extends StatefulWidget {
  const ProcessingExample({
    super.key,
    required this.kind,
    this.enabled = false,
    this.reloadOn,
  });

  final ProcessingExampleKind kind;

  /// 当前是否已开启该处理；只影响状态文案，预览读取阅读器的实际结果。
  final bool enabled;

  /// 展开期间，这个对象通知后重新计算预览（例如降噪模型下载完成）。
  final Listenable? reloadOn;

  @override
  State<ProcessingExample> createState() => _ProcessingExampleState();
}

class _ProcessingExampleState extends State<ProcessingExample> {
  bool _expanded = false;
  bool _loading = false;

  ProcessingPreview? _preview;
  Object? _identity;
  int _generation = 0;
  Timer? _debounce;

  Listenable get _settings => switch (widget.kind) {
    ProcessingExampleKind.autoTrim => AutoTrimSettings.options,
    ProcessingExampleKind.denoise => ImageDenoiseSettings.changes,
  };

  void _attach() {
    CurrentPageImageInfo.instance.addListener(_onPageChanged);
    _settings.addListener(_onSettingsChanged);
    widget.reloadOn?.addListener(_onSettingsChanged);
  }

  void _detach() {
    CurrentPageImageInfo.instance.removeListener(_onPageChanged);
    _settings.removeListener(_onSettingsChanged);
    widget.reloadOn?.removeListener(_onSettingsChanged);
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    if (_expanded) {
      _collapse();
    } else {
      setState(() => _expanded = true);
      _attach();
      unawaited(_reload());
    }
  }

  void _collapse() {
    _detach();
    _debounce?.cancel();
    _generation++;
    final doomed = _preview;
    setState(() {
      _expanded = false;
      _loading = false;
      _preview = null;
      _identity = null;
    });
    // 先让界面摘掉引用，下一帧再释放，避免正在走的这一帧画到已释放的位图。
    WidgetsBinding.instance.addPostFrameCallback((_) => doomed?.dispose());
  }

  /// 阅读器会在同一页上多次上报（原图→处理产物），只有「换了一页」才算变化。
  void _onPageChanged() {
    final identity = ProcessingPreviewLoader.stateOf(
      ProcessingPreviewLoader.currentPage,
      trim: widget.kind == ProcessingExampleKind.autoTrim,
    );
    if (identity == _identity) return;
    _onSettingsChanged();
  }

  void _onSettingsChanged() {
    if (!_expanded) return;
    _scheduleReload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _expanded) unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final doomed = _preview;
    _preview = null;
    final ref = ProcessingPreviewLoader.currentPage;
    _identity = ProcessingPreviewLoader.stateOf(
      ref,
      trim: widget.kind == ProcessingExampleKind.autoTrim,
    );
    setState(() {
      _loading = ref != null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => doomed?.dispose());
    if (ref == null) return;
    ProcessingPreview? result;
    try {
      result = switch (widget.kind) {
        ProcessingExampleKind.autoTrim => await ProcessingPreviewLoader.trim(
          ref,
        ),
        ProcessingExampleKind.denoise => await ProcessingPreviewLoader.denoise(
          ref,
          cancelled: () => !mounted || !_expanded || generation != _generation,
        ),
      };
    } catch (e, s) {
      logger.w('图片处理预览失败', error: e, stackTrace: s);
      result = ProcessingPreview(status: t.realSr.previewFailed(error: e));
    }
    if (!mounted || !_expanded || generation != _generation) {
      result?.dispose();
      return;
    }
    setState(() {
      _preview =
          result ??
          ProcessingPreview(status: t.realSr.exampleImageNotReadyRetry);
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (_expanded) _detach();
    _debounce?.cancel();
    _generation++;
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: ListTile(
                minTileHeight: 56,
                title: Text(
                  widget.kind.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: _expanded
                    ? null
                    : Text(t.realSr.exampleCollapsedHint),
                trailing: AnimatedRotation(
                  turns: _expanded ? .5 : 0,
                  duration: ExpressiveMotion.duration(
                    context,
                    ExpressiveMotion.spatialDuration,
                  ),
                  curve: ExpressiveMotion.spatialCurve,
                  child: const Icon(Icons.expand_more),
                ),
                onTap: _toggle,
              ),
            ),
            if (MediaQuery.disableAnimationsOf(context) ||
                !(SettingsPresentationScope.maybeOf(context)?.animate ?? true))
              _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _body(context),
                    )
                  : const SizedBox.shrink()
            else
              SettingsAnimatedCollapse(
                isExpanded: _expanded,
                showDivider: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _expanded ? _body(context) : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final preview = _preview;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.kind == ProcessingExampleKind.denoise
                    ? t.realSr.loadingDenoiseResult
                    : t.realSr.loadingTrimResult,
              ),
            ),
          ],
        ),
      );
    }
    if (preview == null) {
      return ProcessingPreviewLoader.currentPage == null
          ? _StaticExample(kind: widget.kind)
          : Text(t.realSr.exampleImageNotReady);
    }
    return _LivePreview(
      kind: widget.kind,
      preview: preview,
      enabled: widget.enabled,
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.kind,
    required this.preview,
    required this.enabled,
  });

  final ProcessingExampleKind kind;
  final ProcessingPreview preview;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final before = preview.before;
    final trim = preview.trimRect;
    final hasAfter = switch (kind) {
      ProcessingExampleKind.autoTrim => trim != null,
      ProcessingExampleKind.denoise => preview.after != null,
    };
    final quality = kind == ProcessingExampleKind.autoTrim
        ? FilterQuality.medium
        : FilterQuality.none;
    Widget? beforePanel;
    Widget? afterPanel;
    if (before != null) {
      final markTrim = kind == ProcessingExampleKind.autoTrim && trim != null;
      beforePanel = _PreviewPanel(
        label: markTrim
            ? t.realSr.beforeTrimmedShadow(before: kind.beforeLabel)
            : hasAfter
            ? kind.beforeLabel
            : t.realSr.beforeUnchanged(before: kind.beforeLabel),
        aspectRatio: before.width / before.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RawImage(
              image: before,
              fit: BoxFit.contain,
              filterQuality: quality,
            ),
            if (markTrim)
              CustomPaint(painter: _TrimScrimPainter(trim, colors.primary)),
          ],
        ),
      );
      if (hasAfter) {
        afterPanel = switch (kind) {
          ProcessingExampleKind.autoTrim => _PreviewPanel(
            label: kind.afterLabel,
            highlighted: true,
            aspectRatio:
                (before.width * trim!.width) / (before.height * trim.height),
            child: CustomPaint(
              painter: _CropPainter(before, trim, quality),
              size: Size.infinite,
            ),
          ),
          ProcessingExampleKind.denoise => _PreviewPanel(
            label: kind.afterLabel,
            highlighted: true,
            aspectRatio: preview.after!.width / preview.after!.height,
            child: RawImage(
              image: preview.after,
              fit: BoxFit.contain,
              filterQuality: quality,
            ),
          ),
        };
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(preview.status, style: theme.textTheme.bodyMedium),
        ),
        if (beforePanel != null) ...[
          const SizedBox(height: 12),
          if (afterPanel == null)
            beforePanel
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      beforePanel!,
                      const SizedBox(height: 12),
                      afterPanel!,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: beforePanel!),
                    const SizedBox(width: 12),
                    Expanded(child: afterPanel!),
                  ],
                );
              },
            ),
        ],
        const SizedBox(height: 8),
        Text(
          t.realSr.exampleLiveSource,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.label,
    required this.aspectRatio,
    required this.child,
    this.highlighted = false,
  });

  final String label;
  final double aspectRatio;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(aspectRatio: aspectRatio, child: child),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: highlighted
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: highlighted ? colors.onPrimaryContainer : colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// 在原图上把被裁掉的边缘涂暗，并用主色描出保留区域。
class _TrimScrimPainter extends CustomPainter {
  _TrimScrimPainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final keep = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(keep);
    canvas.drawPath(scrim, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      keep,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrimScrimPainter old) =>
      old.rect != rect || old.color != color;
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.rect, this.quality);

  final ui.Image image;
  final Rect rect;
  final FilterQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(
        rect.left * w,
        rect.top * h,
        rect.right * w,
        rect.bottom * h,
      ),
      Offset.zero & size,
      Paint()..filterQuality = quality,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.rect != rect || old.quality != quality;
}

/// 没有当前页时的内置静态示例，不依赖模型下载、当前页面或图片处理开关。
class _StaticExample extends StatefulWidget {
  const _StaticExample({required this.kind});
  final ProcessingExampleKind kind;

  @override
  State<_StaticExample> createState() => _StaticExampleState();
}

class _StaticExampleState extends State<_StaticExample> {
  ProcessingExampleKind get kind => widget.kind;

  @override
  void dispose() {
    for (final stage in ['before', 'after']) {
      unawaited(
        AssetImage(
          'asset/image/processing_examples/${kind.prefix}_$stage.png',
        ).evict(),
      );
    }
    super.dispose();
  }

  Widget _pair(BuildContext context, {bool enlarged = false}) {
    Widget panel(bool after) {
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: kind == ProcessingExampleKind.autoTrim ? .8 : 1,
              child: Image.asset(
                'asset/image/processing_examples/${kind.prefix}_${after ? 'after' : 'before'}.png',
                fit: BoxFit.contain,
                filterQuality: kind == ProcessingExampleKind.autoTrim
                    ? FilterQuality.medium
                    : FilterQuality.none,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: after
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
            ),
            child: Text(
              after ? kind.afterLabel : kind.beforeLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: after ? colors.onPrimaryContainer : colors.onSurface,
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 大图在手机上纵向排列，避免放大入口仍然只显示小缩略图。
        if (enlarged && constraints.maxWidth < 480) {
          return Column(
            children: [panel(false), const SizedBox(height: 16), panel(true)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: panel(false)),
            const SizedBox(width: 12),
            Expanded(child: panel(true)),
          ],
        );
      },
    );
  }

  void _showEnlarged(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.realSr.exampleTitleSuffix(title: kind.title),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: t.realSr.closeExample,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _pair(context, enlarged: true),
                const SizedBox(height: 16),
                Text(
                  kind.staticDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: t.realSr.exampleSemantics(
      title: kind.title,
      before: kind.beforeLabel,
      after: kind.afterLabel,
      description: kind.staticDescription,
    ),
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showEnlarged(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.realSr.exampleBuiltinHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _pair(context),
          const SizedBox(height: 10),
          Text(
            kind.staticDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
