//! 擦字段的**交替**计时：同一进程里同时持有多个不同 `intra_threads` 的会话，逐轮轮换顺序跑。
//!
//! 为什么不用「跑完 1 线程再跑 2 线程」：本机实测那样**同配置两次差 57%**
//! （`mokuro_001a` 整页 d=3：5 831 ms 与 9 151 ms），串行分块把「这段时间谁在吃 CPU」
//! 直接算进了结论里 —— 顺序设计的偏差与待测效应同量级，等于没测。
//! 交替 + 每轮轮换起点之后，负载漂移对每个臂的影响相同，剩下的差才是线程数的差。
//!
//! 臂的名字：`prod` 走 [`Inpainter::from_file`]（**生产默认**），数字走 `from_file_with(n)`。
//! 有 `prod` 这一臂，才能回答「我把默认值改了，改的到底是不是那条码路」——
//! 只看代码里换了参数、不看跑出来的数，是「注入了」当成「画面上换了」的同一种错。
//!
//! 用法：
//! `inpaint_threads --det det.onnx --inpaint lama.onnx --pages a.jpg [b.jpg …]
//!                  [--thread-list prod,1,4] [--rounds 5] [--dilate 3] [--max-side 1024]`

use anyhow::{Context, anyhow};
use rossi_ocr_core::{Detector, Ep, GroupParams, Inpainter, group_boxes, mask_from_blocks};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Instant;

fn build(name: &str, model: &std::path::Path, max_side: u32) -> anyhow::Result<Inpainter> {
    let painter = match name {
        "prod" => Inpainter::from_file(model, Ep::Cpu)?,
        other => {
            let n: usize = other
                .parse()
                .map_err(|e| anyhow!("臂名「{name}」既不是 prod 也不是线程数：{e}"))?;
            Inpainter::from_file_with(model, Ep::Cpu, n)?
        }
    };
    Ok(painter.with_max_side(max_side))
}

fn median(v: &[u128]) -> u128 {
    let mut s = v.to_vec();
    s.sort_unstable();
    s[s.len() / 2]
}

fn main() -> anyhow::Result<()> {
    let mut det_model: Option<PathBuf> = None;
    let mut inpaint_model: Option<PathBuf> = None;
    let mut pages: Vec<PathBuf> = Vec::new();
    let mut arms = vec!["prod".to_string(), "1".to_string(), "4".to_string()];
    let mut rounds = 5u32;
    let mut dilate = 3i32;
    let mut max_side = 1024u32;
    let mut base_arm = "1".to_string();

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut val = || args.next().ok_or_else(|| anyhow!("{arg} 缺值"));
        match arg.as_str() {
            "--det" => det_model = Some(PathBuf::from(val()?)),
            "--inpaint" => inpaint_model = Some(PathBuf::from(val()?)),
            "--thread-list" => {
                arms = val()?
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect::<Vec<_>>();
                arms.retain(|s| !s.is_empty());
            }
            "--base" => base_arm = val()?,
            "--rounds" => rounds = val()?.parse()?,
            "--dilate" => dilate = val()?.parse()?,
            "--max-side" => max_side = val()?.parse()?,
            "--pages" => {}
            other => pages.push(PathBuf::from(other)),
        }
    }
    let det_model = det_model.ok_or_else(|| anyhow!("要 --det"))?;
    let inpaint_model = inpaint_model.ok_or_else(|| anyhow!("要 --inpaint"))?;
    if pages.is_empty() {
        return Err(anyhow!("要至少一张页"));
    }
    if !arms.contains(&base_arm) {
        return Err(anyhow!("--base {base_arm} 不在臂列表 {arms:?} 里"));
    }

    let mut detector = Detector::from_file(&det_model, Ep::Cpu)?;
    let mut pool: BTreeMap<String, Inpainter> = BTreeMap::new();
    for a in &arms {
        pool.insert(a.clone(), build(a, &inpaint_model, max_side)?);
    }
    println!(
        "臂 {arms:?}（基线 {base_arm}）各持一份模型  每页 {rounds} 轮交替  外扩 {dilate}  max_side {max_side}"
    );

    let mut samples: BTreeMap<(String, String), Vec<u128>> = BTreeMap::new();
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
        let detection = detector.detect(&page)?;
        let blocks = group_boxes(&detection.boxes, &GroupParams::default());
        let mask = mask_from_blocks(&blocks, w, h, dilate);
        println!(
            "[{stem}] {w}x{h} 框 {} → 块 {}",
            detection.boxes.len(),
            blocks.len()
        );

        for round in 0..rounds {
            // 轮换起点：否则永远是列表里第一个臂先跑，吃到冷/热的不对称。
            let keys: Vec<String> = pool.keys().cloned().collect();
            let n = keys.len();
            for i in 0..n {
                let a = keys[(i + round as usize) % n].clone();
                let started = Instant::now();
                let out = pool.get_mut(&a).unwrap().inpaint(&page, &mask)?;
                let ms = started.elapsed().as_millis();
                println!(
                    "  轮{round} {a:<5} {:>6} ms（infer {} ms）",
                    ms, out.infer_ms
                );
                samples.entry((stem.clone(), a)).or_default().push(ms);
            }
        }
    }

    println!("\n每臂中位 / 最小 / 极差（同页内比较，跨页不可加）：");
    for ((page, a), v) in &samples {
        let mut s = v.clone();
        s.sort_unstable();
        let med = s[s.len() / 2];
        println!(
            "  {page:<18} {a:<5} 中位 {:>6} ms  最小 {:>6}  极差 {:>6}（{:.0}%）",
            med,
            s[0],
            s[s.len() - 1] - s[0],
            100.0 * (s[s.len() - 1] - s[0]) as f64 / med.max(1) as f64
        );
    }

    let mut ratios: BTreeMap<String, Vec<f64>> = BTreeMap::new();
    let page_names: Vec<String> = pages
        .iter()
        .filter_map(|p| p.file_stem().map(|s| s.to_string_lossy().to_string()))
        .collect();
    for page in page_names {
        let Some(b) = samples
            .get(&(page.clone(), base_arm.clone()))
            .map(|v| median(v))
        else {
            continue;
        };
        for a in &arms {
            if let Some(v) = samples.get(&(page.clone(), a.clone())) {
                ratios
                    .entry(a.clone())
                    .or_default()
                    .push(median(v) as f64 / b as f64);
            }
        }
    }
    println!("\n相对 {base_arm} 的时间比（<1 才是省时间）：");
    for (a, v) in ratios {
        let mut s = v.clone();
        s.sort_by(|x, y| x.partial_cmp(y).unwrap());
        println!(
            "  {a:<5} 中位 {:.2}  最好 {:.2}  最差 {:.2}（{} 页）",
            s[s.len() / 2],
            s[0],
            s[s.len() - 1],
            s.len()
        );
    }
    Ok(())
}
