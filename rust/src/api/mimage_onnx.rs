//! mImageViewer-compatible ONNX upscaling.
//!
//! The model determines its own scale (all bundled mImage upscalers are 4x).
//! On Apple platforms ONNX Runtime is initialized with CoreML first, which
//! allows Apple Silicon to use the Neural Engine/GPU; ORT falls back to CPU
//! for unsupported operators.

use anyhow::{Context, Result, anyhow};
use flutter_rust_bridge::frb;
use image::{ImageBuffer, Rgb};
use ndarray::Array4;
use ort::{ep, session::Session, value::Tensor};
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

static ORT_READY: OnceLock<Result<(), String>> = OnceLock::new();
/// A CoreML session is expensive to compile. Keep one session per model so
/// turning pages does not rebuild the graph for every image.
static SESSIONS: OnceLock<Mutex<HashMap<String, Session>>> = OnceLock::new();
const TILE_OVERLAP: u32 = 32;

#[derive(Clone, Copy)]
struct TileRect {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
}

/// Match mImageViewer's overlapping tile layout. The overlap removes seams
/// caused by convolution context at tile boundaries while retaining fixed
/// input shapes for CoreML.
fn compute_tiles(img_w: u32, img_h: u32, tile_size: u32) -> Vec<TileRect> {
    let mut tiles = Vec::new();
    let step = tile_size.saturating_sub(TILE_OVERLAP).max(1);
    let mut y = 0;
    loop {
        let h = tile_size.min(img_h.saturating_sub(y));
        if h == 0 {
            break;
        }
        let mut x = 0;
        loop {
            let w = tile_size.min(img_w.saturating_sub(x));
            if w == 0 {
                break;
            }
            tiles.push(TileRect { x, y, w, h });
            if x + w >= img_w {
                break;
            }
            x += step;
            if x + tile_size > img_w {
                x = img_w.saturating_sub(tile_size);
            }
        }
        if y + h >= img_h {
            break;
        }
        y += step;
        if y + tile_size > img_h {
            y = img_h.saturating_sub(tile_size);
        }
    }
    tiles
}

