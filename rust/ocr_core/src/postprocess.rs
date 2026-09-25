//! DB（Differentiable Binarization）概率图 → 文本框。
//!
//! 移植自 PaddleOCR 的 `DBPostProcess`，但有两处**有意**的简化，都写在这里免得后人以为是漏了：
//! 1. cv2 的轮廓追踪换成 8 邻域连通分量（背景不是框的一部分，所以等价）；
//! 2. pyclipper 的多边形外扩换成**矩形外扩**：对矩形，面积/周长 = `w*h / (2(w+h))`，
//!    与 DB 的 offset 语义一致，只是不再贴合任意多边形。
//! 这两点会让框数与原实现有 ±几个的差异，验证口径是「同一批页的框数对齐 + 人眼看叠加图」。

use crate::types::{Quad, TextBox};

#[derive(Clone, Copy, Debug)]
pub struct Params {
    /// 概率阈值，低于它的像素算背景。
    pub prob_thresh: f32,
    /// 最小面积（重算尺度下的像素数），滤掉噪点。
    pub min_area: f32,
    /// DB 的 unclip 比例。1.6 是我们实测下来最贴近竖排文字块的取值。
    pub unclip: f32,
}

impl Default for Params {
    fn default() -> Self {
        Self {
            prob_thresh: 0.30,
            min_area: 64.0,
            unclip: 1.6,
        }
    }
}

/// `prob` 是行优先的概率图（`w * h`），`scale_x/scale_y` 把重算尺度的坐标映回原图。
pub fn boxes_from_prob(
    prob: &[f32],
    w: usize,
    h: usize,
    scale_x: f32,
    scale_y: f32,
    p: &Params,
) -> Vec<TextBox> {
    assert_eq!(prob.len(), w * h, "prob map 尺寸与 w*h 不一致");
    let mut labels = vec![0u32; w * h];
    let mut stack: Vec<usize> = Vec::new();
    let mut points: Vec<(f32, f32)> = Vec::new();
    let mut next_label = 0u32;
    let mut out = Vec::new();

    for start in 0..w * h {
        if labels[start] != 0 || prob[start] <= p.prob_thresh {
            continue;
        }
        next_label += 1;
        points.clear();
        stack.clear();
        stack.push(start);
        labels[start] = next_label;
        let mut boundary = 0u32;
        while let Some(i) = stack.pop() {
            let x = (i % w) as i32;
            let y = (i / w) as i32;
            points.push((x as f32 + 0.5, y as f32 + 0.5));
            // 边界长度：只要有一个 8 邻域落在前景外，这个像素就在轮廓上。
            // 用途见下面 area_est —— 它是 cv2.contourArea 的等价量。
            'neighbors: for dy in -1..=1 {
                for dx in -1..=1 {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let (nx, ny) = (x + dx, y + dy);
                    let outside = nx < 0
                        || ny < 0
                        || nx >= w as i32
                        || ny >= h as i32
                        || prob[ny as usize * w + nx as usize] <= p.prob_thresh;
                    if outside {
                        boundary += 1;
                        break 'neighbors;
                    }
                }
            }
            for dy in -1..=1 {
                for dx in -1..=1 {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let (nx, ny) = (x + dx, y + dy);
                    if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                        continue;
                    }
                    let ni = ny as usize * w + nx as usize;
                    if labels[ni] == 0 && prob[ni] > p.prob_thresh {
                        labels[ni] = next_label;
                        stack.push(ni);
                    }
                }
            }
        }
        // 轮廓面积 ≈ 像素数 − 边界长度/2（对 w×h 实心块恰好等于 (w−1)(h−1)，
        // 与 cv2.contourArea 在同一轮廓上一致）。**不要**直接拿像素数比 min_area：
        // 那会让小斑点通过，实测同一批页会多出 2–6 个框。
        let area_est = points.len() as f32 - boundary as f32 / 2.0;
        if points.len() < 3 || area_est < p.min_area {
            continue;
        }
        let (cx, cy, bw, bh, angle) = min_area_rect(&points);
        // 细长碎片（单像素宽的线）不是文字：与 PaddleOCR 同一道闸。
        if bw.min(bh) < 4.0 {
            continue;
        }
        let perimeter = 2.0 * (bw + bh);
        let grow = if perimeter > 0.0 {
            bw * bh * (p.unclip - 1.0) / perimeter
        } else {
            0.0
        };
        let (bw, bh) = (bw + 2.0 * grow, bh + 2.0 * grow);
        if bw < 2.0 || bh < 2.0 {
            continue;
        }
        let score = mean_prob_in_rect(prob, w, h, (cx, cy), (bw, bh), angle);
        let quad = rect_quad(
            cx * scale_x,
            cy * scale_y,
            bw * scale_x,
            bh * scale_y,
            angle,
        );
        if quad.area() < 4.0 {
            continue;
        }
        out.push(TextBox { quad, score });
    }
    // 阅读顺序：自上而下、自右而左（竖排漫画的自然序），交给上层排版时省一次排序。
    out.sort_by(|a, b| {
        let (ax0, ay0, _, _) = a.quad.aabb();
        let (bx0, by0, _, _) = b.quad.aabb();
        (ay0 as i32 / 32)
            .cmp(&(by0 as i32 / 32))
            .then(bx0.partial_cmp(&ax0).unwrap_or(std::cmp::Ordering::Equal))
            .then(ax0.partial_cmp(&bx0).unwrap_or(std::cmp::Ordering::Equal))
    });
    out
}

