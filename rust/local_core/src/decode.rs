//! 解码：把「一页的字节」变成可上屏的像素。
//!
//! 这一层刻意很薄。v0.1 的目标是**归档直读 → 解码 → GPU 上屏**，
//! 而解码本身交给 `image` crate（与 windcore 同一版本）。
//! 大图 tile 化、GPU 驻留、预取等都在后面，不在这里。

use std::fmt;

use anyhow::{Context, Result, anyhow, bail};
use image::DynamicImage;

/// 核心没有这个格式的解码器，但**外壳（Flutter / Skia）有**。
///
/// 用类型而不是字符串，理由与 `UnsupportedSource` 相同：调用方需要按类别决定动作——
/// 「这本是 avif，走 Dart 兜底能看」和「这个文件坏了」该给用户完全不同的下一步。
/// 见 `page_order::SHELL_DECODABLE_EXTENSIONS` 的模块注释。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShellOnlyFormat {
    /// 小写扩展名（不含点）。
    pub extension: String,
}

impl fmt::Display for ShellOnlyFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "`.{}` 需要外壳（Flutter/Skia）解码，`rossi_local_core` 的内置解码器不支持；\
             这一页可走 Dart 兜底显示路径，但暂不进 Rust → GPU 上屏路径",
            self.extension
        )
    }
}

impl std::error::Error for ShellOnlyFormat {}

/// 单页解码后的 RGBA8 缓冲（未预乘，行主序）。
///
/// 这是交给渲染层的交换格式：显式带尺寸，避免下游再去问一遍图片头。
#[derive(Clone, Debug)]
pub struct PagePixels {
    pub width: u32,
    pub height: u32,
    /// 解码器输出的**原始**尺寸（降采样之前）。
    ///
    /// 与 `width`/`height` 分开是为了让「降采样到底生没生效」在 UI 上可见 ——
    /// 只报解出尺寸的话，`900×1349` 既可能是降采样的结果，也可能是原图本来就小。
    pub source_width: u32,
    pub source_height: u32,
    /// `width * height * 4` 字节。
    pub rgba: Vec<u8>,
}

impl PagePixels {
    pub fn byte_len(&self) -> usize {
        self.rgba.len()
    }

    /// 相对原始像素量省下的比例（0.0 = 没省，0.97 = 只剩 3%）。
    pub fn pixel_saving(&self) -> f64 {
        let source = self.source_width as f64 * self.source_height as f64;
        if source <= 0.0 {
            return 0.0;
        }
        let current = self.width as f64 * self.height as f64;
        (1.0 - current / source).clamp(0.0, 1.0)
    }
}

/// 从内存字节解码。
///
/// 格式由内容（魔数）决定，不看扩展名——漫画包里的扩展名经常是错的，
/// 而 `image` 的猜测足够可靠。
///
/// JXL 单独分流：`image` 0.25 没有 jxl 解码器，魔数命中的走
/// [`crate::jxl_backend`]（后端由编译期 feature 选择，默认 `jxl-rs-mt`）。
pub fn decode(bytes: &[u8]) -> Result<DynamicImage> {
    if bytes.is_empty() {
        bail!("页面字节为空，无法解码");
    }
    #[cfg(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide"))]
    if crate::jxl_backend::sniff_jxl(bytes) {
        return crate::jxl_backend::decode_dispatch(bytes);
    }
    image::load_from_memory(bytes).with_context(|| {
        format!(
            "解码失败（{} 字节，头部 {:02X?}）",
            bytes.len(),
            &bytes[..bytes.len().min(8)]
        )
    })
}

/// 按目标宽度算出解出尺寸。不放大。
///
/// `None` / `0` / 不小于原宽都表示「保持原尺寸」——**放大不做**：
/// 放大是渲染层（`BoxFit`）的事，在这里放大只会多占内存。
///
/// 高度按比例取整，下限 1（极端长条图不会被算成 0 行）。
fn fit_width(width: u32, height: u32, target_width: Option<u32>) -> (u32, u32) {
    let Some(target) = target_width.filter(|value| *value > 0) else {
        return (width, height);
    };
    if target >= width || width == 0 {
        return (width, height);
    }
    let scaled = (height as u64 * target as u64 / width as u64).max(1) as u32;
    (target, scaled)
}

