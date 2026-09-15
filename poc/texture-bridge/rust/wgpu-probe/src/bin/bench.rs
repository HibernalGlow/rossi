//! 离屏拷贝带宽基准的 CLI 壳。
//!
//! 用法：
//!   cargo run --release --bin bench
//!   cargo run --release --bin bench -- --target-gb 8 --out bench.csv
//!   cargo run --release --bin bench -- --mode real --quick
//!
//! 存在的理由：帧率口径被 vsync 封顶（本机 160Hz），一帧只有 2.5MB，
//! 反推出的带宽是假数。这个 bin 把拷贝从帧循环里摘出来批量跑，
//! 用 GPU timestamp 量真实吞吐，用来回答 Phase 1 的决策问题 ——
//! 4K 单次拷贝是 0.08ms 量级（不值得维护 fork）还是 0.6ms 量级（值得）。

use wgpu_probe::bench::{Bench, Mode, Report};

/// 尺寸阶梯。
///
/// 前几档对齐「被 vsync 卡住」的量级，后面一路拉到 8K 双页和 96MP 大图，
/// 用来判断吞吐是随尺寸线性还是有拐点 —— 有拐点就说明瓶颈不在带宽，
/// 而在别处（页表、拷贝引擎调度、驱动路径切换）。
const SIZES: &[(u32, u32, &str)] = &[
    (1264, 487, "当前窗口"),
    (1920, 1080, "1080p"),
    (2048, 2048, "约16MB"),
    (2880, 2880, "约33MB"),
    (3840, 2160, "4K单页"),
    (3840, 4320, "4K双页"),
    (4000, 6000, "单页24MP"),
    (5657, 5657, "约128MB"),
    (7680, 4320, "8K双页"),
    (8000, 12000, "96MP"),
];

/// 快速模式只跑关键几档。
const SIZES_QUICK: &[(u32, u32, &str)] = &[
    (1264, 487, "当前窗口"),
    (3840, 2160, "4K单页"),
    (7680, 4320, "8K双页"),
    (8000, 12000, "96MP"),
];

struct Args {
    modes: Vec<Mode>,
    target_gb: f64,
    quick: bool,
    out: Option<String>,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        modes: Mode::all().to_vec(),
        target_gb: 8.0,
        quick: false,
        out: None,
    };
    let mut argv = std::env::args().skip(1);
    while let Some(a) = argv.next() {
        match a.as_str() {
            "--mode" | "-m" => {
                let v = argv.next().ok_or("--mode 需要参数")?;
                let mut modes = Vec::new();
                for part in v.split(',') {
                    modes.push(
                        Mode::parse(part.trim())
                            .ok_or_else(|| format!("未知模式: {part}（可选 plain/shared/real）"))?,
                    );
                }
                args.modes = modes;
            }
            "--target-gb" | "-t" => {
                let v = argv.next().ok_or("--target-gb 需要参数")?;
                args.target_gb = v.parse().map_err(|_| format!("--target-gb 不是数字: {v}"))?;
            }
            "--quick" | "-q" => args.quick = true,
            "--out" | "-o" => {
                args.out = Some(argv.next().ok_or("--out 需要参数")?);
            }
            "--help" | "-h" => {
                println!("用法: bench [--mode plain,shared,real] [--target-gb 8] [--quick] [--out bench.csv]");
                std::process::exit(0);
            }
            other => return Err(format!("未知参数: {other}")),
        }
    }
    Ok(args)
}

fn mb(bytes: u64) -> f64 {
    bytes as f64 / 1048576.0
}

fn fmt_row(r: &Report) -> String {
    format!(
        "  {:<13} {:>6.2}MP {:>8.1}MB {:>6}  {:>9.3}  {:>9.1}  {:>8.2} {:>8.2}",
        format!("{}x{}", r.width, r.height),
        r.mpix,
        mb(r.bytes),
        r.iterations,
        r.us_per_copy,
        r.gbs_rw,
        r.wall_ms,
        r.gpu_ms,
    )
}

