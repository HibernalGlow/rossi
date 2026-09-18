//! JXL 后端选择层：把「用哪个 crate 解 JXL」做成**编译期 feature**。
//!
//! 三个后端 feature（可叠加，叠加时按固定优先级分发）：
//!
//! | feature | crate | 许可 | 线程 | 实测（§12.8，44.8 MPix） |
//! |---|---|---|---|---|
//! | `jxl-rs-mt`（默认） | `jxl` 0.7（libjxl 官方纯 Rust 重写） | BSD-3 | rayon 全核 | **91 ms**，全场最快 |
//! | `jxl-rs-1t` | `jxl-image-rs-integration` 0.7（官方 image hook） | BSD-3 | 单线程（hook 硬编码） | 563 ms |
//! | `jxl-oxide` | `jxl-oxide` 0.12 | Apache/MIT | 单线程 | 937 ms |
//!
//! 为什么 `jxl-rs-mt` 不走官方 image 集成：`jxl-image-rs-integration` 把
//! `parallel_runner` 硬编码成 `None`（单线程），多线程必须用 `jxl::api` 直连 +
//! 自带 runner（~15 行，见 [`decode_jxl_rs_threaded`]）。
//!
//! 探针（`bin/scale_probe.rs`）复用本模块的三个后端函数，只有 GPL 的 libjxl
//! 对照留在探针里 —— GPL 依赖不许进本模块（本 crate 是 MIT）。

use anyhow::{Result, bail};
use image::DynamicImage;

/// JXL 只有两种载体：裸 codestream（`FF 0A`）与 ISOBMFF 容器
/// （`00 00 00 0C 'JXL \r\n\x87\n'`）。两种都认，别只认一种。
pub fn sniff_jxl(bytes: &[u8]) -> bool {
    bytes.starts_with(&[0xFF, 0x0A])
        || bytes.starts_with(&[
            0x00, 0x00, 0x00, 0x0C, b'J', b'X', b'L', b' ', 0x0D, 0x0A, 0x87, 0x0A,
        ])
}

/// 当前构建实际生效的后端（多个 feature 叠加时与 [`decode_dispatch`] 同优先级）。
pub const ACTIVE_BACKEND: &str = if cfg!(feature = "jxl-rs-mt") {
    "jxl-rs-mt"
} else if cfg!(feature = "jxl-rs-1t") {
    "jxl-rs-1t"
} else if cfg!(feature = "jxl-oxide") {
    "jxl-oxide"
} else {
    "none"
};

// ---------------------------------------------------------------------------
// 后端一：jxl-rs 多线程直连（默认）
// ---------------------------------------------------------------------------

/// **jxl-rs 多线程直连**：`jxl::api` 直接驱动 + rayon runner。
/// 这是与 Chrome 内嵌口径对齐（带线程池）的路径，也是三后端里唯一快过 dav1d 的。
/// 只支持 8-bit 整型输出（漫画页全是）；Float / 16-bit 显式报错，不静默降级。
#[cfg(feature = "jxl-rs-mt")]
pub fn decode_jxl_rs_threaded(bytes: &[u8]) -> Result<DynamicImage> {
    use jxl::api::{
        JxlColorType, JxlDataFormat, JxlDecoder as ApiJxlDecoder, JxlDecoderOptions,
        JxlOutputBuffer, JxlParallelRunner, JxlParallelRunnerFun, JxlPixelFormat, ProcessingResult,
        states,
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
            bail!("JXL 输入被截断（头部未读完）")
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
        _ => bail!("非 8-bit 整型 JXL 页，jxl-rs-mt 路径不支持"),
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
        // 不带 output buffers 再 process 一次：拿「帧信息已就绪」的帧解码器。
        // NeedsMoreInput 的 fallback 是同状态，可重试。
        let mut frame_decoder = match decoder.process(&mut input, Some(&mut runner))? {
            ProcessingResult::Complete { result } => result,
            ProcessingResult::NeedsMoreInput { .. } => bail!("JXL 输入被截断（帧头未读完）"),
        };
        loop {
            match frame_decoder.process(&mut input, outputs, Some(&mut runner))? {
                ProcessingResult::Complete { .. } => break,
                ProcessingResult::NeedsMoreInput { fallback, .. } => {
                    if input.is_empty() {
                        bail!("JXL 输入被截断（帧解码中途耗尽）");
                    }
                    frame_decoder = fallback;
                }
            }
        }
    }
    let dyn_img = match color_type {
        image::ColorType::L8 => {
            image::GrayImage::from_raw(width, height, buf).map(DynamicImage::ImageLuma8)
        }
        image::ColorType::La8 => {
            image::GrayAlphaImage::from_raw(width, height, buf).map(DynamicImage::ImageLumaA8)
        }
        image::ColorType::Rgb8 => {
            image::RgbImage::from_raw(width, height, buf).map(DynamicImage::ImageRgb8)
        }
        image::ColorType::Rgba8 => {
            image::RgbaImage::from_raw(width, height, buf).map(DynamicImage::ImageRgba8)
        }
        _ => unreachable!("上面只构造了这四种"),
    };
    dyn_img.ok_or_else(|| anyhow::anyhow!("像素缓冲尺寸不匹配 {width}x{height}"))
}

