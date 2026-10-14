//! Rossi page adapter for mImageViewer's MIT-licensed `local-adjust-core`.
//! The upstream crate owns mask rasterization, layer ordering, and compositing.

use crate::PagePixels;
use local_adjust_core::{LocalAdjustError, LocalAdjustmentLayer, RgbaImageRef, apply_layers};

/// Render an ordered stack without changing the decoded source page.
pub fn apply_local_adjustments(
    source: &PagePixels,
    layers: &[LocalAdjustmentLayer],
) -> Result<PagePixels, LocalAdjustError> {
    let result = apply_layers(
        RgbaImageRef {
            width: source.width as usize,
            height: source.height as usize,
            pixels: &source.rgba,
        },
        layers,
    )?;
    Ok(PagePixels {
        width: source.width,
        height: source.height,
        source_width: source.source_width,
        source_height: source.source_height,
        rgba: result.pixels,
    })
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use local_adjust_core::{InvertParams, LocalEffect, LocalMask, RasterMask};

    use super::*;

    fn page() -> PagePixels {
        PagePixels {
            width: 3,
            height: 1,
            source_width: 6,
            source_height: 2,
            rgba: vec![10, 20, 30, 255, 40, 50, 60, 211, 70, 80, 90, 255],
        }
    }

    #[test]
    fn masked_layer_changes_only_selected_pixel() {
        let source = page();
        let layer = LocalAdjustmentLayer::new(
            "invert middle",
            LocalMask::Raster(RasterMask {
                width: 3,
                height: 1,
                alpha: Arc::new(vec![0.0, 1.0, 0.0]),
            }),
            LocalEffect::Invert(InvertParams { strength: 1.0 }),
        );
        let output = apply_local_adjustments(&source, &[layer]).unwrap();
        assert_eq!(&output.rgba[0..4], &source.rgba[0..4]);
        assert_ne!(&output.rgba[4..7], &source.rgba[4..7]);
        assert_eq!(output.rgba[7], source.rgba[7]);
        assert_eq!(&output.rgba[8..12], &source.rgba[8..12]);
        assert_eq!((output.source_width, output.source_height), (6, 2));
        assert_eq!(source.rgba[4..8], [40, 50, 60, 211]);
    }

    #[test]
    fn invalid_mask_does_not_modify_source() {
        let source = page();
        let layer = LocalAdjustmentLayer::new(
            "bad mask",
            LocalMask::Raster(RasterMask {
                width: 1,
                height: 1,
                alpha: Arc::new(vec![1.0]),
            }),
            LocalEffect::Invert(InvertParams { strength: 1.0 }),
        );
        assert!(apply_local_adjustments(&source, &[layer]).is_err());
        assert_eq!(source.rgba, page().rgba);
    }
}
