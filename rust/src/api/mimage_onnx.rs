//! mImageViewer-compatible ONNX upscaling.
//!
//! The model determines its own scale (all bundled mImage upscalers are 4x).
//! On Apple platforms ONNX Runtime is initialized with CoreML first, which
//! allows Apple Silicon to use the Neural Engine/GPU; ORT falls back to CPU
//! for unsupported operators.

use anyhow::{Context, Result, anyhow};
use flutter_rust_bridge::frb;
use image::{ImageBuffer, Rgb};
use ort::{ep, session::Session, value::TensorRef};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

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

/// 日志里报的后端名，必须与 `init_ort` 实际注册的 EP 一致。
///
/// 原来这里写死 `ONNXRuntime(CoreML+CPU)`，于是 Windows 上那行日志说自己在用
/// CoreML —— 而这行日志是用户判断「GPU 到底用上没有」的唯一依据，说错比不说更糟。
/// Windows 分支带了 `error_on_failure()`，所以这行能打出来就说明 DirectML 注册成功
/// （个别算子仍可能被 ORT 放回 CPU 跑，与 Apple 那侧同样的口径）。
#[cfg(any(target_os = "macos", target_os = "ios"))]
const ONNX_BACKEND: &str = "ONNXRuntime(CoreML+CPU)";
#[cfg(target_os = "windows")]
const ONNX_BACKEND: &str = "ONNXRuntime(DirectML+CPU)";
#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
const ONNX_BACKEND: &str = "ONNXRuntime(CPU)";