/// 只读 JXL 头（尺寸），不解像素 —— 比 `probe_size` 走全解码便宜几个数量级。
/// （每个后端一个独立名字：feature 可叠加，同名的 cfg 函数会 E0428。）
#[cfg(feature = "jxl-rs-mt")]
pub fn probe_size_rs_mt(bytes: &[u8]) -> Result<(u32, u32)> {
    use jxl::api::{JxlDecoder as ApiJxlDecoder, JxlDecoderOptions, ProcessingResult, states};

    let mut input: &[u8] = bytes;
    let mut runner = RayonProbeRunner;
    let decoder = ApiJxlDecoder::<states::Initialized>::new(JxlDecoderOptions::default());
    let decoder = match decoder.process(&mut input, Some(&mut runner))? {
        ProcessingResult::Complete { result } => result,
        ProcessingResult::NeedsMoreInput { .. } => bail!("JXL 输入被截断（头部未读完）"),
    };
    let info = decoder.basic_info();
    let width = u32::try_from(info.size.0)?;
    let height = u32::try_from(info.size.1)?;
    Ok((width, height))
}

/// 探尺寸用的最小 runner（头部解析基本不派任务，但 trait 得有）。
/// 独立于 [`decode_jxl_rs_threaded`] 里的那个：那个在 fn 作用域内，这里拿不到。
#[cfg(feature = "jxl-rs-mt")]
struct RayonProbeRunner;
#[cfg(feature = "jxl-rs-mt")]
impl jxl::api::JxlParallelRunner for RayonProbeRunner {
    fn run(
        &mut self,
        num: usize,
        fun: &jxl::api::JxlParallelRunnerFun<'_>,
    ) -> jxl::error::Result<()> {
        for i in 0..num {
            fun(i)?;
        }
        Ok(())
    }
    fn num_threads(&self) -> usize {
        1
    }
}

// ---------------------------------------------------------------------------
// 后端二：jxl-rs 官方 image hook（单线程）
// ---------------------------------------------------------------------------

/// **jxl-rs 官方 image 集成**：`register_image_decoding_hook()` 进程级注册一次，
/// `load_from_memory` 对 JXL 魔数自动接管。**hook 把 parallel_runner 硬编码成
/// None（单线程）** —— 这是它的口径，快不过 dav1d，留给对照与回退。
#[cfg(feature = "jxl-rs-1t")]
pub fn decode_jxl_rs_hooked(bytes: &[u8]) -> Result<DynamicImage> {
    use std::sync::Once;
    static REGISTER: Once = Once::new();
    // 返回值是「是否真的注册上了」（false = 槽位被占，多半是注册了两次）。
    // Once 保证只调一次，返回 false 属异常，直接断言失败别静默继续。
    REGISTER.call_once(|| {
        assert!(
            jxl_image_rs_integration::register_image_decoding_hook(),
            "jxl-rs 的 image hook 注册失败"
        );
    });
    Ok(image::load_from_memory(bytes)?)
}