/// 解码 + 按目标宽度降采样 + 转 RGBA8。
///
/// # 为什么要有 `target_width`
///
/// 这一条不是「优化」，是**这条显示路径（Rust 解码 → 过桥 → `decodeImageFromPixels`）
/// 能不能用**的问题。实测（`bin/scale_probe.rs`，5464×8192 的 AVIF）：
///
/// | 档位 | dav1d 解码 | 装箱 | 缩放 | Rust 侧合计 | 位图 |
/// |---|---|---|---|---|---|
/// | 全尺寸 | 248.9 ms | 18.0 ms | 0 | **266.9 ms** | 170.8 MB |
/// | thumbnail → 1440 | 248.9 ms | 1.3 ms | 76.6 ms | **326.7 ms** | 11.9 MB |
/// | thumbnail → 768 | 248.9 ms | 0.4 ms | 55.6 ms | **304.8 ms** | 3.4 MB |
///
/// 两个反直觉的结论，都别再重新发现一遍：
///
/// 1. **dav1d 只占 17%。** Rust 侧全尺寸只要 267 ms，而 App 里同一页量到
///    1526 ms —— 差的 1260 ms 全部花在「170 MB 过桥 + 交给
///    `ui.decodeImageFromPixels`」，与解码无关。所以**砍像素量砍的是那 1260 ms**，
///    位图从 170.8 MB 落到 3.4 MB 时，那一段跟着落到约 1/50。
/// 2. **降采样本身比「多搬那点像素」便宜得多。** 缩到 768 只多花 55.6 ms，
///    却省掉约 1200 ms 的搬运。方向是明确的。
///
/// # 但 dav1d 那一段缩不掉
///
/// AVIF 没有可直接使用的 DCT 缩放档（与 JPEG 的 1/8–1/1 不同），
/// 要缩放就必须先解出全尺寸。这 249 ms 是这条路径的**固定成本**，
/// 只能靠预取（提前解）或 Phase 1 的 GPU 侧接管来藏起来。
///
/// ## 为什么是 `DynamicImage::thumbnail_exact` 而不是 `imageops::thumbnail`
///
/// 后者是**泛型**函数，实例化发生在调用方 crate 里 —— 也就是本 crate，
/// 于是它吃 `[profile.dev] opt-level = 1`（见 `rust/Cargo.toml`）。
/// `DynamicImage::thumbnail_exact` 按具体像素类型在 `image` crate 内部展开，
/// 可以靠 `[profile.dev.package.image]` 单独提优化 —— 热重载构建是日常，
/// 而这条路径就在翻页关键路径上。release 构建下两者本来就是 opt-level 3，无差别。
///
/// 滤波器选 box 平均（`thumbnail` 家族）而不是 `FilterType::Triangle`：
/// release 实测同一档位 76.6 vs 180.0 ms，3× 以上降采样倍数下两者肉眼无差。
pub fn is_jpeg(bytes: &[u8]) -> bool {
    bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
}

fn try_decode_jpeg_rgba(bytes: &[u8]) -> Result<PagePixels> {
    use std::io::Cursor;
    use zune_core::colorspace::ColorSpace;
    use zune_core::options::DecoderOptions;
    use zune_jpeg::JpegDecoder;

    let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::RGBA);
    let mut decoder = JpegDecoder::new_with_options(Cursor::new(bytes), options);
    let rgba = decoder
        .decode()
        .map_err(|e| anyhow!("zune-jpeg 解码失败: {e:?}"))?;
    let (width, height) = decoder
        .dimensions()
        .ok_or_else(|| anyhow!("无法获取 JPEG 尺寸信息"))?;
    Ok(PagePixels {
        width: width as u32,
        height: height as u32,
        source_width: width as u32,
        source_height: height as u32,
        rgba,
    })
}

pub fn decode_rgba_scaled(bytes: &[u8], target_width: Option<u32>) -> Result<PagePixels> {
    // 快速直通：全尺寸原图原解时若为 JPEG，直接通过 zune-jpeg 解出 RGBA，
    // 避免 DynamicImage RGB -> to_rgba8 的二次堆内存分配和逐像素复制
    if target_width.is_none() && is_jpeg(bytes) {
        if let Ok(pixels) = try_decode_jpeg_rgba(bytes) {
            return Ok(pixels);
        }
    }

    let image = decode(bytes)?;
    let (source_width, source_height) = (image.width(), image.height());
    let (target_w, target_h) = fit_width(source_width, source_height, target_width);
    let image = if (target_w, target_h) != (source_width, source_height) {
        image.thumbnail_exact(target_w, target_h)
    } else {
        image
    };

    let rgba = image.to_rgba8();
    let (width, height) = rgba.dimensions();
    Ok(PagePixels {
        width,
        height,
        source_width,
        source_height,
        rgba: rgba.into_raw(),
    })
}

