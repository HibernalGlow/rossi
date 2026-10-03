/// 性能剖析工具的统一出口。
///
/// 用法：调试页装 `FrameTimingMonitor.install()` + `PerfLedger.enabled = true`，
/// 调用点用 `PerfLedger.measureAsync/measureSync` 包一段，Rust 侧同名标签由
/// `crate::perf::perf()` 记录，最后把两边喂给 `PerfReport.build`。
library;

export 'frame_timing_monitor.dart';
export 'perf_ledger.dart';
export 'perf_report.dart';
