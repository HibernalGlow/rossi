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

/// libjxl（jpegxl-rs 封装）→ DynamicImage。**GPL-3.0-or-later**：只许进探针，不许进 App。
/// ThreadsRunner = 全核并行池，与 jxl-oxide 的 rayon 池口径一致。
#[cfg(feature = "jxl-probe-libjxl")]
fn decode_jxl_libjxl(bytes: &[u8], threaded: bool) -> Result<image::DynamicImage> {
    use jpegxl_rs::decoder_builder;
    use jpegxl_rs::image::ToDynamic;
    // 不挂 parallel_runner = libjxl 默认顺序执行（单线程）。
    // 与 jxl-rs 的官方 image 集成同口径（它把 parallel_runner 硬编码成 None）——
    // 没有这一档，「jxl-rs 慢 4×」分不清是实现的锅还是线程的锅。
    // builder 是 typestate（parallel_runner 换类型），只能两支各自 build。
    let frame = if threaded {
        let runner = jpegxl_rs::ThreadsRunner::default();
        let mut decoder = decoder_builder().parallel_runner(&runner).build()?;
        decoder.decode_to_image(bytes)?
    } else {
        let mut decoder = decoder_builder().build()?;
        decoder.decode_to_image(bytes)?
    };
    frame.ok_or_else(|| anyhow::anyhow!("libjxl decode_to_image 返回 None（无可用帧？）"))
}

/// **jxl-rs**（libjxl 官方组织的纯 Rust 解码器，Chrome 145 / Firefox 采用中，BSD-3）。
/// 集成走 image 的 hook 机制：进程级注册一次，`load_from_memory` 对 JXL 魔数自动接管。
/// 注册是全局的，但只命中 JXL 魔数，非 JXL 页走 decode_mod 的路径不受影响。
/// **注意：官方集成把 parallel_runner 硬编码成 None（单线程）** —— 这就是 `jxlrs` 档的口径。
#[cfg(feature = "jxl-probe")]
fn decode_jxl_jxlrs(bytes: &[u8]) -> Result<image::DynamicImage> {
    use std::sync::Once;
    static REGISTER: Once = Once::new();
    // 返回值是「是否真的注册上了」（false = 槽位被占，多半是注册了两次）。
    // 探针里 Once 保证只调一次，返回 false 属异常，直接断言失败别静默继续。
    REGISTER.call_once(|| {
        assert!(
            jxl_image_rs_integration::register_image_decoding_hook(),
            "jxl-rs 的 image hook 注册失败"
        );
    });
    Ok(image::load_from_memory(bytes)?)
}

