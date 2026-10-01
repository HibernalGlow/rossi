//! 识别段的线程/并发实测：**交替**跑，同进程、轮换顺序。
//!
//! 为什么要单独量识别：擦字段那条「1 线程是策略不是实测」的教训在这里重演了一遍 ——
//! 识别一页 28 框串行，实测占整页一半以上（`mokuro_001a` 编码 1 898 ms + 解码 702 ms）。
//! 但**不能照抄擦字的结论**：识别是 28 次小推理，单次越短，线程唤醒与
//! ORT 会话内并行度的固定开销占比越大；而并发多会话又要多份权重常驻（encoder 343 MB）。
//! 所以两条轴分开量，并且把 RSS 一起报出来 —— 只报时间会诱导人去做一件内存翻倍的事。
//!
//! 用法：
//! `rec_bench --det d.onnx --encoder e.onnx --decoder d.onnx --vocab v.txt --page p.jpg
//!            [--threads 1,2,4] [--fanout 1,2,4] [--rounds 5]`

use anyhow::{Result, anyhow};
use image::RgbImage;
use rossi_ocr_core::{Detector, Ep, Recognizer};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

/// 文本集合的 FNV-1a 指纹：线程数改了浮点归约顺序的话，这里就会不一样。
fn text_hash(texts: &[String]) -> String {
    let joined = texts.join("\u{1}");
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in joined.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100_0000_01b3);
    }
    format!("{h:016x}")
}

fn rss_mib() -> u64 {
    let pid = std::process::id();
    let out = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &pid.to_string()])
        .output();
    match out {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().parse::<u64>().unwrap_or(0) / 1024,
        Err(_) => 0,
    }
}

