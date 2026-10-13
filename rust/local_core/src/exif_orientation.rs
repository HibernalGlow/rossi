//! 直接编译 mImageViewer 的 EXIF 朝向读取/变换切片（MIT）。
//! 字节入口不依赖 WIC，不覆盖 ICC/颜色管理。
include!(concat!(env!("OUT_DIR"), "/exif_orientation.rs"));

/// 与 canonical loader 一致：已确认的动画第一帧不另做 EXIF 变换。
pub fn orient_still(image: image::DynamicImage, bytes: &[u8]) -> image::DynamicImage {
    if crate::animation::is_animated_image(bytes) {
        image
    } else {
        apply_exif_orientation_from_bytes(image, bytes)
    }
}

pub fn oriented_dimensions(width: u32, height: u32, bytes: &[u8]) -> (u32, u32) {
    if !crate::animation::is_animated_image(bytes)
        && (5..=8).contains(&read_exif_orientation_from_bytes(bytes))
    {
        (height, width)
    } else {
        (width, height)
    }
}

#[cfg(test)]
pub(crate) fn jpeg_with_orientation(orientation: u16) -> Vec<u8> {
    // 3x2 JPEG + little-endian TIFF IFD0 Orientation APP1。
    let image = image::RgbImage::from_fn(3, 2, |x, y| image::Rgb([x as u8 * 60, y as u8 * 90, 30]));
    let mut jpeg = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 100)
        .encode_image(&image)
        .unwrap();
    let mut exif = b"Exif\0\0II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0".to_vec();
    exif.extend_from_slice(&orientation.to_le_bytes());
    exif.extend_from_slice(&[0; 6]);
    let mut result = vec![0xff, 0xd8, 0xff, 0xe1];
    result.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
    result.extend_from_slice(&exif);
    result.extend_from_slice(&jpeg[2..]);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_exif_orientations_match_expected_pixel_positions() {
        let image = image::RgbImage::from_fn(3, 2, |x, y| image::Rgb([(y * 3 + x) as u8, 0, 0]));
        let expected = [
            vec![0, 1, 2, 3, 4, 5],
            vec![2, 1, 0, 5, 4, 3],
            vec![5, 4, 3, 2, 1, 0],
            vec![3, 4, 5, 0, 1, 2],
            vec![0, 3, 1, 4, 2, 5],
            vec![3, 0, 4, 1, 5, 2],
            vec![5, 2, 4, 1, 3, 0],
            vec![2, 5, 1, 4, 0, 3],
        ];
        for value in 1..=8 {
            let bytes = jpeg_with_orientation(value);
            assert_eq!(read_exif_orientation_from_bytes(&bytes), value);
            let oriented =
                orient_still(image::DynamicImage::ImageRgb8(image.clone()), &bytes).to_rgb8();
            assert_eq!(
                oriented.dimensions(),
                if value >= 5 { (2, 3) } else { (3, 2) }
            );
            let actual: Vec<_> = oriented.pixels().map(|p| p.0[0]).collect();
            assert_eq!(actual, expected[value as usize - 1], "orientation={value}");
        }
        assert_eq!(read_exif_orientation_from_bytes(b"invalid"), 1);
    }
}
