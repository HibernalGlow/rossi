/// 波形条取数 —— mImageViewer `video/seek_strip_wave.rs` 的 Dart 侧对接面。
///
/// 上游那张表的关键判断在这里照搬：
/// 1. **整条列一次算完**（`COARSE_BIN_SECS` 100 ms 一格）。上游之所以要窗口解码，
///    是因为它要做「放大到 10 分钟窗口还能拖动」；Rossi 的进度条就 ~180 格宽，
///    一次整条列既简单又更快。真要做缩放再补窗口路径。
/// 2. **缓存键含 (路径, mtime, size)**（上游的 `WaveFileIdentity`）：
///    文件名会重复、内容会变。
/// 3. **归一化在拿到整条列之后做一次**：解码端刻意返回绝对 RMS，
///    否则每个窗口各自归一化会让整条波形看不出响度差 —— 而那是它唯一的作用。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/video/service/video_frame_preview.dart';

class VideoWaveformService {
  VideoWaveformService({this.targetBins = 180});

  static final VideoWaveformService instance = VideoWaveformService();

  /// 进度条宽度的格数量级。多于这个数也不会在 300 px 上多看出什么。
  final int targetBins;

  /// 粗列的最小格宽 = mimage 的 `COARSE_BIN_SECS`。
  static const double _minBinSecs = 0.1;
  static const int _maxCacheEntries = 24;

  final Map<String, VideoWaveformStrip> _cache = <String, VideoWaveformStrip>{};
  final Map<String, Future<VideoWaveformStrip>> _inFlight =
      <String, Future<VideoWaveformStrip>>{};

  /// 取整条波形。任何失败都退化成 [VideoWaveformStrip.empty]（UI 不画波形条），
  /// 因为波形是装饰，不该让一个视频播不了。
  Future<VideoWaveformStrip> stripFor(String path, Duration duration) async {
    if (duration <= Duration.zero) return VideoWaveformStrip.empty;
    final file = File(path);
    final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      return VideoWaveformStrip.empty;
    }
    if (stat.size == 0) return VideoWaveformStrip.empty;

    final key = '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final work = _build(key, path, duration);
    _inFlight[key] = work;
    try {
      return await work;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<VideoWaveformStrip> _build(
    String key,
    String path,
    Duration duration,
  ) async {
    final seconds = duration.inMicroseconds / 1e6;
    final binSecs = math.max(_minBinSecs, seconds / targetBins);
    final Float32List raw;
    try {
      raw = await localVideoWavePeaks(
        path: path,
        start: 0.0,
        end: seconds,
        binSecs: binSecs,
      );
    } catch (_) {
      // 没有音轨 / 容器不认识 / 没有解码器：都是「这条视频没有波形」，不是错误。
      return VideoWaveformStrip.empty;
    }
    if (raw.isEmpty) return VideoWaveformStrip.empty;

    var max = 0.0;
    for (final value in raw) {
      if (value > max) max = value;
    }
    final samples = <double>[
      if (max > 0)
        for (final value in raw) (value / max).clamp(0.0, 1.0)
      else
        for (final _ in raw) 0.0,
    ];
    final strip = VideoWaveformStrip(
      samples: samples,
      duration: duration,
      binSecs: binSecs,
    );
    _cache[key] = strip;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return strip;
  }

  void clearCache() => _cache.clear();
}
