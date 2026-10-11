//! Rossi macOS GPU 呈现器后端。
//!
//! 全尺寸解码与邻页预渲染复用双轨缓存；wgpu 完成视口缩放后同步回读，
//! 将 BGRA 结果写入 IOSurface 支撑的 CVPixelBuffer，交给 Flutter 合成。
//! 缓存命中时只复制已生成的视口像素，原图对比可旁路超分轨。

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::ambient::{sample_edge_palette, AmbientPalette};
use crate::enhance;
use crate::wgpu_resampler::{ResampleTimings, WgpuResampler};
use anyhow::{anyhow, Context, Result};
use rossi_local_core::{
    compute_final_pipeline_keep_set, interleaved_prefetch_positions, LocalSource, PagePixels,
};

mod cache;
mod frame;
mod methods;
mod prefetch;

use cache::{CachedPage, PageCache};
use frame::{copy_pre_rendered_frame, PreRenderedFrame};
use prefetch::{spawn_prefetch_worker, PrefetchHub};

#[derive(Debug, Clone, Copy, Default)]
pub struct PresentTimings {
    pub decode_ms: f64,
    pub render_ms: f64,
    pub total_ms: f64,
    pub renderer_lock_ms: f64,
    pub cached_copy_ms: f64,
    pub frame_capture_ms: f64,
    pub frame_cache_publish_ms: f64,
    pub resample: ResampleTimings,
}

struct SharedCache {
    cache: Mutex<PageCache>,
    cv: Condvar,
}

impl SharedCache {
    fn new() -> Self {
        Self {
            cache: Mutex::new(PageCache::default()),
            cv: Condvar::new(),
        }
    }
}

/// macOS GPU 呈现器。
pub struct MacPresenter {
    target_width: u32,
    target_height: u32,
    source: Option<Arc<LocalSource>>,
    source_path: Option<PathBuf>,
    source_epoch: u64,
    page_count: usize,
    current_index: Option<usize>,
    generation: u64,

    shared_cache: Arc<SharedCache>,
    hub: Arc<PrefetchHub>,
    prefetch_thread: Option<JoinHandle<()>>,
    last_cache_hit: bool,
    last_prerender_hit: bool,

    /// 最近一次 `show_into_buffer` 那一帧**实际取自哪一轨**。
    ///
    /// `true` = 像素来自超分图；`false` = 来自原图（含"本来就没有超分图"与
    /// "用户正在原图对比"两种）。它是「超分替换有没有真的生效」唯一可核对的证据：
    /// 呈现器自己报，而不是 Dart 侧从"我调过 show"推断 —— 推断错就是这个 bug 的
    /// 表现（日志说成功、画面还是原图）。见 `stats_json` 的 `usedEnhanced`。
    last_used_enhanced: bool,

    /// 原图预览对比旁路（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）。
    /// 类型来自 `enhance` —— Windows 侧共用同一份语义。
    original_preview: enhance::Bypass,

    resampler: Arc<Mutex<WgpuResampler>>,

    last_source_width: u32,
    last_source_height: u32,
    last_decoded_width: u32,
    last_decoded_height: u32,

    /// 最近一次 `show_into_buffer` 那一页的调色板（阅读背景「自适应取色」用）。
    ///
    /// # 它必须跟着 `current_index` 一起报
    ///
    /// Dart 侧读到它之后要**先核对 `currentIndex` 就是它刚 `show` 的那一页**，
    /// 否则翻页竞态下会把上一页的背景色配到这一页的画面上 —— 而那看起来
    /// 不像竞态，像"取色不准"，事后极难查。
    ///
    /// # 它不参与任何判定
    ///
    /// 纯报给界面的一路数据：不选轨、不影响任何呈现分支、不进
    /// `last_used_enhanced` 那类"证据"字段。取不到就是 `null`，
    /// Dart 侧当作"这一页没有自适应背景"，继续用静态底色。
    last_ambient: Option<AmbientPalette>,

    init_ms: f64,
    presents: u64,
    last: PresentTimings,
}

#[cfg(test)]
mod tests {
    use super::*;

    mod frame_cases;
    mod gpu_cases;
    mod texture_cases;
    mod timing_cases;
}