fn main() {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("参数错误: {e}");
            std::process::exit(2);
        }
    };

    let bench = match Bench::new() {
        Ok(b) => b,
        Err(e) => {
            eprintln!("初始化失败: {e}");
            std::process::exit(1);
        }
    };

    println!("=== 适配器 ===");
    println!(
        "{} [{}] luid={:#x}",
        bench.adapter_name, bench.adapter_kind, bench.adapter_luid
    );
    println!();
    println!(
        "目标：每档搬运约 {:.1} GB（读+写各半），尺寸阶梯 {} 档",
        args.target_gb,
        if args.quick { SIZES_QUICK.len() } else { SIZES.len() }
    );
    println!("口径：单次拷贝 = GPU timestamp 独占时长；不掺墙钟、不受刷新率影响");

    let sizes: &[(u32, u32, &str)] = if args.quick { SIZES_QUICK } else { SIZES };

    let mut rows: Vec<Report> = Vec::new();
    let mut bench = bench;

    'outer: for mode in &args.modes {
        println!();
        println!("[{}] {}", mode.as_str(), mode.label());
        println!(
            "  {:<13} {:>8} {:>10} {:>6}  {:>9}  {:>9}  {:>8} {:>8}",
            "尺寸", "像素", "单张", "次数", "单次µs", "读+写GB/s", "墙钟ms", "GPUms"
        );

        for (w, h, tag) in sizes {
            let bytes = *w as u64 * *h as u64 * 4;
            let target = (args.target_gb * 1024.0 * 1024.0 * 1024.0) as u64;
            let iters = bench.iterations_for(bytes, target);
            match bench.run(*mode, *w, *h, iters) {
                Ok(r) => {
                    println!("{}   # {}", fmt_row(&r), tag);
                    rows.push(r);
                }
                Err(e) => {
                    println!(
                        "  {:<13} {:>6.2}MP {:>8.1}MB   -- 失败: {}",
                        format!("{w}x{h}"),
                        (*w as f64 * *h as f64) / 1e6,
                        mb(bytes),
                        e
                    );
                    // 设备一旦 removed 就是终态：继续测只会得到一串同样的
                    // 失败，还会把「失败」误读成「这个尺寸不支持」。
                    if e.contains("DEVICE_REMOVED") {
                        println!();
                        println!("设备已被移除，剩余测量无法进行，提前结束。");
                        break 'outer;
                    }
                }
            }
        }
    }

    // ── 汇总：把最关键的判据直接算出来 ──
    println!();
    println!("=== 判据 ===");
    println!("问题：一次 GPU→GPU 拷贝值多少 GPU 时间？占不占得住帧预算？");
    println!(
        "参照：本机 RTX 4060 Laptop 标称显存带宽 256 GB/s，实测拷贝吞吐约 196 GB/s（约 77%，属正常范围）"
    );
    println!();
    println!(
        "  {:<8} {:<10} {:>10} {:>16} {:>16}",
        "模式", "场景", "单次拷贝", "占60fps预算", "占144fps预算"
    );

    // 只看真正决定方案取舍的几个尺寸：4K 单页 / 4K 双页 / 8K 双页。
    const KEY: &[(u32, u32, &str)] = &[
        (3840, 2160, "4K单页"),
        (3840, 4320, "4K双页"),
        (7680, 4320, "8K双页"),
    ];
    for mode in &args.modes {
        for (w, h, tag) in KEY {
            if let Some(r) = rows
                .iter()
                .find(|r| r.mode == mode.as_str() && r.width == *w && r.height == *h)
            {
                let ms = r.us_per_copy / 1000.0;
                println!(
                    "  {:<8} {:<10} {:>8.3} ms {:>14.1}% {:>15.1}%",
                    mode.as_str(),
                    tag,
                    ms,
                    ms / 16.667 * 100.0,
                    ms / 6.944 * 100.0
                );
            }
        }
    }

    // 给出一个明确的取舍建议 —— 这才是 Phase 1 真正要回答的。
    if let Some(r) = rows
        .iter()
        .find(|r| r.mode == "shared" && r.width == 3840 && r.height == 2160)
    {
        println!();
        let ms = r.us_per_copy / 1000.0;
        let verdict = if ms < 0.15 {
            "不值得为省掉它去维护 wgpu-hal fork：代价低于 1% 帧预算"
        } else if ms < 0.5 {
            "单次成本可观但未致命：先看双页/滚动场景是否叠加到 1ms 以上，再决定"
        } else {
            "值得考虑 fork 或换路径：单次就吃掉 3% 以上帧预算"
        };
        println!("结论（4K 单页，共享堆，真实路径）：{ms:.3} ms → {verdict}");
    }

    // dst barrier 的净成本：shared（含 barrier） - nobar（不含）。
    println!();
    println!("=== dst barrier 净成本（shared - nobar）===");
    for (w, h, _) in sizes {
        let a = rows
            .iter()
            .find(|r| r.mode == "nobar" && r.width == *w && r.height == *h);
        let b = rows
            .iter()
            .find(|r| r.mode == "shared" && r.width == *w && r.height == *h);
        if let (Some(a), Some(b)) = (a, b) {
            println!(
                "  {:<13} 无barrier {:>9.3} µs → 含barrier {:>9.3} µs   净增 {:>9.3} µs ({:+.0}%)",
                format!("{w}x{h}"),
                a.us_per_copy,
                b.us_per_copy,
                b.us_per_copy - a.us_per_copy,
                (b.us_per_copy / a.us_per_copy - 1.0) * 100.0
            );
        }
    }

    // shared 标志本身的代价：shared - plain。
    println!();
    println!("=== shared 标志净成本（shared - plain）===");
    for (w, h, _) in sizes {
        let a = rows
            .iter()
            .find(|r| r.mode == "plain" && r.width == *w && r.height == *h);
        let b = rows
            .iter()
            .find(|r| r.mode == "shared" && r.width == *w && r.height == *h);
        if let (Some(a), Some(b)) = (a, b) {
            println!(
                "  {:<13} 默认堆 {:>9.3} µs → 共享堆 {:>9.3} µs   净增 {:>9.3} µs ({:+.0}%)",
                format!("{w}x{h}"),
                a.us_per_copy,
                b.us_per_copy,
                b.us_per_copy - a.us_per_copy,
                (b.us_per_copy / a.us_per_copy - 1.0) * 100.0
            );
        }
    }

    if let Some(path) = &args.out {
        let mut csv = String::from(
            "mode,width,height,megapixels,bytes,iterations,us_per_copy,gbs_rw,wall_ms,gpu_ms\n",
        );
        for r in &rows {
            csv.push_str(&format!(
                "{},{},{},{:.4},{},{},{:.4},{:.3},{:.4},{:.4}\n",
                r.mode,
                r.width,
                r.height,
                r.mpix,
                r.bytes,
                r.iterations,
                r.us_per_copy,
                r.gbs_rw,
                r.wall_ms,
                r.gpu_ms
            ));
        }
        match std::fs::write(path, csv) {
            Ok(()) => println!("\nCSV 已写入 {path}（{} 行）", rows.len()),
            Err(e) => eprintln!("\n写 CSV 失败: {e}"),
        }
    }
}
