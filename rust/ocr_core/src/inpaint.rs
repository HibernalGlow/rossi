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
use crate::session::{Ep, Stage, build_session};
use anyhow::{Context, Result, anyhow};
use image::{Rgb, RgbImage, imageops::FilterType};
use ort::session::Session;
use ort::value::TensorRef;
use std::path::Path;
use std::time::Instant;

/// 擦字推理的裁剪策略。整页降采样是一期现状，代价与页面积成正比；
/// 而掩膜通常只占页面的一小部分 —— 只在掩膜附近跑，省的是平方级的面积。
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CropPolicy {
    /// 整页（降采样到 `max_side`）一次推理。
    None,
    /// 全部掩膜的轴对齐外接框，一次推理。
    MaskBbox,
    /// 掩膜按连通域分簇（外扩 `gap` px 再分簇，把「间距小于 gap 的两个气泡」算同一簇），逐簇推理。
    Clusters { gap: i32 },
}

pub struct Inpainter {
    session: Session,
    ep: Ep,
    max_side: u32,
    crop: CropPolicy,
    /// 裁剪框相对掩膜框再留的上下文边距。LaMa 靠周围像素补，框贴着掩膜边缘会糊。
    crop_pad: i32,
}

pub struct Inpainted {
    pub image: RgbImage,
    /// 实际送进模型的分辨率 `(w, h)`，排查「糊」的时候先看它。裁剪时是**最大那一块**。
    pub run_size: (u32, u32),
    pub preprocess_ms: u128,
    pub infer_ms: u128,
    pub composite_ms: u128,
    /// 推理次数（`CropPolicy::None` 恒为 1）。裁剪省下的时间要靠这个数一起看：
    /// 次数上去、单次面积下来，净收益不是显然的。
    pub runs: u32,
    /// 各次推理的分辨率，用于核对「裁剪后有没有把分辨率抬上去」。
    pub run_sizes: Vec<(u32, u32)>,
}

impl Inpainter {
    pub fn from_file(model: &Path, ep: Ep) -> Result<Self> {
        // 擦字段用 4 个 intra 线程，**不是** OCR 侧那条「= 1」的默认。
        // 实测（`inpaint_threads`，同进程交替、每轮轮换顺序，8 张真页里的 4 张）：
        // t=4 相对 t=1 是 **0.54–0.74 倍**，跨页一致；t=8 不再更好（0.67 倍，与 t=4 同量级）。
        // 4 = 本机性能核数（`hw.perflevel0.physicalcpu`），把能效核留给阅读器渲染。
        // 之所以要交替测：串行分块跑同一配置两次能差 57%，那台机器上「谁在吃 CPU」比效应本身还大。
        Self::from_file_with(model, ep, 4)
    }

    /// `intra_threads` 交给调用方：一期默认 1（见 [crate::session::build_session] 的抢核说明），
    /// 但「1 够不够」在擦字段**没有被量过** —— 这一段是整条链路里单次最长的一次推理，
    /// 而 Apple 上没有可用的加速器 EP（§8.6.3：CoreML 反而慢 3–5 倍），所以线程是剩下的旋钮。
    pub fn from_file_with(model: &Path, ep: Ep, intra_threads: usize) -> Result<Self> {
        Ok(Self {
            session: build_session(model, ep, Stage::Inpaint, intra_threads)?,
            // 记实际生效的 EP，理由同 Detector。
            ep: ep.resolve(Stage::Inpaint),
            max_side: 1024,
            crop: CropPolicy::None,
            crop_pad: 32,
        })
    }

    pub fn with_max_side(mut self, max_side: u32) -> Self {
        self.max_side = max_side.max(64);
        self
    }

    pub fn with_crop(mut self, crop: CropPolicy) -> Self {
        self.crop = crop;
        self
    }

    /// 台架要在同一个会话上逐档跑，所以除了 builder 还要一个就地设置器。
    pub fn set_crop(&mut self, crop: CropPolicy) {
        self.crop = crop;
    }

    pub fn with_crop_pad(mut self, crop_pad: i32) -> Self {
        self.crop_pad = crop_pad.max(0);
        self
    }

    pub fn ep(&self) -> Ep {
        self.ep
    }

