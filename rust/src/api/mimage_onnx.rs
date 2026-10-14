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
///
/// 值不是裸 `Session`：释放/驱逐时要向日志报「放掉了多少」（模型字节数），
/// 空闲驱逐需要「最近一次使用时刻」。会话空闲超过 [`SESSION_IDLE_TTL`]
/// 会被清掉（每次推理进锁时顺路清 + [`session_sweeper`] 周期兜底），
/// 用户换书后旧模型不再无限常驻。
static SESSIONS: OnceLock<Mutex<HashMap<String, CachedSession>>> = OnceLock::new();

struct CachedSession {
    session: Session,
    model_bytes: u64,
    last_used: Instant,
}

/// 会话空闲多久后释放。超分是逐页就地替换，翻页密集期重建会把每页多付一次
/// 模型加载（OCR 那边实测复用 15–103 ms vs 每页重建 1793–2381 ms，同一个理），
/// 所以阈值取 10 分钟：一卷读完歇下来的空档足够长，连续翻页又不会踩到重建。
const SESSION_IDLE_TTL: Duration = Duration::from_secs(10 * 60);

/// 周期清扫线程：每次驱逐只做一件事 —— 把空闲超时的会话从表里摘掉，
/// `Session` 一 drop，CoreML/DirectML 的模型资源就还给系统。
///
/// 为什么不能只靠「下次推理进锁时顺路清」：用户退出阅读器后可能再也不推理，
/// 那条路没人触发，几百 MB 就一直挂着（2026-10-10 用户反馈的正是这个）。
/// 线程在表空时退出，下一次建会话时重新拉起。
fn ensure_session_sweeper() {
    static SWEEPER_RUNNING: OnceLock<()> = OnceLock::new();
    if SWEEPER_RUNNING.set(()).is_err() {
        return;
    }
    std::thread::Builder::new()
        .name("mimage-onnx-session-sweeper".to_string())
        .spawn(|| {
            loop {
                std::thread::sleep(Duration::from_secs(60));
                let Some(sessions) = SESSIONS.get() else {
                    continue;
                };
                let mut guard = match sessions.lock() {
                    Ok(guard) => guard,
                    Err(_) => continue,
                };
                let before = guard.len();
                guard.retain(|_, cached| cached.last_used.elapsed() <= SESSION_IDLE_TTL);
                if guard.is_empty() {
                    if before > 0 {
                        log::info!(
                            "mImage ONNX: released {before} idle session(s) after {:?}",
                            SESSION_IDLE_TTL
                        );
                    }
                    // 表空了就不空转：让下一次建会话重新拉起清扫线程。
                    break;
                }
            }
        })
        .map(|_| ())
        .ok();
}
const TILE_OVERLAP: u32 = 32;

// tile 布局直接编译 mImageViewer 源码；保持 Rossi 的 overlap=32。
use rossi_local_core::ai_tiles::{compute_tiles, extract_tile};

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
                    .with_model_cache_dir(
                        coreml_cache_dir(Path::new(model_path))
                            .display()
                            .to_string(),
                    )
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
        "denoise_realplksr" => Ok("dejpg_realplksr_otf.onnx"),
        _ => Err(anyhow!("unknown mImage ONNX model: {model_id}")),
    }
}

fn model_output_scale(model_id: &str) -> u32 {
    if model_id == "denoise_realplksr" {
        1
    } else {
        4
    }
}

