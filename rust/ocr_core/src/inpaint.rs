//! 擦字：LaMa 的 manga 导出（`ogkalu/lama-manga-onnx-dynamic`，**apache-2.0**、206 MB、动态尺寸）。
//!
//! 选型与实测见 ADR-0018 §决定 3.1 与 `docs/REFERENCE_RESEARCH.md` §8.6.2：
//! 气泡内白底上 LaMa 干净、AOT-GAN 留方格残影；网点/速度线上的粗笔画则反过来。
//! 一期只用 LaMa（AOT 那份能跑的导出**无 license 字段**，要随包得自己从 MIT 权重 + Apache 实现导）。
//!
//! **成本决定分辨率**：512² 在 CPU 上稳态 1 656 ms（CoreML 反而 3 825 ms，见 §8.6.3），
//! 而一页 1 500×1 100 是它的 6 倍面积 —— 直接原尺寸跑一页要十几秒。所以默认把页与掩膜一起降到
//! `max_side`（默认 1 024，对齐 8），推理后再升采样回原尺寸并**只在掩膜内**合成：
//! 掩膜外保持原图逐像素不变（这点与 LaMa 自身的性质一致：它不碰掩膜外的像素）。

use crate::group::TextBlock;
use crate::session::{Ep, build_session};
use anyhow::{Context, Result, anyhow};
use image::{Rgb, RgbImage, imageops::FilterType};
use ort::session::Session;
use ort::value::TensorRef;
use std::path::Path;
use std::time::Instant;

pub struct Inpainter {
    session: Session,
    ep: Ep,
    max_side: u32,
    /// 掩膜外扩（像素）：把字的外框再放大一点，否则残留的笔画边会被留在页面上。
    pub dilate_px: i32,
}

pub struct Inpainted {
    pub image: RgbImage,
    /// 实际送进模型的分辨率 `(w, h)`，排查「糊」的时候先看它。
    pub run_size: (u32, u32),
    pub preprocess_ms: u128,
    pub infer_ms: u128,
    pub composite_ms: u128,
}

impl Inpainter {
    pub fn from_file(model: &Path, ep: Ep) -> Result<Self> {
        Ok(Self {
            session: build_session(model, ep, 1)?,
            ep,
            max_side: 1024,
            dilate_px: 3,
        })
    }

    pub fn with_max_side(mut self, max_side: u32) -> Self {
        self.max_side = max_side.max(64);
        self
    }

    pub fn ep(&self) -> Ep {
        self.ep
    }