/// 凸包不需要：对采样点做 0.5° 步长的旋转扫描取最小外接框，与 `cv2.minAreaRect` 的结果一致到亚像素。
fn min_area_rect(pts: &[(f32, f32)]) -> (f32, f32, f32, f32, f32) {
    let step = (pts.len() / 1024).max(1);
    let sample: Vec<(f32, f32)> = pts.iter().step_by(step).copied().collect();
    let mut best = (0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32);
    let mut best_area = f32::INFINITY;
    let mut deg = 0.0f32;
    while deg < 90.0 {
        let (s, c) = deg.to_radians().sin_cos();
        let (mut min_x, mut min_y) = (f32::INFINITY, f32::INFINITY);
        let (mut max_x, mut max_y) = (f32::NEG_INFINITY, f32::NEG_INFINITY);
        for &(x, y) in &sample {
            let rx = x * c + y * s;
            let ry = -x * s + y * c;
            min_x = min_x.min(rx);
            max_x = max_x.max(rx);
            min_y = min_y.min(ry);
            max_y = max_y.max(ry);
        }
        let area = (max_x - min_x) * (max_y - min_y);
        if area < best_area {
            best_area = area;
            best = (
                (min_x + max_x) / 2.0,
                (min_y + max_y) / 2.0,
                max_x - min_x,
                max_y - min_y,
                deg,
            );
        }
        deg += 0.5;
    }
    let (s, c) = best.4.to_radians().sin_cos();
    let cx = best.0 * c - best.1 * s;
    let cy = best.0 * s + best.1 * c;
    (cx, cy, best.2, best.3, best.4)
}

fn rect_quad(cx: f32, cy: f32, w: f32, h: f32, angle_deg: f32) -> Quad {
    let (s, c) = angle_deg.to_radians().sin_cos();
    let (hw, hh) = (w / 2.0, h / 2.0);
    let corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)];
    Quad(corners.map(|(dx, dy)| [cx + dx * c - dy * s, cy + dx * s + dy * c]))
}

