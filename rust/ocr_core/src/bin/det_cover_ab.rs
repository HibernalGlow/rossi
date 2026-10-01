//! 检测参数对表：把「擦不干净」这一件事**只归给检测**来量。
//!
//! 为什么不能用「框数」当尺子：`mokuro_001a` 那条竖排旁白「でもリーリィ!?」在 960 输入下
//! 只框到中间两个字 —— 换到接近原尺寸之后它变成**一个整行框**，框数几乎没变（28 → 29），
//! 但漏擦的像素少了一大截。框数看不见「框的完整度」，而完整度才是用户看到的那件事。
//!
//! 所以尺子是**环带漏墨**：在「所有配置都认为可能是字的地方」里，亮度低于阈值、
//! 却没被本配置的掩膜盖住的像素数。参照带取**全部配置框的并集再外扩 `--probe`**，
//! 对所有配置都一样 —— 否则框得少的配置会因为「环带也变小」而显得干净（这是反向的奖罚）。
//!
//! 用法：
//! `det_cover_ab --det det.onnx --pages a.jpg b.jpg [--out jsonl]
//!               [--configs "960:0.30:0.0;1280:0.20:0.6"] [--dilate 3] [--probe 12] [--lum-max 140]`

use anyhow::{Context, Result, anyhow};
use image::RgbImage;
use rossi_ocr_core::{
    Detector, DetectorParams, Ep, GroupParams, TextBlock, group_boxes, mask_from_blocks,
};
use serde_json::json;
use std::io::Write;
use std::path::PathBuf;
use std::time::Instant;

/// 一组检测参数：`limit_side : prob_thresh : box_thresh`。
#[derive(Clone, Copy, Debug)]
struct Cfg {
    limit_side: u32,
    prob_thresh: f32,
    box_thresh: f32,
}

impl Cfg {
    fn parse(s: &str) -> Result<Self> {
        let mut it = s.split(':');
        let take = |it: &mut std::str::Split<'_, char>, what: &str| -> Result<f32> {
            it.next()
                .ok_or_else(|| {
                    anyhow!("配置 {s} 缺 {what}（要 limit_side:prob_thresh:box_thresh）")
                })?
                .trim()
                .parse::<f32>()
                .map_err(|e| anyhow!("配置 {s} 的 {what} 解析失败：{e}"))
        };
        Ok(Self {
            limit_side: take(&mut it, "limit_side")? as u32,
            prob_thresh: take(&mut it, "prob_thresh")?,
            box_thresh: take(&mut it, "box_thresh")?,
        })
    }
    fn label(&self) -> String {
        format!(
            "{}/p{}/b{}",
            self.limit_side, self.prob_thresh, self.box_thresh
        )
    }
}

