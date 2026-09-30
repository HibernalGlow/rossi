//! 检测件的手工验收工具：对给定页跑一遍检测，打印框数与耗时。
//!
//! 它是 ADR-0018 §决定 3.3 那份实测的**可复跑版本**（口径 `prob_thresh = 0.30`、
//! `min_area = 64`、`unclip = 1.6`）。
//!
//! ⚠️ 下面这串是 **Python 参考实现**的框数，不是本工具的期望值：
//! Aisazu 39 / 000a 4 / 000b 18 / 001a 30 / 001b 25 / 002a 18 / 002b 21 / mangaocr 93。
//! Rust 这边 8 张里有 4 张对不上（33 / 28 / 18 / 84），逐张对照与原因分析见
//! `docs/REFERENCE_RESEARCH.md` §8.6.5 —— 别把这里当断言用。
//!
//! 用法：`detect_image <model.onnx> <image> [--ep auto|cpu|coreml|directml] [--json]
//!                     [--limit-side N] [--prob-thresh 0.3] [--min-area 64] [--unclip 1.6]
//!                     [--cover x,y;x,y;...]`
//!
//! `--cover` 是给「漏检」用的尺子：给一批**人眼确认是字**的坐标，打印有多少落进了某个框。
//! 必须同时给一组「现在就框得到」的点当阳性对照 —— 否则参数调松之后分数上涨，
//! 可能只是框变大了，而不是真的找回了漏掉的字。

use anyhow::{Context, Result, anyhow};
use rossi_ocr_core::{Detector, DetectorParams, Ep, TextBox};
use serde_json::json;
use std::path::PathBuf;
use std::time::Instant;

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mut positional: Vec<String> = Vec::new();
    let mut ep = Ep::Cpu;
    let mut print_json = false;
    let mut limit_side = None;
    let mut prob_thresh: Option<f32> = None;
    let mut min_area: Option<f32> = None;
    let mut unclip: Option<f32> = None;
    let mut box_thresh: Option<f32> = None;
    let mut points: Vec<(f32, f32)> = Vec::new();
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
            "--prob-thresh" => {
                prob_thresh = Some(
                    args.next()
                        .ok_or_else(|| anyhow!("--prob-thresh 后面要跟值"))?
                        .parse::<f32>()?,
                );
            }
            "--min-area" => {
                min_area = Some(
                    args.next()
                        .ok_or_else(|| anyhow!("--min-area 后面要跟值"))?
                        .parse::<f32>()?,
                );
            }
            "--unclip" => {
                unclip = Some(
                    args.next()
                        .ok_or_else(|| anyhow!("--unclip 后面要跟值"))?
                        .parse::<f32>()?,
                );
            }
            "--box-thresh" => {
                box_thresh = Some(
                    args.next()
                        .ok_or_else(|| anyhow!("--box-thresh 后面要跟值"))?
                        .parse::<f32>()?,
                );
            }
            "--cover" => {
                let v = args.next().ok_or_else(|| anyhow!("--cover 后面要跟值"))?;
                for pair in v.split(';') {
                    let mut it = pair.split(',');
                    points.push((
                        it.next()
                            .ok_or_else(|| anyhow!("--cover 要 x,y;x,y"))?
                            .parse::<f32>()?,
                        it.next()
                            .ok_or_else(|| anyhow!("--cover 要 x,y;x,y"))?
                            .parse::<f32>()?,
                    ));
                }
            }
            other => positional.push(other.to_string()),
        }
    }
    let [model, image] = match positional.as_slice() {
        [m, i] => [PathBuf::from(m), PathBuf::from(i)],
        _ => {
            return Err(anyhow!(
                "用法：detect_image <model.onnx> <image> [--ep auto|cpu|coreml|directml] [--json]"
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
    if prob_thresh.is_some() || min_area.is_some() || unclip.is_some() || box_thresh.is_some() {
        let mut p = DetectorParams::default();
        if let Some(v) = prob_thresh {
            p.prob_thresh = v;
        }
        if let Some(v) = min_area {
            p.min_area = v;
        }
        if let Some(v) = unclip {
            p.unclip = v;
        }
        if let Some(v) = box_thresh {
            p.box_thresh = v;
        }
        detector = detector.with_params(p);
    }
    let load_ms = load_start.elapsed().as_millis();

    let run = detector.detect(&img)?;
    if !points.is_empty() {
        let hit: Vec<bool> = points
            .iter()
            .map(|(x, y)| {
                run.boxes.iter().any(|b| {
                    let (x0, y0, x1, y1) = b.quad.aabb();
                    *x >= x0 && *x <= x1 && *y >= y0 && *y <= y1
                })
            })
            .collect();
        let n: usize = hit.iter().filter(|v| **v).count();
        println!(
            "cover {n}/{} 逐点 {}",
            points.len(),
            hit.iter()
                .map(|v| if *v { "1" } else { "0" })
                .collect::<Vec<_>>()
                .join("")
        );
    }
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
