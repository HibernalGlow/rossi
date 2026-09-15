//! 归档直读探针：不经过 Flutter / GPU，单纯验证「本地来源 → 有序页 → 解码」这条链路。
//!
//! ```text
//! cargo run -p rossi_local_core --bin local_probe -- <路径> [--repeat N]
//! ```
//!
//! 它同时是 v0.1_acceptance §4.3 那条「未测项」的量具：
//! **非固实归档下 `skip()` 的实际开销**——首/中/末三页的读取耗时差，就是顺序推进
//! 到第 N 条目的地要跨过多少字节的直接证据。

use std::collections::BTreeSet;
use std::path::PathBuf;
use std::time::Instant;

use anyhow::Result;
use rossi_local_core::{LocalSource, SourceKind, rar_source};

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let Some(target) = args.next() else {
        eprintln!("用法: local_probe <散图文件夹 | .cbz | .cbr | .zip | .rar> [--repeat N]");
        std::process::exit(2);
    };
    let mut repeat = 1usize;
    while let Some(flag) = args.next() {
        match flag.as_str() {
            "--repeat" => {
                repeat = args
                    .next()
                    .and_then(|value| value.parse().ok())
                    .unwrap_or(1)
                    .max(1);
            }
            other => {
                eprintln!("未知参数: {other}");
                std::process::exit(2);
            }
        }
    }

    let path = PathBuf::from(&target);

    if rar_source::is_rar_path(&path) {
        match rar_source::inspect(&path) {
            Ok(inspection) => {
                println!("--- RAR 判定 ---");
                println!("decision        : {}", inspection.decision.label());
                println!("volume_kind     : {:?}", inspection.volume_kind);
                println!("resolved_path   : {}", inspection.resolved_path.display());
                println!("image_count     : {}", inspection.image_count);
                println!(
                    "uncompressed    : {:.2} MB",
                    inspection.total_uncompressed_bytes as f64 / 1_048_576.0
                );
                println!("nested_archives : {}", inspection.nested_archive_count);
            }
            Err(error) => println!("--- RAR 判定失败 ---\n{error:#}"),
        }
    }

    let source = LocalSource::open(&path)?;
    println!("--- 来源 ---");
    println!("path            : {}", source.root().display());
    println!("kind            : {}", source.kind().label());
    println!("pages           : {}", source.len());
    println!(
        "encoded bytes   : {:.2} MB",
        source.total_bytes() as f64 / 1_048_576.0
    );

    if source.is_empty() {
        println!("\n（没有可读页面）");
        return Ok(());
    }

    println!("\n--- 页序（前 5 / 后 3）---");
    let listed: BTreeSet<usize> = (0..source.len().min(5))
        .chain(source.len().saturating_sub(3)..source.len())
        .collect();
    for index in listed {
        let page = &source.pages()[index];
        println!(
            "  {index:>5}  {:>10} B  {}",
            page.size,
            shorten(&page.name, 72)
        );
    }

    println!("\n--- 读取 + 解码（repeat={repeat}）---");
    println!("{:>6}  {:>10}  {:>10}  {:>12}  name", "index", "read ms", "decode ms", "size");
    let probes = probe_indices(source.len());
    for index in probes {
        let mut read_total = 0f64;
        let mut decode_total = 0f64;
        let mut dimensions = (0u32, 0u32);
        for _ in 0..repeat {
            let started = Instant::now();
            let bytes = source.page_bytes(index)?;
            read_total += started.elapsed().as_secs_f64() * 1000.0;

            let started = Instant::now();
            let pixels = rossi_local_core::decode_rgba(&bytes)?;
            decode_total += started.elapsed().as_secs_f64() * 1000.0;
            dimensions = (pixels.width, pixels.height);
        }
        println!(
            "{index:>6}  {:>10.3}  {:>10.3}  {:>5}x{:<6}  {}",
            read_total / repeat as f64,
            decode_total / repeat as f64,
            dimensions.0,
            dimensions.1,
            shorten(&source.pages()[index].name, 48)
        );
    }

    // 「不落盘」这条约束是可以被证伪的：读完之后临时目录里不该多出任何东西。
    if source.kind() == SourceKind::Rar {
        println!("\n提示：RAR 直读不产生任何临时文件；若上方 read ms 随 index 线性增长，");
        println!("      说明该归档实际是固实压缩（判定应当已把它拦下）。");
    }

    Ok(())
}

/// 首、1/4、中、3/4、末：既能看出常量开销，也能看出随条目数增长的那部分。
fn probe_indices(len: usize) -> Vec<usize> {
    let mut indices = vec![0, len / 4, len / 2, len * 3 / 4, len.saturating_sub(1)];
    indices.sort_unstable();
    indices.dedup();
    indices
}

fn shorten(text: &str, limit: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= limit {
        return text.to_string();
    }
    let head: String = chars[..limit.saturating_sub(1)].iter().collect();
    format!("{head}…")
}
