//! 擦字段的 A/B 台架：**裁剪推理**（省时间）与**掩膜外扩**（治「擦不干净」）一起量。
//!
//! 为什么两个参数必须一起跑：它们动的是同一次推理 —— 外扩让掩膜面积变大（更慢、残留更少），
//! 裁剪让推理面积变小（更快、但可能改变填充）。只调一个就下结论，另一个的代价会被藏住。
//!
//! 只跑检测（识别与擦字无关）：每个页面上把 `--dilates × --modes` 全跑一遍，**同一批块、
//! 同一个会话**，所以页内可比。产物：每 (模式, 外扩) 一张整页结果 + `runs.jsonl`。
//!
//! 用法：
//! `inpaint_ab --det det.onnx --inpaint lama.onnx --pages a.jpg b.jpg [--out DIR]
//!             [--dilates 0,3,6,8] [--modes full,bbox,cluster] [--gap 40] [--crop-pad 32]`
//!
//! 「擦不干净」拆成两个可分别归因的量：
//! - `missed_ring_ink`：块框外扩 `probe` 的环带里、亮度低于阈值却**没被掩膜盖住**的像素。
//!   纯粹的覆盖问题 —— 外扩调的就是它，与模型无关，所以 d=0 必然显著高于 d=3（阳性对照）。
//! - `residue_in_mask`：掩膜**内部**擦完之后仍然发暗的像素。这是填充质量/降采样损失，
//!   与外扩无关，却会被「加大外扩」掩盖成变好（因为分母里的墨被挪出掩膜了），所以要单独报。
//! 阈值不拍脑袋：`--thresholds` 默认三档同算。裁剪有没有改变填充，看 `diff_in_mask`
//! （与同页同档的整页结果在掩膜内的平均/最大逐通道差）。

use anyhow::{Context, Result, anyhow};
use image::RgbImage;
use rossi_ocr_core::{
    CropPolicy, Detector, Ep, GroupParams, Inpainted, Inpainter, TextBlock, group_boxes,
    mask_from_blocks,
};
use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

