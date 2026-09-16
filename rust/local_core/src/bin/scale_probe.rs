//! 降采样探针：量清楚「一页 44.8 MPix 的 AVIF」这笔账里，
//! dav1d 解码 / 全尺寸装箱 / 缩放 / 小图装箱 各占多少。
//!
//! ```text
//! cargo run -p rossi_local_core --bin scale_probe -- <归档路径> [页下标]
//! ```
//!
//! ## 为什么需要它
//!
//! 调试页观测到「解码 1526.8 ms + 上屏 3887.9 ms = 5414.6 ms」（5464×8192）。
//! 但 `decode_rgba` 是一整段黑盒，无法判断「该砍的是解码还是该砍的是像素量」。
//! 这个探针把黑盒拆开，**在动手改之前**先拿到每个环节的单价 ——
//! 否则很容易得出「dav1d 太慢」这种结论，而实际上 dav1d 只是三分之一。
//!
//! ## 口径
//!
//! 每轮都重新 `decode()`（不复用 DynamicImage），因为真实路径每次翻页都是冷解码。
//! 读页只做一次（它的成本与像素量无关，已经在别处量过）。

use std::time::{Duration, Instant};

use anyhow::Result;
use image::imageops::FilterType;
// `decode` 同时是模块名和函数名（`pub mod decode` 里的 `pub fn decode`），
// `lib.rs` 只 re-export 了 `decode_rgba`。这里显式走模块路径，别指望顶层能用。
use rossi_local_core::{LocalSource, decode as decode_mod};

fn ms(started: Instant) -> f64 {
    started.elapsed().as_secs_f64() * 1000.0
}

/// JXL 只有两种载体：裸 codestream（`FF 0A`）与 ISOBMFF 容器
/// （`00 00 00 0C 'JXL \r\n\x87\n'`）。两种都认，别只认一种。
fn sniff_jxl(bytes: &[u8]) -> bool {
    bytes.starts_with(&[0xFF, 0x0A])
        || bytes.starts_with(&[0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A])
}

/// jxl-oxide → DynamicImage。jxl-oxide 进不了 dev-dependencies 的 bin 目标（E0433 实测），
/// 所以挂在 `jxl-probe` feature 下，只开给探针构建。
#[cfg(feature = "jxl-probe")]
fn decode_jxl(bytes: &[u8]) -> Result<image::DynamicImage> {
    use jxl_oxide::integration::JxlDecoder;
    let decoder = JxlDecoder::new(std::io::Cursor::new(bytes))?;
    Ok(image::DynamicImage::from_decoder(decoder)?)
}