/// 解码并转成 RGBA8（原尺寸）。
///
/// 灰度页（漫画最常见的输入）会在这里被展开成 4 通道；
/// 只解码不转换的路径留给未来的 GPU 侧格式协商。
///
/// 需要控制像素量时用 [`decode_rgba_scaled`] —— 理由见那里的说明，
/// 「先解全尺寸再交给上层缩」在这条显示路径上是不可接受的。
pub fn decode_rgba(bytes: &[u8]) -> Result<PagePixels> {
    decode_rgba_scaled(bytes, None)
}

/// 便宜地读尺寸而不做完整解码（列表/布局阶段用）。
///
/// JXL 魔数命中时走 [`crate::jxl_backend`] 的探尺寸（`jxl-rs-mt` 下只读头，
/// 不解像素）；`image` 的 `with_guessed_format` 不认识 JXL，不分流必报
/// 「无法从内容判断图片格式」。
pub fn probe_size(bytes: &[u8]) -> Result<(u32, u32)> {
    #[cfg(any(feature = "jxl-rs-mt", feature = "jxl-rs-1t", feature = "jxl-oxide"))]
    if crate::jxl_backend::sniff_jxl(bytes) {
        return crate::jxl_backend::probe_size_dispatch(bytes);
    }
    let reader = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .context("无法从内容判断图片格式")?;
    reader.into_dimensions().context("读取图片尺寸失败")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 现造一张 PNG，避免依赖仓库里的二进制样本。
    fn png_bytes(width: u32, height: u32, rgba: [u8; 4]) -> Vec<u8> {
        let mut buffer = image::RgbaImage::new(width, height);
        for pixel in buffer.pixels_mut() {
            *pixel = image::Rgba(rgba);
        }
        let mut out = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(buffer)
            .write_to(&mut out, image::ImageFormat::Png)
            .expect("encode png");
        out.into_inner()
    }

    #[test]
    fn decodes_to_rgba_with_expected_dimensions() {
        let bytes = png_bytes(7, 3, [10, 20, 30, 255]);
        let page = decode_rgba(&bytes).unwrap();
        assert_eq!((page.width, page.height), (7, 3));
        // 原尺寸与解出尺寸分开报：不降采样时两者相等、省下的比例为 0。
        assert_eq!((page.source_width, page.source_height), (7, 3));
        assert_eq!(page.pixel_saving(), 0.0);
        assert_eq!(page.byte_len(), 7 * 3 * 4);
        assert_eq!(&page.rgba[..4], &[10, 20, 30, 255]);
    }

    #[test]
    fn probe_size_agrees_with_full_decode() {
        let bytes = png_bytes(5, 9, [0, 0, 0, 255]);
        assert_eq!(probe_size(&bytes).unwrap(), (5, 9));
    }

    /// 降采样的四件必须成立的事：按宽度缩、高度按比例、**不放大**、`None`/`0` 视为原尺寸。
    ///
    /// 「不放大」单独断言，是因为它很容易被写成 `target >= width` 时也走缩放路径 ——
    /// 那会在 `BoxFit` 已经负责放大的前提下白花内存。
    #[test]
    fn target_width_scales_down_and_never_upscales() {
        let bytes = png_bytes(64, 32, [1, 2, 3, 255]);

        let half = decode_rgba_scaled(&bytes, Some(32)).unwrap();
        assert_eq!((half.width, half.height), (32, 16));
        assert_eq!(half.byte_len(), 32 * 16 * 4);
        // 原始尺寸始终是解码器的输出，不因为降采样而改变。
        assert_eq!((half.source_width, half.source_height), (64, 32));
        assert!((half.pixel_saving() - 0.75).abs() < 1e-9);

        // 非整除也要给出确定结果（不是四舍五入，是向下取整，下限 1）。
        let odd = decode_rgba_scaled(&bytes, Some(20)).unwrap();
        assert_eq!((odd.width, odd.height), (20, 10));

        let bigger = decode_rgba_scaled(&bytes, Some(1024)).unwrap();
        assert_eq!((bigger.width, bigger.height), (64, 32));

        assert_eq!(decode_rgba_scaled(&bytes, None).unwrap().width, 64);
        assert_eq!(decode_rgba_scaled(&bytes, Some(0)).unwrap().width, 64);
    }

    #[test]
    fn empty_and_garbage_input_report_clear_errors() {
        assert!(decode(&[]).is_err());
        assert!(decode(b"not an image at all").is_err());
    }
}