    /// 整页入口：按 [CropPolicy] 切出若干块，逐块推理后再把结果拼回原页。
    ///
    /// 拼接**只覆盖掩膜内的像素**，所以裁剪框的边界（以及边界上可能的接缝）不会落到页面上 ——
    /// 这是裁剪策略低风险的原因，也是它必须靠实测而非直觉取舍的原因：真正会变的是模型看到的上下文。
    pub fn inpaint(&mut self, page: &RgbImage, mask: &[u8]) -> Result<Inpainted> {
        let (w, h) = page.dimensions();
        Self::check_mask(w, h, mask)?;
        let regions = self.regions(w, h, mask);
        if regions.len() == 1 && regions[0] == (0, 0, w, h) {
            return self.inpaint_region(page, mask);
        }

        let mut result = page.clone();
        let mut preprocess_ms = 0u128;
        let mut infer_ms = 0u128;
        let mut composite_ms = 0u128;
        let mut run_sizes = Vec::with_capacity(regions.len());

        for (rx, ry, rw, rh) in &regions {
            let sub_page = image::imageops::crop_imm(page, *rx, *ry, *rw, *rh).to_image();
            let mut sub_mask = vec![0u8; (rw * rh) as usize];
            for y in 0..*rh {
                let src = ((ry + y) as usize * w as usize + *rx as usize)
                    ..((ry + y) as usize * w as usize + *rx as usize + *rw as usize);
                sub_mask[(y as usize * *rw as usize)..(y as usize * *rw as usize + *rw as usize)]
                    .copy_from_slice(&mask[src]);
            }
            let part = self.inpaint_region(&sub_page, &sub_mask)?;
            preprocess_ms += part.preprocess_ms;
            infer_ms += part.infer_ms;
            composite_ms += part.composite_ms;
            run_sizes.push(part.run_size);
            for y in 0..*rh {
                for x in 0..*rw {
                    let si = (y * *rw + x) as usize;
                    if sub_mask[si] == 0 {
                        continue;
                    }
                    result.put_pixel(rx + x, ry + y, *part.image.get_pixel(x, y));
                }
            }
        }

        let max_run = run_sizes
            .iter()
            .copied()
            .max_by_key(|(rw, rh)| rw * rh)
            .unwrap_or((0, 0));
        Ok(Inpainted {
            image: result,
            run_size: max_run,
            preprocess_ms,
            infer_ms,
            composite_ms,
            runs: run_sizes.len() as u32,
            run_sizes,
        })
    }

    /// 对**给定图像**跑一次擦字（降采样 → 推理 → 升采样 → 掩膜内合成）。
    /// `inpaint` 的两种形态最终都走这里，所以「裁剪」与「整页」比的确实是同一条码路。
    pub fn inpaint_region(&mut self, page: &RgbImage, mask: &[u8]) -> Result<Inpainted> {
        let (w, h) = page.dimensions();
        Self::check_mask(w, h, mask)?;

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
            runs: 1,
            run_sizes: vec![(run_w, run_h)],
        })
    }

    fn check_mask(w: u32, h: u32, mask: &[u8]) -> Result<()> {
        if mask.len() != (w * h) as usize {
            return Err(anyhow!("掩膜尺寸不符：{} != {}x{}", mask.len(), w, h));
        }
        if mask.iter().all(|v| *v == 0) {
            return Err(anyhow!("掩膜是空的，没有要擦的区域"));
        }
        Ok(())
    }

    /// 要推理的矩形列表（左上 + 宽高）。恒非空，且每块里确实有掩膜像素。
    fn regions(&self, w: u32, h: u32, mask: &[u8]) -> Vec<(u32, u32, u32, u32)> {
        crop_regions(self.crop, self.crop_pad, w, h, mask)
    }
}

/// [Inpainter::regions] 的实际计算，抽成自由函数是因为单测不想为「算几个框」去加载 206 MB 的会话。
fn crop_regions(
    crop: CropPolicy,
    crop_pad: i32,
    w: u32,
    h: u32,
    mask: &[u8],
) -> Vec<(u32, u32, u32, u32)> {
    match crop {
        CropPolicy::None => vec![(0, 0, w, h)],
        CropPolicy::MaskBbox => match mask_bbox(mask, w) {
            Some((x0, y0, x1, y1)) => vec![grow(x0, y0, x1, y1, crop_pad, w, h)],
            None => vec![(0, 0, w, h)],
        },
        CropPolicy::Clusters { gap } => cluster_regions(mask, w, h, gap, crop_pad),
    }
}

