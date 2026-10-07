import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/cubit/image_size_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/model/page_split.dart';
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

  /// 横长页被拆成两格时，这一格只画原图的**哪一半**（[PageSlice.full] = 整页）。
  ///
  /// 裁剪必须发生在这一层：`ImageSurface` 那条路有纹理/着色器可以只取半幅 UV，
  /// 这条网络/已下载文件的路**没有着色器**，`Image` 自己没有任何办法只画一半 ——
  /// 不在这里裁，整幅横图就会被塞进半格里（等比缩到一半宽，字小到读不了）。
  final PageSlice slice;

  const ImageDisplay({
    super.key,
    required this.imagePath,
    required this.isColumn,
    required this.pageSlotIndex,
    required this.sizeCacheIndex,
    this.imageAlignment = Alignment.center,
    this.paintSize,
    this.slice = PageSlice.full,
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

        if (_rawWidth != null && paintSize == null) {
          // 有 paintSize 时**不**回写尺寸缓存：那时 width 是缩放后的显示尺寸，
          // 拖一下滑条就把宽高比缓存洗一遍，下一本书的首帧比例就错了。
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
        return wrapPageSlice(
          page,
          slice: widget.slice,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
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
