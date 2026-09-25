//! ONNX 会话构建。**EP 按模型指定，且不许静默退回 CPU。**
//!
//! 依据是 ADR-0018 §决定 3.1 的实测：同一台 Apple Silicon 上，512² 稳态中位数
//! LaMa 是 CPU 1 656 ms / CoreML 3 825 ms（**CoreML 更慢**），AOT-GAN 是 CPU 5 916 ms /
//! CoreML 295 ms（快 20 倍）。所以「Apple 一律走 coreml」是错的，EP 必须跟着模型走。
//!
//! 因此调用方显式选 EP：选了 CoreML 而平台/构建不支持时**报错**，不退 CPU ——
//! 与 `lib/util/real_sr` 那条「不允许静默退回 CPU」的口径一致。

use anyhow::{Result, anyhow};
use ort::session::{Session, builder::GraphOptimizationLevel};
use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Ep {
    Cpu,
    CoreMl,
    DirectMl,
}

impl Ep {
    pub fn label(self) -> &'static str {
        match self {
            Ep::Cpu => "cpu",
            Ep::CoreMl => "coreml",
            Ep::DirectMl => "directml",
        }
    }

    pub fn parse(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "cpu" => Ok(Ep::Cpu),
            "coreml" | "core_ml" => Ok(Ep::CoreMl),
            "directml" | "direct_ml" | "dml" => Ok(Ep::DirectMl),
            other => Err(anyhow!("未知 EP：{other}（可选 cpu / coreml / directml）")),
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn apply_accelerator(
    builder: ort::session::builder::SessionBuilder,
    ep: Ep,
) -> Result<ort::session::builder::SessionBuilder> {
    match ep {
        Ep::CoreMl => builder
            .with_execution_providers([ort::ep::CoreML::default()
                .with_compute_units(ort::ep::coreml::ComputeUnits::All)
                .build()
                .error_on_failure()])
            .map_err(|e| anyhow!("注册 CoreML EP 失败（不静默退回 CPU）：{e:?}")),
        Ep::DirectMl => Err(anyhow!("DirectML 只在 Windows 构建里存在")),
        Ep::Cpu => Ok(builder),
    }
}

#[cfg(target_os = "windows")]
fn apply_accelerator(
    builder: ort::session::builder::SessionBuilder,
    ep: Ep,
) -> Result<ort::session::builder::SessionBuilder> {
    match ep {
        Ep::DirectMl => builder
            .with_execution_providers([ort::ep::DirectML::default().build().error_on_failure()])
            .map_err(|e| anyhow!("注册 DirectML EP 失败（不静默退回 CPU）：{e:?}")),
        Ep::CoreMl => Err(anyhow!("CoreML 只在 Apple 构建里存在")),
        Ep::Cpu => Ok(builder),
    }
}

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
fn apply_accelerator(
    builder: ort::session::builder::SessionBuilder,
    ep: Ep,
) -> Result<ort::session::builder::SessionBuilder> {
    match ep {
        Ep::Cpu => Ok(builder),
        other => Err(anyhow!(
            "本平台构建没有 {} 加速器 EP（只有 CPU）；不会静默退回 CPU",
            other.label()
        )),
    }
}

/// 建会话。`intra_threads = 1` 是 OCR 侧的默认：一页推理一次，多线程的收益抵不过
/// 与 Reader 渲染抢核；调用方要并行跑多页时再调高。
pub fn build_session(model: &Path, ep: Ep, intra_threads: usize) -> Result<Session> {
    if !model.is_file() {
        return Err(anyhow!("模型文件不存在：{}", model.display()));
    }
    // `ort::Error<SessionBuilder>` 不是 Send/Sync，用不了 `anyhow::Context` —— 只能 map_err + Debug。
    let builder = Session::builder().map_err(|e| anyhow!("ort session builder：{e:?}"))?;
    let builder = builder
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| anyhow!("设置图优化级别失败：{e:?}"))?;
    let builder = builder
        .with_intra_threads(intra_threads.max(1))
        .map_err(|e| anyhow!("设置 intra 线程数失败：{e:?}"))?;
    let mut builder = apply_accelerator(builder, ep)?;
    builder
        .commit_from_file(model)
        .map_err(|e| anyhow!("加载 ONNX 模型失败（{}）：{e:?}", model.display()))
}
