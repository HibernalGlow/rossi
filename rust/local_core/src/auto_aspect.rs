//! 缩略图比例的自动选择 — 纯函数模块。
//!
//! 设计文档: [docs/auto-thumb-aspect-plan.md](../../docs/auto-thumb-aspect-plan.md)
//!
//! 这里只放无副作用的判定逻辑。cooldown / streak / scroll-idle /
//! switches_done 这类 **state-dependent** 的判定由调用方 (App) 完成。
//!
//! ## 设计上的说明: 为什么用「median-of-log-ratio」
//!
//! 设计评审阶段曾采用 Codex 提案的「拟合指标 `min(r/a, a/r)` 的均值最大化」，
//! 但动手实现时的单元测试发现，「一半 r=0.5 + 一半 r=2.0」这类
//! **双峰对称分布下会选出 Landscape16x9 / Portrait9x16**
//! (两端桶的「匹配侧 0.889」在 mean 上压过「不匹配侧 0.281」，
//! 因此赢过 Square 的 0.5)。
//!
//! 这与用户决定 C「混合 → Square」矛盾，因此改成了 **log(ratio) 的中位数 →
//! 最近邻桶** 的方式:
//! - 中位数对离群值稳健，左右对称的分布会自然收敛到 median=0 (= log 1.0)
//! - 与用户「横竖对称混合 → Square」的直觉一致
//! - 是一维的，计算也简单
//!
//! `fit_score` 函数还留着，但它不是选择逻辑，只用于诊断和测试。

use crate::settings::ThumbAspect;
use std::collections::HashMap;
use std::time::Instant;

/// 缩略图比例自动选择的运行时状态。
///
/// 在 App 结构体里持有 1 个，切换文件夹时调用 `reset_for_new_generation()`。
/// 具体行为 (sample 采集、切换判定、cooldown 管理) 在 `App` 的 impl 侧完成。
#[derive(Debug, Clone)]
pub struct AutoAspectState {
    /// 该文件夹的 items 世代。世代变化后全部重置。
    pub items_generation: u64,
    /// 已聚合的样本: idx -> ratio (h/w)。为防止重复添加，以 idx 为键。
    pub samples: HashMap<usize, f32>,
    /// 已确定（或临时确定）的自动比例。None 表示未确定。
    /// auto 模式下由 `App::effective_thumb_aspect` 引用。
    pub current: Option<ThumbAspect>,
    /// 门禁：在收集到不低于上次水平的实测 sample 之前，不允许覆盖
    /// 从 auto_aspect_cache.db 恢复出的比例。None 则走通常判定。
    pub cached_sample_gate: Option<usize>,
    /// 该文件夹内切换过几次 (0..=2)。达到最大值后不再重新切换。
    pub switches_done: u8,
    /// 最近一次切换的时刻 (用于 cooldown 判定)。
    pub last_switch_at: Option<Instant>,
    /// 正在连胜的候选及其持续信息。
    /// `(候选, 连胜开始时刻, 连胜开始时的样本数)` — 用于判定切换条件「750ms 或
    /// +8 个样本内同一候选持续获胜」。
    pub streak: Option<(ThumbAspect, Instant, usize)>,
}

impl Default for AutoAspectState {
    fn default() -> Self {
        Self {
            items_generation: 0,
            samples: HashMap::new(),
            current: None,
            cached_sample_gate: None,
            switches_done: 0,
            last_switch_at: None,
            streak: None,
        }
    }
}

impl AutoAspectState {
    /// 移到新文件夹时的全部重置。
    pub fn reset_for_new_generation(&mut self, generation: u64) {
        self.items_generation = generation;
        self.samples.clear();
        self.current = None;
        self.cached_sample_gate = None;
        self.switches_done = 0;
        self.last_switch_at = None;
        self.streak = None;
    }

    /// 用户（重新）选择「自动」时重置确定值。
    /// `samples` 继续保留，以便下一次判定重新评估。
    pub fn reset_decision_only(&mut self) {
        self.current = None;
        self.cached_sample_gate = None;
        self.switches_done = 0;
        self.last_switch_at = None;
        self.streak = None;
    }
}

