//! 解码：把「一页的字节」变成可上屏的像素。
//!
//! 这一层刻意很薄。v0.1 的目标是**归档直读 → 解码 → GPU 上屏**，
//! 而解码本身交给 `image` crate（与 windcore 同一版本）。
//! 大图 tile 化、GPU 驻留、预取等都在后面，不在这里。

use std::fmt;

use anyhow::{Context, Result, bail};
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
    /// `width * height * 4` 字节。
    pub rgba: Vec<u8>,
}

impl PagePixels {
    pub fn byte_len(&self) -> usize {
        self.rgba.len()
    }
}

/// 从内存字节解码。
///
/// 格式由内容（魔数）决定，不看扩展名——漫画包里的扩展名经常是错的，
/// 而 `image` 的猜测足够可靠。
pub fn decode(bytes: &[u8]) -> Result<DynamicImage> {
    if bytes.is_empty() {
        bail!("页面字节为空，无法解码");
    }
    image::load_from_memory(bytes).with_context(|| {
        format!(
            "解码失败（{} 字节，头部 {:02X?}）",
            bytes.len(),
            &bytes[..bytes.len().min(8)]
        )
    })
}

/// 解码并转成 RGBA8。
///
/// 灰度页（漫画最常见的输入）会在这里被展开成 4 通道；
/// 只解码不转换的路径留给未来的 GPU 侧格式协商。
pub fn decode_rgba(bytes: &[u8]) -> Result<PagePixels> {
    let image = decode(bytes)?;
    let rgba = image.to_rgba8();
    let (width, height) = rgba.dimensions();
    Ok(PagePixels {
        width,
        height,
        rgba: rgba.into_raw(),
    })
}

/// 便宜地读尺寸而不做完整解码（列表/布局阶段用）。
pub fn probe_size(bytes: &[u8]) -> Result<(u32, u32)> {
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
        assert_eq!(page.byte_len(), 7 * 3 * 4);
        assert_eq!(&page.rgba[..4], &[10, 20, 30, 255]);
    }

    #[test]
    fn probe_size_agrees_with_full_decode() {
        let bytes = png_bytes(5, 9, [0, 0, 0, 255]);
        assert_eq!(probe_size(&bytes).unwrap(), (5, 9));
    }

    #[test]
    fn empty_and_garbage_input_report_clear_errors() {
        assert!(decode(&[]).is_err());
        assert!(decode(b"not an image at all").is_err());
    }
}
