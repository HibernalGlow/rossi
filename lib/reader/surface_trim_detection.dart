import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/reader/margin_fit_cache.dart';
import 'package:zephyr/reader/page_source.dart';

typedef SurfaceTrimDetector =
    Future<Rect?> Function(
      PageSource source,
      int index,
      Uint8List rgba,
      int width,
      int height,
    );

Future<Rect?> detectSurfaceTrim(
  PageSource source,
  int index,
  Uint8List rgba,
  int width,
  int height,
) => MarginFitCache.instance.bboxFor(
  source: source,
  pageIndex: index,
  rgba: rgba,
  width: width,
  height: height,
);

/// 检测只排一次；换页、参数变化和关闭开关会作废在飞结果。
/// GPU 路按最长边采样，CPU 路复用已解码像素，两条路共用同一请求身份。
class SurfaceTrimDetection {
  static const maxEdge = 1000;
  int _generation = 0;
  (PageSource, int, String)? _request;

  void reset() {
    _generation++;
    _request = null;
  }

  int? _claim(PageSource source, int index) {
    final request = (source, index, AutoTrimSettings.options.value.cacheKey);
    if (_request == request) return null;
    _request = request;
    return ++_generation;
  }

  Future<void> fromSource({
    required PageSource source,
    required int index,
    required Future<Size?> Function() sizeOf,
    required bool Function() isCurrent,
    required void Function(Rect?, Size) resolved,
    SurfaceTrimDetector detector = detectSurfaceTrim,
  }) async {
    final generation = _claim(source, index);
    if (generation == null) return;
    bool current() => generation == _generation && isCurrent();
    try {
      final size = await sizeOf();
      if (!current()) return;
      if (size == null ||
          size.isEmpty ||
          !size.width.isFinite ||
          !size.height.isFinite) {
        _request = null;
        return;
      }
      final width = math
          .min(
            size.width,
            maxEdge * size.width / math.max(size.width, size.height),
          )
          .round()
          .clamp(1, maxEdge);
      final outcome = await source.load(
        index,
        targetWidth: width,
        intent: PageLoadIntent.prefetch,
      );
      if (!current()) return;
      if (outcome case PageLoaded(
        content: RasterPageContent(:final rgba, :final width, :final height),
      )) {
        final rect = await detector(source, index, rgba, width, height);
        if (current()) resolved(rect, size);
      } else {
        _request = null;
      }
    } catch (_) {
      if (current()) _request = null;
    }
  }

  Future<void> fromPixels({
    required PageSource source,
    required int index,
    required Uint8List rgba,
    required int width,
    required int height,
    required bool Function() isCurrent,
    required void Function(Rect?, Size) resolved,
    SurfaceTrimDetector detector = detectSurfaceTrim,
  }) async {
    final generation = _claim(source, index);
    if (generation == null) return;
    try {
      final rect = await detector(source, index, rgba, width, height);
      if (generation == _generation && isCurrent()) {
        resolved(rect, Size(width.toDouble(), height.toDouble()));
      }
    } catch (_) {
      if (generation == _generation) _request = null;
    }
  }
}