/// 掩膜像素的轴对齐外接框 `(x0, y0, x1, y1)`（闭区间）；空掩膜返回 `None`。
fn mask_bbox(mask: &[u8], w: u32) -> Option<(u32, u32, u32, u32)> {
    let mut x0 = u32::MAX;
    let mut y0 = u32::MAX;
    let mut x1 = 0u32;
    let mut y1 = 0u32;
    for i in 0..mask.len() {
        if mask[i] == 0 {
            continue;
        }
        let (x, y) = ((i as u32) % w, (i as u32) / w);
        x0 = x0.min(x);
        y0 = y0.min(y);
        x1 = x1.max(x);
        y1 = y1.max(y);
    }
    if x0 > x1 {
        None
    } else {
        Some((x0, y0, x1, y1))
    }
}

/// 把闭区间外接框 `(x0,y0,x1,y1)` 各边外扩 `pad` 并夹到页内，转成左上 + 宽高。
fn grow(x0: u32, y0: u32, x1: u32, y1: u32, pad: i32, w: u32, h: u32) -> (u32, u32, u32, u32) {
    let xs = (x0 as i32 - pad).clamp(0, w as i32 - 1) as u32;
    let ys = (y0 as i32 - pad).clamp(0, h as i32 - 1) as u32;
    let xe = (x1 as i32 + pad).clamp(xs as i32, w as i32 - 1) as u32;
    let ye = (y1 as i32 + pad).clamp(ys as i32, h as i32 - 1) as u32;
    (xs, ys, xe - xs + 1, ye - ys + 1)
}

/// 连通域分簇：先把掩膜外扩 `gap`（把「气泡之间的距离小于 gap」的并成一簇），
/// 再做四连通标号，最后逐簇取外接框并留 `crop_pad` 的上下文。
///
/// 两簇的外接框**可能重叠**（L 形互相咬进对方的框）—— 重叠区按后跑的覆盖，
/// 两边都是合法填充，所以不额外处理；簇数极少时可忽略。
fn cluster_regions(
    mask: &[u8],
    w: u32,
    h: u32,
    gap: i32,
    crop_pad: i32,
) -> Vec<(u32, u32, u32, u32)> {
    let joined = dilate_mask(mask, w, h, gap.max(0));
    let mut labels = vec![0u32; joined.len()];
    let mut out: Vec<(u32, u32, u32, u32)> = Vec::new();
    let mut stack: Vec<usize> = Vec::new();

    for start in 0..joined.len() {
        if joined[start] == 0 || labels[start] != 0 {
            continue;
        }
        labels[start] = 1;
        stack.clear();
        stack.push(start);
        let p = start as u32;
        let mut bbox = (p % w, p / w, p % w, p / w);
        let mut has_real = mask[start] > 0;
        while let Some(i) = stack.pop() {
            let (x, y) = ((i as u32) % w, (i as u32) / w);
            bbox.0 = bbox.0.min(x);
            bbox.1 = bbox.1.min(y);
            bbox.2 = bbox.2.max(x);
            bbox.3 = bbox.3.max(y);
            for (dx, dy) in [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
                let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                    continue;
                }
                let ni = ny as usize * w as usize + nx as usize;
                if joined[ni] == 0 || labels[ni] != 0 {
                    continue;
                }
                labels[ni] = 1;
                if mask[ni] > 0 {
                    has_real = true;
                }
                stack.push(ni);
            }
        }
        // 只由「外扩 gap」连出来的纯空簇（掩膜像素一个没有）要丢掉，否则白跑一次推理。
        if has_real {
            out.push(grow(bbox.0, bbox.1, bbox.2, bbox.3, crop_pad, w, h));
        }
    }
    if out.is_empty() {
        out.push((0, 0, w, h));
    }
    out.sort_unstable();
    out
}

