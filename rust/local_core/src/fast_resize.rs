// Vendored from vendor/mimageviewer/src/fast_resize.rs (MIT License)
// SIMD 高速リサイズ用ユーティリティ (fast_image_resize ラッパー)。

use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, RgbImage, RgbaImage};

/// リサイズ品質。Triangle 相当 (`Bilinear`) と Lanczos3 の 2 択。
#[derive(Clone, Copy, Debug)]
pub enum Quality {
    Bilinear,
    Lanczos3,
}

impl From<Quality> for FilterType {
    fn from(q: Quality) -> FilterType {
        match q {
            Quality::Bilinear => FilterType::Bilinear,
            Quality::Lanczos3 => FilterType::Lanczos3,
        }
    }
}

/// RGBA8 画像を指定サイズに正確にリサイズする。
pub fn resize_rgba8_exact(src: &RgbaImage, new_w: u32, new_h: u32, quality: Quality) -> RgbaImage {
    let mut dst = RgbaImage::new(new_w.max(1), new_h.max(1));
    let mut resizer = Resizer::new();
    let opts = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(quality.into()));
    resizer
        .resize(src, &mut dst, &opts)
        .expect("fast_image_resize: rgba8 resize must succeed for matching pixel types");
    dst
}

/// RGB8 画像を指定サイズに正確にリサイズする。
pub fn resize_rgb8_exact(src: &RgbImage, new_w: u32, new_h: u32, quality: Quality) -> RgbImage {
    let mut dst = RgbImage::new(new_w.max(1), new_h.max(1));
    let mut resizer = Resizer::new();
    let opts = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(quality.into()));
    resizer
        .resize(src, &mut dst, &opts)
        .expect("fast_image_resize: rgb8 resize must succeed for matching pixel types");
    dst
}

/// DynamicImage を指定サイズに正確にリサイズする。
pub fn resize_dynamic_exact(
    src: &DynamicImage,
    new_w: u32,
    new_h: u32,
    quality: Quality,
) -> DynamicImage {
    match src {
        DynamicImage::ImageRgba8(buf) => {
            DynamicImage::ImageRgba8(resize_rgba8_exact(buf, new_w, new_h, quality))
        }
        DynamicImage::ImageRgb8(buf) => {
            DynamicImage::ImageRgb8(resize_rgb8_exact(buf, new_w, new_h, quality))
        }
        _ => {
            let rgba = src.to_rgba8();
            DynamicImage::ImageRgba8(resize_rgba8_exact(&rgba, new_w, new_h, quality))
        }
    }
}

/// DynamicImage を (max_w, max_h) の矩形にアスペクト比保持で収める。
pub fn resize_dynamic_fit(
    src: &DynamicImage,
    max_w: u32,
    max_h: u32,
    quality: Quality,
) -> DynamicImage {
    resize_dynamic_fit_with_source_aspect(src, max_w, max_h, (src.width(), src.height()), quality)
}

const THUMBNAIL_ASPECT_ERROR_TARGET: f64 = 0.0005;

pub(crate) fn aspect_accurate_fit_dimensions(
    raster_size: (u32, u32),
    max_size: (u32, u32),
    source_aspect_size: (u32, u32),
) -> (u32, u32) {
    let (raster_w, raster_h) = (raster_size.0.max(1), raster_size.1.max(1));
    let bound_w = raster_w.min(max_size.0.max(1));
    let bound_h = raster_h.min(max_size.1.max(1));
    let (aspect_w, aspect_h) = (
        source_aspect_size.0.max(1) as f64,
        source_aspect_size.1.max(1) as f64,
    );
    let source_ratio = aspect_w / aspect_h;

    #[derive(Clone, Copy)]
    struct Candidate {
        width: u32,
        height: u32,
        error: f64,
    }

    impl Candidate {
        fn long_edge(self) -> u32 {
            self.width.max(self.height)
        }

        fn area(self) -> u64 {
            self.width as u64 * self.height as u64
        }
    }

    fn better_acceptable(candidate: Candidate, current: Candidate) -> bool {
        candidate.long_edge() > current.long_edge()
            || (candidate.long_edge() == current.long_edge()
                && (candidate.error < current.error
                    || (candidate.error == current.error && candidate.area() > current.area())))
    }

    fn better_fallback(candidate: Candidate, current: Candidate) -> bool {
        candidate.error < current.error
            || (candidate.error == current.error
                && (candidate.long_edge() > current.long_edge()
                    || (candidate.long_edge() == current.long_edge()
                        && candidate.area() > current.area())))
    }

    let mut acceptable: Option<Candidate> = None;
    let mut fallback: Option<Candidate> = None;
    let mut consider = |width: u32, height: u32| {
        if width == 0 || height == 0 || width > bound_w || height > bound_h {
            return;
        }
        let ratio = width as f64 / height as f64;
        let candidate = Candidate {
            width,
            height,
            error: ((ratio / source_ratio) - 1.0).abs(),
        };
        if candidate.error <= THUMBNAIL_ASPECT_ERROR_TARGET
            && acceptable.is_none_or(|current| better_acceptable(candidate, current))
        {
            acceptable = Some(candidate);
        }
        if fallback.is_none_or(|current| better_fallback(candidate, current)) {
            fallback = Some(candidate);
        }
    };

    for height in 1..=bound_h {
        let ideal_width = source_ratio * height as f64;
        consider(ideal_width.floor().max(1.0) as u32, height);
        consider(ideal_width.ceil().max(1.0) as u32, height);
    }
    for width in 1..=bound_w {
        let ideal_height = width as f64 / source_ratio;
        consider(width, ideal_height.floor().max(1.0) as u32);
        consider(width, ideal_height.ceil().max(1.0) as u32);
    }

    let selected = acceptable.or(fallback).unwrap_or(Candidate {
        width: bound_w,
        height: bound_h,
        error: f64::INFINITY,
    });
    (selected.width, selected.height)
}

pub fn resize_dynamic_fit_with_source_aspect(
    src: &DynamicImage,
    max_w: u32,
    max_h: u32,
    source_aspect_size: (u32, u32),
    quality: Quality,
) -> DynamicImage {
    let (w, h) = (src.width(), src.height());
    let (new_w, new_h) = aspect_accurate_fit_dimensions((w, h), (max_w, max_h), source_aspect_size);
    if w == new_w && h == new_h {
        return src.clone();
    }
    resize_dynamic_exact(src, new_w, new_h, quality)
}
