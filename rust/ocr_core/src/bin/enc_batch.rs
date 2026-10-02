//! **encoder 攒批**的收益与等价性实测（ADR-0019 的前置量测）。
//!
//! 为什么先量这个而不是 KV cache：`rec_bench` 把一页的成本拆开看过之后，
//! encoder 占 **66–69%**、decoder 只占 30–33%（三页真页，见 ADR-0019 §实测）。
//! 所以「给 decoder 加 past_key_values」最多动那三成，而且那份导出**没有** cache 输入、
//! 必须重导出；而 encoder 的 batch 维是**动态的**（`pixel_values [-1,-1,-1,-1]`，
//! 符号维 `batch_size`），攒批是纯代码改动，不用碰模型。
//!
//! 两件事必须一起量，因为攒批有一个众所周知的暗坑：
//! 1. **省多少**：batch=1 逐框 vs batch=N 一次前向，各档的 ms/框；
//! 2. **是不是同一批数**：batched 的 `last_hidden_state` 与单框的是否逐位相同。
//!    不相同就不只是「快一点」的问题 —— 下游文本会变，成品页缓存必须加一维，
//!    否则「同参数不同译文」会静默发生（本 ADR 一路在防的就是这个）。
//!    浮点上 batch 改变归约顺序是有可能的，所以这条**不能靠推理排除，只能测**。
//!
//! 用法：
//! `enc_batch --det d.onnx --encoder e.onnx --page p.jpg [--batches 1,4,8,16,32]
//!            [--rounds 3] [--threads 4]`

use anyhow::{Context, Result, anyhow};
use image::{RgbImage, imageops::FilterType};
use ort::session::Session;
use ort::value::TensorRef;
use rossi_ocr_core::session::{Ep as Ep2, Stage, build_session};
use rossi_ocr_core::{Detector, Ep, GroupParams, group_boxes};
use std::path::PathBuf;
use std::time::Instant;

const IMAGE_SIZE: u32 = 224;
const PLANE: usize = (IMAGE_SIZE * IMAGE_SIZE) as usize;

/// 与 `recognize.rs::preprocess` 逐字一致（224×224 压扁、`(v/255 - 0.5)/0.5`、NCHW）。
///
/// 复制而不是调用，是因为这一段是**私有**的，而台架要量的就是它那份预处理在攒批下的形状。
/// 两处一旦分叉，这里量的就不是生产的那条路 —— 所以断言里把常数也钉住。
fn preprocess(crop: &RgbImage) -> Vec<f32> {
    let resized = image::imageops::resize(crop, IMAGE_SIZE, IMAGE_SIZE, FilterType::Triangle);
    let mut out = vec![0.0f32; 3 * PLANE];
    for (x, y, px) in resized.enumerate_pixels() {
        let idx = (y * IMAGE_SIZE + x) as usize;
        for c in 0..3 {
            out[c * PLANE + idx] = (px.0[c] as f32 / 255.0 - 0.5) / 0.5;
        }
    }
    out
}

fn run_encoder(session: &mut Session, batch: &[Vec<f32>]) -> Result<(u128, Vec<f32>, Vec<i64>)> {
    let n = batch.len();
    let mut flat = Vec::with_capacity(n * 3 * PLANE);
    for b in batch {
        flat.extend_from_slice(b);
    }
    let tensor = TensorRef::from_array_view((
        [n, 3, IMAGE_SIZE as usize, IMAGE_SIZE as usize],
        flat.as_slice(),
    ))
    .context("构造 encoder 输入")?;
    let started = Instant::now();
    let encoded = session
        .run(ort::inputs![tensor])
        .map_err(|e| anyhow!("encoder 推理失败：{e:?}"))?;
    let (shape, raw) = encoded[0]
        .try_extract_tensor::<f32>()
        .context("读取 encoder 输出")?;
    let ms = started.elapsed().as_millis();
    Ok((ms, raw.to_vec(), shape.to_vec()))
}

