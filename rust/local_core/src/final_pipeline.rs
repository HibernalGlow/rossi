//! 最终呈现与 AI 超分增强流水线（复用自 mImageViewer `src/ai/final_pipeline.rs` 与 `src/ai/upscale.rs`）。
//!
//! 提供：
//! 1. `ModelKind`：超分/增强模型种类定义；
//! 2. `AiProcessSizeLimit` 与 `should_process_rect`：尺寸上限判定，避免超大图重复超分；
//! 3. `FinalAiExecutionOutput`：超分产出物封装；
//! 4. `compute_final_pipeline_keep_set`：保留集计算（用于显存淘汰控制）。

use crate::PagePixels;
use std::sync::Arc;

/// 使用可能な AI モデルの種類（对齐 mImageViewer `ModelKind`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModelKind {
    /// Real-ESRGAN x4plus（写真・CG、ノイズ除去強）
    UpscaleRealEsrganX4Plus,
    /// Real-ESRGAN Anime 6B（イラスト・アニメ、線画シャープ）
    UpscaleRealEsrganAnime6B,
    /// realesr-general-x4v3（高速軽量汎用）
    UpscaleRealEsrGeneralV3,
    /// Real-CUGAN 4x conservative（漫画、スクリーントーン保持）
    UpscaleRealCugan4x,
    /// 4x-NMKD-Siax-200k（写真、質感・テクスチャ保持）
    UpscaleNmkdSiax4x,
    /// JPEG ノイズ除去 (RealPLKSR)
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

/// AI 处理对象尺寸上限（长边 / 短边，对齐 mImageViewer `AiProcessSizeLimit`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiProcessSizeLimit {
    pub long_edge_px: u32,
    pub short_edge_px: u32,
}

impl AiProcessSizeLimit {
    /// 以正方形尺寸构建上限。
    pub fn square(px: u32) -> Self {
        Self {
            long_edge_px: px,
            short_edge_px: px,
        }
    }
}

impl Default for AiProcessSizeLimit {
    fn default() -> Self {
        // 默认 4096 x 4096，大于此尺寸的图片通常无需超分
        Self::square(4096)
    }
}

/// 判定图像长边与短边是否都在处理上限之内（对齐 mImageViewer `should_process_rect`）。
///
/// 无论横图还是竖图，均归一化为长边/短边比对。
pub fn should_process_rect(width: u32, height: u32, limit: AiProcessSizeLimit) -> bool {
    let long = width.max(height);
    let short = width.min(height);
    let limit_long = limit.long_edge_px.max(limit.short_edge_px);
    let limit_short = limit.long_edge_px.min(limit.short_edge_px);
    long < limit_long && short < limit_short
}

/// final pipeline 超分执行产出结果（对齐 mImageViewer `FinalAiExecutionOutput`）。
#[derive(Clone)]
pub struct FinalAiExecutionOutput {
    pub pixels: Arc<PagePixels>,
    pub source_width: u32,
    pub source_height: u32,
    pub scale: u32,
    pub used_upscale: bool,
    pub model_kind: ModelKind,
}

/// 计算 final_pipeline 的保留集页码列表（对齐 mImageViewer 保留集机制）。
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
