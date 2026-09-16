//! 页加载调度事件的出口。**本地新增，不对应上游任何文件。**
//!
//! 上游 `fs_page_load_scheduler.rs` 用 `crate::perf::event(...)` / `crate::perf::is_enabled()`
//! 上报调度事件，字段值走 `serde_json::Value`（上游 `src/perf.rs` 是一套完整的
//! JSONL 性能日志系统，约 200 行）。
//!
//! Rossi 的移植**不引 serde_json**（`rossi_local_core` 目前只依赖 anyhow / image / zip /
//! unrar，加 serde 会让这一层凭空背上一棵依赖树），改成这里的轻量 `PerfValue` +
//! 可注入 sink。`is_enabled()` / `event()` 的**签名形状与上游一致**，
//! 上游改埋点字段时能逐行对照 —— 这是刻意保持的。
//!
//! 默认 sink 不存在 ⇒ `is_enabled()` 为 false ⇒ 调度器一次也不构造事件载荷
//! （与上游 `perf` 未启用时的行为一致）。要接上，App 侧调 [`install`]。

use std::sync::{Arc, OnceLock};

/// 调度事件的字段值，替代上游的 `serde_json::Value`。
///
/// 只覆盖调度器实际用到的四类：计数、序号、毫秒、标签。
#[derive(Clone, Debug, PartialEq)]
pub enum PerfValue {
    Usize(usize),
    U64(u64),
    F64(f64),
    Str(&'static str),
}

impl From<usize> for PerfValue {
    fn from(value: usize) -> Self {
        Self::Usize(value)
    }
}

impl From<u64> for PerfValue {
    fn from(value: u64) -> Self {
        Self::U64(value)
    }
}

impl From<f64> for PerfValue {
    fn from(value: f64) -> Self {
        Self::F64(value)
    }
}

impl From<&'static str> for PerfValue {
    fn from(value: &'static str) -> Self {
        Self::Str(value)
    }
}

impl PerfValue {
    /// 给日志用。刻意不实现 `Display` —— 这是埋点载荷，不是面向用户的值。
    pub fn as_text(&self) -> String {
        match self {
            Self::Usize(v) => v.to_string(),
            Self::U64(v) => v.to_string(),
            Self::F64(v) => format!("{v:.3}"),
            Self::Str(v) => (*v).to_string(),
        }
    }
}

/// 接收调度事件的出口。实现方决定落地形式（日志、JSONL、计数器都行）。
pub trait PageLoadPerfSink: Send + Sync {
    fn event(
        &self,
        cat: &str,
        kind: &str,
        key: Option<&str>,
        seq: u64,
        extras: &[(&str, PerfValue)],
    );
}

static SINK: OnceLock<Arc<dyn PageLoadPerfSink>> = OnceLock::new();

/// 装上出口。进程内只生效一次，返回是否为本次调用所装。
pub fn install(sink: Arc<dyn PageLoadPerfSink>) -> bool {
    SINK.set(sink).is_ok()
}

/// 与上游 `perf::is_enabled()` 同义：没装出口就没人在听，事件载荷不必构造。
pub fn is_enabled() -> bool {
    SINK.get().is_some()
}

/// 与上游 `perf::event()` 同形。`key` / `seq` 是上游的调用点标识（归档路径 + 序号）。
pub fn event(cat: &str, kind: &str, key: Option<&str>, seq: u64, extras: &[(&str, PerfValue)]) {
    let Some(sink) = SINK.get() else {
        return;
    };
    sink.event(cat, kind, key, seq, extras);
}
