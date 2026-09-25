//! 检测件的手工验收工具：对给定页跑一遍检测，打印框数与耗时。
//!
//! 它是 ADR-0018 §决定 3.3 那份实测的**可复跑版本** —— 期望值与 Python 参考实现对齐
//! （8 张真实页：Aisazu 39 / 000a 4 / 000b 18 / 001a 30 / 001b 25 / 002a 18 / 002b 21 /
//! mangaocr 93；框数相同的口径为 `prob_thresh = 0.30`、`min_area = 64`、`unclip = 1.6`）。
//!
//! 用法：`detect_image <model.onnx> <image> [--ep cpu|coreml] [--json]`

use anyhow::{Context, Result, anyhow};
use rossi_ocr_core::{Detector, Ep, TextBox};
use serde_json::json;
use std::path::PathBuf;
use std::time::Instant;

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mut positional: Vec<String> = Vec::new();
    let mut ep = Ep::Cpu;
    let mut print_json = false;
    let mut limit_side = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--ep" => {
                let value = args.next().ok_or_else(|| anyhow!("--ep 后面要跟值"))?;
                ep = Ep::parse(&value)?;
            }
            "--limit-side" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("--limit-side 后面要跟值"))?;
                limit_side = Some(value.parse::<u32>()?);
            }
            "--json" => print_json = true,
            other => positional.push(other.to_string()),
        }
    }
    let [model, image] = match positional.as_slice() {
        [m, i] => [PathBuf::from(m), PathBuf::from(i)],
        _ => {
            return Err(anyhow!(
                "用法：detect_image <model.onnx> <image> [--ep cpu|coreml] [--json]"
            ));
        }
    };

    let img = image::open(&image)
        .with_context(|| format!("读图失败：{}", image.display()))?
        .to_rgb8();
    let (w, h) = img.dimensions();

    let load_start = Instant::now();
    let mut detector = Detector::from_file(&model, ep)?;
    if let Some(limit) = limit_side {
        detector = detector.with_limit_side(limit);
    }
    let load_ms = load_start.elapsed().as_millis();

    let run = detector.detect(&img)?;
    let total_ms = load_ms + run.preprocess_ms + run.infer_ms + run.postprocess_ms;

    if print_json {
        let boxes: Vec<_> = run
            .boxes
            .iter()
            .map(|b: &TextBox| json!({ "quad": b.quad.0, "score": b.score }))
            .collect();
        println!(
            "{}",
            json!({
                "image": image.display().to_string(),
                "size": [w, h],
                "ep": detector.ep().label(),
                "input_size": [run.input_size.0, run.input_size.1],
                "count": run.boxes.len(),
                "ms": { "load": load_ms, "pre": run.preprocess_ms, "infer": run.infer_ms, "post": run.postprocess_ms, "total": total_ms },
                "boxes": boxes,
            })
        );
    } else {
        println!(
            "{:<28} {:>5}x{:<5} ep={:<7} 推理输入={}x{} 框数={:<4} 载入={}ms 前处理={}ms 推理={}ms 后处理={}ms",
            image
                .file_name()
                .map(|v| v.to_string_lossy().to_string())
                .unwrap_or_default(),
            w,
            h,
            detector.ep().label(),
            run.input_size.0,
            run.input_size.1,
            run.boxes.len(),
            load_ms,
            run.preprocess_ms,
            run.infer_ms,
            run.postprocess_ms
        );
    }
    Ok(())
}