fn main() -> Result<()> {
    let mut det = None;
    let mut encoder = None;
    let mut decoder = None;
    let mut vocab = None;
    let mut page_arg = None;
    let mut ep = Ep::Cpu;
    let mut threads = vec![1usize, 2, 4];
    let mut fanout = vec![1usize, 2, 4];
    let mut rounds = 5u32;

    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = || args.next().ok_or_else(|| anyhow!("{a} 缺值"));
        match a.as_str() {
            "--det" => det = Some(PathBuf::from(val()?)),
            "--encoder" => encoder = Some(PathBuf::from(val()?)),
            "--decoder" => decoder = Some(PathBuf::from(val()?)),
            "--vocab" => vocab = Some(PathBuf::from(val()?)),
            "--page" => page_arg = Some(PathBuf::from(val()?)),
            "--ep" => ep = Ep::parse(&val()?)?,
            "--threads" => threads = parse_list(&val()?)?,
            "--fanout" => fanout = parse_list(&val()?)?,
            "--rounds" => rounds = val()?.parse()?,
            other => return Err(anyhow!("未知参数 {other}")),
        }
    }
    let (det, encoder, decoder, vocab, page_arg) = (
        det.ok_or_else(|| anyhow!("要 --det"))?,
        encoder.ok_or_else(|| anyhow!("要 --encoder"))?,
        decoder.ok_or_else(|| anyhow!("要 --decoder"))?,
        vocab.ok_or_else(|| anyhow!("要 --vocab"))?,
        page_arg.ok_or_else(|| anyhow!("要 --page"))?,
    );

    let page = image::open(&page_arg)?.to_rgb8();
    let (w, h) = page.dimensions();
    let mut detector = Detector::from_file(&det, ep)?;
    let detection = detector.detect(&page)?;
    // 裁剪先做完：这一段测的是推理，不是 imageops。
    let crops: Vec<RgbImage> = detection
        .boxes
        .iter()
        .map(|b| {
            let (x0, y0, x1, y1) = b.quad.aabb();
            let xs = (x0 as i32 - 6).clamp(0, w as i32) as u32;
            let ys = (y0 as i32 - 6).clamp(0, h as i32) as u32;
            let xe = (x1 as i32 + 6).clamp(0, w as i32) as u32;
            let ye = (y1 as i32 + 6).clamp(0, h as i32) as u32;
            image::imageops::crop_imm(&page, xs, ys, xe - xs, ye - ys).to_image()
        })
        .collect();
    println!(
        "{}x{}，{} 个框，裁剪合计 {} 像素；轮数 {rounds}",
        w,
        h,
        crops.len(),
        crops.iter().map(|c| c.width() * c.height()).sum::<u32>()
    );

    // ---- 轴 A：单会话、不同 intra_threads ----
    let mut results: Vec<(String, u128, u64)> = Vec::new();
    for round in 0..rounds {
        let keys: Vec<usize> = threads.clone();
        let n = keys.len();
        for i in 0..n {
            let t = keys[(i + round as usize) % n];
            let mut rec = Recognizer::from_files_with_threads(&encoder, &decoder, &vocab, ep, t)?;
            let started = Instant::now();
            let mut texts = Vec::with_capacity(crops.len());
            for c in &crops {
                texts.push(rec.recognize(c)?.text);
            }
            let ok = texts.iter().filter(|t| !t.is_empty()).count();
            let ms = started.elapsed().as_millis();
            if round == 0 {
                let chars: usize = texts.iter().map(|t| t.chars().count()).sum();
                println!(
                    "  threads={t} 一轮 {ms} ms（{ok}/{} 框有字，{chars} 字）RSS {} MiB  文本指纹 {}",
                    crops.len(),
                    rss_mib(),
                    text_hash(&texts)
                );
            }
            results.push((format!("threads={t}"), ms, rss_mib()));
        }
    }

    // ---- 轴 B：多会话并发（每份都 1 线程），看要不要付内存的代价 ----
    for round in 0..rounds {
        let keys: Vec<usize> = fanout.clone();
        let n = keys.len();
        for i in 0..n {
            let f = keys[(i + round as usize) % n];
            // ⚠️ 会话必须在**计时之外**建好：把 `from_files` 放线程里等于把 460 MB 权重的
            // 加载时间算进识别耗时，测出来会让并发看起来慢十倍，结论直接反掉。
            let mut pool = Vec::with_capacity(f);
            for _ in 0..f {
                pool.push(Recognizer::from_files_with_threads(
                    &encoder, &decoder, &vocab, ep, 1,
                )?);
            }
            let started = Instant::now();
            let all = Arc::new(crops.clone());
            let mut handles = Vec::new();
            for (k, mut rec) in pool.into_iter().enumerate() {
                let all = Arc::clone(&all);
                handles.push(std::thread::spawn(move || -> Result<usize> {
                    let mut n_ok = 0;
                    // 交错分片：让每个会话拿到的行长度尽量均衡，不然一个会话拖后腿。
                    for (j, c) in all.iter().enumerate() {
                        if j % f != k {
                            continue;
                        }
                        if !rec.recognize(c)?.text.is_empty() {
                            n_ok += 1;
                        }
                    }
                    Ok(n_ok)
                }));
            }
            let mut total = 0;
            for hd in handles {
                total += hd.join().map_err(|_| anyhow!("识别线程 panic"))??;
            }
            let ms = started.elapsed().as_millis();
            if round == 0 {
                println!(
                    "  fanout={f} 一轮 {ms} ms（{total}/{} 框有字）RSS {} MiB",
                    crops.len(),
                    rss_mib()
                );
            }
            results.push((format!("fanout={f}"), ms, rss_mib()));
        }
    }

    println!("\n中位数（同机交替，跨配置可比）：");
    let mut seen: Vec<String> = Vec::new();
    for (label, _, _) in &results {
        if !seen.contains(label) {
            seen.push(label.clone());
        }
    }
    for label in seen {
        let mut v: Vec<u128> = results.iter().filter(|r| r.0 == *label).map(|r| r.1).collect();
        v.sort_unstable();
        let rss = results.iter().filter(|r| r.0 == *label).map(|r| r.2).max().unwrap_or(0);
        println!(
            "  {label:<12} 中位 {:>6} ms   最快 {:>6} ms   峰值 RSS {} MiB",
            v[v.len() / 2],
            v[0],
            rss
        );
    }
    Ok(())
}

fn parse_list<T: std::str::FromStr>(s: &str) -> Result<Vec<T>>
where
    T::Err: std::fmt::Display,
{
    s.split(',')
        .map(|p| p.trim().parse::<T>().map_err(|e| anyhow!("解析 {p} 失败：{e}")))
        .collect()
}