/// jxl-rs **多线程**直连路径：绕开官方 image 集成（它把 parallel_runner 硬编码成 None），
/// 用 `jxl::api` 直接驱动 + rayon runner，量 jxl-rs 多线程的真实水平 ——
/// 这才是和 Chrome 内嵌口径（带线程池）对齐的数字。
/// 只支持 8-bit 输出（探针样本全是 Rgba8）；Float/16-bit 页显式报错，不静默降级。
#[cfg(feature = "jxl-probe")]
fn decode_jxl_jxlrs_threaded(bytes: &[u8]) -> Result<image::DynamicImage> {
    use jxl::api::{
        JxlColorType, JxlDataFormat, JxlDecoder as ApiJxlDecoder, JxlDecoderOptions,
        JxlOutputBuffer, JxlParallelRunner, JxlParallelRunnerFun, JxlPixelFormat,
        ProcessingResult, states,
    };
    use std::sync::Mutex;

    /// rayon 背书的 runner：~10 行，trait 只要求 run + num_threads。
    struct RayonRunner;
    impl JxlParallelRunner for RayonRunner {
        fn run(&mut self, num: usize, fun: &JxlParallelRunnerFun<'_>) -> jxl::error::Result<()> {
            use rayon::prelude::*;
            let err = Mutex::new(None);
            (0..num).into_par_iter().for_each(|i| {
                if let Err(e) = fun(i) {
                    *err.lock().unwrap() = Some(e);
                }
            });
            match err.into_inner().unwrap() {
                Some(e) => Err(e),
                None => Ok(()),
            }
        }
        fn num_threads(&self) -> usize {
            rayon::current_num_threads()
        }
    }

    let mut input: &[u8] = bytes; // &[u8] 自带 JxlBitstreamInput 实现
    let mut runner = RayonRunner;

    let decoder = ApiJxlDecoder::<states::Initialized>::new(JxlDecoderOptions::default());
    let mut decoder = match decoder.process(&mut input, Some(&mut runner))? {
        ProcessingResult::Complete { result } => result,
        ProcessingResult::NeedsMoreInput { .. } => {
            anyhow::bail!("输入被截断（不该发生：探针是全量内存输入）")
        }
    };

    let info = decoder.basic_info().clone();
    let width = u32::try_from(info.size.0)?;
    let height = u32::try_from(info.size.1)?;
    let has_alpha = info
        .extra_channels
        .iter()
        .any(|c| c.ec_type == jxl::headers::extra_channels::ExtraChannel::Alpha);
    let grayscale = decoder.current_pixel_format().color_type.is_grayscale();

    let (color_type, jxl_ct) = match (&info.bit_depth, grayscale, has_alpha) {
        (jxl::api::JxlBitDepth::Int { bits_per_sample }, g, a) if *bits_per_sample <= 8 => {
            match (g, a) {
                (true, false) => (image::ColorType::L8, JxlColorType::Grayscale),
                (true, true) => (image::ColorType::La8, JxlColorType::GrayscaleAlpha),
                (false, false) => (image::ColorType::Rgb8, JxlColorType::Rgb),
                (false, true) => (image::ColorType::Rgba8, JxlColorType::Rgba),
            }
        }
        _ => anyhow::bail!("非 8-bit 整型 JXL 页，多线程直连路径不支持"),
    };
    decoder.set_pixel_format(JxlPixelFormat {
        color_type: jxl_ct,
        color_data_format: Some(JxlDataFormat::U8 { bit_depth: 8 }),
        extra_channel_format: vec![None; info.extra_channels.len()],
    })?;

    let bpp = color_type.bytes_per_pixel() as usize;
    let bytes_per_row = width as usize * bpp;
    let mut buf = vec![0u8; bytes_per_row * height as usize];
    {
        let mut output = JxlOutputBuffer::new(&mut buf, height as usize, bytes_per_row);
        let outputs = std::slice::from_mut(&mut output);
        let mut frame_decoder = match decoder.process(&mut input, Some(&mut runner))? {
            ProcessingResult::Complete { result } => result,
            ProcessingResult::NeedsMoreInput { .. } => anyhow::bail!("输入被截断"),
        };
        // WithFrameInfo::process 才吃 buffers；NeedsMoreInput 的 fallback 是同状态，可重试。
        loop {
            match frame_decoder.process(&mut input, outputs, Some(&mut runner))? {
                ProcessingResult::Complete { .. } => break,
                ProcessingResult::NeedsMoreInput { fallback, .. } => {
                    if input.is_empty() {
                        anyhow::bail!("输入被截断（帧解码中途耗尽）");
                    }
                    frame_decoder = fallback;
                }
            }
        }
    }
    let dyn_img = match color_type {
        image::ColorType::L8 => {
            image::GrayImage::from_raw(width, height, buf).map(image::DynamicImage::ImageLuma8)
        }
        image::ColorType::La8 => image::GrayAlphaImage::from_raw(width, height, buf)
            .map(image::DynamicImage::ImageLumaA8),
        image::ColorType::Rgb8 => {
            image::RgbImage::from_raw(width, height, buf).map(image::DynamicImage::ImageRgb8)
        }
        image::ColorType::Rgba8 => {
            image::RgbaImage::from_raw(width, height, buf).map(image::DynamicImage::ImageRgba8)
        }
        _ => unreachable!("上面只构造了这四种"),
    };
    dyn_img.ok_or_else(|| anyhow::anyhow!("像素缓冲尺寸不匹配 {width}x{height}"))
}

/// JXL 后端分发：`--jxl-backend libjxl|libjxl1t|jxlrs|jxlrs-mt|oxide`。
/// 各路产同样的 DynamicImage，下游全复用。
fn decode_jxl_dispatch(bytes: &[u8], backend: &str) -> Result<image::DynamicImage> {
    match backend {
        #[cfg(feature = "jxl-probe-libjxl")]
        "libjxl" => decode_jxl_libjxl(bytes, true),
        #[cfg(feature = "jxl-probe-libjxl")]
        "libjxl1t" => decode_jxl_libjxl(bytes, false),
        #[cfg(feature = "jxl-probe")]
        "jxlrs" => decode_jxl_jxlrs(bytes),
        #[cfg(feature = "jxl-probe")]
        "jxlrs-mt" => decode_jxl_jxlrs_threaded(bytes),
        #[cfg(feature = "jxl-probe")]
        _ => decode_jxl(bytes),
        #[cfg(not(any(feature = "jxl-probe", feature = "jxl-probe-libjxl")))]
        _ => anyhow::bail!("未开任何 jxl-probe feature，解不了 JXL"),
    }
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
    let mut jxl_backend = "libjxl".to_string();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--rounds" => {
                rounds = args.next().and_then(|v| v.parse().ok()).unwrap_or(3).max(1);
            }
            "--jxl-backend" => {
                jxl_backend = args.next().unwrap_or_else(|| "libjxl".to_string());
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
        println!("格式分流  : JXL (backend={jxl_backend})");
    }
    let probe = if jxl {
        decode_jxl_dispatch(&bytes, &jxl_backend)?
    } else {
        decode_mod::decode(&bytes)?
    };
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
        let img = if jxl {
            decode_jxl_dispatch(&bytes, &jxl_backend)?
        } else {
            decode_mod::decode(&bytes)?
        };
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
