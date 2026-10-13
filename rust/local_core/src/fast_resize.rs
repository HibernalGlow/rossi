//! 直接编译 mImageViewer 的 SIMD 缩放与比例策略切片（MIT）。
//! 不引入其 RAW 探测/LibRaw 运行时；函数体随子模块更新。
use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, RgbImage, RgbaImage};
include!(concat!(env!("OUT_DIR"), "/fast_resize.rs"));

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn resize_preserves_constant_rgba_and_bounds() {
        let image = RgbaImage::from_pixel(31, 17, image::Rgba([12, 24, 48, 255]));
        for quality in [Quality::Bilinear, Quality::Lanczos3] {
            let scaled = resize_rgba8_exact(&image, 7, 5, quality);
            assert_eq!(scaled.dimensions(), (7, 5));
            assert!(scaled.pixels().all(|p| p.0 == [12, 24, 48, 255]));
        }
        let original = DynamicImage::ImageRgba8(image);
        let unchanged = resize_dynamic_fit(&original, 99, 99, Quality::Lanczos3);
        assert_eq!(unchanged.to_rgba8(), original.to_rgba8());
        let fit = resize_dynamic_fit(&original, 10, 10, Quality::Bilinear);
        assert!(fit.width() <= 10 && fit.height() <= 10);
    }
}