fn main() -> Result<()> {
    let mut det_model: Option<PathBuf> = None;
    let mut inpaint_model: Option<PathBuf> = None;
    let mut out_dir = PathBuf::from("/tmp/ocr-lab/inpaint-ab");
    let mut ep = Ep::Cpu;
    let mut dilates = vec![0i32, 3, 6, 8];
    let mut modes = vec![
        "full".to_string(),
        "bbox".to_string(),
        "cluster".to_string(),
    ];
    let mut gap = 40i32;
    let mut crop_pad = 32i32;
    let mut max_side = 1024u32;
    let mut thresholds = vec![100u16, 140, 180];
    let mut probe = 12i32;
    let mut repeat = 2u32;
    let mut threads = 1usize;
    let mut pages: Vec<PathBuf> = Vec::new();

    let mut args = std::env::args().skip(1).peekable();
    macro_rules! val {
        ($name:expr) => {
            args.next()
                .ok_or_else(|| anyhow!("{} 缺值", $name))?
                .to_string()
        };
    }
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--det" => det_model = Some(PathBuf::from(val!("--det"))),
            "--inpaint" => inpaint_model = Some(PathBuf::from(val!("--inpaint"))),
            "--out" => out_dir = PathBuf::from(val!("--out")),
            "--ep" => ep = Ep::parse(&val!("--ep"))?,
            "--dilates" => {
                dilates = parse_list(&val!("--dilates"))?;
            }
            "--modes" => {
                modes = val!("--modes")
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect()
            }
            "--thresholds" => {
                thresholds = parse_list(&val!("--thresholds"))?;
            }
            "--gap" => gap = val!("--gap").parse()?,
            "--crop-pad" => crop_pad = val!("--crop-pad").parse()?,
            "--max-side" => max_side = val!("--max-side").parse()?,
            "--probe" => probe = val!("--probe").parse()?,
            "--repeat" => repeat = val!("--repeat").parse()?,
            "--threads" => threads = val!("--threads").parse()?,
            "--pages" => {}
            other => pages.push(PathBuf::from(other)),
        }
    }

    let det_model = det_model.ok_or_else(|| anyhow!("要 --det"))?;
    let inpaint_model = inpaint_model.ok_or_else(|| anyhow!("要 --inpaint"))?;
    if pages.is_empty() {
        return Err(anyhow!("要至少一个页图"));
    }
    std::fs::create_dir_all(&out_dir)?;

    let mut detector = Detector::from_file(&det_model, ep)?;
    let mut inpainter = Inpainter::from_file_with(&inpaint_model, ep, threads)?
        .with_max_side(max_side)
        .with_crop_pad(crop_pad);
    let ep_used = inpainter.ep().label().to_string();
    eprintln!(
        "擦字 EP={ep_used}  max_side={max_side}  crop_pad={crop_pad}  gap={gap}\n\
         档位：外扩 {dilates:?} × 模式 {modes:?}，阈值 {thresholds:?}，环带 probe={probe}"
    );

    let mut rows: Vec<Value> = Vec::new();
    let mut page_ms = 0u128;
    for page_path in &pages {
        let started = Instant::now();
        let page = image::open(page_path)
            .with_context(|| format!("读图失败：{page_path:?}"))?
            .to_rgb8();
        let (w, h) = page.dimensions();
        let stem = page_path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let detection = detector
            .detect(&page)
            .with_context(|| format!("检测失败：{stem}"))?;
        let blocks = group_boxes(&detection.boxes, &GroupParams::default());
        eprintln!("[{stem}] {w}x{h} 框 {}", blocks.len());

        let lum = luma(&page);
        for d in &dilates {
            let mask = mask_from_blocks(&blocks, w, h, *d);
            let cov = coverage(&mask, &lum, w, h, &blocks, &thresholds, *d, probe);
            for mode in &modes {
                let crop = match mode.as_str() {
                    "full" => CropPolicy::None,
                    "bbox" => CropPolicy::MaskBbox,
                    "cluster" => CropPolicy::Clusters { gap },
                    other => return Err(anyhow!("未知模式 {other}（full/bbox/cluster）")),
                };
                inpainter.set_crop(crop);
                // 每档跑两遍取**较小值**，第一遍单独记 `first_ms`：
                // 动态尺寸的会话第一次见到某个 shape 要重新装配内核，实测那一次是稳态的 4 倍
                // （27.6 s vs 6.7 s）。只报单次，裁剪与外扩谁快谁慢会被冷启动淹没。
                let mut first_ms = 0u128;
                let mut min_ms = u128::MAX;
                let mut erased: Option<Inpainted> = None;
                for r in 0..repeat.max(1) {
                    let run = Instant::now();
                    let out = inpainter
                        .inpaint(&page, &mask)
                        .with_context(|| format!("擦字失败：{stem} d={d} {mode}"))?;
                    let ms = run.elapsed().as_millis();
                    if r == 0 {
                        first_ms = ms;
                    }
                    // 记的是**最快那一次**的整套数：如果只换 wall 不换 erased，
                    // 分段 ms 会来自另一次运行，出现 infer > wall 这种不可能的数。
                    if ms <= min_ms {
                        min_ms = ms;
                        erased = Some(out);
                    }
                }
                let erased = erased.ok_or_else(|| anyhow!("repeat 没跑出结果"))?;
                let wall_ms = min_ms;
                let out = out_dir.join(format!("{stem}_d{d}_{mode}.png"));
                erased.image.save(&out)?;
                if *mode == *"full" {
                    annotate(&lum, &mask, w, h, &thresholds)
                        .save(out_dir.join(format!("{stem}_d{d}_map.png")))?;
                }
                let res = residue(&erased.image, &mask, w, h, &thresholds);
                let res_s = format!("{res:?}");
                let missed_s = cov["missed"].to_string();
                rows.push(json!({
                    "page": stem,
                    "dilate": d,
                    "mode": mode,
                    "ep": ep_used,
                    "threads": threads,
                    "runs": erased.runs,
                    "run_sizes": erased.run_sizes.iter().map(|(a, b)| [a, b]).collect::<Vec<_>>(),
                    "run_area_px": erased.run_sizes.iter().map(|(a, b)| a * b).sum::<u32>(),
                    "preprocess_ms": erased.preprocess_ms,
                    "infer_ms": erased.infer_ms,
                    "composite_ms": erased.composite_ms,
                    "first_ms": first_ms,
                    "wall_ms": wall_ms,
                    "mask_px": cov["mask_px"],
                    "missed_ring_ink": cov["missed"],
                    "ring_ink_total": cov["ring_total"],
                    "newly_dark": cov["newly_dark"],
                    "newly_bright": cov["newly_bright"],
                    "residue_in_mask": res,
                    "png": out.to_string_lossy(),
                }));
                eprintln!(
                    "  d={d:<2} {mode:<8} {} 次 稳态 {:>5}ms（冷 {:>5}ms）infer {:>5}ms 面积 {:>8} 环带漏墨 {} 掩膜内残 {}",
                    erased.runs,
                    wall_ms,
                    first_ms,
                    erased.infer_ms,
                    erased.run_sizes.iter().map(|(a, b)| a * b).sum::<u32>(),
                    missed_s,
                    res_s,
                );
            }
            // 同一页同一档：bbox/cluster 的结果与整页逐像素比，量「裁剪改变了填充没有」。
            for mode in modes.iter().filter(|m| *m != "full") {
                let other = out_dir.join(format!("{stem}_d{d}_{mode}.png"));
                let diff = diff_in_mask(
                    &out_dir.join(format!("{stem}_d{d}_full.png")),
                    &other,
                    &mask,
                )?;
                if let Some(row) = rows.iter_mut().find(|r| {
                    r["page"] == json!(stem)
                        && r["dilate"] == json!(d)
                        && r["mode"] == json!(mode.as_str())
                }) {
                    row["diff_in_mask"] = diff["mean"].clone();
                    row["diff_in_mask_max"] = diff["max"].clone();
                }
            }
        }
        let ms = started.elapsed().as_millis();
        page_ms += ms;
        eprintln!("[{stem}] 本页 {} ms", ms);
    }

    let jsonl = out_dir.join("runs.jsonl");
    let mut f = std::fs::File::create(&jsonl)?;
    for r in &rows {
        writeln!(f, "{r}")?;
    }
    eprintln!(
        "\n共 {} 行 → {}（总 {} s）",
        rows.len(),
        jsonl.display(),
        page_ms / 1000
    );
    Ok(())
}