/// 「单元格比例 `candidate` 下，图片比例 `ratio` 能把单元格填满多少」的得分。
///
/// - `ratio = h / w` (图片的高 / 宽)
/// - `candidate.height_ratio() = a` (单元格的高 / 宽)
/// - 返回值是 `min(r/a, a/r)`，范围 `0 < fit ≤ 1`，1 表示完全一致
///
/// 主要供 **诊断与测试** 使用。实际的桶选择由 `pick_best` (= median-of-log-ratio)
/// 负责。
pub fn fit_score(ratio: f32, candidate: ThumbAspect) -> f32 {
    if !ratio.is_finite() || ratio <= 0.0 {
        return 0.0;
    }
    let a = candidate.height_ratio();
    if !a.is_finite() || a <= 0.0 {
        return 0.0;
    }
    (ratio / a).min(a / ratio)
}

/// 返回 `log(height_ratio)` 最接近 `log(r)` 中位数的 `ThumbAspect`。
/// 做成纯函数是为了能单独传入 `target`（既是 `pick_best` 的辅助，也便于测试）。
fn nearest_bucket_to_log_ratio(target: f32) -> ThumbAspect {
    let mut best: ThumbAspect = ThumbAspect::Square;
    let mut best_dist = f32::INFINITY;
    for &candidate in ThumbAspect::all() {
        let a = candidate.height_ratio();
        if !a.is_finite() || a <= 0.0 {
            continue;
        }
        let dist = (target - a.ln()).abs();
        if dist < best_dist {
            best_dist = dist;
            best = candidate;
        }
    }
    best
}

/// 从 `samples` (各元素是 `h / w`) 计算 **log 空间的中位数**，返回最接近
/// 该值的 `ThumbAspect` 桶。
///
/// - `samples` 为空、或没有有效值时返回 `None`
/// - 非法值 (`<= 0.0`, NaN, Inf) 从聚合中排除
/// - 偶数个时取中间两个值的平均 (= 教科书式的中位数)
///
/// 计算量: `O(N log N)` (排序)。N 只有数十左右，可以忽略。
pub fn pick_best(samples: &[f32]) -> Option<ThumbAspect> {
    let mut log_ratios: Vec<f32> = samples
        .iter()
        .filter(|&&r| r > 0.0 && r.is_finite())
        .map(|&r| r.ln())
        .collect();
    if log_ratios.is_empty() {
        return None;
    }
    log_ratios.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = log_ratios.len();
    let median = if n % 2 == 1 {
        log_ratios[n / 2]
    } else {
        (log_ratios[n / 2 - 1] + log_ratios[n / 2]) / 2.0
    };
    Some(nearest_bucket_to_log_ratio(median))
}

/// 返回确定判定所需的最小样本数。
///
/// 公式 (plan §4.3):
/// - 基本是 `max(8, eligible_total / 4)`，上限 `24`
/// - 但会 clip 到不超过 `eligible_total` 本身 (= 照顾小文件夹)
///
/// 例如: `eligible_total=5 → 5`、`eligible_total=20 → 8`、`eligible_total=100 → 24`。
pub fn min_samples_for(eligible_total: usize) -> usize {
    let ideal = (eligible_total / 4).max(8).min(24);
    ideal.min(eligible_total)
}

/// `decide_auto_aspect` 的返回值。
///
/// - `Hold`: 不切换 (样本不足 / 与 current 相同 / 改善幅度不足)
/// - `Switch(best)`: 应切换到 `best`
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AspectDecision {
    Hold,
    Switch(ThumbAspect),
}

