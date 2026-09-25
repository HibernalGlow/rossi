//! 检测与识别的结果类型。坐标系一律是**原图像素坐标**（左上为原点、y 向下）。

use serde::{Deserialize, Serialize};

/// 四角点，顺序固定为 左上 → 右上 → 右下 → 左下（顺时针）。
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct Quad(pub [[f32; 2]; 4]);

impl Quad {
    /// 轴对齐外接框 `(x0, y0, x1, y1)`。
    pub fn aabb(&self) -> (f32, f32, f32, f32) {
        let xs = self.0.map(|p| p[0]);
        let ys = self.0.map(|p| p[1]);
        (
            xs.iter().copied().fold(f32::INFINITY, f32::min),
            ys.iter().copied().fold(f32::INFINITY, f32::min),
            xs.iter().copied().fold(f32::NEG_INFINITY, f32::max),
            ys.iter().copied().fold(f32::NEG_INFINITY, f32::max),
        )
    }

    pub fn area(&self) -> f32 {
        let mut a = 0.0;
        for i in 0..4 {
            let p = self.0[i];
            let q = self.0[(i + 1) % 4];
            a += p[0] * q[1] - q[0] * p[1];
        }
        (a / 2.0).abs()
    }
}

/// 一个文字区域。一期只有检测产出它（识别/翻译会往后挂在同一个记录上）。
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TextBox {
    pub quad: Quad,
    /// 概率图在该框内的均值，与 PaddleOCR 的 `box_score` 同义。
    pub score: f32,
}
