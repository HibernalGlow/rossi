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

/// スクロール停止 (= 最後の scroll input から) 経過時間がこの閾値以上なら "idle" 扱い。
pub const PREFETCH_IDLE_THRESHOLD: std::time::Duration = std::time::Duration::from_millis(100);

/// visible が永久 Pending のまま prefetch が永久停止しないよう、絶対 timeout。
/// この時間 scroll なしが経過したら visible_pending によらず prefetch を allow する。
pub const PREFETCH_BACKSTOP: std::time::Duration = std::time::Duration::from_secs(3);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AllowReason {
    /// `last_prefetch_scroll_at == None` (= 起動直後 / フォルダ切替時の sentinel `Some(now)` でなく未設定)。
    NoScrollYet,
    /// scroll idle 100ms 経過 + visible 全部 ready。
    ScrollIdleAndVisibleReady,
    /// 3 秒 backstop 発動 (= visible が永久 Pending でも prefetch 再開)。
    Backstop3s,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockReason {
    /// 最後の scroll input から `PREFETCH_IDLE_THRESHOLD` 未満。
    ScrollNotIdle { elapsed_ms: u64 },
    /// scroll idle だが visible 範囲のサムネがまだ Loaded/Failed でない。
    VisibleStillLoading { pending: usize },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrefetchDecision {
    Allow { reason: AllowReason },
    Block { reason: BlockReason },
}

/// prefetch (= 非可視範囲) を enqueue してよいか判定。
///
/// 順序:
/// 1. `last_prefetch_scroll_at` が `PREFETCH_BACKSTOP` 以上前 → 無条件 Allow (Backstop3s)
/// 2. `last_prefetch_scroll_at` から `PREFETCH_IDLE_THRESHOLD` 未満 → Block (ScrollNotIdle)
/// 3. `visible_state_pending > 0` → Block (VisibleStillLoading)
/// 4. それ以外 → Allow (NoScrollYet or ScrollIdleAndVisibleReady)
///
/// `last_prefetch_scroll_at = None` は「起動直後 / 一度もスクロールしてない」状態。
/// `emit_scroll_settle_event` で `last_scroll_event_at` は clear されるが、
/// 本関数が見る `last_prefetch_scroll_at` は **clear されない** (= backstop 計時起点が安定)。
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
        // (1) backstop: 3 秒経ったら無条件 allow
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

/// final-effect の先読み対象を viewer mode、連結読み keep-set、texel LOW 水位から判定する。
/// ページ送りでは keep-set / 水位を参照せず従来の AI 先読み対象を維持する。連結読みは
/// keep-set 内だけを許可し、準備帯は LOW 水位をバイパス、それ以外は LOW 未満に限定する。
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

/// 先読み対象を距離順・forward 先で交互配置: +1, -1, +2, -2, +3, -3, …
/// 同距離の組では forward (次ページ方向) が先。片側が尽きたら反対側だけ続く。
/// fs_cache / AI アップスケール / サムネイルグリッド の全先読みで方針統一。
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

/// 表示順の位置で選んだ先読み対象を raw item index へ引き直す。
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

    /// P6-6: `interleaved_prefetch_targets` 純関数の境界条件を符号化する。
    ///
    /// この関数は `App::ai_prefetch_targets` の中核で、UI スレッドから 1 フレーム
    /// 数回呼ばれる経路にいる。順序 (forward, back, forward, back, ...) を変えると
    /// 「ユーザーが次に見るページから優先して AI を温める」スケジュールが崩れる
    /// (= ページ送り直後に毎回 cold miss する退行)。
    ///
    /// それぞれ独立した境界 (= 先頭で back が無い / 末尾で forward が無い /
    /// 全 0 で空 / 大きい d で末尾にぶつかったらスキップ) を 1 個ずつチェックする。
    #[test]
    fn interleaved_prefetch_targets_boundary_cases() {
        // 通常 case: 中央 (pos=3), forward=2, back=1
        // 期待順: forward d=1 → back d=1 → forward d=2  (back d=2 は無し: pf_back=1)
        let indices: Vec<usize> = (0..7).collect(); // [0,1,2,3,4,5,6]
        assert_eq!(
            interleaved_prefetch_targets(&indices, 3, 7, 2, 1),
            vec![4, 2, 5],
            "通常 case: forward → back → forward 順 (d=1 forward, d=1 back, d=2 forward)"
        );

        // 先頭: pos=0, forward=3, back=2
        // pos.checked_sub(d) → None で back は何も生やさない
        assert_eq!(
            interleaved_prefetch_targets(&indices, 0, 7, 3, 2),
            vec![1, 2, 3],
            "先頭: back は全部 None なので forward のみ"
        );

        // 末尾: pos=6, forward=2, back=3
        // pos+d >= n で forward はカット、back は 3 件取れる
        assert_eq!(
            interleaved_prefetch_targets(&indices, 6, 7, 2, 3),
            vec![5, 4, 3],
            "末尾: forward は 範囲外なので back のみ"
        );

        // 全 0: forward=0, back=0
        assert!(
            interleaved_prefetch_targets(&indices, 3, 7, 0, 0).is_empty(),
            "forward=back=0 → 空"
        );

        // 非対称: forward >> back の旧既定ケース (forward=2, back=1)
        // pos=2, n=5 → forward d=1→3, back d=1→1, forward d=2→4 (back d=2 は無し)
        let small: Vec<usize> = vec![10, 20, 30, 40, 50];
        assert_eq!(
            interleaved_prefetch_targets(&small, 2, 5, 2, 1),
            vec![40, 20, 50],
            "旧既定 forward=2 back=1 のインタリーブ順序"
        );

        // forward が n を越える: 末尾を超えたらスキップ
        assert_eq!(
            interleaved_prefetch_targets(&small, 2, 5, 10, 0),
            vec![40, 50],
            "forward が n を越えても、範囲内のものだけが選ばれる (overflow scenarios)"
        );
    }

    #[test]
    fn interleaved_prefetch_positions_handle_display_boundaries() {
        assert_eq!(
            interleaved_prefetch_positions(0, 4, 2, 2),
            vec![1, 2],
            "表示先頭では forward 側の位置だけを近い順に返す"
        );
        assert_eq!(
            interleaved_prefetch_positions(3, 4, 2, 2),
            vec![2, 1],
            "表示末尾では back 側の位置だけを近い順に返す"
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
            // last_prefetch_scroll_at = None なら elapsed check しないので
            // visible_pending > 0 でも (Codex 設計: 起動直後経路) — ただし起動経路は
            // 通常 `start_loading_items` が `Some(now)` を立てるので、
            // 厳密には起動から最初の `update` までの極短い窓でしか発生しない。
            let now = Instant::now();
            let d = decide_prefetch_allowed(now, None, 5);
            // visible_pending check は last_prefetch_scroll_at の elapsed branch を
            // 抜けた後に走るので、None だとそのまま到達して Block { VisibleStillLoading }。
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
            // backstop 未到達 + visible 残り → block
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
            // backstop 境界 (≥ 3000ms) → visible pending あっても allow
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
            // backstop 超過 + visible 揃ってる → 同じく allow (Backstop3s)
            // Backstop は (1) で先に判定されるので visible_pending=0 でも Backstop3s 扱い。
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