/// 只凭样本和滞回基准决定「是否应该切换」的纯函数。
///
/// 本函数的职责只有 **样本达到下限** + **log 距离余量判定**。
/// cooldown / switches_done / streak / scroll-idle 由调用方 (App) 判定。
///
/// `log_margin` 是桶间距离在 log 空间上的余量。
/// 例如: `0.10` (= 约 10% 的比例差)，只有「best 桶比 current 桶更接近中位数
/// 达 log_margin 以上」时才 switch。
///
/// 相邻桶之间 log 距离的最小值约 0.117 (例如: Landscape4x3↔Landscape3x2)，
/// 所以 `log_margin = 0.05` 左右也允许相邻迁移，`0.10` 偏谨慎，
/// `0.15` 接近「只有跨越 2 个桶以上才切换」。数值需在真机上调整。
pub fn decide_auto_aspect(
    samples: &[f32],
    eligible_total: usize,
    current: ThumbAspect,
    log_margin: f32,
) -> AspectDecision {
    if samples.len() < min_samples_for(eligible_total) {
        return AspectDecision::Hold;
    }
    // 取 median (为复用 pick_best 的逻辑，先算出中位数)
    let mut log_ratios: Vec<f32> = samples
        .iter()
        .filter(|&&r| r > 0.0 && r.is_finite())
        .map(|&r| r.ln())
        .collect();
    if log_ratios.is_empty() {
        return AspectDecision::Hold;
    }
    log_ratios.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = log_ratios.len();
    let median = if n % 2 == 1 {
        log_ratios[n / 2]
    } else {
        (log_ratios[n / 2 - 1] + log_ratios[n / 2]) / 2.0
    };
    let best = nearest_bucket_to_log_ratio(median);
    if best == current {
        return AspectDecision::Hold;
    }
    let curr_log = current.height_ratio().ln();
    let best_log = best.height_ratio().ln();
    let curr_dist = (median - curr_log).abs();
    let best_dist = (median - best_log).abs();
    if curr_dist - best_dist > log_margin {
        AspectDecision::Switch(best)
    } else {
        AspectDecision::Hold
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approx_eq(a: f32, b: f32) -> bool {
        (a - b).abs() < 1e-4
    }

    // --- fit_score (用于诊断) ---

    #[test]
    fn fit_score_perfect_match_is_1() {
        assert!(approx_eq(fit_score(1.0, ThumbAspect::Square), 1.0));
        assert!(approx_eq(
            fit_score(9.0 / 16.0, ThumbAspect::Landscape16x9),
            1.0
        ));
        assert!(approx_eq(fit_score(1.5, ThumbAspect::Portrait2x3), 1.0));
    }

    #[test]
    fn fit_score_symmetric() {
        let a = ThumbAspect::Square;
        assert!(approx_eq(fit_score(2.0, a), fit_score(0.5, a)));
        assert!(approx_eq(fit_score(2.0, ThumbAspect::Square), 0.5));
    }

    #[test]
    fn fit_score_invalid_inputs() {
        assert_eq!(fit_score(0.0, ThumbAspect::Square), 0.0);
        assert_eq!(fit_score(-1.0, ThumbAspect::Square), 0.0);
        assert_eq!(fit_score(f32::NAN, ThumbAspect::Square), 0.0);
        assert_eq!(fit_score(f32::INFINITY, ThumbAspect::Square), 0.0);
    }

    // --- nearest_bucket_to_log_ratio ---

    #[test]
    fn nearest_bucket_zero_is_square() {
        // log(1.0) = 0 → 正好落在 Square
        assert_eq!(nearest_bucket_to_log_ratio(0.0), ThumbAspect::Square);
    }

    #[test]
    fn nearest_bucket_exact_buckets() {
        for &candidate in ThumbAspect::all() {
            let target = candidate.height_ratio().ln();
            assert_eq!(
                nearest_bucket_to_log_ratio(target),
                candidate,
                "exact log(height_ratio) should return the same bucket"
            );
        }
    }

    // --- pick_best ---

    #[test]
    fn pick_best_empty_is_none() {
        assert_eq!(pick_best(&[]), None);
    }

    #[test]
    fn pick_best_all_square() {
        let samples = vec![1.0; 10];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Square));
    }

    #[test]
    fn pick_best_all_portrait_2x3() {
        // r = 1.5 → 与 Portrait2x3 (h/w = 3/2 = 1.5) 完全一致
        let samples = vec![1.5; 10];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Portrait2x3));
    }

    #[test]
    fn pick_best_all_landscape_16x9() {
        // r = 9/16 ≈ 0.5625 → 与 Landscape16x9 (a=9/16) 完全一致
        let samples = vec![9.0 / 16.0; 10];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Landscape16x9));
    }

    #[test]
    fn pick_best_mixed_lands_on_square() {
        // 一半 r=0.5 (横向)，一半 r=2.0 (纵向): 对称分布
        // log(0.5) = -0.693, log(2.0) = 0.693, median = 0 → Square
        let samples = vec![0.5, 2.0, 0.5, 2.0, 0.5, 2.0, 0.5, 2.0];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Square));
    }

    #[test]
    fn pick_best_all_portrait_9x16() {
        // r = 16/9 ≈ 1.778 → 与 Portrait9x16 (a=16/9) 完全一致
        let samples = vec![16.0 / 9.0; 10];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Portrait9x16));
    }

    #[test]
    fn pick_best_ignores_invalid_values() {
        // 非法值被排除，只有剩下的 1.5 生效
        let samples = vec![0.0, f32::NAN, f32::INFINITY, -1.0, 1.5, 1.5, 1.5];
        assert_eq!(pick_best(&samples), Some(ThumbAspect::Portrait2x3));
    }

    #[test]
    fn pick_best_all_invalid_is_none() {
        let samples = vec![0.0, -1.0, f32::NAN];
        assert_eq!(pick_best(&samples), None);
    }

    // --- min_samples_for (边界值表 — plan §9.1) ---

    #[test]
    fn min_samples_for_boundaries() {
        assert_eq!(min_samples_for(0), 0);
        assert_eq!(min_samples_for(1), 1);
        assert_eq!(min_samples_for(5), 5);
        assert_eq!(min_samples_for(8), 8);
        assert_eq!(min_samples_for(20), 8); // 20/4 = 5 < 8 → 下限 8
        assert_eq!(min_samples_for(32), 8); // 32/4 = 8 正好
        assert_eq!(min_samples_for(36), 9); // 36/4 = 9，走 25% 规则
        assert_eq!(min_samples_for(96), 24); // 96/4 = 24 正好到上限
        assert_eq!(min_samples_for(100), 24); // 按上限裁剪
        assert_eq!(min_samples_for(1000), 24); // 维持上限
    }

    // --- decide_auto_aspect (滞回测试) ---

    #[test]
    fn decide_holds_when_samples_below_min() {
        // eligible_total = 20 → min_samples = 8。samples = 3 件未达标
        let samples = vec![1.5; 3];
        let d = decide_auto_aspect(&samples, 20, ThumbAspect::Square, 0.10);
        assert_eq!(d, AspectDecision::Hold);
    }

    #[test]
    fn decide_small_folder_can_decide_when_full() {
        // eligible_total = 5 → min_samples = 5。samples = 5 件时达到
        // log(1.5) ≈ 0.405，log(1.0)=0，从 Square 看偏离了 0.405。
        // log(Portrait2x3) = log(1.5) = 0.405 正好吻合，距离 0。
        // 改善 = 0.405 - 0 = 0.405 > log_margin 0.10 → Switch
        let samples = vec![1.5; 5];
        let d = decide_auto_aspect(&samples, 5, ThumbAspect::Square, 0.10);
        assert_eq!(d, AspectDecision::Switch(ThumbAspect::Portrait2x3));
    }

    #[test]
    fn decide_small_folder_holds_when_short() {
        // eligible_total = 5, samples = 4 件未达标
        let samples = vec![1.5; 4];
        let d = decide_auto_aspect(&samples, 5, ThumbAspect::Square, 0.10);
        assert_eq!(d, AspectDecision::Hold);
    }

    #[test]
    fn decide_holds_when_best_equals_current() {
        // 全部 1:1，current 也是 Square
        let samples = vec![1.0; 10];
        let d = decide_auto_aspect(&samples, 10, ThumbAspect::Square, 0.10);
        assert_eq!(d, AspectDecision::Hold);
    }

    #[test]
    fn decide_holds_for_small_improvement() {
        // 全部 r = 1.05 (log ≈ 0.0488)，current = Square (log=0)
        //   curr_dist = 0.0488
        //   best = Square (= current，最近邻) → Hold (走 best == current 分支)
        //
        // 把 current 错开一格，设为 Portrait3x4 (log=0.288):
        //   median = 0.0488
        //   curr_dist (Portrait3x4) = |0.0488 - 0.288| = 0.239
        //   best = Square (距离 0.0488)
        //   改善 = 0.239 - 0.0488 = 0.190 > 0.10 → Switch
        // → 这种情形会被 Switch。要看到「改善太小时 Hold」，得把 median 放在 best 与
        //    current 之间正中间附近的位置。
        //
        // median = 0.15 (Square 与 Portrait3x4 的中间附近)。
        //   curr (Square) 距离 0.15，best (Portrait3x4) 距离 0.138 → 改善 0.012 → Hold
        let target_log: f32 = 0.15;
        let r = target_log.exp(); // ≈ 1.162
        let samples = vec![r; 10];
        let d = decide_auto_aspect(&samples, 10, ThumbAspect::Square, 0.10);
        assert_eq!(d, AspectDecision::Hold);
    }

    #[test]
    fn decide_switches_for_large_improvement() {
        // 全部 r = 1.0 (正好是 Square)，current = Portrait9x16 (log = 0.575)
        //   median = 0
        //   curr_dist = 0.575
        //   best (Square) 距离 0
        //   改善 = 0.575 > 0.10 → Switch
        let samples = vec![1.0; 10];
        let d = decide_auto_aspect(&samples, 10, ThumbAspect::Portrait9x16, 0.10);
        assert_eq!(d, AspectDecision::Switch(ThumbAspect::Square));
    }

    #[test]
    fn decide_mixed_symmetric_switches_to_square_from_portrait() {
        // 对称混合，current 为 Portrait9x16 时会转向 Square
        let samples = vec![0.5, 2.0, 0.5, 2.0, 0.5, 2.0, 0.5, 2.0, 0.5, 2.0];
        let d = decide_auto_aspect(&samples, 10, ThumbAspect::Portrait9x16, 0.10);
        assert_eq!(d, AspectDecision::Switch(ThumbAspect::Square));
    }

    // --- AutoAspectState reset methods ---

    #[test]
    fn auto_state_reset_for_new_generation_clears_everything() {
        let mut s = AutoAspectState::default();
        s.samples.insert(0, 1.5);
        s.samples.insert(1, 0.5);
        s.current = Some(ThumbAspect::Portrait2x3);
        s.cached_sample_gate = Some(24);
        s.switches_done = 2;
        s.last_switch_at = Some(Instant::now());
        s.streak = Some((ThumbAspect::Square, Instant::now(), 3));

        s.reset_for_new_generation(42);

        assert_eq!(s.items_generation, 42);
        assert!(s.samples.is_empty());
        assert_eq!(s.current, None);
        assert_eq!(s.cached_sample_gate, None);
        assert_eq!(s.switches_done, 0);
        assert!(s.last_switch_at.is_none());
        assert!(s.streak.is_none());
    }

    #[test]
    fn auto_state_reset_decision_only_keeps_samples() {
        let mut s = AutoAspectState::default();
        s.items_generation = 7;
        s.samples.insert(0, 1.5);
        s.samples.insert(1, 1.5);
        s.current = Some(ThumbAspect::Portrait2x3);
        s.cached_sample_gate = Some(24);
        s.switches_done = 1;
        s.last_switch_at = Some(Instant::now());
        s.streak = Some((ThumbAspect::Square, Instant::now(), 0));

        s.reset_decision_only();

        // samples / items_generation 仍然有效
        assert_eq!(s.items_generation, 7);
        assert_eq!(s.samples.len(), 2);
        // 只重置决定状态
        assert_eq!(s.current, None);
        assert_eq!(s.cached_sample_gate, None);
        assert_eq!(s.switches_done, 0);
        assert!(s.last_switch_at.is_none());
        assert!(s.streak.is_none());
    }
}
