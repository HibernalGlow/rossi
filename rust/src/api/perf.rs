//! 性能账本的 FRB 门面。与 [`crate::api::memory`] 同形：
//! 纯同步读，返回累计值，由调试页轮询。
//!
//! 标签含义见 [`crate::perf::ledger`]。Dart 侧负责算「自耗时」
//! （父标签减去子标签），这里只出扁平累计。

use flutter_rust_bridge::frb;

use crate::perf;

/// 打开/关闭记账。关掉不清空已有数据。
#[frb(sync)]
pub fn set_perf_enabled(enabled: bool) {
    perf::set_enabled(enabled);
}

#[frb(sync)]
pub fn is_perf_enabled() -> bool {
    perf::is_enabled()
}

/// 当前快照，按累计总时长降序。
pub fn get_perf_snapshot() -> Vec<PerfEntry> {
    perf::snapshot()
}

/// 清空账本。分两段看数据时用（例如「进阅读页前 / 翻 20 页后」）。
pub fn reset_perf_stats() {
    perf::reset();
}

/// 快照里的一行。直接沿用账本的类型，避免门面与内核各有一份字段表。
pub use crate::perf::PerfEntry;
