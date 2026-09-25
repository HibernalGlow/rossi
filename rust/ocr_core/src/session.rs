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
// 只有 CoreML 那条目录策略用得上 `PathBuf`；不挂 cfg 的话 Linux / Android 构建会报未使用。
#[cfg(any(target_os = "macos", target_os = "ios"))]
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Ep {
    /// 按「平台 + 哪一段模型」落到具体 EP（见 [Ep::resolve] 那张实测表）。
    ///
    /// 为什么需要它：单一 EP 在两个平台上都不是最优 —— Windows 上 DirectML 让识别快 4 倍、
    /// 擦字快 8.7 倍，但检测反而慢；macOS 上 CoreML 对这几个模型全都更慢。
    /// 所以「选一个 EP」这个问题本身问错了，得按段选。
    Auto,
    Cpu,
    CoreMl,
    DirectMl,
}

/// 流水线里的一段。EP 策略按段决定，不按「整个 OCR 会话」。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    Detect,
    Recognize,
    Inpaint,
}

impl Ep {
    pub fn label(self) -> &'static str {
        match self {
            Ep::Auto => "auto",
            Ep::Cpu => "cpu",
            Ep::CoreMl => "coreml",
            Ep::DirectMl => "directml",
        }
    }

    pub fn parse(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "auto" | "" => Ok(Ep::Auto),
            "cpu" => Ok(Ep::Cpu),
            "coreml" | "core_ml" => Ok(Ep::CoreMl),
            "directml" | "direct_ml" | "dml" => Ok(Ep::DirectMl),
            other => Err(anyhow!(
                "未知 EP：{other}（可选 auto / cpu / coreml / directml）"
            )),
        }
    }

    /// 把 [Ep::Auto] 落到具体 EP；显式选的就照办（显式选择被尊重，哪怕它更慢）。
    ///
    /// 数字都是实测（`docs/REFERENCE_RESEARCH.md` §8.6.3），不是猜的：
    /// - Windows（RTX 3090）：检测 cpu 151 ms / dml 209 ms → **cpu**；
    ///   识别 28 框 cpu 10 665 ms / dml 2 632 ms → **DirectML**；
    ///   擦字 LaMa cpu 12 494 ms / dml 1 438 ms → **DirectML**。
    /// - Apple Silicon：CoreML 对 det / encoder / LaMa 都更慢（§8.6.3、§8.6.4、§3.1）→ **cpu**。
    /// - 其余平台构建里根本没注册加速器 EP → **cpu**。
    pub fn resolve(self, stage: Stage) -> Ep {
        if self != Ep::Auto {
            return self;
        }
        #[cfg(target_os = "windows")]
        {
            match stage {
                Stage::Detect => Ep::Cpu,
                Stage::Recognize | Stage::Inpaint => Ep::DirectMl,
            }
        }
        #[cfg(not(target_os = "windows"))]
        {
            let _ = stage;
            Ep::Cpu
        }
    }
}

/// CoreML EP 的编译产物目录：落在模型旁边的 `.coreml_cache`。
///
/// 不设 `ModelCacheDirectory` 时 ORT **每次建 session 都把 .onnx 重编译一遍**，产物还丢在
/// 系统临时目录里（macOS 每天清一次）。目录从调用方传进来的模型路径派生，Rust 不另猜一套
/// 目录策略；与 `rust/src/api/mimage_onnx.rs` 同一口径、同一个 `.coreml_cache` 名字。
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn coreml_cache_dir(model: &Path) -> PathBuf {
    let dir = model.parent().unwrap_or(model).join(".coreml_cache");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn apply_accelerator(
    builder: ort::session::builder::SessionBuilder,
    ep: Ep,
    model: &Path,
) -> Result<ort::session::builder::SessionBuilder> {
    match ep {
        Ep::Auto => Err(anyhow!(
            "内部错误：Auto 应在 build_session 里就被 resolve 掉"
        )),
        Ep::CoreMl => builder
            .with_execution_providers([ort::ep::CoreML::default()
                .with_compute_units(ort::ep::coreml::ComputeUnits::All)
                .with_model_cache_dir(coreml_cache_dir(model).display().to_string())
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
    model: &Path,
) -> Result<ort::session::builder::SessionBuilder> {
    match ep {
        Ep::Auto => Err(anyhow!(
            "内部错误：Auto 应在 build_session 里就被 resolve 掉"
        )),
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
    // 这些构建上没有任何加速器 EP，用不到模型路径；下划线是「这里有意不用」，
    // 不是「还没写完」（Windows / Apple 那两版都要用它选 EP 与缓存目录）。
    _model: &Path,
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
pub fn build_session(model: &Path, ep: Ep, stage: Stage, intra_threads: usize) -> Result<Session> {
    let ep = ep.resolve(stage);
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
    let mut builder = apply_accelerator(builder, ep, model)?;
    builder
        .commit_from_file(model)
        .map_err(|e| anyhow!("加载 ONNX 模型失败（{}）：{e:?}", model.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_按平台与那一段模型落到具体_ep() {
        if cfg!(target_os = "windows") {
            // 检测：DirectML 反而慢（151 → 209 ms），所以 auto 给 cpu。
            assert_eq!(Ep::Auto.resolve(Stage::Detect), Ep::Cpu);
            // 识别与擦字：DirectML 分别快 4 倍与 8.7 倍。
            assert_eq!(Ep::Auto.resolve(Stage::Recognize), Ep::DirectMl);
            assert_eq!(Ep::Auto.resolve(Stage::Inpaint), Ep::DirectMl);
        } else {
            // Apple 上 CoreML 对这三个模型都更慢（§8.6.3 / §8.6.4），其余平台没有加速器 EP。
            for stage in [Stage::Detect, Stage::Recognize, Stage::Inpaint] {
                assert_eq!(Ep::Auto.resolve(stage), Ep::Cpu);
            }
        }
    }

    #[test]
    fn 显式选的_ep_一定照办哪怕更慢() {
        // 「auto 才是聪明选择」不等于可以无视用户显式选的值 —— 那是另一种骗人。
        assert_eq!(Ep::CoreMl.resolve(Stage::Detect), Ep::CoreMl);
        assert_eq!(Ep::Cpu.resolve(Stage::Inpaint), Ep::Cpu);
    }

    #[test]
    fn 解析接受_auto_与空串并拒绝未知值() {
        assert_eq!(Ep::parse("auto").unwrap(), Ep::Auto);
        assert_eq!(Ep::parse("").unwrap(), Ep::Auto);
        assert_eq!(Ep::parse("DIRECTML").unwrap(), Ep::DirectMl);
        assert!(Ep::parse("cuda").is_err());
        assert_eq!(Ep::Auto.label(), "auto");
    }
}
