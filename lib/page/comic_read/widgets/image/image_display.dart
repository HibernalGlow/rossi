import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/image_header_size.dart';

class ImageDisplay extends StatefulWidget {
  final String imagePath;
  final bool isColumn;
  final int pageSlotIndex;
  final int sizeCacheIndex;
  final Alignment imageAlignment;

  /// 顶栏缩放/旋转面板算出来的**这一页该画多大**（未旋转的图片自身尺寸）。
  ///
  /// null = 还没有可信尺寸（图片没解出来 / 呈现层没参与），退回改造前的铺排：
  /// 给满宽度、让 `Image` 自己 contain。第一帧因此与今天完全一致。
  final Size? paintSize;

  /// 横长页被拆成两格时，这一格只画原图的**哪一半**（[PageSlice.full] = 整页）。
  ///
  /// 裁剪必须发生在这一层：`ImageSurface` 那条路有纹理/着色器可以只取半幅 UV，
  /// 这条网络/已下载文件的路**没有着色器**，`Image` 自己没有任何办法只画一半 ——
  /// 不在这里裁，整幅横图就会被塞进半格里（等比缩到一半宽，字小到读不了）。
  final PageSlice slice;
  final void Function(Rect?)? onTrimResolved;

  const ImageDisplay({
    super.key,
    required this.imagePath,
    required this.isColumn,
    required this.pageSlotIndex,
    required this.sizeCacheIndex,
    this.imageAlignment = Alignment.center,
    this.paintSize,
    this.slice = PageSlice.full,
    this.onTrimResolved,
  });

  @override
  State<ImageDisplay> createState() => _ImageDisplayState();
}

