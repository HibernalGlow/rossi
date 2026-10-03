//! 跨语言性能账本。**本地新增，不对应上游任何文件。**
//!
//! 回答的问题是「时间掉在哪一层」，不是「代码写得对不对」，所以刻意做得很薄：
//! 一个 `DashMap<&'static str, PerfCounter>`，配一个 Drop 时记账的守卫。
//!
//! # 为什么不开 `tracing::instrument`
//!
//! 本仓的 subscriber（`api/user_utils.rs`）把事件送到 logcat / stdout / HTTP 日志，
//! 每条 span 都要格式化并落盘。阅读页一次滚动就是几十次解码，埋点本身就会变成
//! 被观测对象的一部分。这里只改几个 `u64`，观测者不进被观测系统。
//!
//! # 默认关
//!
//! [`perf`] 在 [`is_enabled`] 为 false 时的成本是一次 relaxed 原子读 + 分支，
//! 且**不取时钟**。由 Dart 侧调试页显式打开，release 路径常态为零。
//!
//! # 标签即层级
//!
//! 标签用 `.` 分段（`frb.local_page_pixels.decode`）。父子关系不记录在账本里 ——
//! Dart 侧按前缀算「自耗时」，所以这里不需要维护嵌套栈，也允许父子跨线程。
//!
//! # 为什么是可实例化的 `Arc` 而不是纯全局
//!
//! 单测共用进程级全局会互相撞（libtest 默认并行）：断言「关掉后什么都没记上」
//! 会被另一条测试的 `set_enabled(true)` 直接打穿。所以内核是 [`PerfLedger`] 实例，
//! 全局那份只是 [`global()`] 的一个 `LazyLock`，测试各自 new 一份。

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};

/// 一个标签的累计量。全是累计值，不是样本序列 —— 要分位数得落 trace 文件。
#[derive(Clone, Copy, Debug)]
pub struct PerfCounter {
    pub count: u64,
    pub total_ns: u64,
    pub max_ns: u64,
    /// 初值是 `u64::MAX` 而不是 0，否则「最小值」永远报 0。
    pub min_ns: u64,
    /// 只有 [`PerfLedger::record_bytes`] 会填：跨桥载荷的字节累计，
    /// 用来把「拷贝」从「计算」里摘出去。
    pub bytes: u64,
}

impl Default for PerfCounter {
    fn default() -> Self {
        Self {
            count: 0,
            total_ns: 0,
            max_ns: 0,
            min_ns: u64::MAX,
            bytes: 0,
        }
    }
}

/// 性能账本。用 `DashMap`（已是本仓依赖）而不是 `Mutex<HashMap>`：
/// 解码跑在 `spawn_blocking` 的线程池上，一次翻页会有多个标签并发落账，
/// 单锁会让埋点自己变成串行点。
#[derive(Default)]
pub struct PerfLedger {
    counters: dashmap::DashMap<&'static str, PerfCounter>,
    enabled: AtomicBool,
}

impl PerfLedger {
    pub fn new() -> Self {
        Self::default()
    }

    /// 记账总开关。关掉只停止**新增**，不清空已有数据。
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// 开始一段计时。关掉时返回空守卫，Drop 是 no-op。
    pub fn start(self: &Arc<Self>, label: &'static str) -> PerfSample {
        if self.is_enabled() {
            PerfSample {
                inner: Some(PerfSampleInner {
                    ledger: self.clone(),
                    label,
                    start: Instant::now(),
                }),
            }
        } else {
            PerfSample { inner: None }
        }
    }

    /// 已经算好的时长（例如从队列时间戳减出来的等待时间）直接入账。
    pub fn record(self: &Arc<Self>, label: &'static str, elapsed: Duration) {
        if !self.is_enabled() {
            return;
        }
        let ns = elapsed.as_nanos() as u64;
        self.counters
            .entry(label)
            .and_modify(|c| {
                c.count += 1;
                c.total_ns += ns;
                c.max_ns = c.max_ns.max(ns);
                c.min_ns = c.min_ns.min(ns);
            })
            .or_insert(PerfCounter {
                count: 1,
                total_ns: ns,
                max_ns: ns,
                min_ns: ns,
                bytes: 0,
            });
    }

    /// 记一批字节。标签通常与同名的计时标签一致，Dart 侧就能并排显示「多少 ms / 多少 MB」。
    pub fn record_bytes(self: &Arc<Self>, label: &'static str, bytes: u64) {
        if !self.is_enabled() {
            return;
        }
        self.counters
            .entry(label)
            .and_modify(|c| c.bytes += bytes)
            .or_insert(PerfCounter {
                count: 0,
                bytes,
                ..PerfCounter::default()
            });
    }

    /// 快照：按累计总时长降序。跨桥只在这一次发生，且只在调试页点「刷新」时。
    pub fn snapshot(&self) -> Vec<PerfEntry> {
        let mut rows: Vec<PerfEntry> = self
            .counters
            .iter()
            .map(|e| {
                let c = *e.value();
                PerfEntry {
                    label: (*e.key()).to_string(),
                    count: c.count,
                    total_us: c.total_ns / 1_000,
                    avg_us: avg_us(c.total_ns, c.count),
                    max_us: c.max_ns / 1_000,
                    // 没记过的标签把哨兵折成 0，别让 UI 显示一个天文数字。
                    min_us: if c.min_ns == u64::MAX {
                        0
                    } else {
                        c.min_ns / 1_000
                    },
                    bytes: c.bytes,
                }
            })
            .collect();

        rows.sort_by(|a, b| {
            b.total_us
                .cmp(&a.total_us)
                .then_with(|| a.label.cmp(&b.label))
        });
        rows
    }