/// Run one mImage ONNX model and write a PNG. Upscalers output 4x; RealPLKSR
/// removes JPEG noise at 1x. Git-LFS pointer files are rejected before inference.
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
        let expected_scale = model_output_scale(&model_id);
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
        // 进锁先清一轮空闲超时的会话：无后台触发时这里就是唯一的清扫时机
        // （后台清扫线程见 `ensure_session_sweeper`）。持锁清是安全的 ——
        // 锁覆盖整个推理过程，不会打断进行中的推理。
        sessions.retain(|_, cached| cached.last_used.elapsed() <= SESSION_IDLE_TTL);
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
            ensure_session_sweeper();
            sessions.insert(
                session_key.clone(),
                CachedSession {
                    session,
                    model_bytes: meta.len(),
                    last_used: Instant::now(),
                },
            );
            true
        } else {
            false
        };
        let cached = sessions
            .get_mut(&session_key)
            .ok_or_else(|| anyhow!("mImage ONNX session cache insert failed"))?;
        cached.last_used = Instant::now();
        let session = &mut cached.session;
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
        let out_w = iw.saturating_mul(expected_scale);
        let out_h = ih.saturating_mul(expected_scale);
        let mut out = ImageBuffer::<Rgb<u8>, Vec<u8>>::new(out_w, out_h);
        let mut weights = vec![0.0f32; (out_w as usize).saturating_mul(out_h as usize)];
        let tiles = compute_tiles(iw, ih, tile as u32, TILE_OVERLAP);
        let tile_count = tiles.len();
        for tile_rect in tiles {
            let prepare_start = Instant::now();
            let x = tile_rect.x;
            let y = tile_rect.y;
            let tw = tile_rect.w as usize;
            let th = tile_rect.h as usize;
            // 直接使用上游 NCHW 与固定 tile 零填充；ORT 借用本次 tensor。
            let input = extract_tile(&rgb, &tile_rect, tile as u32);
            let data = input.as_slice().expect("upstream tile tensor is contiguous NCHW");
            let tensor = TensorRef::from_array_view(([1usize, 3, tile, tile], data))
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
            if s != expected_scale {
                return Err(anyhow!(
                    "mImage model {model_id} returned {s}x, expected {expected_scale}x output"
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
        let final_scale = scale.unwrap_or(expected_scale);
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

/// 主动交还全部 mImage ONNX 会话（含正在被后台清扫线程盯着的那份表）。
///
/// 调用时机 = **离开阅读器**（Dart 侧 `LocalReadSession.dispose`，与
/// `ocr_release_sessions` 同点）：换章不调，人还在读，下一页省下的模型
/// 加载才是应得的。返回释放的模型字节数合计（0 = 本进程没建过会话），
/// Dart 侧据此打日志。CoreML 的编译产物落在磁盘 `.coreml_cache`，
/// 这里放掉的只是内存里的模型，重载不需要重新编译。
#[frb]
pub async fn mimage_onnx_release_sessions() -> Result<u64> {
    tokio::task::spawn_blocking(move || {
        let Some(sessions) = SESSIONS.get() else {
            return Ok(0);
        };
        let mut guard = sessions
            .lock()
            .map_err(|_| anyhow!("mImage ONNX session cache poisoned"))?;
        let freed: u64 = guard.values().map(|cached| cached.model_bytes).sum();
        if freed > 0 {
            log::info!(
                "mImage ONNX: released {} session(s), {} bytes of models",
                guard.len(),
                freed
            );
        }
        guard.clear();
        Ok(freed)
    })
    .await
    .map_err(|e| anyhow!(e.to_string()))?
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{model_kind_file, model_output_scale};

    #[test]
    fn denoise_uses_its_fixed_one_x_model() {
        assert_eq!(
            model_kind_file("denoise_realplksr").unwrap(),
            "dejpg_realplksr_otf.onnx"
        );
        assert_eq!(model_output_scale("denoise_realplksr"), 1);
    }

    #[test]
    fn upscalers_remain_four_x() {
        for id in [
            "realcugan_4x",
            "realesrgan_anime6b",
            "realesrgan_x4plus",
            "realesr_general_v3",
            "nmkd_siax_4x",
        ] {
            assert!(model_kind_file(id).is_ok());
            assert_eq!(model_output_scale(id), 4);
        }
    }

    #[tokio::test]
    #[ignore = "runs a 28 MB ONNX model; use for local backend verification"]
    async fn realplksr_preserves_image_size() {
        let model = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../vendor/mimageviewer/models/dejpg_realplksr_otf.onnx");
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("input.png");
        let output = dir.path().join("output.png");
        image::RgbImage::from_pixel(16, 16, image::Rgb([80, 110, 140]))
            .save(&input)
            .unwrap();
        super::mimage_onnx_upscale(
            input.display().to_string(),
            output.display().to_string(),
            model.display().to_string(),
            "denoise_realplksr".to_string(),
            0,
        )
        .await
        .unwrap();
        assert_eq!(image::image_dimensions(output).unwrap(), (16, 16));
    }
}
