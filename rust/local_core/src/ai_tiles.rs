//! mImageViewer 的重叠 tile 布局，直接从 AI 源码提取编译（MIT）。
//! overlap 由调用者传入；tensor 采用上游 NCHW/零填充，推理与平台 EP 留在 windcore。
include!(concat!(env!("OUT_DIR"), "/ai_tiles.rs"));
include!(concat!(env!("OUT_DIR"), "/ai_tensor.rs"));

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tensor_is_rgb_nchw_with_zero_padding() {
        let image =
            image::RgbImage::from_fn(3, 2, |x, y| image::Rgb([x as u8 * 10, y as u8 * 20, 255]));
        let tile = TileRect {
            x: 1,
            y: 0,
            w: 2,
            h: 2,
        };
        let tensor = extract_tile(&image, &tile, 4);
        assert_eq!(tensor.shape(), &[1, 3, 4, 4]);
        assert_eq!(tensor[[0, 0, 0, 0]], 10.0 / 255.0);
        assert_eq!(tensor[[0, 0, 0, 1]], 20.0 / 255.0);
        assert_eq!(tensor[[0, 1, 1, 0]], 20.0 / 255.0);
        assert_eq!(tensor[[0, 2, 1, 1]], 1.0);
        for y in 0..4 {
            for x in 0..4 {
                if x >= 2 || y >= 2 {
                    for c in 0..3 {
                        assert_eq!(tensor[[0, c, y, x]], 0.0);
                    }
                }
            }
        }
    }
    #[test]
    fn partial_and_empty_images_have_bounded_tiles() {
        assert!(compute_tiles(0, 10, 8, 2).is_empty());
        assert!(compute_tiles(10, 0, 8, 2).is_empty());
        assert!(compute_tiles(10, 10, 0, 2).is_empty());
        let tiles = compute_tiles(3, 2, 8, 2);
        assert_eq!(tiles.len(), 1);
        assert_eq!(
            (tiles[0].x, tiles[0].y, tiles[0].w, tiles[0].h),
            (0, 0, 3, 2)
        );
    }
    #[test]
    fn golden_layout_and_coverage_include_snapped_edges() {
        let tiles = compute_tiles(17, 13, 8, 2);
        let actual: Vec<_> = tiles.iter().map(|t| (t.x, t.y, t.w, t.h)).collect();
        assert_eq!(
            actual,
            vec![
                (0, 0, 8, 8),
                (6, 0, 8, 8),
                (9, 0, 8, 8),
                (0, 5, 8, 8),
                (6, 5, 8, 8),
                (9, 5, 8, 8)
            ]
        );
        for y in 0..13 {
            for x in 0..17 {
                assert!(
                    tiles
                        .iter()
                        .any(|t| x >= t.x && x < t.x + t.w && y >= t.y && y < t.y + t.h)
                );
            }
        }
        assert!(compute_tiles(9, 9, 8, 99).len() <= 4);
    }
}