fn main() -> Result<()> {
    let mut det_model: Option<PathBuf> = None;
    let mut enc_model: Option<PathBuf> = None;
    let mut page_arg: Option<PathBuf> = None;
    let mut batches: Vec<usize> = vec![1, 4, 8, 16, 32];
    let mut rounds = 3usize;
    let mut threads = 4usize;
    let mut args = std::env::args().skip(1);
    let mut positional: Vec<String> = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--det" => det_model = Some(PathBuf::from(take_value(&mut args, "--det")?)),
            "--encoder" => enc_model = Some(PathBuf::from(take_value(&mut args, "--encoder")?)),
            "--page" => page_arg = Some(PathBuf::from(take_value(&mut args, "--page")?)),
            "--batches" => {
                let s = take_value(&mut args, "--batches")?;
                batches = s.split(',').filter_map(|x| x.trim().parse().ok()).collect();
            }
            "--rounds" => rounds = take_value(&mut args, "--rounds")?.parse()?,
            "--threads" => threads = take_value(&mut args, "--threads")?.parse()?,
            other => positional.push(other.to_string()),
        }
    }
    let det_model = det_model.ok_or_else(|| anyhow!("要 --det"))?;
    let enc_model = enc_model.ok_or_else(|| anyhow!("要 --encoder"))?;
    let page_path = match (&page_arg, positional.first()) {
        (Some(p), _) => p.clone(),
        (None, Some(p)) => PathBuf::from(p),
        _ => return Err(anyhow!("要 --page")),
    };

    let page = image::open(&page_path)
        .with_context(|| format!("读图失败：{page_path:?}"))?
        .to_rgb8();
    let mut detector = Detector::from_file(&det_model, Ep::Cpu)?;
    let detection = detector.detect(&page)?;
    let blocks = group_boxes(&detection.boxes, &GroupParams::default());
    let _ = blocks;
    let crops: Vec<RgbImage> = detection
        .boxes
        .iter()
        .map(|b| {
            let (x0, y0, x1, y1) = b.quad.aabb();
            let (w, h) = (page.width() as i32, page.height() as i32);
            let xs = (x0 as i32 - 6).clamp(0, w) as u32;
            let ys = (y0 as i32 - 6).clamp(0, h) as u32;
            let xe = (x1 as i32 + 6).clamp(0, w) as u32;
            let ye = (y1 as i32 + 6).clamp(0, h) as u32;
            image::imageops::crop_imm(&page, xs, ys, xe - xs, ye - ys).to_image()
        })
        .collect();
    println!(
        "{}：{} 个框，每框预处理成 {}×{} 后攒批",
        page_path.file_name().unwrap_or_default().to_string_lossy(),
        crops.len(),
        IMAGE_SIZE,
        IMAGE_SIZE
    );
    let inputs: Vec<Vec<f32>> = crops.iter().map(preprocess).collect();

    // 与生产**同一套**会话配置（Level3 优化 + 同一个 EP 解析），否则台架量的不是那条码路。
    let mut session = build_session(&enc_model, Ep2::Cpu, Stage::Recognize, threads)?;

    // ---- 等价性：每个样本**各自单跑**当参照，再比它在批里的输出 ----
    //
    // 第一版这里犯了个蠢错：拿样本 0 的单跑输出去比批里**每一个**样本，
    // 于是「最大绝对差 1.25e1」——那不过是「两张不同的图不一样」，
    // 看着像攒批改了数值，其实什么都没测。判据必须逐样本配自己的参照。
    let mut singles: Vec<Vec<f32>> = Vec::with_capacity(inputs.len());
    for i in 0..inputs.len() {
        let (_, out, _) = run_encoder(&mut session, &inputs[i..i + 1])?;
        singles.push(out);
    }
    let per = singles[0].len();
    println!("参照：逐框单跑，每框输出 {per} 个 f32");
    for &b in &batches {
        if b == 1 {
            continue;
        }
        let take = inputs.len().min(b);
        let (_, out, dims) = run_encoder(&mut session, &inputs[..take])?;
        let mut max_diff = 0.0f32;
        let mut worst = 0usize;
        for i in 0..take {
            let seg = &out[i * per..(i + 1) * per];
            for (x, y) in seg.iter().zip(singles[i].iter()) {
                let d = (x - y).abs();
                if d > max_diff {
                    max_diff = d;
                    worst = i;
                }
            }
        }
        println!(
            "  batch={b:<3} 前 {take} 个样本 输出维 {dims:?}  与各自单跑最大绝对差 {max_diff:.2e}（出现在第 {worst} 框）{}",
            if max_diff == 0.0 {
                "  ← 逐位相同"
            } else {
                "  ← 不相同"
            }
        );
    }

    // ---- 收益：交替轮次，取每档最小 ----
    let mut best: std::collections::BTreeMap<usize, u128> = Default::default();
    for round in 0..rounds {
        let keys: Vec<usize> = {
            let mut v = batches.clone();
            let r = round % v.len();
            v.rotate_left(r);
            v
        };
        for &b in &keys {
            let started = Instant::now();
            let mut done = 0usize;
            while done < inputs.len() {
                let take = inputs.len().min(done + b);
                let chunk: Vec<Vec<f32>> = inputs[done..take].to_vec();
                run_encoder(&mut session, &chunk)?;
                done = take;
            }
            let ms = started.elapsed().as_millis();
            *best.entry(b).or_insert(u128::MAX) = (*best.entry(b).or_insert(u128::MAX)).min(ms);
            if round == 0 {
                println!(
                    "  轮0 batch={b:<3} 整页 encoder {ms:>5} ms（{:.1} ms/框）",
                    ms as f64 / inputs.len() as f64
                );
            }
        }
    }
    let base = *best.get(&1).unwrap_or(&0);
    println!("\n每档最小（同页交替 {rounds} 轮）：");
    for b in &batches {
        let ms = best[b];
        println!(
            "  batch={b:<3} {ms:>5} ms  {:.1} ms/框  相对 batch=1 {:.2} 倍",
            ms as f64 / inputs.len() as f64,
            if base > 0 {
                ms as f64 / base as f64
            } else {
                0.0
            }
        );
    }
    Ok(())
}

fn take_value(args: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    args.next().ok_or_else(|| anyhow!("{flag} 后面要跟值"))
}
