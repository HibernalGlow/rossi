//! 把检测框聚成**文本块**：翻译与擦字都以块为单位，不是以框为单位。
//!
//! 为什么需要它：检测件会把一个长竖排列切成几段（实测「トカゲじゃ」/「ない!?」、
//! 「どっから捕まえて」/「きたんだよお前!」），逐框翻译只会得到半句；擦字也要整块一起填。
//!
//! 合并条件有**两条，缺一不可**（第二条是实测补上的）：
//! 1. **邻接**：两框沿某一轴的间隙 ≤ `gap`（`clamp(gap_ratio × 最短边, min, max)`，随分辨率缩放）；
//! 2. **投影重叠**：并排的两框在 y 上重叠 ≥ `overlap_ratio`（或上下堆叠的两框在 x 上重叠 ≥ 该值）。
//!
//! 只用第 1 条会跨气泡串簇：实测页上「きたんだよお前!」与「初めて見たよ!」上下只差 3 px、
//! 距离为 0，但横向重叠只有 0.18 —— 第 2 条把它们分开（0.18 < 0.6）。
//!
//! 块内文本序是**列优先**（右列先、同列内自上而下），见 `TextBlock::order_reading`：
//! 竖排漫画里同列的两段是「上→下」、不同列是「右→左」，只按 y 分桶会打乱列内顺序
//! （实测「あ」「田舎とかに」「いる!?」「の」曾被拼成「あ田舎とかにいる!?の」）。

use crate::types::{Quad, TextBox};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug)]
pub struct GroupParams {
    pub gap_ratio: f32,
    pub min_gap_px: f32,
    /// 上限防的是「大字号页把两个相邻气泡串成一簇」。
    pub max_gap_px: f32,
    /// 邻接轴上的投影重叠率下限（相对较短的一边）。
    pub overlap_ratio: f32,
}

impl Default for GroupParams {
    /// 依据 mokuro 那页（28 框）的实测：同气泡相邻列间隙 7.5–15 px、跨气泡最近 ~26 px；
    /// 串簇那对的横向重叠 0.18，正常并排对 ≥ 0.75。换页面尺度时这份实测要重做。
    fn default() -> Self {
        Self {
            gap_ratio: 0.9,
            min_gap_px: 6.0,
            max_gap_px: 20.0,
            overlap_ratio: 0.6,
        }
    }
}

/// 一个文本块：成员下标（指向传入的 `boxes`）+ 轴对齐并集框。
#[derive(Clone, Debug)]
pub struct TextBlock {
    pub quad: Quad,
    pub members: Vec<usize>,
}

impl TextBlock {
    /// 块内读序：**列优先**（右→左，列内上→下）。返回成员下标的排列。
    ///
    /// 列宽用成员宽度的中位数估计；同列判定是「中心 x 相差 ≤ 0.6 × 列宽」。
    pub fn order_reading(&self, boxes: &[TextBox]) -> Vec<usize> {
        if self.members.len() <= 1 {
            return self.members.clone();
        }
        let centers: Vec<(usize, f32, f32, f32)> = self
            .members
            .iter()
            .map(|&m| {
                let (x0, y0, x1, y1) = boxes[m].quad.aabb();
                (m, (x0 + x1) / 2.0, (y0 + y1) / 2.0, (x1 - x0).max(1.0))
            })
            .collect();
        let mut widths: Vec<f32> = centers.iter().map(|c| c.3).collect();
        widths.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let median_w = widths[widths.len() / 2].max(1.0);
        let same_column = 0.6 * median_w;

        // 右→左分列：先按中心 x 降序，再把 x 相近的归进同一列。
        let mut by_x: Vec<(usize, f32, f32)> = centers.iter().map(|c| (c.0, c.1, c.2)).collect();
        by_x.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        let mut columns: Vec<Vec<(usize, f32, f32)>> = Vec::new();
        for item in by_x {
            match columns.last_mut() {
                Some(col) if (col[0].1 - item.1).abs() <= same_column => col.push(item),
                _ => columns.push(vec![item]),
            }
        }
        // 列内上→下。
        let mut out = Vec::with_capacity(self.members.len());
        for col in columns.iter_mut() {
            col.sort_by(|a, b| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal));
            out.extend(col.iter().map(|c| c.0));
        }
        out
    }
}

pub fn group_boxes(boxes: &[TextBox], p: &GroupParams) -> Vec<TextBlock> {
    if boxes.is_empty() {
        return Vec::new();
    }
    let rects: Vec<(f32, f32, f32, f32)> = boxes.iter().map(|b| b.quad.aabb()).collect();
    let n = boxes.len();
    let mut parent: Vec<usize> = (0..n).collect();

    fn find(parent: &mut [usize], mut i: usize) -> usize {
        while parent[i] != i {
            parent[i] = parent[parent[i]];
            i = parent[i];
        }
        i
    }

    for i in 0..n {
        for j in (i + 1)..n {
            if !neighbours(rects[i], rects[j], p) {
                continue;
            }
            let (ri, rj) = (find(&mut parent, i), find(&mut parent, j));
            if ri != rj {
                parent[ri] = rj;
            }
        }
    }

    let mut blocks: Vec<TextBlock> = Vec::new();
    let mut root_to_out: HashMap<usize, usize> = HashMap::new();
    for i in 0..n {
        let root = find(&mut parent, i);
        let out = *root_to_out.entry(root).or_insert_with(|| {
            blocks.push(TextBlock {
                quad: Quad(boxes[i].quad.0),
                members: Vec::new(),
            });
            blocks.len() - 1
        });
        blocks[out].members.push(i);
    }
    for b in blocks.iter_mut() {
        b.quad = union_over(&b.members, &rects);
    }
    blocks
}

