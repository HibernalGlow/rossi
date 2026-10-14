import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 只持有预览缩略图；面板收起、换页后释放，不持有整页位图或模型会话。
class ProcessingPreview {
  ProcessingPreview({
    required this.status,
    this.before,
    this.after,
    this.trimRect,
  });
  final String status;
  final ui.Image? before;
  final ui.Image? after;
  final Rect? trimRect;

  void dispose() {
    before?.dispose();
    if (!identical(before, after)) after?.dispose();
  }
}

/// 展开后检查阅读器已经应用的结果。这里不重新检测、不启动 AI 推理。
abstract final class ProcessingPreviewLoader {
  static const displayEdge = 720;
  static CurrentPageImageRef? get currentPage =>
      CurrentPageImageInfo.instance.current;

  static Object? identityOf(CurrentPageImageRef? ref) {
    if (ref == null) return null;
    if (ref.source != null) return (ref.source, ref.index);
    return ref.originalPath ?? ref.filePath;
  }

  /// 同页处理完成也要刷新；单纯重绘纹理则不重新读取预览图。
  static Object? stateOf(CurrentPageImageRef? ref, {required bool trim}) {
    if (ref == null) return null;
    if (trim) {
      final key = AutoTrimSettings.options.value.cacheKey;
      return (
        identityOf(ref),
        ref.filePath,
        ref.trimEnabled,
        ref.halfPage,
        key,
        ref.trimLayout?.hasResultFor(ref.trimIndex ?? -1, key),
        ref.trimLayout?.rectFor(ref.trimIndex ?? -1, key),
      );
    }
    final presenter = ref.presenter;
    final status = presenter?.upscaleStatusForPage(ref.index ?? -1);
    return (
      identityOf(ref),
      ref.filePath,
      status?.phase,
      presenter?.isDenoiseEnabled,
      presenter?.isUpscaleEnabled,
    );
  }

  static Future<ProcessingPreview?> trim(CurrentPageImageRef ref) async {
    final key = AutoTrimSettings.options.value.cacheKey;
    final index = ref.trimIndex ?? -1;
    final ready = ref.trimLayout?.hasResultFor(index, key) ?? false;
    final rect = ref.trimEnabled && !ref.halfPage
        ? ref.trimLayout?.rectFor(index, key)
        : null;
    final status = !ref.trimEnabled
        ? t.realSr.previewTrimOff
        : ref.halfPage
        ? t.realSr.previewTrimSplitPage
        : !ready
        ? t.realSr.previewTrimPending
        : rect == null
        ? t.realSr.previewTrimNotNeeded
        : t.realSr.previewTrimApplied(summary: _trimSummary(rect));
    // 本地页对应原纹理；文件页必须解当前显示文件，矩形可能检测自增强图或译文。
    final (image, _) = await _decodeRef(ref, displayed: true);
    return ProcessingPreview(before: image, trimRect: rect, status: status);
  }

  static String _trimSummary(Rect rect) {
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    return t.realSr.trimInsets(
      left: pct(rect.left),
      top: pct(rect.top),
      right: pct(1 - rect.right),
      bottom: pct(1 - rect.bottom),
    );
  }

  static Future<ProcessingPreview?> denoise(
    CurrentPageImageRef ref, {
    required bool Function() cancelled,
  }) async {
    ui.Image? before;
    ui.Image? after;
    try {
      final decoded = await _decodeRef(ref);
      before = decoded.$1;
      if (cancelled()) return null;
      final options = await ImageDenoiseSettings.loadOptions();
      String? resultPath;
      String status;
      if (options.jpegOnly && !decoded.$2) {
        status = t.realSr.previewDenoiseJpegOnly;
      } else if (ref.presenter case final presenter?) {
        final pageStatus = presenter.upscaleStatusForPage(ref.index!);
        if (!presenter.isDenoiseEnabled) {
          status = t.realSr.previewDenoiseOff;
        } else if (pageStatus.phase == SuperResolutionPagePhase.applied &&
            identical(presenter.presentedFrame?.source, ref.source) &&
            presenter.presentedFrame?.index == ref.index) {
          final key = await ImageDenoiseSettings.cacheKey(
            denoise: true,
            options: options,
            upscale: presenter.isUpscaleEnabled,
            upscaleKey: await RealSrSettings.loadCacheKey(),
          );
          resultPath = p.join(
            (await SuperResolutionLog.cacheDirectory()).path,
            'sr_${ref.source!.path.hashCode}_${ref.index}_$key.png',
          );
          status = presenter.isUpscaleEnabled
              ? t.realSr.previewBothApplied
              : t.realSr.previewDenoiseApplied;
        } else {
          status = t.realSr.previewDenoisePending(
            phase: imageEnhancementPhaseLabel(pageStatus),
          );
        }
      } else if (await ImageDenoiseSettings.enabledFor(ref.bookKey) &&
          ref.originalPath != null &&
          ref.filePath != ref.originalPath) {
        resultPath = ref.filePath;
        status = t.realSr.previewDenoiseCompare;
      } else {
        status = t.realSr.previewDenoiseOriginal;
      }
      if (cancelled()) return null;
      if (resultPath != null) {
        after = await _decodeFile(File(resultPath));
        if (after == null) status = t.realSr.previewEnhancedUnreadable;
      }
      final preview = ProcessingPreview(
        before: before,
        after: after,
        status: status,
      );
      before = null;
      after = null;
      return preview;
    } finally {
      before?.dispose();
      after?.dispose();
    }
  }

  static Future<(ui.Image?, bool)> _decodeRef(
    CurrentPageImageRef ref, {
    bool displayed = false,
  }) async {
    final path = displayed ? ref.filePath : ref.originalPath ?? ref.filePath;
    if (path != null) {
      final bytes = await File(path).readAsBytes();
      return (await _decodeBytes(bytes), _isJpeg(bytes));
    }
    final source = ref.source;
    final index = ref.index;
    if (source == null || index == null) return (null, false);
    final direct = await source.getPageFilePath(index);
    final bytes = direct != null
        ? await File(direct).readAsBytes()
        : await source.getPageBytes(index);
    if (bytes != null) {
      final image = await _decodeBytes(bytes);
      if (image != null) return (image, _isJpeg(bytes));
    }
    // Flutter 不认识的格式才回退原生解码；尺寸未知时不冒险展开整张长条页。
    final size = await ref.presenter?.sourceSizeFor(source, index);
    if (size == null || size.isEmpty) return (null, false);
    final width = (displayEdge * size.width / size.longestSide).round().clamp(
      1,
      displayEdge,
    );
    final outcome = await source.load(
      index,
      targetWidth: width,
      intent: PageLoadIntent.prefetch,
    );
    if (outcome case PageLoaded(
      content: RasterPageContent(:final rgba, :final width, :final height),
    )) {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return (await completer.future, bytes != null && _isJpeg(bytes));
    }
    return (null, false);
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8;

  static Future<ui.Image?> _decodeFile(File file) async {
    if (!await file.exists()) return null;
    return _decodeBytes(await file.readAsBytes());
  }

  static Future<ui.Image?> _decodeBytes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final wide = descriptor.width >= descriptor.height;
      codec = await descriptor.instantiateCodec(
        targetWidth: wide && descriptor.width > displayEdge
            ? displayEdge
            : null,
        targetHeight: !wide && descriptor.height > displayEdge
            ? displayEdge
            : null,
      );
      if (codec.frameCount != 1) return null;
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
