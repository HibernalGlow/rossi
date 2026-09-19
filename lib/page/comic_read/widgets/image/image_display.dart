import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/setting/real_sr/service/upscaled_image_cache.dart';

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

  const ImageDisplay({
    super.key,
    required this.imagePath,
    required this.isColumn,
    required this.pageSlotIndex,
    required this.sizeCacheIndex,
    this.imageAlignment = Alignment.center,
    this.paintSize,
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

  double? _rawWidth;
  double? _rawHeight;
  bool _einkDelayFinished = true;
  bool _wasRowActive = false;

  bool get isColumn => widget.isColumn;

  @override
  void initState() {
    super.initState();
    _replacementSubscription = UpscaledImageCache.replacements.listen(
      _onImageReplaced,
    );
    _resolveImageMeta();
    _startEinkDelayIfNeeded(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
  }

  @override
  void didUpdateWidget(covariant ImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isColumn != oldWidget.isColumn ||
        widget.imagePath != oldWidget.imagePath) {
      _stopListening();
      _rawWidth = null;
      _rawHeight = null;
      _resolveImageMeta();
    }

    if (widget.isColumn) {
      _einkDelayTimer?.cancel();
      _einkDelayFinished = true;
      _wasRowActive = false;
      return;
    }

    _startEinkDelayIfNeeded(
      context.read<GlobalSettingCubit>().state.readSetting,
    );
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

  void _onImageReplaced(String path) {
    if (!mounted || path != widget.imagePath) return;

    _stopListening();
    setState(() {
      _rawWidth = null;
      _rawHeight = null;
      _imageRevision++;
    });
    _resolveImageMeta();
  }

  void _resolveImageMeta() {
    final imageProvider = FileImage(File(widget.imagePath));
    final newStream = imageProvider.resolve(ImageConfiguration.empty);

    final newListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        if (!mounted) return;

        _rawWidth = imageInfo.image.width.toDouble();
        _rawHeight = imageInfo.image.height.toDouble();

        if (context.mounted) {
          // 原始像素尺寸要单独报给 cubit：`reader.original`（原始大小）要的是绝对
          // 像素，而下面 `_updateCubitSize` 记的是「按某个宽度铺出来的显示尺寸」，
          // 那里只有宽高比可信。
          context.read<ImageSizeCubit>().updateIntrinsicSize(
            widget.sizeCacheIndex,
            Size(_rawWidth!, _rawHeight!),
          );
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            _updateCubitSize(renderBox.size.width);
          }
        }
      },
      onError: (exception, stackTrace) {
        logger.e('Failed to resolve image size: $exception');
      },
    );

    _imageStream = newStream;
    _imageListener = newListener;
    newStream.addListener(newListener);
  }

  void _updateCubitSize(double actualWidth) {
    if (_rawWidth == null || _rawHeight == null || _rawWidth == 0) return;

    final index = widget.sizeCacheIndex;
    final cubit = context.read<ImageSizeCubit>();

    final double finalHeight = (_rawHeight! / _rawWidth!) * actualWidth;

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

  @override
  void dispose() {
    _replacementSubscription?.cancel();
    _stopListening();
    _einkDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );
    final brightness = Theme.of(context).brightness;
    final backgroundColor = readSetting.resolveReaderBackgroundColor(
      brightness,
    );
    final foregroundColor = readSetting.resolveReaderForegroundColor(
      brightness,
    );
    final progressColor = foregroundColor.withValues(alpha: 0.3);
    final readMode = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.readMode,
    );
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

        if (_rawWidth != null && paintSize == null) {
          // 有 paintSize 时**不**回写尺寸缓存：那时 width 是缩放后的显示尺寸，
          // 拖一下滑条就把宽高比缓存洗一遍，下一本书的首帧比例就错了。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateCubitSize(width);
          });
        }

        return Align(
          alignment: widget.imageAlignment,
          child: Image.file(
            File(widget.imagePath),
            // 同路径覆盖后必须重建 ImageState，单独清理缓存不会切换旧图片流。
            key: ValueKey((widget.imagePath, _imageRevision)),
            width: width,
            height: paintSize?.height,
            fit: paintSize != null
                ? BoxFit.fill
                : isColumn
                ? BoxFit.fill
                : BoxFit.contain,
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

              if (isColumn) {
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
              } else {
                if (canUseEinkMask && isActiveRowImage && !_einkDelayFinished) {
                  return Container(width: width, color: Colors.white);
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
            },
          ),
        );
      },
    );
  }
}