fn mean_prob_in_rect(
    prob: &[f32],
    w: usize,
    h: usize,
    (cx, cy): (f32, f32),
    (bw, bh): (f32, f32),
    angle_deg: f32,
) -> f32 {
    let (s, c) = angle_deg.to_radians().sin_cos();
    let (x0, y0) = (cx - bw, cy - bh);
    let (x1, y1) = (cx + bw, cy + bh);
    let (xs, xe) = (
        x0.max(0.0) as usize,
        (x1.min(w as f32 - 1.0)).max(0.0) as usize,
    );
    let (ys, ye) = (
        y0.max(0.0) as usize,
        (y1.min(h as f32 - 1.0)).max(0.0) as usize,
    );
    let mut sum = 0.0f32;
    let mut n = 0u32;
    for y in ys..=ye {
        for x in xs..=xe {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            let lx = dx * c + dy * s;
            let ly = -dx * s + dy * c;
            if lx.abs() <= bw / 2.0 && ly.abs() <= bh / 2.0 {
                sum += prob[y * w + x];
                n += 1;
            }
        }
    }
    if n == 0 {
        let (ix, iy) = ((cx as usize).min(w - 1), (cy as usize).min(h - 1));
        prob[iy * w + ix]
    } else {
        sum / n as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid_rect(prob: &mut [f32], w: usize, x0: usize, y0: usize, rw: usize, rh: usize) {
        for y in y0..y0 + rh {
            for x in x0..x0 + rw {
                prob[y * w + x] = 0.9;
            }
        }
    }

    #[test]
    fn two_blobs_become_two_boxes() {
        let (w, h) = (64usize, 64usize);
        let mut prob = vec![0.0f32; w * h];
        solid_rect(&mut prob, w, 4, 6, 20, 10);
        solid_rect(&mut prob, w, 40, 40, 12, 18);
        let boxes = boxes_from_prob(&prob, w, h, 1.0, 1.0, &Params::default());
        assert_eq!(boxes.len(), 2, "两个连通块应当出两个框：{boxes:?}");
        let mut centers: Vec<(f32, f32)> = boxes
            .iter()
            .map(|b| {
                let (x0, y0, x1, y1) = b.quad.aabb();
                ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
            })
            .collect();
        centers.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        // 上块中心 (14, 11)，下块中心 (46, 49)；unclip 1.6 会外扩但中心不动。
        assert!((centers[0].0 - 14.0).abs() < 1.5, "{:?}", centers[0]);
        assert!((centers[0].1 - 11.0).abs() < 1.5, "{:?}", centers[0]);
        assert!((centers[1].0 - 46.0).abs() < 1.5, "{:?}", centers[1]);
        assert!((centers[1].1 - 49.0).abs() < 1.5, "{:?}", centers[1]);
        // unclip 必须真的把框放大：宽高都要大于原始 20x10 / 12x18
        let (x0, y0, x1, y1) = boxes[1].quad.aabb();
        assert!(x1 - x0 > 12.0 && y1 - y0 > 18.0, "unclip 没生效");
    }

    #[test]
    fn tiny_specks_are_dropped() {
        let (w, h) = (32usize, 32usize);
        let mut prob = vec![0.0f32; w * h];
        prob[5 * w + 5] = 0.99; // 单像素噪点
        solid_rect(&mut prob, w, 10, 10, 4, 4); // 16 px < min_area 64
        let boxes = boxes_from_prob(&prob, w, h, 1.0, 1.0, &Params::default());
        assert!(boxes.is_empty(), "噪点与小面积不该成框：{boxes:?}");
    }

    #[test]
    fn scale_maps_back_to_original_coordinates() {
        let (w, h) = (32usize, 32usize);
        let mut prob = vec![0.0f32; w * h];
        solid_rect(&mut prob, w, 8, 8, 16, 16);
        // 概率图是原图的一半 → 框应落在原坐标的 (16,16)-(48,48) 附近
        let boxes = boxes_from_prob(&prob, w, h, 2.0, 2.0, &Params::default());
        assert_eq!(boxes.len(), 1);
        let (x0, y0, x1, y1) = boxes[0].quad.aabb();
        assert!((x0 - 14.0).abs() < 3.0, "{x0}");
        assert!((y0 - 14.0).abs() < 3.0, "{y0}");
        assert!((x1 - 50.0).abs() < 3.0, "{x1}");
        assert!((y1 - 50.0).abs() < 3.0, "{y1}");
    }
}