/// 降到这么多宽（保持比例）。档位覆盖「预览区宽度 × DPR」的常见落点：
/// 1080p 屏在 1.0–1.5 DPR 下预览区宽 600–1200 px，4K 屏能到 2600 px。
const TARGETS: [u32; 6] = [4096, 2048, 1440, 1024, 768, 600];

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let Some(path) = args.next() else {
        eprintln!("用法: scale_probe <归档路径> [页下标] [--rounds N]");
        std::process::exit(2);
    };
    let mut index = 0usize;
    let mut rounds = 3usize;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--rounds" => {
                rounds = args.next().and_then(|v| v.parse().ok()).unwrap_or(3).max(1);
            }
            other => index = other.parse().unwrap_or(0),
        }
    }

    let source = LocalSource::open(&path)?;
    if index >= source.len() {
        anyhow::bail!("页下标越界: {index} / {}", source.len());
    }

    println!("归档      : {}", source.root().display());
    println!("页数      : {}", source.len());
    println!("目标页    : {index}  {}", source.pages()[index].name);
    println!(
        "解码归属  : {}",
        source
            .page_decode_support(index)
            .map_or("unknown", |s| s.label())
    );

    let started = Instant::now();
    let bytes = source.page_bytes(index)?;
    println!("读页      : {:>8.1} ms  ({} B)", ms(started), bytes.len());

    // 先看一次真尺寸与色彩类型，后面所有档位都以它为基准。
    // JXL 单独分流：`image` 0.25 不支持 jxl，走 jxl-oxide 的 JxlDecoder（同样产 DynamicImage），
    // 下游缩放/装箱代码完全复用 —— 三种格式的差异只在这一步。
    let jxl = sniff_jxl(&bytes);
    if jxl {
        #[cfg(not(feature = "jxl-probe"))]
        anyhow::bail!("该页是 JXL，但本次构建未开 --features jxl-probe，解不了");
        println!("格式分流  : JXL (jxl-oxide)");
    }
    let probe = if jxl { decode_jxl(&bytes)? } else { decode_mod::decode(&bytes)? };
    let (full_w, full_h) = (probe.width(), probe.height());
    println!(
        "原始尺寸  : {full_w}x{full_h} = {:.1} MPix",
        (full_w as f64 * full_h as f64) / 1e6
    );
    println!("色彩类型  : {:?}", probe.color());
    drop(probe);

    println!("\n--- 各档位（rounds={rounds}，取每段最小值）---");
    println!(
        "{:>22}  {:>9}  {:>9}  {:>9}  {:>10}  {:>10}  {:>9}",
        "档位", "解码ms", "装箱ms", "缩放ms", "合计ms", "像素MPix", "位图MB"
    );

    // 全尺寸单独一行：它的「缩放」是恒等的零成本，留着当基线。
    let mut full_decode = f64::MAX;
    let mut full_pack = f64::MAX;
    let mut full_size = (0u32, 0u32);
    let mut full_bytes = 0usize;

    // 每个档位记 (tri 结果, thumb 结果)。按 TARGETS 长度预铺 Option：
    // 页宽小于第一档（4096）时前排档位会被跳过，若用 slot 当 rows 下标会越界
    // （页 19 宽 3858，panic "index out of bounds" 实测）。
    let mut rows: Vec<Option<(u32, f64, f64, f64, (u32, u32), usize, f64, f64)>> =
        vec![None; TARGETS.len()];

    for _ in 0..rounds {
        let started = Instant::now();
        let img = if jxl { decode_jxl(&bytes)? } else { decode_mod::decode(&bytes)? };
        full_decode = full_decode.min(ms(started));

        let started = Instant::now();
        let rgba = img.to_rgba8();
        full_pack = full_pack.min(ms(started));
        full_size = rgba.dimensions();
        full_bytes = rgba.len();
        drop(rgba);

        for (slot, target) in TARGETS.iter().enumerate() {
            if *target >= full_w {
                continue;
            }
            let entry = rows[slot].get_or_insert((
                *target,
                f64::MAX,
                f64::MAX,
                f64::MAX,
                (0, 0),
                0,
                f64::MAX,
                f64::MAX,
            ));

            let started = Instant::now();
            let small = img.resize(*target, u32::MAX, FilterType::Triangle);
            let resize = ms(started);
            let started = Instant::now();
            let packed = small.to_rgba8();
            let pack = ms(started);
            let dims = packed.dimensions();
            let len = packed.len();
            drop(packed);

            entry.1 = entry.1.min(resize);
            entry.2 = entry.2.min(pack);
            entry.4 = dims;
            entry.5 = len;

            let started = Instant::now();
            let thumb = img.thumbnail(*target, u32::MAX);
            let t_resize = ms(started);
            let started = Instant::now();
            let t_packed = thumb.to_rgba8();
            let t_pack = ms(started);
            entry.6 = entry.6.min(t_resize);
            entry.7 = entry.7.min(t_pack);
            drop(t_packed);
            drop(thumb);
            drop(small);
        }
        drop(img);
    }

    println!(
        "{:>22}  {:>9.1}  {:>9.1}  {:>9.1}  {:>10.1}  {:>10.1}  {:>9.1}",
        "全尺寸（基线）",
        full_decode,
        full_pack,
        0.0,
        full_decode + full_pack,
        (full_size.0 as f64 * full_size.1 as f64) / 1e6,
        full_bytes as f64 / 1_048_576.0
    );
    for (target, resize, pack, _, dims, len, t_resize, t_pack) in rows.iter().flatten() {
        println!(
            "{:>22}  {:>9.1}  {:>9.1}  {:>9.1}  {:>10.1}  {:>10.1}  {:>9.1}",
            format!("triangle -> {target}"),
            full_decode,
            pack,
            resize,
            full_decode + pack + resize,
            (dims.0 as f64 * dims.1 as f64) / 1e6,
            *len as f64 / 1_048_576.0
        );
        println!(
            "{:>22}  {:>9.1}  {:>9.1}  {:>9.1}  {:>10.1}",
            format!("  thumbnail -> {target}"),
            full_decode,
            t_pack,
            t_resize,
            full_decode + t_pack + t_resize
        );
    }

    println!(
        "\n读法：\n\
         - 「解码ms」是 dav1d + YUV→RGB，**它不随目标尺寸变小**（AVIF 没有可用的 DCT 缩放档）。\n\
         - 「装箱ms」是 to_rgba8，全尺寸时 ≈ 179 MB 的写；缩到 600 px 后只剩几 MB。\n\
         - 「缩放ms」是从全尺寸 DynamicImage 重采样到目标宽度的代价。\n\
         - 真正的判据是「合计ms」对「位图MB」——上屏那一段的成本跟着位图 MB 走。"
    );

    let _ = Duration::from_millis(0);
    Ok(())
}