fn main() -> Result<()> {
    let mut det_model: Option<PathBuf> = None;
    let mut out = PathBuf::from("/tmp/ocr-lab/det-cover.jsonl");
    let mut ep = Ep::Cpu;
    let mut pages: Vec<PathBuf> = Vec::new();
    let mut configs = vec![
        "960:0.30:0.0",
        "960:0.30:0.6",
        "1280:0.30:0.0",
        "1280:0.30:0.6",
        "1280:0.20:0.5",
        "1280:0.20:0.6",
        "1280:0.20:0.7",
        "1600:0.20:0.6",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect::<Vec<_>>();
    let mut dilate = 3i32;
    let mut probe = 12i32;
    let mut lum_max = 140u16;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut val = || args.next().ok_or_else(|| anyhow!("{arg} 缺值"));
        match arg.as_str() {
            "--det" => det_model = Some(PathBuf::from(val()?)),
            "--out" => out = PathBuf::from(val()?),
            "--ep" => ep = Ep::parse(&val()?)?,
            "--dilate" => dilate = val()?.parse()?,
            "--probe" => probe = val()?.parse()?,
            "--lum-max" => lum_max = val()?.parse()?,
            "--configs" => configs = val()?.split(';').map(|s| s.trim().to_string()).collect(),
            "--pages" => {}
            other => pages.push(PathBuf::from(other)),
        }
    }
    let det_model = det_model.ok_or_else(|| anyhow!("要 --det"))?;
    if pages.is_empty() {
        return Err(anyhow!("要至少一张页"));
    }
    let cfgs: Vec<Cfg> = configs
        .iter()
        .map(|s| Cfg::parse(s))
        .collect::<Result<_>>()?;
    let configs_json: Vec<String> = cfgs.iter().map(|c| c.label()).collect();
    eprintln!("配置 {configs_json:?}  外扩 {dilate}  环带 {probe}  亮度阈 {lum_max}");

    // 第一遍：每页每配置只跑一次检测（检测是唯一的不确定源），把块留住。
    let mut rows = Vec::new();
    let mut all: Vec<(String, u32, u32, Vec<u16>, Vec<Vec<TextBlock>>)> = Vec::new();
    for page_path in &pages {
        let page = image::open(page_path)
            .with_context(|| format!("读图失败：{page_path:?}"))?
            .to_rgb8();
        let (w, h) = page.dimensions();
        let stem = page_path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let lum = luma(&page);
        let mut per_cfg = Vec::with_capacity(cfgs.len());
        for c in &cfgs {
            let mut detector = Detector::from_file(&det_model, ep)?
                .with_limit_side(c.limit_side)
                .with_params(DetectorParams {
                    prob_thresh: c.prob_thresh,
                    min_area: 64.0,
                    unclip: 1.6,
                    box_thresh: c.box_thresh,
                });
            let started = Instant::now();
            let detection = detector
                .detect(&page)
                .with_context(|| format!("检测失败：{stem} {}", c.label()))?;
            let ms = started.elapsed().as_millis();
            let blocks = group_boxes(&detection.boxes, &GroupParams::default());
            eprintln!(
                "[{stem}] {} 框 {} → 块 {}  检测 {} ms",
                c.label(),
                detection.boxes.len(),
                blocks.len(),
                ms
            );
            per_cfg.push((detection.boxes.len(), blocks, ms));
        }
        for (i, (boxes, _, ms)) in per_cfg.iter().enumerate() {
            rows.push(json!({
                "page": stem.as_str(), "cfg": cfgs[i].label(), "boxes": boxes, "det_ms": ms,
            }));
        }
        all.push((
            stem,
            w,
            h,
            lum,
            per_cfg.into_iter().map(|(_, b, _)| b).collect(),
        ));
    }

    // 参照带：所有配置的块框并集再外扩 probe —— 对每个配置都公平。
    for (stem, w, h, lum, blocks_per_cfg) in &all {
        let band = band_mask(*w, *h, blocks_per_cfg, probe);
        let band_ink: usize = (0..(w * h) as usize)
            .filter(|i| band[*i] > 0 && lum[*i] < lum_max)
            .count();
        for (i, cfg) in cfgs.iter().enumerate() {
            let mask = mask_from_blocks(&blocks_per_cfg[i], *w, *h, dilate);
            let missed = (0..(w * h) as usize)
                .filter(|k| band[*k] > 0 && lum[*k] < lum_max && mask[*k] == 0)
                .count();
            let mask_px = mask.iter().filter(|v| **v > 0).count();
            if let Some(row) = rows
                .iter_mut()
                .find(|r| r["page"] == json!(stem) && r["cfg"] == json!(cfg.label()))
            {
                row["blocks"] = json!(blocks_per_cfg[i].len());
                row["mask_px"] = json!(mask_px);
                row["band_ink"] = json!(band_ink);
                row["missed"] = json!(missed);
                row["dilate"] = json!(dilate);
            }
            eprintln!(
                "  {stem} {} 块 {} 掩膜 {:>7} 参照带墨 {:>6} 漏 {:>6}（{:.1}%）",
                cfg.label(),
                blocks_per_cfg[i].len(),
                mask_px,
                band_ink,
                missed,
                100.0 * missed as f64 / band_ink.max(1) as f64
            );
        }
    }

    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut f = std::fs::File::create(&out)?;
    for r in &rows {
        writeln!(f, "{r}")?;
    }
    eprintln!("\n{} 行 → {}", rows.len(), out.display());
    Ok(())
}

fn luma(page: &RgbImage) -> Vec<u16> {
    page.as_raw()
        .chunks(3)
        .map(|p| ((p[0] as u32 * 299 + p[1] as u32 * 587 + p[2] as u32 * 114) / 1000) as u16)
        .collect()
}

/// 所有配置的块框并集，各边外扩 `probe`。
fn band_mask(w: u32, h: u32, blocks_per_cfg: &[Vec<TextBlock>], probe: i32) -> Vec<u8> {
    let mut band = vec![0u8; (w * h) as usize];
    for blocks in blocks_per_cfg {
        for b in blocks {
            let (x0, y0, x1, y1) = b.quad.aabb();
            let xs = (x0 as i32 - probe).max(0) as u32;
            let ys = (y0 as i32 - probe).max(0) as u32;
            let xe = ((x1 as i32 + probe).min(w as i32 - 1)) as u32;
            let ye = ((y1 as i32 + probe).min(h as i32 - 1)) as u32;
            for y in ys..=ye {
                let row = y as usize * w as usize;
                for x in xs..=xe {
                    band[row + x as usize] = 255;
                }
            }
        }
    }
    band
}
