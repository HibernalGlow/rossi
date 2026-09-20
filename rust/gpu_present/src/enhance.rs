//! 超分增强轨的**公共**部分：选轨规则、「原图对比」旁路、证据口径。
//!
//! # 为什么单独一个模块，而不是两份各自实现
//!
//! mac 与 Windows 的像素容器确实不一样：
//!
//! - mac（`mac_presenter.rs`）额外持有**视口尺寸预渲染帧**（`pre_rendered_raw` /
//!   `pre_rendered_enhanced`），并且增强图寄生在页 LRU 条目里，淘汰与原图耦合；
//! - Windows（`presenter.rs`）每次呈现都在 GPU 上重采样，没有预渲染帧，
//!   增强图只能自己按 `(index, epoch)` 存。
//!
//! 把存储强行拍成一份会改掉 mac 侧已验证过的内存行为，不值得。但下面这些**必须**只有一份：
//!
//! 1. 「这一页该用哪一轨」的判定（[`prefers_enhanced`]）；
//! 2. 「原图对比」的旁路语义（[`Bypass`]）；
//! 3. 报给 Dart 的证据字段名（[`STATS_CURRENT_INDEX`] / [`STATS_USED_ENHANCED`]）。
//!
//! 理由不是整洁，而是这个 bug 的原形：证据与选轨规则各写一遍，规则一改就会出现
//! 「画面还是原图、证据说用了超分图」的**假证据** —— 那时日志说成功、画面没换，
//! 而所有断言都是绿的。
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use rossi_local_core::PagePixels;

/// 按 `(index, epoch)` 存增强图。
///
/// # 为什么 mac 不用它
///
/// mac 的增强图寄生在页 LRU 条目里（`CachedPage::enhanced_pixels`），淘汰与原图
/// 耦合，还额外有视口预渲染帧桶；改成这个独立存储会动到 mac 侧已验证过的内存行为。
/// 所以共享的是**规则与证据口径**（[`prefers_enhanced`] / [`Bypass`] / 下面的键名），
/// 存储形状各留一份。Windows 每帧都在 GPU 上重采样、没有预渲染桶，用这个最直。
#[derive(Default)]
pub struct EnhancedStore {
    entries: HashMap<(usize, u64), Arc<PagePixels>>,
    bytes: usize,
    /// 注入过的页数（只增不清），用于诊断「有没有真的注进来过」。
    injected: u64,
}

impl EnhancedStore {
    /// 上限按页留，避免 4× 大图把内存吃掉：一页 2720×3784 RGBA ≈ 41 MB。
    pub const MAX_PAGES: usize = 6;
    pub const MAX_BYTES: usize = 256 * 1024 * 1024;

    pub fn put(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        let key = (index, epoch);
        if let Some(old) = self.entries.remove(&key) {
            self.bytes -= old.byte_len();
        }
        self.bytes += pixels.byte_len();
        self.entries.insert(key, pixels);
        self.injected += 1;
        self.trim();
    }

    pub fn get(&self, index: usize, epoch: u64) -> Option<Arc<PagePixels>> {
        self.entries.get(&(index, epoch)).cloned()
    }

    pub fn has(&self, index: usize, epoch: u64) -> bool {
        self.entries.contains_key(&(index, epoch))
    }

    /// 换来源（`epoch` 变了）时旧代次整体作废。
    pub fn retain_epoch(&mut self, epoch: u64) {
        let stale: Vec<(usize, u64)> = self
            .entries
            .keys()
            .filter(|(_, e)| *e != epoch)
            .copied()
            .collect();
        for key in stale {
            if let Some(p) = self.entries.remove(&key) {
                self.bytes -= p.byte_len();
            }
        }
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        self.bytes = 0;
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// 空不空 —— `len` 配 `is_empty` 是 clippy 的要求，不是装饰：
    /// 上层诊断要直接问「现在有没有增强图可用」。
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn bytes(&self) -> usize {
        self.bytes
    }

    pub fn injected(&self) -> u64 {
        self.injected
    }

    fn trim(&mut self) {
        while self.entries.len() > Self::MAX_PAGES || self.bytes > Self::MAX_BYTES {
            // HashMap 没有 LRU 顺序，这里按"页号离当前最远"无从判断，
            // 退化成任意淘汰并计数；上限本身足够宽，正常阅读不会触发。
            let Some(key) = self.entries.keys().next().copied() else {
                break;
            };
            if let Some(p) = self.entries.remove(&key) {
                self.bytes -= p.byte_len();
            }
        }
    }
}

/// 唯一一条选轨规则：旁路关着、且这一页确实有增强图，才用增强轨。
///
/// 判定与证据必须共用它 —— 呈现路径拿它决定画哪一轨，`stats` 拿它回答
/// 「刚才那一帧用的是哪一轨」。
pub fn prefers_enhanced(enhanced_present: bool, bypass: bool) -> bool {
    !bypass && enhanced_present
}

/// 「原图对比」旁路开关。置位期间增强轨整体不参显（画面回到原图），
/// 但增强图**不删除** —— 关掉对比要能立刻换回去。
#[derive(Default)]
pub struct Bypass(AtomicBool);

impl Bypass {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set(&self, active: bool) {
        self.0.store(active, Ordering::SeqCst);
    }

