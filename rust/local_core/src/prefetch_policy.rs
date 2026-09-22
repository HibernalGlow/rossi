//! 预取准入策略（纯函数，无状态、无缓存、不碰 IO）。
//!
//! ── 来源与形态 ──
//!
//! 搬自 mImageViewer `src/app/prefetch_policy.rs` @ `1fd6f863`（MIT）。上游在
//! `mod app;` 之下、通体 `pub(crate)`，跨 crate 用不了，只能搬源码。
//!
//! 版权：Copyright (c) 2026 SANO Taku (佐野 拓), online handle "Mikage Sawatari"。
//! 上游以 MIT 授权（全文见 `vendor/mimageviewer/LICENSE`），本文件保留该来源声明。
//!
//! **搬了什么**（函数名与签名与上游逐字一致）：
//!
//! - [`decide_prefetch_allowed`]：预取的**唯一**准入判决。三种放行理由
//!   （没滚动过 / 滚动静默且可见区就绪 / 3 秒兜底）、两种拦截理由
//!   （滚动未静默 / 可见区还在加载），带理由而非 bool —— 理由要能显示给人看。
//! - [`interleaved_prefetch_positions`] / [`interleaved_prefetch_targets`]：
//!   目标选择顺序 `+1, -1, +2, -2, …`，同距离 forward 先。
//! - [`should_prefetch_final_effect`]：连续阅读（滚动）模式下的 keep-set 与 LOW 水位门。
//!
//! **刻意偏离共两处**，登记在 `script/sync_vendored_modules.py` 的 `PORTS` 里：
//!
//! 1. `pub(crate)` → `pub`（机械替换）。
//! 2. 文件末尾新增 `mod tests` —— 上游这个文件自己**没有**测试，纯函数测试散在
//!    `src/app/tests.rs` 里且和 `App` 混放；这里把其中只用纯函数的那些搬了过来，
//!    作为「搬运等价」的证据。
//!
//! **刻意没搬什么，以及为什么**：
//!
//! 上游同文件还含一套 UI 指示器数据模型（`FsPrefetchIndicator` / `FsPrefetchSideDisplay` /
//! `FsPrefetchStateCount` / `build_fs_prefetch_indicator` / `BehindDisplay`/`AheadDisplay` /
//! `MAX_DOTS_PER_SIDE` / `tooltip_text`）。那是**给 egui 画点用的显示模型**，
//! 带日文 tooltip 文案，而 Rossi 的 UI 在 Flutter 侧、由 Dart 自己画。
//! 搬过来只会得到「一个没人渲染的数据结构 + 一段日文」。
//! 若将来要照抄它的显示规则（近处画点、远处折成计数），照上游文件取即可。
//!
//! 上游这个文件**不带测试**（纯函数测试散在 `src/app/tests.rs` 里、且与 `App` 混放）。
//! 本模块底部把其中**只用纯函数**的那些逐字搬了过来，作为「搬运等价」的证据。

/// 滚动停止（= 距最后一次 scroll input）的经过时间达到此阈值即视为 "idle"。
pub const PREFETCH_IDLE_THRESHOLD: std::time::Duration = std::time::Duration::from_millis(100);