fn init_ort() -> Result<()> {
    ORT_READY
        .get_or_init(|| {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            let result = ort::init()
                .with_name("rossi-mimage-onnx")
                .with_execution_providers([ep::CoreML::default()
                    .with_compute_units(ep::coreml::ComputeUnits::All)
                    .build()
                    .error_on_failure()])
                .commit();
            #[cfg(not(any(target_os = "macos", target_os = "ios")))]
            let result = ort::init().with_name("rossi-mimage-onnx").commit();
            if result {
                Ok(())
            } else {
                Err("ONNX Runtime environment commit failed".to_string())
            }
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
            return Err(anyhow!(
                "invalid mImage ONNX model (Git-LFS pointer or empty): {model_path}"
            ));
        }
        let expected = model_kind_file(&model_id)?;
        if !Path::new(&model_path)
            .file_name()
            .map(|v| v == expected)
            .unwrap_or(false)
        {
            return Err(anyhow!(
                "model id/path mismatch: {model_id} != {model_path}"
            ));
        }
        let input =
            image::open(&input_path).with_context(|| format!("decode input: {input_path}"))?;
        let rgb = input.to_rgb8();
        let (iw, ih) = rgb.dimensions();
        let session_key = format!("{model_path}:{}", meta.len());
        let mut builder = Session::builder()
            .map_err(|e| anyhow!("session builder: {e:?}"))?
            .with_optimization_level(ort::session::builder::GraphOptimizationLevel::Level3)
            .map_err(|e| anyhow!("session optimization: {e:?}"))?
            .with_intra_threads(1)
            .map_err(|e| anyhow!("session threads: {e:?}"))?;
        let sessions = SESSIONS.get_or_init(|| Mutex::new(HashMap::new()));
        let mut sessions = sessions
            .lock()
            .map_err(|_| anyhow!("mImage ONNX session cache poisoned"))?;
        let session_created = if !sessions.contains_key(&session_key) {
            let session = builder
                .commit_from_file(&model_path)
                .map_err(|e| anyhow!("load model with CoreML: {e:?}"))?;
            sessions.insert(session_key.clone(), session);
            true
        } else {
            false
        };
        let session = sessions
            .get_mut(&session_key)
            .ok_or_else(|| anyhow!("mImage ONNX session cache insert failed"))?;
        // Use the model's declared fixed input size when present. Dynamic
        // models use mImage's recommended tile size unless the user selected
        // another valid tile in the RealSR settings.
        let fixed_tile = session
            .inputs()
            .first()
            .and_then(|input| input.dtype().tensor_shape())
            .and_then(|shape| shape.get(2).copied())
            .filter(|size| *size >= 64 && *size <= 512)
            .map(|size| size as usize);
        let recommended_tile = if model_id == "realesr_general_v3" {
            512
        } else {
            192
        };
        let tile = fixed_tile.unwrap_or_else(|| {
            if tile_size == 0 {
                recommended_tile
            } else {
                tile_size.clamp(64, 512) as usize
            }
        });
        let mut scale = None;
        let out_w = iw.saturating_mul(4);
        let out_h = ih.saturating_mul(4);
        let mut out = ImageBuffer::<Rgb<u8>, Vec<u8>>::new(out_w, out_h);
        let mut weights = vec![0.0f32; (out_w as usize).saturating_mul(out_h as usize)];
        let tiles = compute_tiles(iw, ih, tile as u32);
        for tile_rect in tiles {
                let x = tile_rect.x;
                let y = tile_rect.y;
                let tw = tile_rect.w as usize;
                let th = tile_rect.h as usize;
                let mut data = vec![0.0f32; 3 * tile * tile];
                for dy in 0..th {
                    for dx in 0..tw {
                        let p = rgb.get_pixel(x + dx as u32, y + dy as u32).0;
                        for c in 0..3 {
                            data[c * tile * tile + dy * tile + dx] = p[c] as f32 / 255.0;
                        }
                    }
                }
                let array = Array4::from_shape_vec((1, 3, tile, tile), data)
                    .map_err(|e| anyhow!("tensor shape: {e}"))?;
                let tensor = Tensor::from_array(array).map_err(|e| anyhow!("tensor: {e:?}"))?;
                let outputs = session
                    .run(ort::inputs![tensor])
                    .map_err(|e| anyhow!("inference: {e:?}"))?;
                let (shape, raw) = outputs[0]
                    .try_extract_tensor::<f32>()
                    .map_err(|e| anyhow!("output: {e:?}"))?;
                if shape.len() < 4 || shape[1] < 3 || shape[2] <= 0 || shape[3] <= 0 {
                    return Err(anyhow!("mImage output shape is not RGB NCHW: {shape:?}"));
                }
                let sh = shape[2] as usize;
                let sw = shape[3] as usize;
                let required_values = 3usize
                    .checked_mul(sh)
                    .and_then(|value| value.checked_mul(sw))
                    .ok_or_else(|| anyhow!("mImage output shape is too large: {shape:?}"))?;
                if raw.len() < required_values {
                    return Err(anyhow!(
                        "mImage output tensor is truncated: {} values, expected at least {}",
                        raw.len(),
                        required_values
                    ));
                }
                let s = (sh / tile).max(1) as u32;
                if let Some(prev) = scale {
                    if prev != s {
                        return Err(anyhow!("model output scale changed"));
                    }
                } else {
                    scale = Some(s);
                }
                if s != 4 {
                    return Err(anyhow!(
                        "mImage model {model_id} returned {s}x, expected its native 4x output"
                    ));
                }
                let crop_w = tw * s as usize;
                let crop_h = th * s as usize;
                if crop_w > sw || crop_h > sh {
                    return Err(anyhow!(
                        "mImage output {}x{} is smaller than tile crop {}x{}",
                        sw,
                        sh,
                        crop_w,
                        crop_h
                    ));
                }
                let ramp = (TILE_OVERLAP * s).max(1) as f32;
                let first_x = x == 0;
                let first_y = y == 0;
                let last_x = x + tile_rect.w >= iw;
                let last_y = y + tile_rect.h >= ih;
                for dy in 0..crop_h {
                    let dist_top = if first_y { ramp } else { dy as f32 };
                    let dist_bottom = if last_y {
                        ramp
                    } else {
                        crop_h.saturating_sub(1).saturating_sub(dy) as f32
                    };
                    let wy = (dist_top.min(dist_bottom) / ramp).clamp(1e-4, 1.0);
                    for dx in 0..crop_w {
                        let ox = x * s + dx as u32;
                        let oy = y * s + dy as u32;
                        if ox >= out_w || oy >= out_h {
                            continue;
                        }
                        let dist_left = if first_x { ramp } else { dx as f32 };
                        let dist_right = if last_x {
                            ramp
                        } else {
                            crop_w.saturating_sub(1).saturating_sub(dx) as f32
                        };
                        let weight = wy * (dist_left.min(dist_right) / ramp).clamp(1e-4, 1.0);
                        let pixel_index = oy as usize * out_w as usize + ox as usize;
                        let idx = dy * sw + dx;
                        let old_weight = weights[pixel_index];
                        let new_weight = old_weight + weight;
                        let old = *out.get_pixel(ox, oy);
                        let r = ((old[0] as f32 * old_weight
                            + raw[idx].clamp(0.0, 1.0) * 255.0 * weight)
                            / new_weight)
                            .round()
                            .clamp(0.0, 255.0) as u8;
                        let g = ((old[1] as f32 * old_weight
                            + raw[sh * sw + idx].clamp(0.0, 1.0) * 255.0 * weight)
                            / new_weight)
                            .round()
                            .clamp(0.0, 255.0) as u8;
                        let b = ((old[2] as f32 * old_weight
                            + raw[2 * sh * sw + idx].clamp(0.0, 1.0) * 255.0 * weight)
                            / new_weight)
                            .round()
                            .clamp(0.0, 255.0) as u8;
                        weights[pixel_index] = new_weight;
                        out.put_pixel(ox, oy, Rgb([r, g, b]));
                    }
                }
        }
        let final_scale = scale.unwrap_or(4);
        out.save(&output_path)
            .with_context(|| format!("write output: {output_path}"))?;
        Ok(format!(
            "model={model_id} backend=CoreML scale={final_scale}x input={iw}x{ih} output={}x{} model_bytes={} tile={} (requested_tile={tile_size}) session={}",
            out.width(),
            out.height(),
            meta.len(),
            tile,
            if session_created { "created" } else { "cached" },
        ))
    })
    .await
    .map_err(|e| anyhow!(e.to_string()))?
}