    pub fn reset(&self) {
        self.counters.clear();
    }
}

fn avg_us(total_ns: u64, count: u64) -> u64 {
    if count == 0 {
        0
    } else {
        (total_ns / count) / 1_000
    }
}

/// 进程级的那一份，给埋点调用点用。
static GLOBAL: LazyLock<Arc<PerfLedger>> = LazyLock::new(|| Arc::new(PerfLedger::new()));

pub fn global() -> Arc<PerfLedger> {
    GLOBAL.clone()
}

/// 埋点调用点的主入口。未启用时只多一次 relaxed 读。
#[inline]
pub fn perf(label: &'static str) -> PerfSample {
    global().start(label)
}

pub fn record(label: &'static str, elapsed: Duration) {
    global().record(label, elapsed);
}

pub fn record_bytes(label: &'static str, bytes: u64) {
    global().record_bytes(label, bytes);
}

pub fn set_enabled(enabled: bool) {
    global().set_enabled(enabled);
}

pub fn is_enabled() -> bool {
    global().is_enabled()
}

pub fn snapshot() -> Vec<PerfEntry> {
    global().snapshot()
}

pub fn reset() {
    global().reset();
}

struct PerfSampleInner {
    ledger: Arc<PerfLedger>,
    label: &'static str,
    start: Instant,
}

/// Drop 时把本次时长入账。未启用时 `inner` 为 None，Drop 什么都不做。
pub struct PerfSample {
    inner: Option<PerfSampleInner>,
}

impl PerfSample {
    /// 提前落账（成功/失败分支时长不同时用），返回是否真的记上了。
    /// 落过之后再次调用返回 false，不会记第二笔。
    pub fn stop(&mut self) -> bool {
        let Some(inner) = self.inner.take() else {
            return false;
        };
        inner.ledger.record(inner.label, inner.start.elapsed());
        true
    }

    /// 这段是否真的在计时。关着的时候为 false，调用点可据此跳过昂贵的标签拼接。
    pub fn is_active(&self) -> bool {
        self.inner.is_some()
    }
}

impl Drop for PerfSample {
    fn drop(&mut self) {
        self.stop();
    }
}

/// 快照里的一行，直接给 FRB / Dart。
#[derive(Debug, Clone)]
pub struct PerfEntry {
    pub label: String,
    pub count: u64,
    pub total_us: u64,
    pub avg_us: u64,
    pub max_us: u64,
    pub min_us: u64,
    pub bytes: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 每条测试各拿一份独立账本：不碰 [`GLOBAL`]，所以并行跑也不会互相打穿。
    fn ledger() -> Arc<PerfLedger> {
        let l = Arc::new(PerfLedger::new());
        l.set_enabled(true);
        l
    }

    #[test]
    fn disabled_records_nothing_and_takes_no_clock() {
        let l = Arc::new(PerfLedger::new());
        assert!(!l.is_enabled());
        {
            let s = l.start("test.disabled");
            assert!(!s.is_active(), "关闭时守卫不应在计时");
        }
        l.record("test.disabled", Duration::from_millis(5));
        l.record_bytes("test.disabled", 1024);
        assert!(l.snapshot().is_empty());
    }

    #[test]
    fn aggregation_and_min_sentinel() {
        let l = ledger();
        l.record("test.agg", Duration::from_micros(300));
        l.record("test.agg", Duration::from_micros(1_000));
        let row = l
            .snapshot()
            .into_iter()
            .find(|r| r.label == "test.agg")
            .unwrap();
        assert_eq!(row.count, 2);
        assert_eq!(row.total_us, 1_300);
        assert_eq!(row.max_us, 1_000);
        assert_eq!(row.min_us, 300);
        assert_eq!(row.avg_us, 650);
    }

    #[test]
    fn guard_stop_is_idempotent() {
        let l = ledger();
        let mut s = l.start("test.guard");
        assert!(s.is_active());
        assert!(s.stop());
        assert!(!s.stop(), "重复 stop 不该记第二笔");
        drop(s);
        let row = l
            .snapshot()
            .into_iter()
            .find(|r| r.label == "test.guard")
            .unwrap();
        assert_eq!(row.count, 1);
    }

    #[test]
    fn record_bytes_does_not_inflate_time() {
        let l = ledger();
        l.record_bytes("test.bytes", 4096);
        let row = l
            .snapshot()
            .into_iter()
            .find(|r| r.label == "test.bytes")
            .unwrap();
        assert_eq!(row.bytes, 4096);
        assert_eq!(row.total_us, 0);
        assert_eq!(row.min_us, 0, "只记字节时 min 不该漏出哨兵值");
    }

    #[test]
    fn snapshot_orders_by_total_desc() {
        let l = ledger();
        l.record("test.big", Duration::from_secs(2));
        l.record("test.small", Duration::from_micros(1));
        let rows = l.snapshot();
        assert_eq!(rows.first().unwrap().label, "test.big");
    }

    #[test]
    fn reset_keeps_the_switch_on() {
        let l = ledger();
        l.record("test.a", Duration::from_micros(1));
        l.reset();
        assert!(l.snapshot().is_empty());
        assert!(l.is_enabled(), "清空不该顺手关掉记账");
        l.record("test.b", Duration::from_micros(1));
        assert_eq!(l.snapshot().len(), 1);
    }
}
