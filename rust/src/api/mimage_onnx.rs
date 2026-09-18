//! mImageViewer-compatible ONNX upscaling.
//!
//! The model determines its own scale (all bundled mImage upscalers are 4x).
//! On Apple platforms ONNX Runtime is initialized with CoreML first, which
//! allows Apple Silicon to use the Neural Engine/GPU; ORT falls back to CPU
//! for unsupported operators.

use anyhow::{anyhow, Context, Result};
use flutter_rust_bridge::frb;
use image::{ImageBuffer, Rgb};
use ndarray::Array4;
use ort::{ep, session::Session, value::Tensor};
use std::path::Path;
use std::sync::OnceLock;

static ORT_READY: OnceLock<Result<(), String>> = OnceLock::new();

fn init_ort() -> Result<()> {
    ORT_READY
        .get_or_init(|| {
            let result = ort::init()
                .with_name("rossi-mimage-onnx")
                .with_execution_providers([
                    ep::CoreML::default()
                        .with_compute_units(ep::coreml::ComputeUnits::All)
                        .build(),
                ])
                .commit();
            if result { Ok(()) } else { Err("ONNX Runtime environment commit failed".to_string()) }
        })
        .clone()
        .map_err(|e| anyhow!(e))
}

fn model_kind_file(model_id: &str) -> Result<&'static str> {
    match model_id {
        "realcugan_4x" => Ok("realcugan_4x_conservative.onnx"),
        "realesrgan_anime6b" => Ok("realesrgan_x4plus_anime_6b.onnx"),
        "realesrgan_x4plus" => Ok("realesrgan_x4plus.onnx"),
        "realesr_general_v3" => Ok("realesr_general_x4v3.onnx"),
        "nmkd_siax_4x" => Ok("4x_NMKD-Siax_200k.onnx"),
        _ => Err(anyhow!("unknown mImage ONNX model: {model_id}")),
    }
}

/// Run one mImage ONNX model and write a PNG. `model_path` must be a real
/// ONNX file; Git-LFS pointer files are rejected before inference.
#[frb]
pub async fn mimage_onnx_upscale(
    input_path: String,
    output_path: String,
    model_path: String,
    model_id: String,
    tile_size: u32,
) -> Result<String> {
    tokio::task::spawn_blocking(move || {
        init_ort()?;
        let meta = std::fs::metadata(&model_path)
            .with_context(|| format!("mImage ONNX model missing: {model_path}"))?;
        if meta.len() < 1024 {
            return Err(anyhow!("invalid mImage ONNX model (Git-LFS pointer or empty): {model_path}"));
        }
        let expected = model_kind_file(&model_id)?;
        if !Path::new(&model_path).file_name().map(|v| v == expected).unwrap_or(false) {
            return Err(anyhow!("model id/path mismatch: {model_id} != {model_path}"));
        }
        let input = image::open(&input_path).with_context(|| format!("decode input: {input_path}"))?;
        let rgb = input.to_rgb8();
        let (iw, ih) = rgb.dimensions();
        let tile = tile_size.clamp(64, 512) as usize;
        let mut session = Session::builder()
            .map_err(|e| anyhow!("session builder: {e:?}"))?
            .with_intra_threads(1)
            .map_err(|e| anyhow!("session threads: {e:?}"))?
            .commit_from_file(&model_path)
            .map_err(|e| anyhow!("load model: {e:?}"))?;
        let mut scale = None;
        let mut out = ImageBuffer::<Rgb<u8>, Vec<u8>>::new(iw.saturating_mul(4), ih.saturating_mul(4));
        let mut y = 0u32;
        while y < ih {
            let mut x = 0u32;
            while x < iw {
                let tw = (tile as u32).min(iw - x) as usize;
                let th = (tile as u32).min(ih - y) as usize;
                let mut data = vec![0.0f32; 3 * tile * tile];
                for dy in 0..th {
                    for dx in 0..tw {
                        let p = rgb.get_pixel(x + dx as u32, y + dy as u32).0;
                        for c in 0..3 { data[c * tile * tile + dy * tile + dx] = p[c] as f32 / 255.0; }
                    }
                }
                let array = Array4::from_shape_vec((1, 3, tile, tile), data)
                    .map_err(|e| anyhow!("tensor shape: {e}"))?;
                let tensor = Tensor::from_array(array)
                    .map_err(|e| anyhow!("tensor: {e:?}"))?;
                let outputs = session.run(ort::inputs![tensor])
                    .map_err(|e| anyhow!("inference: {e:?}"))?;
                let (shape, raw) = outputs[0]
                    .try_extract_tensor::<f32>()
                    .map_err(|e| anyhow!("output: {e:?}"))?;
                if shape.len() < 4 { return Err(anyhow!("mImage output shape is not NCHW: {shape:?}")); }
                let sh = shape[2] as usize;
                let sw = shape[3] as usize;
                let s = (sh / tile).max(1) as u32;
                if let Some(prev) = scale { if prev != s { return Err(anyhow!("model output scale changed")); } } else { scale = Some(s); }
                if s != 4 { return Err(anyhow!("mImage model {model_id} returned {s}x, expected its native 4x output")); }
                let crop_w = tw * s as usize;
                let crop_h = th * s as usize;
                for dy in 0..crop_h { for dx in 0..crop_w {
                    let ox = x * s + dx as u32; let oy = y * s + dy as u32;
                    let idx = dy * sw + dx;
                    let r = (raw[idx].clamp(0.0, 1.0) * 255.0) as u8;
                    let g = (raw[sh * sw + idx].clamp(0.0, 1.0) * 255.0) as u8;
                    let b = (raw[2 * sh * sw + idx].clamp(0.0, 1.0) * 255.0) as u8;
                    out.put_pixel(ox, oy, Rgb([r, g, b]));
                }}
                x += tile as u32;
            }
            y += tile as u32;
        }
        let final_scale = scale.unwrap_or(4);
        out.save(&output_path).with_context(|| format!("write output: {output_path}"))?;
        Ok(format!("model={model_id} backend=CoreML scale={final_scale}x input={iw}x{ih} output={}x{}", out.width(), out.height()))
    }).await.map_err(|e| anyhow!(e.to_string()))?
}