    pub fn inpaint(&mut self, page: &RgbImage, mask: &[u8]) -> Result<Inpainted> {
        let (w, h) = page.dimensions();
        if mask.len() != (w * h) as usize {
            return Err(anyhow!("掩膜尺寸不符：{} != {}x{}", mask.len(), w, h));
        }
        if mask.iter().all(|v| *v == 0) {
            return Err(anyhow!("掩膜是空的，没有要擦的区域"));
        }

        let start = Instant::now();
        let longest = w.max(h) as f32;
        let ratio = if longest > self.max_side as f32 {
            self.max_side as f32 / longest
        } else {
            1.0
        };
        let align8 = |v: f32| (((v / 8.0).round() as u32).max(1)) * 8;
        let run_w = align8(w as f32 * ratio);
        let run_h = align8(h as f32 * ratio);

        let small_page = image::imageops::resize(page, run_w, run_h, FilterType::Triangle);
        let mask_img = image::GrayImage::from_raw(w, h, mask.to_vec())
            .ok_or_else(|| anyhow!("掩膜构造失败"))?;
        let small_mask = image::imageops::resize(&mask_img, run_w, run_h, FilterType::Nearest);

        let plane = (run_w * run_h) as usize;
        let mut image_in = vec![0.0f32; 3 * plane];
        for (x, y, px) in small_page.enumerate_pixels() {
            let idx = (y * run_w + x) as usize;
            for c in 0..3 {
                image_in[c * plane + idx] = px.0[c] as f32 / 255.0;
            }
        }
        // 掩膜用 0/1（实测就该是这个取向：255 表示要擦除的像素）。
        let mask_in: Vec<f32> = small_mask
            .iter()
            .map(|v| if *v > 127 { 1.0 } else { 0.0 })
            .collect();
        let preprocess_ms = start.elapsed().as_millis();

        let image_tensor = TensorRef::from_array_view((
            [1usize, 3, run_h as usize, run_w as usize],
            image_in.as_slice(),
        ))
        .context("构造擦字输入图像")?;
        let mask_tensor = TensorRef::from_array_view((
            [1usize, 1, run_h as usize, run_w as usize],
            mask_in.as_slice(),
        ))
        .context("构造擦字输入掩膜")?;

        let input_names: Vec<String> = self
            .session
            .inputs()
            .iter()
            .map(|i| i.name().to_string())
            .collect();
        if !input_names.iter().any(|n| n == "image") || !input_names.iter().any(|n| n == "mask") {
            return Err(anyhow!(
                "擦字模型的输入名不是 image/mask，实际是 {input_names:?} —— 换模型时先核对这里"
            ));
        }

        let infer_start = Instant::now();
        let (out_dims, output) = {
            let outputs = self
                .session
                .run(ort::inputs!["image" => image_tensor, "mask" => mask_tensor])
                .map_err(|e| anyhow!("擦字推理失败：{e:?}"))?;
            let (shape, raw) = outputs[0]
                .try_extract_tensor::<f32>()
                .context("读取擦字输出")?;
            let dims: Vec<usize> = shape.iter().map(|d| *d as usize).collect();
            (dims, raw.to_vec())
        };
        let infer_ms = infer_start.elapsed().as_millis();
        if out_dims.len() < 3 {
            return Err(anyhow!("擦字输出维数不足：{out_dims:?}"));
        }
        let (out_h, out_w) = (out_dims[out_dims.len() - 2], out_dims[out_dims.len() - 1]);
        let out_plane = out_h * out_w;

        let composite_start = Instant::now();
        // 输出升采样回原尺寸（逐通道），再只在掩膜内合成。
        let mut up = vec![0.0f32; 3 * (w * h) as usize];
        for c in 0..3 {
            let channel: Vec<u8> = (0..out_plane)
                .map(|i| (output[c * out_plane + i].clamp(0.0, 1.0) * 255.0).round() as u8)
                .collect();
            let img = image::GrayImage::from_raw(out_w as u32, out_h as u32, channel)
                .ok_or_else(|| anyhow!("擦字输出通道构造失败"))?;
            let resized = image::imageops::resize(&img, w, h, FilterType::Triangle);
            for (i, v) in resized.iter().enumerate() {
                up[c * (w * h) as usize + i] = *v as f32 / 255.0;
            }
        }
        let mut result = page.clone();
        for y in 0..h {
            for x in 0..w {
                let i = (y * w + x) as usize;
                if mask[i] == 0 {
                    continue;
                }
                let px = Rgb([
                    (up[i] * 255.0).round().clamp(0.0, 255.0) as u8,
                    (up[(w * h) as usize + i] * 255.0).round().clamp(0.0, 255.0) as u8,
                    (up[2 * (w * h) as usize + i] * 255.0)
                        .round()
                        .clamp(0.0, 255.0) as u8,
                ]);
                result.put_pixel(x, y, px);
            }
        }
        let composite_ms = composite_start.elapsed().as_millis();
        Ok(Inpainted {
            image: result,
            run_size: (run_w, run_h),
            preprocess_ms,
            infer_ms,
            composite_ms,
        })
    }
}

/// 由文本块生成掩膜：块框并集外扩 `dilate_px`。返回 `w * h` 的 `u8`（255 = 要擦）。
pub fn mask_from_blocks(blocks: &[TextBlock], w: u32, h: u32, dilate_px: i32) -> Vec<u8> {
    let mut mask = vec![0u8; (w * h) as usize];
    for b in blocks {
        let (x0, y0, x1, y1) = b.quad.aabb();
        let xs = (x0 as i32 - dilate_px).clamp(0, w as i32 - 1);
        let ys = (y0 as i32 - dilate_px).clamp(0, h as i32 - 1);
        let xe = (x1 as i32 + dilate_px).clamp(0, w as i32 - 1);
        let ye = (y1 as i32 + dilate_px).clamp(0, h as i32 - 1);
        for y in ys..=ye {
            let row = y as usize * w as usize;
            for x in xs..=xe {
                mask[row + x as usize] = 255;
            }
        }
    }
    mask
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Quad;

    fn block(x0: f32, y0: f32, x1: f32, y1: f32) -> TextBlock {
        TextBlock {
            quad: Quad([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]),
            members: vec![0],
        }
    }

    #[test]
    fn mask_covers_dilated_block_rects() {
        let blocks = vec![block(10.0, 10.0, 20.0, 30.0)];
        let mask = mask_from_blocks(&blocks, 64, 64, 3);
        assert_eq!(mask[15 * 64 + 15], 255, "块内必为掩膜");
        assert_eq!(mask[15 * 64 + 7], 255, "外扩 3 px 应覆盖 x=7");
        assert_eq!(mask[15 * 64 + 6], 0, "外扩 3 px 不该覆盖 x=6");
        assert_eq!(mask[0], 0);
    }

    #[test]
    fn mask_clamps_at_page_edges() {
        let blocks = vec![block(0.0, 0.0, 5.0, 5.0)];
        let mask = mask_from_blocks(&blocks, 16, 16, 8);
        assert_eq!(mask[0], 255);
        assert_eq!(mask.len(), 256);
    }
}