/// CoreML EP 的编译产物目录：落在模型旁边的 `.coreml_cache`。
///
/// 不设 `ModelCacheDirectory` 时，ORT **每次建 session 都重编译一遍** `.onnx`，产物还丢在
/// 系统临时目录里（macOS 每天清一次）。目录从 Dart 传进来的模型路径派生 —— Rust 不另猜
/// 一套目录策略（口径见 `lib/util/get_path.dart` 的注释）。所有 mImage 模型都在同一个
/// `super_resolution/mimage_onnx/` 下，所以进程内第一次算出来的就是大家共用的那一份。
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn coreml_cache_dir(model: &Path) -> PathBuf {
    let dir = model.parent().unwrap_or(model).join(".coreml_cache");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn init_ort(model_path: &str) -> Result<()> {
    ORT_READY
        .get_or_init(|| {
            #[cfg(not(any(target_os = "macos", target_os = "ios")))]
            let _ = model_path;
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            let result = ort::init()
                .with_name("rossi-mimage-onnx")
                .with_execution_providers([ep::CoreML::default()
                    .with_compute_units(ep::coreml::ComputeUnits::All)
                    .with_model_cache_dir(coreml_cache_dir(Path::new(model_path)).display().to_string())
                    .build()
                    .error_on_failure()])
                .commit();
            #[cfg(target_os = "windows")]
            // DirectML 是唯一被允许的 EP：`error_on_failure()` 让注册失败在**建 session 时**
            // 报错（`init().commit()` 本身只把配置塞进全局 OnceLock，不会因 EP 不可用而失败），
            // 错误经 `mimage_onnx_upscale` 透到 Dart 侧弹 toast —— 不允许静默退回 CPU。
            let result = ort::init()
                .with_name("rossi-mimage-onnx")
                .with_execution_providers([ep::DirectML::default().build().error_on_failure()])
                .commit();
            #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
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
        let started = Instant::now();
        init_ort(&model_path)?;
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
        let decode_ms = started.elapsed().as_millis();
        let session_start = Instant::now();
        let session_key = format!("{model_path}:{}:{:?}", meta.len(), meta.modified()?);
        let sessions = SESSIONS.get_or_init(|| Mutex::new(HashMap::new()));
        let mut sessions = sessions
            .lock()
            .map_err(|_| anyhow!("mImage ONNX session cache poisoned"))?;
        let session_created = if !sessions.contains_key(&session_key) {
            // 本地重新导入同名模型后释放旧 session，避免反复安装积累内存。
            let prefix = format!("{model_path}:");
            sessions.retain(|key, _| !key.starts_with(&prefix));
            let mut builder = Session::builder()
                .map_err(|e| anyhow!("session builder: {e:?}"))?
                .with_optimization_level(ort::session::builder::GraphOptimizationLevel::Level3)
                .map_err(|e| anyhow!("session optimization: {e:?}"))?
                .with_intra_threads(1)
                .map_err(|e| anyhow!("session threads: {e:?}"))?;
            let session = builder
                .commit_from_file(&model_path)
                .map_err(|e| anyhow!("load model with ONNX Runtime: {e:?}"))?;
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
        let session_ms = session_start.elapsed().as_millis();
        let mut prepare_time = Duration::ZERO;
        let mut inference_time = Duration::ZERO;
        let mut merge_time = Duration::ZERO;
        let mut scale = None;
        let out_w = iw.saturating_mul(4);
        let out_h = ih.saturating_mul(4);
        let mut out = ImageBuffer::<Rgb<u8>, Vec<u8>>::new(out_w, out_h);
        let mut weights = vec![0.0f32; (out_w as usize).saturating_mul(out_h as usize)];
        let tiles = compute_tiles(iw, ih, tile as u32);
        let tile_count = tiles.len();
        // 单 worker 复用输入存储，ORT 只借用本次切片，避免逐块分配和清零。
        let mut data = vec![0.0f32; 3 * tile * tile];
        for tile_rect in tiles {
            let prepare_start = Instant::now();
            let x = tile_rect.x;
            let y = tile_rect.y;
            let tw = tile_rect.w as usize;
            let th = tile_rect.h as usize;
            if tw < tile || th < tile {
                data.fill(0.0);
            }
            for dy in 0..th {
                for dx in 0..tw {
                    let p = rgb.get_pixel(x + dx as u32, y + dy as u32).0;
                    for c in 0..3 {
                        data[c * tile * tile + dy * tile + dx] = p[c] as f32 / 255.0;
                    }
                }
            }
            let tensor = TensorRef::from_array_view(([1usize, 3, tile, tile], data.as_slice()))
                .map_err(|e| anyhow!("tensor: {e:?}"))?;
            prepare_time += prepare_start.elapsed();
            let inference_start = Instant::now();
            let outputs = session
                .run(ort::inputs![tensor])
                .map_err(|e| anyhow!("inference: {e:?}"))?;
            inference_time += inference_start.elapsed();
            let merge_start = Instant::now();
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
            // 每列的融合权重只算一次；逐行借用输出切片，保留原有融合公式。
            let horizontal: Vec<f32> = (0..crop_w).map(|dx| {
                let left = if first_x { ramp } else { dx as f32 };
                let right = if last_x { ramp } else { (crop_w - 1 - dx) as f32 };
                (left.min(right) / ramp).clamp(1e-4, 1.0)
            }).collect();
            let output_data = out.as_mut();
            for dy in 0..crop_h {
                let top = if first_y { ramp } else { dy as f32 };
                let bottom = if last_y { ramp } else { (crop_h - 1 - dy) as f32 };
                let wy = (top.min(bottom) / ramp).clamp(1e-4, 1.0);
                let row_start = (y as usize * s as usize + dy) * out_w as usize + x as usize * s as usize;
                let weight_row = &mut weights[row_start..row_start + crop_w];
                let output_row = &mut output_data[row_start * 3..(row_start + crop_w) * 3];
                let offset = dy * sw;
                let red = &raw[offset..offset + crop_w];
                let green = &raw[sh * sw + offset..sh * sw + offset + crop_w];
                let blue = &raw[2 * sh * sw + offset..2 * sh * sw + offset + crop_w];
                for (dx, pixel) in output_row.chunks_exact_mut(3).enumerate() {
                    let weight = wy * horizontal[dx];
                    let old_weight = weight_row[dx];
                    let new_weight = old_weight + weight;
                    for (channel, value) in [red[dx], green[dx], blue[dx]].into_iter().enumerate() {
                        pixel[channel] = ((pixel[channel] as f32 * old_weight
                            + value.clamp(0.0, 1.0) * 255.0 * weight)
                            / new_weight).round().clamp(0.0, 255.0) as u8;
                    }
                    weight_row[dx] = new_weight;
                }
            }
            merge_time += merge_start.elapsed();
        }
        let final_scale = scale.unwrap_or(4);
        let encode_start = Instant::now();
        out.save(&output_path)
            .with_context(|| format!("write output: {output_path}"))?;
        Ok(format!(
            "model={model_id} backend={ONNX_BACKEND} scale={final_scale}x input={iw}x{ih} output={}x{} model_bytes={} tile={} (requested_tile={tile_size}) session={} tiles={tile_count} decode_ms={decode_ms} session_ms={session_ms} prepare_ms={} inference_ms={} merge_ms={} encode_ms={} total_ms={}",
            out.width(),
            out.height(),
            meta.len(),
            tile,
            if session_created { "created" } else { "cached" },
            prepare_time.as_millis(),
            inference_time.as_millis(),
            merge_time.as_millis(),
            encode_start.elapsed().as_millis(),
            started.elapsed().as_millis(),
        ))
    })
    .await
    .map_err(|e| anyhow!(e.to_string()))?
}
