//! 检测 → 识别 的最小端到端工具（一期链路的第二段）。
//!
//! 用法：
//! `ocr_page --det det.onnx --encoder enc.onnx --decoder dec.onnx --vocab vocab.txt <page.jpg>
//!           [--ep cpu|coreml] [--limit N] [--dump-crops DIR] [--json]`
//!
//! 裁剪口径：取框的轴对齐外接框再各边外扩 `--pad`（默认 2 px）——
//! 旋转框不做透视矫正，一期先按 v1 简化；竖排列基本都是近轴对齐的。

use anyhow::{Context, Result, anyhow};
use image::RgbImage;
use rossi_ocr_core::{Detector, Ep, Recognizer};
use serde_json::json;
use std::path::PathBuf;
use std::time::Instant;

fn main() -> Result<()> {
    let mut det = None;
    let mut encoder = None;
    let mut decoder = None;
    let mut vocab = None;
    let mut ep = Ep::Cpu;
    let mut limit = usize::MAX;
    let mut dump_crops: Option<PathBuf> = None;
    // 默认 6 是实测出来的：pad=2 时「出てきなさ」被裁成半截，pad=6 补全为「出てきなさい」
    // （竖排末字常贴着框边）。再大就会把相邻列的墨也带进来，反而干扰识别。
    let mut pad: i32 = 6;
    let mut print_json = false;
    let mut positional: Vec<String> = Vec::new();

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--det" => det = Some(PathBuf::from(take_value(&mut args, &arg)?)),
            "--encoder" => encoder = Some(PathBuf::from(take_value(&mut args, &arg)?)),
            "--decoder" => decoder = Some(PathBuf::from(take_value(&mut args, &arg)?)),
            "--vocab" => vocab = Some(PathBuf::from(take_value(&mut args, &arg)?)),
            "--ep" => ep = Ep::parse(&take_value(&mut args, &arg)?)?,
            "--limit" => limit = take_value(&mut args, &arg)?.parse()?,
            "--pad" => pad = take_value(&mut args, &arg)?.parse()?,
            "--dump-crops" => {
                let dir = PathBuf::from(take_value(&mut args, &arg)?);
                std::fs::create_dir_all(&dir)?;
                dump_crops = Some(dir);
            }
            "--json" => print_json = true,
            other => positional.push(other.to_string()),
        }
    }
    let image_path = positional
        .first()
        .ok_or_else(|| anyhow!("要一个页图路径"))?;
    let (det, encoder, decoder, vocab) = match (det, encoder, decoder, vocab) {
        (Some(a), Some(b), Some(c), Some(d)) => (a, b, c, d),
        _ => {
            return Err(anyhow!(
                "四个模型参数都要给：--det / --encoder / --decoder / --vocab"
            ));
        }
    };

    let page = image::open(image_path)
        .with_context(|| format!("读图失败：{image_path}"))?
        .to_rgb8();
    let (page_w, page_h) = page.dimensions();

    let mut detector = Detector::from_file(&det, ep)?;
    let detection = detector.detect(&page)?;
    let mut recognizer = Recognizer::from_files(&encoder, &decoder, &vocab, ep)?;
    if print_json {
        eprintln!(
            "词表 {} 条；检测到 {} 个框（推理输入 {}x{}）",
            recognizer.vocab_size(),
            detection.boxes.len(),
            detection.input_size.0,
            detection.input_size.1
        );
    }

    let mut items = Vec::new();
    let mut recognize_total_ms = 0u128;
    for (idx, b) in detection.boxes.iter().take(limit).enumerate() {
        let (x0, y0, x1, y1) = b.quad.aabb();
        let crop = crop_with_pad(&page, x0, y0, x1, y1, pad);
        if crop.width() == 0 || crop.height() == 0 {
            continue;
        }
        if let Some(dir) = &dump_crops {
            let name = format!("{:02}_x{}_y{}.png", idx, x0 as i32, y0 as i32);
            crop.save(dir.join(name))?;
        }
        let started = Instant::now();
        let recognition = recognizer.recognize(&crop)?;
        recognize_total_ms += started.elapsed().as_millis();
        items.push(json!({
            "quad": b.quad.0,
            "score": b.score,
            "text": recognition.text,
            "tokens": recognition.tokens,
            "truncated": recognition.truncated,
            "encoder_ms": recognition.encoder_ms,
            "decoder_ms": recognition.decoder_ms,
        }));
    }

    if print_json {
        println!(
            "{}",
            json!({
                "image": image_path,
                "size": [page_w, page_h],
                "ep": detector.ep().label(),
                "boxes": items.len(),
                "detect_ms": { "pre": detection.preprocess_ms, "infer": detection.infer_ms, "post": detection.postprocess_ms },
                "recognize_total_ms": recognize_total_ms,
                "items": items,
            })
        );
    } else {
        for it in &items {
            println!(
                "{:>6}  {:<40} tokens={} trunc={} enc/dec={}/{}ms",
                it["score"].as_f64().unwrap_or(0.0).round(),
                it["text"].as_str().unwrap_or(""),
                it["tokens"],
                it["truncated"],
                it["encoder_ms"],
                it["decoder_ms"]
            );
        }
        println!(
            "共 {} 个框；检测 前/推/后 = {}/{}/{} ms；识别合计 {} ms",
            items.len(),
            detection.preprocess_ms,
            detection.infer_ms,
            detection.postprocess_ms,
            recognize_total_ms
        );
    }
    Ok(())
}

fn take_value(args: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    args.next().ok_or_else(|| anyhow!("{flag} 后面要跟值"))
}

fn crop_with_pad(img: &RgbImage, x0: f32, y0: f32, x1: f32, y1: f32, pad: i32) -> RgbImage {
    let (w, h) = (img.width() as i32, img.height() as i32);
    let xs = (x0 as i32 - pad).clamp(0, w);
    let ys = (y0 as i32 - pad).clamp(0, h);
    let xe = (x1 as i32 + pad).clamp(0, w);
    let ye = (y1 as i32 + pad).clamp(0, h);
    if xe <= xs || ye <= ys {
        return RgbImage::new(0, 0);
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
