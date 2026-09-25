//! 文字检测：PP-OCRv4 mobile det（`ch_PP-OCRv4_det_infer.onnx`，apache-2.0、4.7 MB）。
//!
//! 选型依据见 ADR-0018 §决定 3.3：8 张真实页实测下它框紧贴竖排文字列、误报极少，
//! 约 70 ms/页；已知缺口是**漏手写拟声词**（三家检测件都漏，登记为能力缺口而非 bug）。
//!
//! 预处理与 PaddleOCR 保持一致（`limit_type = max`、边长对齐 32、ImageNet 均值方差），
//! 否则概率图会整体偏暗、框数显著偏少。

use crate::postprocess::{Params, boxes_from_prob};
use crate::session::{Ep, Stage, build_session};
use crate::types::TextBox;
use anyhow::{Context, Result, anyhow};
use image::{RgbImage, imageops::FilterType};
use ort::session::Session;
use ort::value::TensorRef;
use std::path::Path;
use std::time::Instant;

/// PaddleOCR 的 `DetResizeForTest(limit_type='max')` 默认值。
const LIMIT_SIDE: u32 = 960;
const MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const STD: [f32; 3] = [0.229, 0.224, 0.225];

pub struct Detector {
    session: Session,
    ep: Ep,
    params: Params,
    limit_side: u32,
}

pub struct Detection {
    pub boxes: Vec<TextBox>,
    /// 预处理后的推理输入尺寸 `(w, h)`，排查「框数不对」时第一眼看它。
    pub input_size: (u32, u32),
    pub preprocess_ms: u128,
    pub infer_ms: u128,
    pub postprocess_ms: u128,
}

impl Detector {
    pub fn from_file(model: &Path, ep: Ep) -> Result<Self> {
        Ok(Self {
            session: build_session(model, ep, Stage::Detect, 1)?,
            // 记**实际生效**的那个 EP：auto 报成 auto 等于把「到底跑了什么」藏起来。
            ep: ep.resolve(Stage::Detect),
            params: Params::default(),
            limit_side: LIMIT_SIDE,
        })
    }

    pub fn with_params(mut self, params: Params) -> Self {
        self.params = params;
        self
    }

    /// 推理前的长边上限（默认 960，PaddleOCR 的 `limit_type='max'`）。
    /// 漫画小字密集时值得往上调（1280 / 1536）：代价是推理时间按面积增长，
    /// 收益需要用真实页量一遍召回，别凭感觉改。
    pub fn with_limit_side(mut self, limit_side: u32) -> Self {
        self.limit_side = limit_side.max(32);
        self
    }

    pub fn ep(&self) -> Ep {
        self.ep
    }

    pub fn detect(&mut self, img: &RgbImage) -> Result<Detection> {
        let (w, h) = img.dimensions();
        if w == 0 || h == 0 {
            return Err(anyhow!("空图"));
        }
        let start = Instant::now();
        let (input, input_w, input_h) = preprocess(img, self.limit_side);
        let preprocess_ms = start.elapsed().as_millis();

        let tensor = TensorRef::from_array_view((
            [1usize, 3, input_h as usize, input_w as usize],
            input.as_slice(),
        ))
        .context("构造输入张量")?;
        let infer_start = Instant::now();
        let outputs = self
            .session
            .run(ort::inputs![tensor])
            .map_err(|e| anyhow!("检测推理失败：{e:?}"))?;
        let infer_ms = infer_start.elapsed().as_millis();

        let post_start = Instant::now();
        let (shape, raw) = outputs[0]
            .try_extract_tensor::<f32>()
            .context("读取概率图")?;
        let dims: Vec<usize> = shape.iter().map(|d| *d as usize).collect();
        let (map_w, map_h, prob) = match dims.as_slice() {
            // [1, 1, H, W]：单通道概率图
            [_, 1, mh, mw] => (*mw, *mh, raw),
            // 个别导出会去掉 batch 维
            [1, mh, mw] => (*mw, *mh, raw),
            other => {
                return Err(anyhow!("检测输出形状不认识：{other:?}（期望 [1,1,H,W]）"));
            }
        };
        let boxes = boxes_from_prob(
            prob,
            map_w,
            map_h,
            w as f32 / map_w as f32,
            h as f32 / map_h as f32,
            &self.params,
        );
        let postprocess_ms = post_start.elapsed().as_millis();
        Ok(Detection {
            boxes,
            input_size: (input_w, input_h),
            preprocess_ms,
            infer_ms,
            postprocess_ms,
        })
    }
}

/// `(NCHW, 对齐后的宽, 对齐后的高)`
fn preprocess(img: &RgbImage, limit_side: u32) -> (Vec<f32>, u32, u32) {
    let (w, h) = img.dimensions();
    let longest = w.max(h) as f32;
    let ratio = if longest > limit_side as f32 {
        limit_side as f32 / longest
    } else {
        1.0
    };
    let align = |v: f32| ((v / 32.0).round() as u32).max(1) * 32;
    let resized_w = align(w as f32 * ratio);
    let resized_h = align(h as f32 * ratio);
    let resized = image::imageops::resize(img, resized_w, resized_h, FilterType::Triangle);

    let plane = (resized_w * resized_h) as usize;
    let mut out = vec![0.0f32; 3 * plane];
    for (x, y, px) in resized.enumerate_pixels() {
        let idx = (y * resized_w + x) as usize;
        for c in 0..3 {
            out[c * plane + idx] = (px.0[c] as f32 / 255.0 - MEAN[c]) / STD[c];
        }
    }
    (out, resized_w, resized_h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preprocess_aligns_to_32_and_keeps_aspect() {
        let img = RgbImage::new(800, 1600);
        let (data, w, h) = preprocess(&img, 960);
        assert_eq!(h, 960, "长边应缩到 limit 并保持 32 对齐");
        assert_eq!(w % 32, 0);
        assert_eq!(w, 480, "800x1600 → 480x960");
        assert_eq!(data.len(), 3 * 480 * 960);
    }

    #[test]
    fn preprocess_downscales_long_side_and_aligns() {
        // 827x1170 的页：长边 1170 > 960 → **缩小**到长边 960，再对齐 32。
        // 这是 PaddleOCR `limit_type='max'` 的行为，也是 ADR-0018 §决定 3.3 那批框数的口径
        // （Python 参考实现跑的就是缩小后的输入）。想在不缩小的分辨率上检测，
        // 要调大 `limit_side`（`Detector::with_limit_side`），不能靠改这里。
        let img = RgbImage::new(827, 1170);
        let (_, w, h) = preprocess(&img, 960);
        assert_eq!((w, h), (672, 960));
    }

    #[test]
    fn preprocess_never_upscales() {
        // 长边不足 960 的页：比例 1.0，只做 32 对齐（放大只会浪费算力）。
        let img = RgbImage::new(600, 800);
        let (_, w, h) = preprocess(&img, 960);
        assert_eq!((w, h), (608, 800));
    }
}