/// 官方 hook 没有便宜的「只读头」入口，探尺寸只能整页解出来再量。
#[cfg(feature = "jxl-rs-1t")]
pub fn probe_size_1t(bytes: &[u8]) -> Result<(u32, u32)> {
    let img = decode_jxl_rs_hooked(bytes)?;
    Ok((img.width(), img.height()))
}

// ---------------------------------------------------------------------------
// 后端三：jxl-oxide（纯 Rust，最慢，留作对照）
// ---------------------------------------------------------------------------

/// **jxl-oxide**：纯 Rust、单线程、比 jxl-rs 慢约 10×（§12.7/12.8）。
/// 留在 feature 里只为切换对照，不该被选成 App 默认。
#[cfg(feature = "jxl-oxide")]
pub fn decode_jxl_oxide(bytes: &[u8]) -> Result<DynamicImage> {
    use jxl_oxide::integration::JxlDecoder;
    let decoder = JxlDecoder::new(std::io::Cursor::new(bytes))?;
    Ok(DynamicImage::from_decoder(decoder)?)
}

/// jxl-oxide 的 `JxlImage::builder().read()` 只读头不渲像素，探尺寸是便宜的。
#[cfg(feature = "jxl-oxide")]
pub fn probe_size_oxide(bytes: &[u8]) -> Result<(u32, u32)> {
    let image = jxl_oxide::JxlImage::builder()
        .read(std::io::Cursor::new(bytes))
        .map_err(|e| anyhow::anyhow!("jxl-oxide 探尺寸失败: {e}"))?;
    Ok((image.width(), image.height()))
}

// ---------------------------------------------------------------------------
// 分发
// ---------------------------------------------------------------------------

/// 按编译期 feature 分发到当前生效的后端。叠加时的优先级：`jxl-rs-mt` >
/// `jxl-rs-1t` > `jxl-oxide`（与 [`ACTIVE_BACKEND`] 一致）。
pub fn decode_dispatch(bytes: &[u8]) -> Result<DynamicImage> {
    #[cfg(feature = "jxl-rs-mt")]
    return decode_jxl_rs_threaded(bytes);
    #[cfg(all(not(feature = "jxl-rs-mt"), feature = "jxl-rs-1t"))]
    return decode_jxl_rs_hooked(bytes);
    #[cfg(all(
        not(feature = "jxl-rs-mt"),
        not(feature = "jxl-rs-1t"),
        feature = "jxl-oxide"
    ))]
    return decode_jxl_oxide(bytes);
    #[cfg(not(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide")))]
    bail!("构建未启用任何 JXL 后端 feature（jxl-rs-mt / jxl-rs-1t / jxl-oxide）")
}

/// JXL 探尺寸：有便宜头的后端走便宜头，没有的退回全解码。
pub fn probe_size_dispatch(bytes: &[u8]) -> Result<(u32, u32)> {
    #[cfg(feature = "jxl-rs-mt")]
    return probe_size_rs_mt(bytes);
    #[cfg(all(not(feature = "jxl-rs-mt"), feature = "jxl-rs-1t"))]
    return probe_size_1t(bytes);
    #[cfg(all(
        not(feature = "jxl-rs-mt"),
        not(feature = "jxl-rs-1t"),
        feature = "jxl-oxide"
    ))]
    return probe_size_oxide(bytes);
    #[cfg(not(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide")))]
    bail!("构建未启用任何 JXL 后端 feature")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn garbage_bytes_error_cleanly_not_panic() {
        // FF 0A 开头会命中嗅探，但内容不是合法 JXL —— 必须是干净的错误，不能 panic。
        if sniff_jxl(&[0xFF, 0x0A, 1, 2, 3]) {
            assert!(decode_dispatch(&[0xFF, 0x0A, 1, 2, 3]).is_err());
        }
    }

    #[test]
    fn non_jxl_magic_is_not_sniffed() {
        assert!(!sniff_jxl(b"\x89PNG\r\n\x1a\n"));
        assert!(!sniff_jxl(b"\xFF\xD8\xFF\xE0"));
        assert!(!sniff_jxl(b""));
    }
}