fn union_over(members: &[usize], rects: &[(f32, f32, f32, f32)]) -> Quad {
    let mut x0 = f32::INFINITY;
    let mut y0 = f32::INFINITY;
    let mut x1 = f32::NEG_INFINITY;
    let mut y1 = f32::NEG_INFINITY;
    for &m in members {
        let r = rects[m];
        x0 = x0.min(r.0);
        y0 = y0.min(r.1);
        x1 = x1.max(r.2);
        y1 = y1.max(r.3);
    }
    Quad([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
}

fn neighbours(a: (f32, f32, f32, f32), b: (f32, f32, f32, f32), p: &GroupParams) -> bool {
    let (aw, ah) = (a.2 - a.0, a.3 - a.1);
    let (bw, bh) = (b.2 - b.0, b.3 - b.1);
    let gap = (p.gap_ratio * aw.min(ah).min(bw).min(bh)).clamp(p.min_gap_px, p.max_gap_px);
    let dx = axis_gap(a.0, a.2, b.0, b.2);
    let dy = axis_gap(a.1, a.3, b.1, b.3);
    let x_overlap = overlap(a.0, a.2, b.0, b.2) / aw.min(bw).max(1.0);
    let y_overlap = overlap(a.1, a.3, b.1, b.3) / ah.min(bh).max(1.0);

    let side_by_side = dx <= gap && y_overlap >= p.overlap_ratio;
    let stacked = dy <= gap && x_overlap >= p.overlap_ratio;
    side_by_side || stacked
}

/// 一维轴上两个区间的间隙（重叠时为 0）。
fn axis_gap(a0: f32, a1: f32, b0: f32, b1: f32) -> f32 {
    (b0 - a1).max(a0 - b1).max(0.0)
}

/// 一维轴上两个区间的重叠长度。
fn overlap(a0: f32, a1: f32, b0: f32, b1: f32) -> f32 {
    (a1.min(b1) - a0.max(b0)).max(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bx(x0: f32, y0: f32, w: f32, h: f32) -> TextBox {
        TextBox {
            quad: Quad([[x0, y0], [x0 + w, y0], [x0 + w, y0 + h], [x0, y0 + h]]),
            score: 1.0,
        }
    }

    #[test]
    fn adjacent_columns_merge_into_one_block() {
        // 真实几何：17 px 宽、间隙 8 px、y 几乎完全重叠。
        let boxes = vec![bx(100.0, 10.0, 17.0, 120.0), bx(75.0, 10.0, 17.0, 120.0)];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 1, "{blocks:?}");
        assert_eq!(blocks[0].members, vec![0, 1]);
        let (x0, y0, x1, y1) = blocks[0].quad.aabb();
        assert_eq!((x0, y0, x1, y1), (75.0, 10.0, 117.0, 130.0));
    }

    #[test]
    fn wide_gap_within_a_bubble_still_merges() {
        // 真实几何：间隙 15 px（「トカゲじゃ」/「ない!?」），y 重叠 0.96。
        let boxes = vec![bx(345.0, 336.0, 17.0, 110.0), bx(308.0, 333.0, 22.0, 77.0)];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 1, "{blocks:?}");
    }

    #[test]
    fn stacked_bubbles_with_tiny_overlap_do_not_merge() {
        // 真实几何（串簇那对）：y 只差 3 px，但横向重叠 0.18 < 0.6 → 必须分开。
        let boxes = vec![bx(679.0, 804.0, 18.0, 167.0), bx(665.0, 968.0, 17.0, 157.0)];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 2, "跨气泡不该合并：{blocks:?}");
    }

    #[test]
    fn distant_bubbles_stay_separate() {
        let boxes = vec![bx(0.0, 0.0, 20.0, 60.0), bx(50.0, 0.0, 20.0, 60.0)];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 2, "{blocks:?}");
    }

    #[test]
    fn horizontal_lines_stack_into_one_block() {
        // 横排四行：行距 4 px、行高 18、x 完全重叠。
        let boxes = vec![
            bx(10.0, 0.0, 120.0, 18.0),
            bx(10.0, 22.0, 120.0, 18.0),
            bx(10.0, 44.0, 120.0, 18.0),
            bx(10.0, 66.0, 120.0, 18.0),
        ];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 1, "{blocks:?}");
        assert_eq!(blocks[0].members.len(), 4);
    }

    #[test]
    fn chain_of_columns_transitively_merges() {
        let boxes = vec![
            bx(100.0, 0.0, 17.0, 100.0),
            bx(75.0, 0.0, 17.0, 100.0),
            bx(50.0, 0.0, 17.0, 100.0),
        ];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 1, "{blocks:?}");
        assert_eq!(blocks[0].members, vec![0, 1, 2]);
    }

    #[test]
    fn reading_order_is_column_major() {
        // 真实几何：右列「あ」(上)/「の」(下)，左列「田舎とかに」/「いる!?」。
        // 期望读序 0 → 1 → 2 → 3（只按 y 分桶会拼成「あ田舎とかにいる!?の」）。
        let boxes = vec![
            bx(111.0, 342.0, 13.0, 20.0),
            bx(109.0, 363.0, 17.0, 19.0),
            bx(79.0, 339.0, 23.0, 112.0),
            bx(53.0, 341.0, 18.0, 65.0),
        ];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks.len(), 1, "{blocks:?}");
        assert_eq!(blocks[0].order_reading(&boxes), vec![0, 1, 2, 3]);
    }

    #[test]
    fn single_member_order_is_identity() {
        let boxes = vec![bx(0.0, 0.0, 10.0, 10.0)];
        let blocks = group_boxes(&boxes, &GroupParams::default());
        assert_eq!(blocks[0].order_reading(&boxes), vec![0]);
    }
}