    pub fn active(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }

    /// 本次呈现是否该用增强轨。
    pub fn prefers_enhanced(&self, enhanced_present: bool) -> bool {
        prefers_enhanced(enhanced_present, self.active())
    }
}

/// 证据字段名：Dart 侧 `GpuPresentController::_presenterUsesEnhanced` 按这两个键读，
/// 判据是 `usedEnhanced` 必须是 0 或 1、且 `currentIndex` 就是它问的那一页。
///
/// 写成常量而不是两处各敲一遍字符串：拼错一个字母的代价是「永远无法核对」，
/// 而那条路径在 Dart 侧是**静默**返回 null 的。
pub const STATS_CURRENT_INDEX: &str = "currentIndex";
pub const STATS_USED_ENHANCED: &str = "usedEnhanced";

/// `usedEnhanced` 的取值：1 = 这一帧取自超分轨，0 = 取自原图轨。
///
/// 只有 0/1 两个值是「已核对」；Dart 侧把其它值（含缺键）一律当「无法核对」，
/// 既不报成功也不报失败。
pub fn used_enhanced_flag(enhanced_used: bool) -> u8 {
    u8::from(enhanced_used)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 规则的往返：旁路开着时，即使有增强图也必须回原图轨。
    ///
    /// 只验 `off` 方向是免费的，失败永远藏在「按回去」那一侧 —— 所以四个组合全跑。
    #[test]
    fn track_rule_round_trips() {
        assert!(prefers_enhanced(true, false));
        assert!(!prefers_enhanced(true, true));
        assert!(!prefers_enhanced(false, false));
        assert!(!prefers_enhanced(false, true));
    }

    #[test]
    fn bypass_round_trips_and_keeps_enhanced_usable() {
        let bypass = Bypass::new();
        assert!(!bypass.active());
        assert!(bypass.prefers_enhanced(true));

        bypass.set(true);
        assert!(bypass.active());
        assert!(!bypass.prefers_enhanced(true), "对比原图时不许仍走增强轨");

        bypass.set(false);
        assert!(
            bypass.prefers_enhanced(true),
            "取消对比后必须立刻能换回增强轨（增强图不该被旁路顺手删掉）"
        );
    }

    #[test]
    fn evidence_flag_is_only_zero_or_one() {
        assert_eq!(used_enhanced_flag(true), 1);
        assert_eq!(used_enhanced_flag(false), 0);
    }

    fn pixels(side: u32) -> Arc<PagePixels> {
        Arc::new(PagePixels {
            width: side,
            height: side,
            source_width: side,
            source_height: side,
            rgba: vec![7u8; (side * side * 4) as usize],
        })
    }

    /// 增强图按 `(index, epoch)` 存：换来源后旧代次必须整体作废。
    ///
    /// 不作废的话，打开第二本书时第 3 页会沿用第一本书第 3 页的超分图 ——
    /// 页号相同而内容无关，属于"看着像缓存坏了"的那类最难查的错。
    #[test]
    fn store_is_keyed_by_epoch_and_drops_stale_source() {
        let mut store = EnhancedStore::default();
        store.put(2, 1, pixels(8));
        store.put(3, 1, pixels(8));
        assert!(store.has(2, 1));

        store.retain_epoch(2);
        assert!(store.is_empty(), "换 epoch 后旧增强图必须全部作废");
        assert!(!store.has(2, 1));
        assert!(!store.has(2, 2), "新代次没有注入过就不该有增强图");
    }

    #[test]
    fn re_put_same_page_does_not_double_count_bytes() {
        let mut store = EnhancedStore::default();
        store.put(1, 1, pixels(8));
        let after_first = store.bytes();
        store.put(1, 1, pixels(8));
        assert_eq!(
            store.bytes(),
            after_first,
            "同页重复注入要把旧的换掉而不是叠上"
        );
        assert_eq!(store.len(), 1);
    }

    #[test]
    fn store_trims_at_its_cap() {
        let mut store = EnhancedStore::default();
        for i in 0..(EnhancedStore::MAX_PAGES as u32 + 5) {
            store.put(i as usize, 1, pixels(64));
        }
        assert!(
            store.len() <= EnhancedStore::MAX_PAGES,
            "超过上限必须淘汰，否则 4× 大图会把内存吃掉"
        );
    }
}