/// 绝对 timeout：防止 visible 一直 Pending 导致 prefetch 永久停止。
/// 距上次 scroll 超过该时间后，不论 visible_pending 如何都 allow prefetch。
pub const PREFETCH_BACKSTOP: std::time::Duration = std::time::Duration::from_secs(3);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AllowReason {
    /// `last_prefetch_scroll_at == None`（= 启动后 / 切换文件夹时未设置，而非 sentinel `Some(now)`）。
    NoScrollYet,
    /// 滚动静默 100ms 以上且可见区全部就绪。
    ScrollIdleAndVisibleReady,
    /// 3 秒兜底触发（= 即使 visible 一直 Pending 也恢复 prefetch）。
    Backstop3s,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockReason {
    /// 距最后一次 scroll input 不足 `PREFETCH_IDLE_THRESHOLD`。
    ScrollNotIdle { elapsed_ms: u64 },
    /// 滚动已静默，但可见范围的缩略图还不是 Loaded/Failed。
    VisibleStillLoading { pending: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrefetchDecision {
    Allow { reason: AllowReason },
    Block { reason: BlockReason },
}

/// 判定能否 enqueue 预取（= 非可见范围）。
///
/// 顺序:
/// 1. `last_prefetch_scroll_at` 距今达 `PREFETCH_BACKSTOP` 以上 → 无条件 Allow (Backstop3s)
/// 2. `last_prefetch_scroll_at` 距今不足 `PREFETCH_IDLE_THRESHOLD` → Block (ScrollNotIdle)
/// 3. `visible_state_pending > 0` → Block (VisibleStillLoading)
/// 4. 其余情况 → Allow (NoScrollYet or ScrollIdleAndVisibleReady)
///
/// `last_prefetch_scroll_at = None` 表示「刚启动 / 从未滚动过」状态。
/// `emit_scroll_settle_event` 会 clear `last_scroll_event_at`，但
/// 本函数读取的 `last_prefetch_scroll_at` **不会被 clear**（= backstop 计时起点稳定）。
///
/// Rossi 侧的对应关系（同一个函数，换了一套输入名）：
/// 「滚动」= 翻页/跳页，「可见区待完成」= 当前页还没出图。
/// `last_prefetch_scroll_at` 传上一次翻页的时刻，`visible_state_pending`
/// 传当前页是否仍在加载（0 = 已出图）。语义完全对上 —— 这正是它被搬过来的原因：
/// 我们手搓的「延迟 + 一个布尔」是它的退化版。
pub fn decide_prefetch_allowed(
    now: std::time::Instant,
    last_prefetch_scroll_at: Option<std::time::Instant>,
    visible_state_pending: usize,
) -> PrefetchDecision {
    if let Some(t) = last_prefetch_scroll_at {
        let elapsed = now.saturating_duration_since(t);
        // (1) backstop: 过 3 秒即无条件 allow
        if elapsed >= PREFETCH_BACKSTOP {
            return PrefetchDecision::Allow {
                reason: AllowReason::Backstop3s,
            };
        }
        // (2) scroll idle 不足
        if elapsed < PREFETCH_IDLE_THRESHOLD {
            return PrefetchDecision::Block {
                reason: BlockReason::ScrollNotIdle {
                    elapsed_ms: elapsed.as_millis() as u64,
                },
            };
        }
    }
    // (3) visible ready
    if visible_state_pending > 0 {
        return PrefetchDecision::Block {
            reason: BlockReason::VisibleStillLoading {
                pending: visible_state_pending,
            },
        };
    }
    let reason = if last_prefetch_scroll_at.is_none() {
        AllowReason::NoScrollYet
    } else {
        AllowReason::ScrollIdleAndVisibleReady
    };
    PrefetchDecision::Allow { reason }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FinalEffectPrefetchAdmission {
    Allow,
    NotInKeepSet,
    OverLowWatermark,
}

impl FinalEffectPrefetchAdmission {
    pub fn blocked_reason(self) -> Option<&'static str> {
        match self {
            Self::Allow => None,
            Self::NotInKeepSet => Some("not_in_keep_set"),
            Self::OverLowWatermark => Some("over_low_watermark"),
        }
    }
}

/// 从 viewer mode、连续阅读 keep-set、texel LOW 水位判定 final-effect 的预取对象。
/// 翻页时不参考 keep-set / 水位，维持原有的 AI 预取对象。连续阅读只
/// 允许 keep-set 内的页面，准备带绕过 LOW 水位，其余限定在 LOW 以下。
pub fn should_prefetch_final_effect(
    reading_is_paged: bool,
    continuous_keep_set: &std::collections::HashSet<usize>,
    idx: usize,
    in_prepare_band: bool,
    continuous_loaded_texels: usize,
    continuous_low_watermark: Option<usize>,
) -> FinalEffectPrefetchAdmission {
    if reading_is_paged {
        return FinalEffectPrefetchAdmission::Allow;
    }
    if !continuous_keep_set.contains(&idx) {
        return FinalEffectPrefetchAdmission::NotInKeepSet;
    }
    if in_prepare_band || continuous_low_watermark.is_none_or(|low| continuous_loaded_texels < low)
    {
        FinalEffectPrefetchAdmission::Allow
    } else {
        FinalEffectPrefetchAdmission::OverLowWatermark
    }
}

/// 预取对象按距离、forward 优先交替排列: +1, -1, +2, -2, +3, -3, …
/// 同距离的一组中 forward（下一页方向）在前。一侧用尽后只继续另一侧。
/// fs_cache / AI 放大 / 缩略图网格的全部预取统一采用此策略。
pub fn interleaved_prefetch_positions(
    pos: usize,
    n: usize,
    pf_forward: usize,
    pf_back: usize,
) -> Vec<usize> {
    let max_d = pf_forward.max(pf_back);
    let mut out = Vec::with_capacity(pf_forward + pf_back);
    for d in 1..=max_d {
        if d <= pf_forward {
            if let Some(p) = pos.checked_add(d) {
                if p < n {
                    out.push(p);
                }
            }
        }
        if d <= pf_back {
            if let Some(p) = pos.checked_sub(d) {
                out.push(p);
            }
        }
    }
    out
}

/// 把按显示顺序位置选出的预取对象换算回 raw item index。
pub fn interleaved_prefetch_targets(
    image_indices: &[usize],
    pos: usize,
    n: usize,
    pf_forward: usize,
    pf_back: usize,
) -> Vec<usize> {
    interleaved_prefetch_positions(pos, n, pf_forward, pf_back)
        .into_iter()
        .map(|position| image_indices[position])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    // ── 以下、上游 src/app/tests.rs 里只用纯函数的用例，逐字搬运 ──

    /// P6-6: 编码固定 `interleaved_prefetch_targets` 纯函数的边界条件。
    ///
    /// 该函数是 `App::ai_prefetch_targets` 的核心，位于 UI 线程每帧
    /// 调用数次的路径上。改变顺序 (forward, back, forward, back, ...) 会破坏
    /// 「优先预热用户接下来要看的页面」的调度安排
    /// （= 翻页之后每次都 cold miss 的退化）。
    ///
    /// 逐一检查各自独立的边界（= 开头没有 back / 末尾没有 forward /
    /// 全 0 时为空 / 较大的 d 撞到末尾则跳过），每种各验证 1 次。
    #[test]
    fn interleaved_prefetch_targets_boundary_cases() {
        // 通常 case: 中央 (pos=3), forward=2, back=1
        // 期望顺序: forward d=1 → back d=1 → forward d=2  (无 back d=2: pf_back=1)
        let indices: Vec<usize> = (0..7).collect(); // [0,1,2,3,4,5,6]
        assert_eq!(
            interleaved_prefetch_targets(&indices, 3, 7, 2, 1),
            vec![4, 2, 5],
            "通常 case: forward → back → forward 顺序 (d=1 forward, d=1 back, d=2 forward)"
        );

        // 开头: pos=0, forward=3, back=2
        // pos.checked_sub(d) → None，back 不产生任何结果
        assert_eq!(
            interleaved_prefetch_targets(&indices, 0, 7, 3, 2),
            vec![1, 2, 3],
            "开头: back 全部为 None，只有 forward"
        );

        // 末尾: pos=6, forward=2, back=3
        // pos+d >= n 时 forward 被裁掉，back 可取 3 个
        assert_eq!(
            interleaved_prefetch_targets(&indices, 6, 7, 2, 3),
            vec![5, 4, 3],
            "末尾: forward 超出范围，只有 back"
        );

        // 全 0: forward=0, back=0
        assert!(
            interleaved_prefetch_targets(&indices, 3, 7, 0, 0).is_empty(),
            "forward=back=0 → 空"
        );

        // 非对称: forward >> back 的旧默认情形 (forward=2, back=1)
        // pos=2, n=5 → forward d=1→3, back d=1→1, forward d=2→4 (无 back d=2)
        let small: Vec<usize> = vec![10, 20, 30, 40, 50];
        assert_eq!(
            interleaved_prefetch_targets(&small, 2, 5, 2, 1),
            vec![40, 20, 50],
            "旧默认 forward=2 back=1 的交错顺序"
        );

        // forward 超过 n: 越过末尾则跳过
        assert_eq!(
            interleaved_prefetch_targets(&small, 2, 5, 10, 0),
            vec![40, 50],
            "forward 超过 n 时，也只选出范围内的项 (overflow scenarios)"
        );
    }

    #[test]
    fn interleaved_prefetch_positions_handle_display_boundaries() {
        assert_eq!(
            interleaved_prefetch_positions(0, 4, 2, 2),
            vec![1, 2],
            "显示开头时只按由近到远返回 forward 侧的位置"
        );
        assert_eq!(
            interleaved_prefetch_positions(3, 4, 2, 2),
            vec![2, 1],
            "显示末尾时只按由近到远返回 back 侧的位置"
        );
    }

    #[test]
    fn final_effect_prefetch_admission_reports_each_condition() {
        let empty = std::collections::HashSet::new();
        assert_eq!(
            should_prefetch_final_effect(true, &empty, 42, false, 100, Some(100)),
            FinalEffectPrefetchAdmission::Allow
        );

        let keep_set = std::collections::HashSet::from([2]);
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 2, false, 99, Some(100)),
            FinalEffectPrefetchAdmission::Allow
        );
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 3, true, 99, Some(100)),
            FinalEffectPrefetchAdmission::NotInKeepSet
        );
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 2, false, 100, Some(100)),
            FinalEffectPrefetchAdmission::OverLowWatermark
        );
    }

    #[test]
    fn final_effect_prepare_band_bypasses_low_but_not_keep_set() {
        let keep_set = std::collections::HashSet::from([2]);
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 2, true, 100, Some(100)),
            FinalEffectPrefetchAdmission::Allow
        );
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 3, true, 100, Some(100)),
            FinalEffectPrefetchAdmission::NotInKeepSet
        );
        assert_eq!(
            should_prefetch_final_effect(false, &keep_set, 2, false, usize::MAX, None),
            FinalEffectPrefetchAdmission::Allow,
            "unlimited mode must disable the LOW admission gate"
        );
    }

    /// 上游把下面这组放在 `mod prefetch_gate_tests` 里，与 `App` 的滚动簿记耦合
    /// （`last_prefetch_scroll_at` / `note_fullscreen_seek_activity`）。这里只留
    /// 判决本身 —— 纯函数部分，输入即全部前提。
    mod prefetch_gate_tests {
        use super::*;

        #[test]
        fn no_scroll_yet_allows() {
            let now = Instant::now();
            let d = decide_prefetch_allowed(now, None, 0);
            assert_eq!(
                d,
                PrefetchDecision::Allow {
                    reason: AllowReason::NoScrollYet,
                }
            );
        }

        #[test]
        fn no_scroll_yet_with_visible_pending_still_allows() {
            // 因为 last_prefetch_scroll_at = None 时不做 elapsed check，所以
            // visible_pending > 0 也一样（Codex 设计: 启动后直接路径）— 但启动路径
            // 通常 `start_loading_items` 会设 `Some(now)`，因此严格来说，
            // 只在启动到第一次 `update` 之间的极短窗口内才会出现。
            let now = Instant::now();
            let d = decide_prefetch_allowed(now, None, 5);
            // visible_pending check 在走完 last_prefetch_scroll_at 的 elapsed branch
            // 之后才跑，所以 None 时径直到达并 Block { VisibleStillLoading }。
            assert_eq!(
                d,
                PrefetchDecision::Block {
                    reason: BlockReason::VisibleStillLoading { pending: 5 },
                }
            );
        }

        #[test]
        fn scroll_50ms_ago_blocks() {
            let now = Instant::now();
            let t = now - Duration::from_millis(50);
            let d = decide_prefetch_allowed(now, Some(t), 0);
            assert!(matches!(
                d,
                PrefetchDecision::Block {
                    reason: BlockReason::ScrollNotIdle { .. }
                }
            ));
        }

        #[test]
        fn scroll_exactly_100ms_ago_allows() {
            let now = Instant::now();
            let t = now - Duration::from_millis(100);
            let d = decide_prefetch_allowed(now, Some(t), 0);
            assert_eq!(
                d,
                PrefetchDecision::Allow {
                    reason: AllowReason::ScrollIdleAndVisibleReady,
                }
            );
        }

        #[test]
        fn scroll_99ms_ago_blocks() {
            let now = Instant::now();
            let t = now - Duration::from_millis(99);
            let d = decide_prefetch_allowed(now, Some(t), 0);
            assert!(matches!(
                d,
                PrefetchDecision::Block {
                    reason: BlockReason::ScrollNotIdle { .. }
                }
            ));
        }

        #[test]
        fn scroll_200ms_visible_pending_blocks() {
            let now = Instant::now();
            let t = now - Duration::from_millis(200);
            let d = decide_prefetch_allowed(now, Some(t), 5);
            assert_eq!(
                d,
                PrefetchDecision::Block {
                    reason: BlockReason::VisibleStillLoading { pending: 5 },
                }
            );
        }

        #[test]
        fn scroll_200ms_visible_ready_allows() {
            let now = Instant::now();
            let t = now - Duration::from_millis(200);
            let d = decide_prefetch_allowed(now, Some(t), 0);
            assert_eq!(
                d,
                PrefetchDecision::Allow {
                    reason: AllowReason::ScrollIdleAndVisibleReady,
                }
            );
        }

        #[test]
        fn scroll_2999ms_with_pending_blocks() {
            // 未达 backstop + visible 仍有剩余 → block
            let now = Instant::now();
            let t = now - Duration::from_millis(2999);
            let d = decide_prefetch_allowed(now, Some(t), 5);
            assert_eq!(
                d,
                PrefetchDecision::Block {
                    reason: BlockReason::VisibleStillLoading { pending: 5 },
                }
            );
        }

        #[test]
        fn scroll_exactly_3000ms_backstop_allows() {
            // backstop 边界 (≥ 3000ms) → 即使 visible pending 存在也 allow
            let now = Instant::now();
            let t = now - Duration::from_millis(3000);
            let d = decide_prefetch_allowed(now, Some(t), 5);
            assert_eq!(
                d,
                PrefetchDecision::Allow {
                    reason: AllowReason::Backstop3s,
                }
            );
        }

        #[test]
        fn scroll_3001ms_backstop_allows_no_pending() {
            // 超过 backstop + visible 已就绪 → 同样 allow (Backstop3s)
            // Backstop 在 (1) 处先判定，所以 visible_pending=0 也按 Backstop3s 处理。
            let now = Instant::now();
            let t = now - Duration::from_millis(3001);
            let d = decide_prefetch_allowed(now, Some(t), 0);
            assert_eq!(
                d,
                PrefetchDecision::Allow {
                    reason: AllowReason::Backstop3s,
                }
            );
        }
    }
}
