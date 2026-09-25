//! 检测 → 识别（→ 按块聚簇）的最小端到端工具。
//!
//! 用法：
//! `ocr_page --det det.onnx --encoder enc.onnx --decoder dec.onnx --vocab vocab.txt <page.jpg>
//!           [--ep cpu|coreml] [--limit N] [--group] [--dump-crops DIR] [--dump-groups PNG] [--json]`
//!
//! 裁剪口径：取框的轴对齐外接框再各边外扩 `--pad`（默认 6 px，见 main 里的实测说明）——
//! 旋转框不做透视矫正，一期先按 v1 简化；竖排列基本都是近轴对齐的。
//! `--group` 会额外输出「按列/行邻接聚成的块」及其拼接文本（拼块是翻译与擦字的单位）。

use anyhow::{Context, Result, anyhow};
use image::{Rgb, RgbImage};
use rossi_ocr_core::{Detector, Ep, GroupParams, Recognizer, TextBlock, group_boxes};
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
    let mut dump_groups: Option<PathBuf> = None;
    let mut group = false;
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
            "--group" => group = true,
            "--dump-groups" => dump_groups = Some(PathBuf::from(take_value(&mut args, &arg)?)),
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

    // 按块聚簇：翻译与擦字都以**块**为单位。成员下标顺序 = 检测给出的竖排阅读序，
    // 所以直接按顺序把各框文本拼起来就是整块文本（「トカゲじゃ」+「ない!?」=「トカゲじゃない!?」）。
    let mut blocks_json = Vec::new();
    if group {
        let blocks = group_boxes(&detection.boxes, &GroupParams::default());
        for (bi, blk) in blocks.iter().enumerate() {
            // 读序用列优先（右→左、列内上→下），不是成员下标顺序 —— 后者是「y 分桶 + x 降序」，
            // 会把同列的两段拆开（实测「あの」会被拼到别的列后面）。
            let ordered = blk.order_reading(&detection.boxes);
            let text: String = ordered
                .iter()
                .filter_map(|m| items.get(*m))
                .filter_map(|v| v["text"].as_str())
                .collect();
            blocks_json.push(json!({
                "index": bi,
                "quad": blk.quad.0,
                "members": ordered,
                "boxes": blk.members.len(),
                "text": text,
            }));
        }
        if let Some(path) = &dump_groups {
            dump_group_overlay(&page, &blocks, path)?;
        }
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
                "blocks": blocks_json,
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
        if group {
            println!("--- 块（{} 个）---", blocks_json.len());
            for b in &blocks_json {
                println!(
                    "块{:>3}  框数={:<2} {}",
                    b["index"],
                    b["boxes"],
                    b["text"].as_str().unwrap_or("")
                );
            }
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

/// 把每个块的并集框画成彩色矩形，用于人眼复核聚簇是否与气泡一致。
fn dump_group_overlay(page: &RgbImage, blocks: &[TextBlock], path: &PathBuf) -> Result<()> {
    const PALETTE: [Rgb<u8>; 6] = [
        Rgb([220, 30, 30]),
        Rgb([30, 120, 220]),
        Rgb([20, 160, 60]),
        Rgb([230, 140, 20]),
        Rgb([150, 40, 190]),
        Rgb([0, 170, 170]),
    ];
    let mut canvas = page.clone();
    for (i, blk) in blocks.iter().enumerate() {
        let color = PALETTE[i % PALETTE.len()];
        let (x0, y0, x1, y1) = blk.quad.aabb();
        draw_rect(&mut canvas, x0, y0, x1, y1, color, 3);
    }
    canvas
        .save(path)
        .with_context(|| format!("写分组图失败：{path:?}"))?;
    Ok(())
}

fn draw_rect(
    img: &mut RgbImage,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    color: Rgb<u8>,
    thickness: i32,
) {
    let (w, h) = (img.width() as i32, img.height() as i32);
    let (xs, xe) = ((x0 as i32).clamp(0, w - 1), (x1 as i32).clamp(0, w - 1));
    let (ys, ye) = ((y0 as i32).clamp(0, h - 1), (y1 as i32).clamp(0, h - 1));
    for t in 0..thickness {
        for x in xs..=xe {
            for y in [ys + t, ye - t] {
                if y >= 0 && y < h {
                    img.put_pixel(x as u32, y as u32, color);
                }
            }
        }
        for y in ys..=ye {
            for x in [xs + t, xe - t] {
                if x >= 0 && x < w {
                    img.put_pixel(x as u32, y as u32, color);
                }
            }
        }
    }
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