fn parse_list<T: std::str::FromStr>(s: &str) -> Result<Vec<T>>
where
    T::Err: std::fmt::Display,
{
    s.split(',')
        .map(|p| {
            p.trim()
                .parse::<T>()
                .map_err(|e| anyhow!("解析 {p} 失败：{e}"))
        })
        .collect()
}

/// 亮度图（0..=255），一次算好供各判据复用。
fn luma(page: &RgbImage) -> Vec<u16> {
    page.as_raw()
        .chunks(3)
        .map(|p| ((p[0] as u32 * 299 + p[1] as u32 * 587 + p[2] as u32 * 114) / 1000) as u16)
        .collect()
}

/// 覆盖类判据（与模型无关，只看掩膜）。
///
/// 环带 = 块框各边外扩 `probe`。`missed[t]` = 环带内亮度 < t 却不在掩膜里的像素数；
/// `ring_total[t]` = 环带内亮度 < t 的总数（分母）；
/// `newly_*` = 相对 d=0 新增覆盖（即框外、环带内、被掩膜盖住）中暗（<140）/亮（≥220）的个数。
fn coverage(
    mask: &[u8],
    lum: &[u16],
    w: u32,
    h: u32,
    blocks: &[TextBlock],
    thresholds: &[u16],
    d: i32,
    probe: i32,
) -> Value {
    let mut missed = vec![0u64; thresholds.len()];
    let mut ring_total = vec![0u64; thresholds.len()];
    let mut newly_dark = 0u64;
    let mut newly_bright = 0u64;
    let mut mask_px = 0u64;
    let mut seen = vec![false; (w * h) as usize];

    for b in blocks {
        let (bx0, by0, bx1, by1) = b.quad.aabb();
        let x0 = (bx0 as i32 - probe).max(0) as u32;
        let y0 = (by0 as i32 - probe).max(0) as u32;
        let x1 = ((bx1 as i32 + probe).min(w as i32 - 1)) as u32;
        let y1 = ((by1 as i32 + probe).min(h as i32 - 1)) as u32;
        for y in y0..=y1 {
            for x in x0..=x1 {
                let i = (y * w + x) as usize;
                if seen[i] {
                    continue;
                }
                seen[i] = true;
                let v = lum[i];
                let covered = mask[i] > 0;
                if covered {
                    mask_px += 1;
                }
                for (ti, t) in thresholds.iter().enumerate() {
                    if v < *t {
                        ring_total[ti] += 1;
                        if !covered {
                            missed[ti] += 1;
                        }
                    }
                }
                if d > 0 && covered {
                    let in_box = x as i32 >= bx0 as i32
                        && x as i32 <= bx1 as i32
                        && y as i32 >= by0 as i32
                        && y as i32 <= by1 as i32;
                    if !in_box {
                        if v < 140 {
                            newly_dark += 1;
                        } else if v >= 220 {
                            newly_bright += 1;
                        }
                    }
                }
            }
        }
    }
    json!({
        "mask_px": mask_px,
        "missed": missed,
        "ring_total": ring_total,
        "newly_dark": newly_dark,
        "newly_bright": newly_bright,
    })
}

