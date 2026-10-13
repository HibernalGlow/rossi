//! 直接编译 mImageViewer 完整的纯预取策略模块（MIT）。
//! 构建期只提升 pub(crate) 可见性；上游新增纯函数/指示器策略自动进入模块。
//! 现有 Rossi 契约测试保留，Flutter 负责实际显示与缓存所有权。
include!(concat!(env!("OUT_DIR"), "/prefetch_policy.rs"));

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
