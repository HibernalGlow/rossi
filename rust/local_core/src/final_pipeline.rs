//! Rossi 的 AI 兼容类型与显存保留窗口；不是 mImageViewer 完整 final pipeline 的移植。
//! AI 尺寸判定直接复用 `ai_size_limit` 的上游切片；ModelKind、输出类型与邻页保留集
//! 是 Rossi 适配，维护责任见 docs/mimageviewer-reuse-inventory.json。
//!
//! 提供：
//! 1. `ModelKind`：超分/增强模型种类定义；
//! 2. `AiProcessSizeLimit` 与 `should_process_rect`：尺寸上限判定，避免超大图重复超分；
//! 3. `FinalAiExecutionOutput`：超分产出物封装；
//! 4. `compute_final_pipeline_keep_set`：保留集计算（用于显存淘汰控制）。

use crate::PagePixels;
pub use crate::ai_size_limit::{AiProcessSizeLimit, should_process_rect};
use std::sync::Arc;

/// Rossi 可选模型标识，参照上游模型名称并含本地 CoreML 选项。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModelKind {
    /// Real-ESRGAN x4plus（照片、CG，降噪强）
    UpscaleRealEsrganX4Plus,
    /// Real-ESRGAN Anime 6B（插画、动画，线条锐利）
    UpscaleRealEsrganAnime6B,
    /// realesr-general-x4v3（高速轻量通用）
    UpscaleRealEsrGeneralV3,
    /// Real-CUGAN 4x conservative（漫画，保留网点）
    UpscaleRealCugan4x,
    /// 4x-NMKD-Siax-200k（照片，保留质感与纹理）
    UpscaleNmkdSiax4x,
    /// JPEG 降噪 (RealPLKSR)
    DenoiseRealplksr,
    /// 移动端 / Apple 原生 CoreML 模型 (waifu2x / Real-CUGAN 2x)
    NativeCoreML,
}

impl ModelKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            ModelKind::UpscaleRealEsrganX4Plus => "realesrgan_x4plus",
            ModelKind::UpscaleRealEsrganAnime6B => "realesrgan_anime6b",
            ModelKind::UpscaleRealEsrGeneralV3 => "realesr_general_v3",
            ModelKind::UpscaleRealCugan4x => "realcugan_4x",
            ModelKind::UpscaleNmkdSiax4x => "nmkd_siax_4x",
            ModelKind::DenoiseRealplksr => "denoise_realplksr",
            ModelKind::NativeCoreML => "native_coreml",
        }
    }

    pub fn display_label(&self) -> &'static str {
        match self {
            ModelKind::UpscaleRealEsrganX4Plus => "Real-ESRGAN x4+ (强降噪)",
            ModelKind::UpscaleRealEsrganAnime6B => "Real-ESRGAN Anime (线条锐利)",
            ModelKind::UpscaleRealEsrGeneralV3 => "Real-ESRGAN General (轻量高速)",
            ModelKind::UpscaleRealCugan4x => "Real-CUGAN 4x (漫画网点保护)",
            ModelKind::UpscaleNmkdSiax4x => "NMKD-Siax 4x (纹理细节)",
            ModelKind::DenoiseRealplksr => "JPEG 降噪 (RealPLKSR)",
            ModelKind::NativeCoreML => "Apple Neural Engine (CoreML 2x)",
        }
    }
}

/// Rossi 阅读器的超分输出协议；不是上游执行器的类型移植。
#[derive(Clone)]
pub struct FinalAiExecutionOutput {
    pub pixels: Arc<PagePixels>,
    pub source_width: u32,
    pub source_height: u32,
    pub scale: u32,
    pub used_upscale: bool,
    pub model_kind: ModelKind,
}

/// 计算 Rossi 连续邻页窗口的保留集页码。
///
/// 保留当前停驻页及其前后 `radius` 页的超分结果，其余页面的超分大图自动释放以控制显存。
pub fn compute_final_pipeline_keep_set(
    current_idx: usize,
    total_pages: usize,
    radius: usize,
) -> Vec<usize> {
    if total_pages == 0 {
        return Vec::new();
    }
    let start = current_idx.saturating_sub(radius);
    let end = (current_idx + radius + 1).min(total_pages);
    (start..end).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_should_process_rect() {
        let limit = AiProcessSizeLimit::square(2048);
        assert!(should_process_rect(1920, 1080, limit));
        assert!(should_process_rect(1080, 1920, limit)); // 竖图归一化
        assert!(!should_process_rect(3000, 1000, limit)); // 超过长边
        assert!(!should_process_rect(2048, 2048, limit)); // 等于上限也拒绝
    }

    #[test]
    fn test_compute_keep_set() {
        assert_eq!(compute_final_pipeline_keep_set(0, 10, 1), vec![0, 1]);
        assert_eq!(compute_final_pipeline_keep_set(5, 10, 1), vec![4, 5, 6]);
        assert_eq!(compute_final_pipeline_keep_set(9, 10, 1), vec![8, 9]);
    }
}