/// 掩膜内擦完之后仍发暗的像素数（填充质量，与外扩无关）。
fn residue(img: &RgbImage, mask: &[u8], w: u32, h: u32, thresholds: &[u16]) -> Vec<u64> {
    let lum = luma(img);
    let mut out = vec![0u64; thresholds.len()];
    for i in 0..(w * h) as usize {
        if mask[i] == 0 {
            continue;
        }
        for (ti, t) in thresholds.iter().enumerate() {
            if lum[i] < *t {
                out[ti] += 1;
            }
        }
    }
    out
}

/// 覆盖标注图：**红 = 掩膜要擦的像素**，**蓝 = 页面上还发暗却不在掩膜里的像素**。
///
/// 为什么必须有这张图：`missed_ring_ink` 只统计块框附近，而用户说的「还没擦干净」
/// 很可能是**检测根本没框到的字**（拟声词、散字）—— 那种残留加大外扩治不了，
/// 只有看图能把它和「框到了但外扩不够」分开。判据先数，结论再看眼。
fn annotate(lum: &[u16], mask: &[u8], w: u32, h: u32, thresholds: &[u16]) -> RgbImage {
    let t = thresholds.last().copied().unwrap_or(180);
    let mut out = RgbImage::from_pixel(w, h, image::Rgb([255, 255, 255]));
    for i in 0..(w * h) as usize {
        let (x, y) = (i as u32 % w, i as u32 / w);
        if mask[i] > 0 {
            out.put_pixel(x, y, image::Rgb([255, 170, 170]));
        } else if lum[i] < t {
            out.put_pixel(x, y, image::Rgb([40, 60, 255]));
        }
    }
    out
}

fn diff_in_mask(a: &Path, b: &Path, mask: &[u8]) -> Result<Value> {
    let ia = image::open(a)?.to_rgb8();
    let ib = image::open(b)?.to_rgb8();
    if ia.dimensions() != ib.dimensions() {
        return Err(anyhow!("比对的两张图尺寸不同：{a:?} vs {b:?}"));
    }
    let (w, h) = ia.dimensions();
    let mut sum = 0u64;
    let mut n = 0u64;
    let mut max = 0u32;
    let ra = ia.as_raw();
    let rb = ib.as_raw();
    for i in 0..(w * h) as usize {
        if mask[i] == 0 {
            continue;
        }
        for c in 0..3 {
            let dd = ra[i * 3 + c].abs_diff(rb[i * 3 + c]) as u32;
            sum += dd as u64;
            max = max.max(dd);
        }
        n += 3;
    }
    if n == 0 {
        return Ok(json!({"mean": null, "max": null}));
    }
    Ok(json!({"mean": sum as f64 / n as f64, "max": max}))
}
