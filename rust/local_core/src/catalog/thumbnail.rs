//! 缩略图图像的 WebP 编码与仅读头部的解码。
//!
//! `CatalogDb` 的本体在 `catalog.rs` / `catalog/db.rs`。这里只负责字节列
//! 的表示形式。

pub const THUMB_LONG_SIDE: u32 = 512;
/// 从已保存缩略图的字节序列中仅靠头部取出 `(w, h)`。
/// 格式为 auto-detect (`with_guessed_format`)。这是为了与旧版本以 JPEG
/// 保存的条目 ([`decode_thumb_to_color_image`] 会读取 "WebP or old JPEG"
/// 两种格式) 保持兼容。不会走完整解码
/// (`ImageReader::into_dimensions` 只读取 chunk 头部)。
pub fn decode_thumb_dims(data: &[u8]) -> Option<(u32, u32)> {
    image::ImageReader::new(std::io::Cursor::new(data))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}
// -----------------------------------------------------------------------
// WebP 编解码辅助函数
// -----------------------------------------------------------------------

/// 将图像缩放到 `long_side` px，并有损编码为 WebP。
/// `quality` 为 0.0–100.0 (与 JPEG 的 quality 含义同等)。
/// 返回值: (webp_bytes, width, height)
///
/// 缩放使用 SIMD 实现的 `fast_image_resize`，以 Lanczos3 进行
/// (比 image crate 的标量 Lanczos3 快 3-5 倍)。
pub fn encode_thumb_webp(
    img: &image::DynamicImage,
    long_side: u32,
    quality: f32,
) -> Option<(Vec<u8>, u32, u32)> {
    encode_thumb_webp_with_source_dims(img, long_side, quality, (img.width(), img.height()))
}

/// `encode_thumb_webp` variant that uses canonical source dimensions for aspect.
///
/// PDF page boxes and DCT-scaled JPEG buffers can differ slightly from the decoded
/// raster's already-rounded aspect. The output still never exceeds `long_side` or
/// upscales the supplied raster.
pub fn encode_thumb_webp_with_source_dims(
    img: &image::DynamicImage,
    long_side: u32,
    quality: f32,
    source_dims: (u32, u32),
) -> Option<(Vec<u8>, u32, u32)> {
    encode_thumb_webp_with_aspect_dims(img, long_side, quality, source_dims)
}

/// `encode_thumb_webp` variant that uses dimensions supplied only for aspect.
/// The values may be pixel source dimensions or PDF page-layout dimensions.
pub fn encode_thumb_webp_with_aspect_dims(
    img: &image::DynamicImage,
    long_side: u32,
    quality: f32,
    aspect_dims: (u32, u32),
) -> Option<(Vec<u8>, u32, u32)> {
    let thumb = crate::fast_resize::resize_dynamic_fit_with_source_aspect(
        img,
        long_side,
        long_side,
        aspect_dims,
        crate::fast_resize::Quality::Lanczos3,
    );
    let rgb = thumb.to_rgb8();
    let (w, h) = (rgb.width(), rgb.height());
    let encoder = webp::Encoder::from_rgb(rgb.as_raw(), w, h);
    let webp_data = encoder.encode(quality.clamp(1.0, 100.0));
    Some((webp_data.to_vec(), w, h))
}

/// 用 `image::load_from_memory` 解码并返回 RGBA8 + (w, h)。
/// 视频瓦片缩略图 cache 的 WebP 还原共用。
pub fn decode_thumb_to_rgba(data: &[u8]) -> Option<(u32, u32, Vec<u8>)> {
    let img = image::load_from_memory(data).ok()?;
    let rgba = img.to_rgba8();
    let (w, h) = (rgba.width(), rgba.height());
    Some((w, h, rgba.into_raw()))
}
