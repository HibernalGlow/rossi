/// 帧时长监控：把 Flutter 引擎报的 [ui.FrameTiming] 汇成「掉帧在哪条线程」。
///
/// 这是本套工具里唯一直接量 UI 表现的一块，也是唯一不需要跨桥的一块，
/// 所以它和 `PerfLedger` 是**互补**而不是重叠：
/// - 账本回答「某件事花了多久」；
/// - 本文件回答「屏幕上哪一帧超标了，超在 build 还是 raster」。
///
/// 刷新周期不查 API，直接从相邻帧 `vsyncStart` 的时间差取中位数推出来。
/// 理由：`displayRefreshRate` 各平台可用性不一致，而自适应刷新率的屏
/// （1–120Hz）根本不存在一个常数预算可拿来比 —— 观测到的节奏比声明的规格诚实。
library;

import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// 累计的帧统计。全是累计值，与账本口径一致。
class FrameStats {
  int frames = 0;

  /// 任一条线程超标即算 janky；两条都超只算一次。
  int jankyFrames = 0;
  int severeFrames = 0;

  int totalBuildUs = 0;
  int totalRasterUs = 0;
  int totalVsyncOverheadUs = 0;

  int maxBuildUs = 0;
  int maxRasterUs = 0;

  /// 超标帧里 build 占多数还是 raster 占多数 —— 决定去看 Dart 侧还是去看纹理/上传。
  int buildLimitedJank = 0;
  int rasterLimitedJank = 0;

  /// 相邻帧间隔远大于预算的次数。这类不是「这帧慢」而是「那段时间根本没出帧」，
  /// 通常是 isolate 被一件同步慢事占住。和慢帧是两种病，混看会误诊。
  int stallFrames = 0;
  int maxGapUs = 0;

  int totalLayerCacheBytes = 0;
  int totalPictureCacheBytes = 0;

  int _lastVsyncUs = -1;
  List<int> _gapsUs = const [];

  /// 由观测推导的刷新周期。样本不足时为 null，此时**不做**任何超标判定。
  int? refreshPeriodUs;

  double get jankRate => frames == 0 ? 0 : jankyFrames / frames;
  double get severeRate => frames == 0 ? 0 : severeFrames / frames;
  int get avgBuildUs => frames == 0 ? 0 : totalBuildUs ~/ frames;
  int get avgRasterUs => frames == 0 ? 0 : totalRasterUs ~/ frames;

  void observe(ui.FrameTiming t) {
    final build = t.buildDuration.inMicroseconds;
    final raster = t.rasterDuration.inMicroseconds;
    final vsync = t.vsyncOverhead.inMicroseconds;
    final vsyncStart = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);

    frames += 1;
    totalBuildUs += build;
    totalRasterUs += raster;
    totalVsyncOverheadUs += vsync;
    if (build > maxBuildUs) maxBuildUs = build;
    if (raster > maxRasterUs) maxRasterUs = raster;
    totalLayerCacheBytes += t.layerCacheBytes;
    totalPictureCacheBytes += t.pictureCacheBytes;

    if (_lastVsyncUs >= 0) {
      final gap = vsyncStart - _lastVsyncUs;
      if (gap > 0) {
        if (gap > maxGapUs) maxGapUs = gap;
        _gapsUs = [..._gapsUs, gap];
        if (_gapsUs.length > 240) {
          _gapsUs = _gapsUs.sublist(_gapsUs.length - 240);
        }
        final period = refreshPeriodUs;
        if (period != null && gap > period * 4) {
          stallFrames += 1;
        }
      }
    }
    _lastVsyncUs = vsyncStart;

    _deriveRefreshPeriod();

    final period = refreshPeriodUs;
    if (period == null) return;

    // 预算取一个完整刷新周期，判定用 `>` 不用 `>=`：
    // 刚好一帧的常态抖动不该被计入。
    if (build > period || raster > period) {
      jankyFrames += 1;
      if (build > raster) {
        buildLimitedJank += 1;
      } else {
        rasterLimitedJank += 1;
      }
    }
    if (build > period * 2 || raster > period * 2) {
      severeFrames += 1;
    }
  }

  /// 中位数间隔即屏的刷新周期。样本少于 30 帧不下结论 ——
  /// 冷启动首帧与后续帧的间隔本来就不可比。
  void _deriveRefreshPeriod() {
    if (_gapsUs.length < 30) return;
    final sorted = [..._gapsUs]..sort();
    final median = sorted[sorted.length ~/ 2];
    // 夹在合理区间：4ms(250Hz) ~ 40ms(25Hz)。越界说明取到的是「停帧」不是节奏。
    if (median < 4000 || median > 40000) return;
    refreshPeriodUs = median;
  }

  void reset() {
    frames = 0;
    jankyFrames = 0;
    severeFrames = 0;
    totalBuildUs = 0;
    totalRasterUs = 0;
    totalVsyncOverheadUs = 0;
    maxBuildUs = 0;
    maxRasterUs = 0;
    buildLimitedJank = 0;
    rasterLimitedJank = 0;
    stallFrames = 0;
    maxGapUs = 0;
    totalLayerCacheBytes = 0;
    totalPictureCacheBytes = 0;
    _lastVsyncUs = -1;
    _gapsUs = const [];
    refreshPeriodUs = null;
  }
}

/// 进程内单例。装一次，之后由引擎回调驱动。
///
/// 不设开关：帧时长回调在 release 下引擎本来就在攒，注册与否只影响是否上报，
/// 代价与账本不是一个量级。要清零用 [reset]。
class FrameTimingMonitor {
  FrameTimingMonitor._();

  static final FrameStats stats = FrameStats();
  static bool _installed = false;

  /// 最近 [recentCap] 次超标帧的**挂钟**时刻（ms since epoch）。
  /// 用来回答「刚才那一下卡是几秒前」，并和账本的采样窗口对齐。
  static final List<int> _recentJankWallMs = [];
  static const int recentCap = 64;

  static List<int> get recentJankWallMs => List.unmodifiable(_recentJankWallMs);

  static bool get isInstalled => _installed;

  static void install() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void uninstall() {
    if (!_installed) return;
    _installed = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  static void reset() {
    stats.reset();
    _recentJankWallMs.clear();
  }

  static void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      final before = stats.jankyFrames;
      stats.observe(t);
      if (stats.jankyFrames > before) {
        _recentJankWallMs.add(DateTime.now().millisecondsSinceEpoch);
        if (_recentJankWallMs.length > recentCap) {
          _recentJankWallMs.removeAt(0);
        }
      }
    }
  }
}