/// 方框膨胀（`r` px，四连通近似为两次一维滑窗）。`r == 0` 时原样返回。
fn dilate_mask(mask: &[u8], w: u32, h: u32, r: i32) -> Vec<u8> {
    if r <= 0 {
        return mask.to_vec();
    }
    let r = r as usize;
    let mut tmp = vec![0u8; mask.len()];
    let mut out = vec![0u8; mask.len()];
    // 横向
    for y in 0..h as usize {
        let row = y * w as usize;
        for x in 0..w as usize {
            if mask[row + x] == 0 {
                continue;
            }
            let a = x.saturating_sub(r);
            for k in a..(x + r + 1).min(w as usize) {
                tmp[row + k] = 255;
            }
        }
    }
    // 纵向
    for y in 0..h as usize {
        for x in 0..w as usize {
            if tmp[y * w as usize + x] == 0 {
                continue;
            }
            let a = y.saturating_sub(r);
            for k in a..(y + r + 1).min(h as usize) {
                out[k * w as usize + x] = 255;
            }
        }
    }
    out
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

    /// 裁剪策略的**底线**：掩膜里的每一个像素都必须落在某个裁剪区域内。
    /// 漏一个就是「擦不干净」里最隐蔽的那类 —— 不是模型没填好，而是那块根本没进模型。
    #[test]
    fn every_mask_pixel_lands_in_some_crop_region() {
        let (w, h) = (200u32, 120u32);
        let blocks = vec![
            block(10.0, 10.0, 60.0, 30.0),
            block(150.0, 80.0, 190.0, 110.0),
            block(70.0, 55.0, 90.0, 70.0),
        ];
        for d in [0i32, 3, 8] {
            let mask = mask_from_blocks(&blocks, w, h, d);
            for crop in [
                CropPolicy::None,
                CropPolicy::MaskBbox,
                CropPolicy::Clusters { gap: 40 },
                CropPolicy::Clusters { gap: 0 },
            ] {
                for pad in [0i32, 32] {
                    let regions = crop_regions(crop, pad, w, h, &mask);
                    assert!(
                        !regions.is_empty(),
                        "{crop:?} pad={pad} d={d} 一个区域都没切出来"
                    );
                    for (x, y, rw, rh) in &regions {
                        assert!(
                            x + rw <= w && y + rh <= h && *rw > 0 && *rh > 0,
                            "{crop:?} pad={pad} d={d} 的裁剪框跑出页面：{x},{y},{rw},{rh}"
                        );
                    }
                    for i in 0..mask.len() {
                        if mask[i] == 0 {
                            continue;
                        }
                        let (px, py) = ((i as u32) % w, (i as u32) / w);
                        assert!(
                            regions.iter().any(|(x, y, rw, rh)| px >= *x
                                && px < *x + *rw
                                && py >= *y
                                && py < *y + *rh),
                            "{crop:?} pad={pad} d={d} 漏掉掩膜像素 ({px},{py})"
                        );
                    }
                }
            }
        }
    }

    /// 分簇的语义：两块间距小于 `2 * gap` 才并成一簇。
    /// 这是裁剪收益的来源（簇数），也是它的风险来源（簇越大越不省），所以两个方向都要断言。
    #[test]
    fn cluster_gap_merges_near_bubbles_and_splits_far_ones() {
        let (w, h) = (400u32, 100u32);
        // d=3 之后两块的掩膜是 x∈[7,63] 与 x∈[87,143]，中间空 23 px。
        let blocks = vec![
            block(10.0, 10.0, 60.0, 40.0),
            block(90.0, 10.0, 140.0, 40.0),
        ];
        let mask = mask_from_blocks(&blocks, w, h, 3);
        assert_eq!(
            crop_regions(CropPolicy::Clusters { gap: 10 }, 0, w, h, &mask).len(),
            1 + 1,
            "间距 23 px > 2×gap(10) 应该还是两簇"
        );
        assert_eq!(
            crop_regions(CropPolicy::Clusters { gap: 15 }, 0, w, h, &mask).len(),
            1,
            "2×gap(15) = 30 > 23，应该把两簇连成一块"
        );
        // 阳性对照：整页模式永远是 1 次。
        assert_eq!(crop_regions(CropPolicy::None, 0, w, h, &mask).len(), 1);
    }

    #[test]
    fn mask_bbox_is_tighter_than_page() {
        let (w, h) = (400u32, 300u32);
        let blocks = vec![block(200.0, 20.0, 260.0, 60.0)];
        let mask = mask_from_blocks(&blocks, w, h, 3);
        let (x, y, rw, rh) = crop_regions(CropPolicy::MaskBbox, 0, w, h, &mask).remove(0);
        assert_eq!((x, y), (197, 17), "外接框要含 3 px 外扩");
        assert_eq!((rw, rh), (67, 47));
        // 带上下文边距时夹在页内，不许负坐标。
        let (x2, y2, rw2, rh2) = crop_regions(CropPolicy::MaskBbox, 64, w, h, &mask).remove(0);
        assert_eq!((x2, y2), (133, 0));
        assert_eq!((rw2, rh2), (195, 128));
    }

    /// 整页裁剪等于不裁：`inpaint` 在这种情况走的是同一条老路（单次、原图尺寸）。
    #[test]
    fn full_page_region_is_the_whole_image() {
        let (w, h) = (64u32, 32u32);
        let mask = mask_from_blocks(&[block(1.0, 1.0, 60.0, 30.0)], w, h, 3);
        assert_eq!(
            crop_regions(CropPolicy::None, 32, w, h, &mask),
            vec![(0, 0, w, h)]
        );
    }
}