class _ImageDisplayState extends State<ImageDisplay> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Timer? _einkDelayTimer;
  StreamSubscription<String>? _replacementSubscription;
  int _imageRevision = 0;
  int _trimRequestRevision = -1;
  int _trimResolvedRevision = -1;
  Rect? _trimRect;

  /// 图片宽高比（height / width）。null 表示尚未解析出来。
  double? _aspectRatio;
  bool _einkDelayFinished = true;
  bool _wasRowActive = false;

  bool get isColumn => widget.isColumn;

  @override
  void initState() {
    super.initState();
    _replacementSubscription = UpscaledImageCache.replacements.listen(
      _onImageReplaced,
    );
    AutoTrimSettings.options.addListener(_onTrimOptionsChanged);
    unawaited(AutoTrimSettings.load());
    _resolveImageMeta();
    _startEinkDelayIfNeeded(context.readEffectiveReadSetting());
  }

  @override
  void didUpdateWidget(covariant ImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.imagePath != oldWidget.imagePath) {
      _stopListening();
      _aspectRatio = null;
      _resolveImageMeta();
    }

    if (widget.isColumn) {
      _einkDelayTimer?.cancel();
      _einkDelayFinished = true;
      _wasRowActive = false;
      return;
    }

    _startEinkDelayIfNeeded(context.readEffectiveReadSetting());
  }

  void _startEinkDelayIfNeeded(ReadSettingState readSetting) {
    if (isColumn) {
      _einkDelayTimer?.cancel();
      _einkDelayFinished = true;
      return;
    }

    if (!readSetting.einkOptimization) {
      _einkDelayTimer?.cancel();
      _einkDelayFinished = true;
      return;
    }

    _einkDelayTimer?.cancel();
    _einkDelayFinished = false;
    final delayMs = readSetting.einkDelayMs.clamp(50, 500);
    _einkDelayTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        _einkDelayFinished = true;
      });
    });
  }

  /// 解析图片宽高比。
  ///
  /// 优先只读文件头拿宽高（不解码），只有文件头解析失败时才退回整图解码探测，
  /// 避免为了拿一个宽高比把整张大图解码进 ImageCache。
  void _resolveImageMeta() {
    unawaited(_resolveAspectRatioFromHeader());
  }

  Future<void> _resolveAspectRatioFromHeader() async {
    final path = widget.imagePath;
    final Size? headerSize = await readImageHeaderSize(path);
    if (!mounted || path != widget.imagePath) return;

    if (headerSize != null && headerSize.width > 0 && headerSize.height > 0) {
      _aspectRatio = headerSize.height / headerSize.width;
      _reportSizeToCubit();
      return;
    }

    _resolveAspectRatioByDecoding();
  }

  void _resolveAspectRatioByDecoding() {
    final imageProvider = FileImage(File(widget.imagePath));
    final newStream = imageProvider.resolve(ImageConfiguration.empty);

    final newListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        try {
          if (!mounted) return;

        final int width = imageInfo.image.width;
        final int height = imageInfo.image.height;
        if (width <= 0 || height <= 0) return;

        _aspectRatio = height / width;
        _reportSizeToCubit();
      },
      onError: (exception, stackTrace) {
        logger.e('Failed to resolve image size: $exception');
      },
    );

    _imageStream = newStream;
    _imageListener = newListener;
    newStream.addListener(newListener);
  }

  void _reportSizeToCubit() {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      _updateCubitSize(renderBox.size.width);
      return;
    }
    // 首次布局还没完成，等这一帧结束后再上报。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        _updateCubitSize(box.size.width);
      }
    });
  }

  void _updateCubitSize(double actualWidth) {
    final ratio = _aspectRatio;
    if (ratio == null || actualWidth <= 0) return;

    final index = widget.sizeCacheIndex;
    final cubit = context.read<ImageSizeCubit>();

    final double finalHeight = ratio * actualWidth;

    final currentCachedSize = cubit.getSize(index);

    if (!currentCachedSize.isCached ||
        (currentCachedSize.size.height - finalHeight).abs() > 0.5 ||
        (currentCachedSize.size.width - actualWidth).abs() > 0.5) {
      cubit.updateSize(index, Size(actualWidth, finalHeight));
    }
  }

  void _stopListening() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  Future<void> _detectTrim() async {
    if (widget.slice.isHalf ||
        _rawWidth == null ||
        _rawHeight == null ||
        _trimRequestRevision == _imageRevision) {
      return;
    }
    final path = widget.imagePath;
    final revision = _imageRevision;
    _trimRequestRevision = revision;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final file = File(path);
      final stat = await file.stat();

      if (stat.type != FileSystemEntityType.file) return;
      final targetWidth =
          (1000 *
                  _rawWidth! /
                  (_rawWidth! > _rawHeight! ? _rawWidth! : _rawHeight!))
              .round()
              .clamp(1, 1000);
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: targetWidth,
      );

      if (codec.frameCount != 1) return;
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (data == null) return;
      final detected = await MarginFitCache.instance.bboxForFile(
        path: path,
        revision: revision,
        byteLength: stat.size,
        modified: stat.modified,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );

      if (!mounted || widget.imagePath != path || _imageRevision != revision) {
        return;
      }
      setState(() {
        _trimResolvedRevision = revision;
        _trimRect = trimRectForScroll(
          detected: detected,
          verticalScroll: widget.isColumn,
        );
      });
      final layout = context.read<ImageSizeCubit>().trimLayout;
      layout.report(
        widget.sizeCacheIndex,
        AutoTrimSettings.options.value.cacheKey,
        _trimRect,
      );
      widget.onTrimResolved?.call(_trimRect);
    } catch (error) {
      logger.w('Failed to detect page margins: $error');
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    AutoTrimSettings.options.removeListener(_onTrimOptionsChanged);
    _replacementSubscription?.cancel();
    _stopListening();
    _einkDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readSetting = context.watchEffectiveReadSetting();
    if (readSetting.autoTrimPageMargins &&
        _rawWidth != null &&
        _trimRequestRevision != _imageRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_detectTrim());
      });
    }
    final showStaticPlaceholder = context.select(
      (GlobalSettingCubit c) => c.state.eInkSetting.shouldRemoveLoadingSpinner,
    );
    final brightness = Theme.of(context).brightness;
    final backgroundColor = readSetting.resolveReaderBackgroundColor(
      brightness,
    );
    final foregroundColor = readSetting.resolveReaderForegroundColor(
      brightness,
    );
    final progressColor = foregroundColor.withValues(alpha: 0.3);
    final readMode = context.watchEffectiveReadMode();
    final currentPageIndex = context.select(
      (ReaderCubit c) => c.state.currentSlot,
    );
    final canUseEinkMask =
        !isColumn && readMode != 0 && readSetting.einkOptimization;
    final isActiveRowImage =
        !isColumn && currentPageIndex == widget.pageSlotIndex;

    if (canUseEinkMask && isActiveRowImage && !_wasRowActive) {
      _wasRowActive = true;
      _startEinkDelayIfNeeded(readSetting);
    } else if (!isActiveRowImage && _wasRowActive) {
      _wasRowActive = false;
    }

    if (!canUseEinkMask && !_einkDelayFinished) {
      _einkDelayTimer?.cancel();
      _einkDelayFinished = true;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 呈现层给了明确尺寸就照它画；没给才退回「占满可用宽度」这一套老逻辑。
        final paintSize = widget.paintSize;
        final width = paintSize?.width ?? constraints.maxWidth;

        if (_aspectRatio != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateCubitSize(width);
          });
        }

        Widget loadingPlaceholder() {
          if (showStaticPlaceholder) {
            return Container(width: width, color: backgroundColor);
          }
          return Container(
            width: width,
            color: backgroundColor,
            alignment: Alignment.center,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: progressColor,
              ),
            ),
          );
        }

        final Widget page = Align(
          alignment: widget.imageAlignment,
          child: Image.file(
            File(widget.imagePath),
            // 同路径覆盖后必须重建 ImageState，单独清理缓存不会切换旧图片流。
            key: ValueKey((widget.imagePath, _imageRevision)),
            width: width,
            // 按屏幕密度解码（useLogicalCacheSize 内部乘 devicePixelRatio），
            // 避免超大扫描图整张解码进 ImageCache 挤占内存。
            cacheWidth: width.isFinite && width >= 1 ? width.round() : null,
            useLogicalCacheSize: true,
            fit: isColumn ? BoxFit.fill : BoxFit.contain,
            alignment: widget.imageAlignment,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                if (!isColumn &&
                    canUseEinkMask &&
                    isActiveRowImage &&
                    !_einkDelayFinished) {
                  return Container(width: width, color: Colors.white);
                }
                return child;
              }

              if (canUseEinkMask && isActiveRowImage && !_einkDelayFinished) {
                return Container(width: width, color: Colors.white);
              }
              return loadingPlaceholder();
            },
          ),
        );

        // 半页要在这里裁：这条路没有着色器，`Image` 自己没法只画半幅。
        // 盒子尺寸取 `LayoutBuilder` 的约束而不是 `context.screenWidth` —— 侧边
        // 留白开着时后者比 contentWidth 宽，拿它裁就是一条溢出红条（与上面
        // `width` 的取值同一回事）。
        final visiblePage = wrapPageSlice(
          page,
          slice: widget.slice,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
        final trim = _trimRect;
        if (!readSetting.autoTrimPageMargins ||
            widget.slice.isHalf ||
            trim == null ||
            _rawWidth == null ||
            _rawHeight == null ||
            !constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight) {
          return visiblePage;
        }
        return PageTrimTransform(
          boxSize: Size(constraints.maxWidth, constraints.maxHeight),
          imageSize: Size(_rawWidth!, _rawHeight!),
          contentRect: trim,
          child: visiblePage,
        );
      },
    );
  }
}

