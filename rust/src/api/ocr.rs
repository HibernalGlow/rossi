//! OCR 链路的桥接入口（ADR-0018）。
//!
//! **分工**（ADR-0018 §决定 3 与 §决定 7）：Rust 只管像素与几何 —— 检测 / 识别 / 聚块 / 擦字；
//! 翻译走 Dart 侧的 `WindHttp`（不把 LLM 或 NMT 塞进 Rust），译文绘制也留在 Dart
//! （复用 Flutter 的 CJK 整形）。所以这里暴露的是「给我这一页的块与原文 + 一张擦干净的底图」，
//! 而不是「给我译文」。
//!
//! 模型路径由调用方给：权重**不随包**（§决定 5），首下与目录管理在 Dart 侧。

use anyhow::{Context, Result, anyhow};
use flutter_rust_bridge::frb;
use rossi_ocr_core::{
    Detector, Ep, GroupParams, Inpainter, Recognizer, group_boxes, mask_from_blocks,
};
use std::path::PathBuf;
use std::time::Instant;

/// 四个模型文件的路径。检测件与识别件分别来自各自的模型仓库，见 `REFERENCE_RESEARCH.md` §8.6.1。
pub struct OcrModelPaths {
    pub det: String,
    pub encoder: String,
    pub decoder: String,
    pub vocab: String,
}

/// 一个文本块。`quad` 是 8 个数（左上 / 右上 / 右下 / 左下，原图像素坐标）。
pub struct OcrBlock {
    pub quad: Vec<f32>,
    /// 按**列优先读序**拼好的原文（右→左、列内上→下）。
    pub text: String,
    /// 组成该块的检测框数量，用来判断这一块是否由多列拼成。
    pub boxes: u32,
    /// 识别是否因达到上限被截断 —— 截断的文本应在上层标为可疑。
    pub truncated: bool,
}

/// 一页的分析结果。耗时字段的单位是毫秒。
pub struct OcrPageResult {
    pub blocks: Vec<OcrBlock>,
    pub page_width: u32,
    pub page_height: u32,
    pub detect_ms: u64,
    pub recognize_ms: u64,
    pub inpaint_ms: u64,
    /// 擦干净的底图（仅在给了 `erased_output` 时写出）。译文要画在这张图上。
    pub erased_path: Option<String>,
}

/// 检测 → 识别 → 聚块（→ 可选擦字）。**不做翻译**，也不画字。
///
/// `ep` 取 `cpu` / `coreml` / `directml`：EP 按模型指定，且选了不支持的不静默退回 CPU
/// （ADR-0018 §决定 3.1 的实测结论）。
#[frb]
pub async fn ocr_analyze_page(
    image_path: String,
    models: OcrModelPaths,
    ep: String,
    inpaint_model: Option<String>,
    erased_output: Option<String>,
    max_new_tokens: Option<u32>,
) -> Result<OcrPageResult> {
    tokio::task::spawn_blocking(move || {
        let ep = Ep::parse(&ep)?;
        let page = image::open(&image_path)
            .with_context(|| format!("读图失败：{image_path}"))?
            .to_rgb8();
        let (page_w, page_h) = page.dimensions();

        let mut detector = Detector::from_file(&PathBuf::from(&models.det), ep)?;
        let detection = detector.detect(&page)?;
        let detect_ms =
            (detection.preprocess_ms + detection.infer_ms + detection.postprocess_ms) as u64;

        let mut recognizer = Recognizer::from_files(
            &PathBuf::from(&models.encoder),
            &PathBuf::from(&models.decoder),
            &PathBuf::from(&models.vocab),
            ep,
        )?;
        if let Some(n) = max_new_tokens {
            recognizer = recognizer.with_max_new_tokens(n as usize);
        }

        let recognize_start = Instant::now();
        let mut texts: Vec<(String, bool)> = Vec::with_capacity(detection.boxes.len());
        for b in &detection.boxes {
            let (x0, y0, x1, y1) = b.quad.aabb();
            let crop = crop_with_pad(&page, x0, y0, x1, y1, CROP_PAD);
            if crop.width() == 0 || crop.height() == 0 {
                texts.push((String::new(), false));
                continue;
            }
            let r = recognizer.recognize(&crop)?;
            texts.push((r.text, r.truncated));
        }
        let recognize_ms = recognize_start.elapsed().as_millis() as u64;

        let blocks_raw = group_boxes(&detection.boxes, &GroupParams::default());
        let blocks: Vec<OcrBlock> = blocks_raw
            .iter()
            .map(|blk| {
                let ordered = blk.order_reading(&detection.boxes);
                let text: String = ordered
                    .iter()
                    .filter_map(|m| texts.get(*m))
                    .map(|(t, _)| t.as_str())
                    .collect();
                let truncated = ordered
                    .iter()
                    .filter_map(|m| texts.get(*m))
                    .any(|(_, trunc)| *trunc);
                OcrBlock {
                    quad: blk.quad.0.iter().flat_map(|p| [p[0], p[1]]).collect(),
                    text,
                    boxes: blk.members.len() as u32,
                    truncated,
                }
            })
            .collect();

        let mut inpaint_ms = 0u64;
        let mut erased_path = None;
        if let Some(model) = inpaint_model {
            let out = erased_output
                .clone()
                .ok_or_else(|| anyhow!("给了擦字模型就必须给输出路径"))?;
            let mask = mask_from_blocks(&blocks_raw, page_w, page_h, 3);
            if mask.iter().any(|v| *v > 0) {
                let mut inpainter = Inpainter::from_file(&PathBuf::from(&model), ep)?;
                let erased = inpainter.inpaint(&page, &mask)?;
                inpaint_ms = (erased.preprocess_ms + erased.infer_ms + erased.composite_ms) as u64;
                erased
                    .image
                    .save(&out)
                    .with_context(|| format!("写擦字结果失败：{out}"))?;
                erased_path = Some(out);
            }
        }

        Ok(OcrPageResult {
            blocks,
            page_width: page_w,
            page_height: page_h,
            detect_ms,
            recognize_ms,
            inpaint_ms,
            erased_path,
        })
    })
    .await
    .context("OCR 分析任务 panic")?
}

/// 识别时的裁剪外扩：实测 6 px 才能把竖排末字（「出てきなさい」）补全，见 §8.6.6。
const CROP_PAD: i32 = 6;

fn crop_with_pad(
    img: &image::RgbImage,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    pad: i32,
) -> image::RgbImage {
    let (w, h) = (img.width() as i32, img.height() as i32);
    let xs = (x0 as i32 - pad).clamp(0, w);
    let ys = (y0 as i32 - pad).clamp(0, h);
    let xe = (x1 as i32 + pad).clamp(0, w);
    let ye = (y1 as i32 + pad).clamp(0, h);
    if xe <= xs || ye <= ys {
        return image::RgbImage::new(0, 0);
    }
    image::imageops::crop_imm(
        img,
        xs as u32,
        ys as u32,
        (xe - xs) as u32,
        (ye - ys) as u32,
    )
    .to_image()
}
