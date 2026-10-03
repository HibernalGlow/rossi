/// Dart 侧性能账本，与 Rust 的 `crate::perf::ledger` 一对一。
///
/// 分工是这样切的：
/// - **Rust 账本**量的是「Rust 自己花了多久」，在计算线程上取时间，不受 isolate 调度影响。
/// - **本文件**量的是「Dart 等这一件事等了多久」，是墙钟，包含 isolate 排队、FRB 序列化、
///   以及跨桥的内存拷贝。
///
/// 两边用**同名标签**，报告层就把「等」减去「算」，差值即过桥成本。
/// 差值为负说明埋点写错了，报告里显式标出来而不是吞掉。
///
/// 默认关。打开只由调试页做，release 常态下一次 `measure` 的成本是一次布尔判断。
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 一个标签的累计值。与 Rust 的 `PerfCounter` 字段对齐。
class PerfBucket {
  PerfBucket(this.label);

  final String label;
  int count = 0;
  int totalUs = 0;
  int maxUs = 0;

  /// 初值取哨兵 `-1` 而不是 0，否则最小值永远报 0。
  int minUs = -1;
  int bytes = 0;

  void add(int microseconds, {int byteCount = 0}) {
    count += 1;
    totalUs += microseconds;
    if (microseconds > maxUs) maxUs = microseconds;
    if (minUs < 0 || microseconds < minUs) minUs = microseconds;
    bytes += byteCount;
  }

  int get avgUs => count == 0 ? 0 : totalUs ~/ count;

  /// 未记过时把哨兵值折成 0，别让 UI 显示 `-1`。
  int get minUsOrZero => minUs < 0 ? 0 : minUs;
}

/// 一段手动计时的句柄，允许在 `await` 之前先落账。
class PerfScope {
  PerfScope._(this._label, this._sw);

  final String? _label;
  final Stopwatch? _sw;
  bool _done = false;

  bool get isActive => _sw != null && !_done;

  /// 落账并返回本次时长。重复调用返回 0。
  int stop({int byteCount = 0}) {
    final sw = _sw;
    if (sw == null || _done) return 0;
    _done = true;
    final us = sw.elapsedMicroseconds;
    PerfLedger.record(_label!, us, byteCount: byteCount);
    return us;
  }
}

/// 进程内账本。
///
/// 用普通 [Map]：Dart 侧只有一个 isolate 写它，不存在竞态。
class PerfLedger {
  PerfLedger._();

  static final Map<String, PerfBucket> _buckets = {};

  /// 记账总开关。关掉只停止新增，不清空。
  static bool enabled = false;

  static Map<String, PerfBucket> snapshot() => Map.unmodifiable(_buckets);

  static void reset() => _buckets.clear();

  static PerfBucket bucketFor(String label) =>
      _buckets.putIfAbsent(label, () => PerfBucket(label));

  static void record(String label, int microseconds, {int byteCount = 0}) {
    if (!enabled) return;
    bucketFor(label).add(microseconds, byteCount: byteCount);
  }

  static void recordBytes(String label, int byteCount) {
    if (!enabled) return;
    bucketFor(label).bytes += byteCount;
  }

  /// 开一段计时窗口。关掉时返回空句柄，[PerfScope.stop] 恒为 0 且不取时钟。
  static PerfScope open(String label) {
    if (!enabled) return PerfScope._(null, null);
    return PerfScope._(label, Stopwatch()..start());
  }

  /// 量一段同步代码。同步路径顺带写一条 DevTools Timeline 事件，
  /// 这样 profile 构建的帧图里能直接看见同名区段与 Rust span 对齐。
  static T measureSync<T>(String label, T Function() body) {
    if (!enabled) return body();
    final sw = Stopwatch()..start();
    if (_timelineOn) developer.Timeline.startSync(label);
    try {
      return body();
    } finally {
      if (_timelineOn) developer.Timeline.finishSync();
      record(label, sw.elapsedMicroseconds);
    }
  }

  /// 量一次 `await`。**这是墙钟**：包含 isolate 被别的事占住的时间。
  /// 只有与 Rust 同名标签的自耗时相减才得到过桥成本，所以调用点上不要省这一层。
  static Future<T> measureAsync<T>(String label, Future<T> Function() body) async {
    if (!enabled) return await body();
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      record(label, sw.elapsedMicroseconds);
    }
  }

  /// Timeline 只在 debug/profile 写：release 下 `dart:developer` 依然会构造参数，
  /// 而我们不想让埋点自己进被观测的那几帧。
  static bool get _timelineOn => kDebugMode || kProfileMode;
}