/// 把 [child] 按 [slice] 裁成半页：让子节点按**两倍宽**铺排，再用 [ClipRect]
/// 只露出左半或右半。
///
/// 机制与 `ImageSurface._wrapSlice` 逐行相同 —— 同一个语义才能保证 GPU 路与这条
/// 网络/文件路之间来回切（超分、翻页预览开关）时半页的位置不跳。
/// [PageSlice.full] 原样返回 [child]，因此未拆分的页面与拆分前完全一致。
///
/// 给 `OverflowBox` 的四条约束都是**定值**（min == max，紧约束），不是无界 ——
/// 这是这里唯一的雷：`OverflowBox` 一旦给子节点无界约束，`Row` 就会拿着无界
/// 约束参与命中测试并报 "Cannot hit test a render box with no size"（踩坑记录见
/// `read_mode_slot_builder.dart`）。所以不要把它改成只传 `maxWidth`。
///
/// 约束无界时（列模式在 `paintSize` 到位之前高度未定）根本没有可裁的盒子，
/// 只能原样交出去 —— 宁可看到整图，也不要 `SizedBox` 当场抛
/// "BoxConstraints forces an infinite height"。
Widget wrapPageSlice(
  Widget child, {
  required PageSlice slice,
  required double width,
  required double height,
}) {
  if (!slice.isHalf) return child;
  if (!width.isFinite || !height.isFinite) return child;
  return ClipRect(
    child: SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        minWidth: width * 2,
        maxWidth: width * 2,
        minHeight: height,
        maxHeight: height,
        alignment: slice == PageSlice.left
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: child,
      ),
    ),
  );
}
