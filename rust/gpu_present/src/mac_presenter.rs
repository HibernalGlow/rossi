//! Rossi macOS GPU 呈现器后端。
//!
//! 全尺寸解码与邻页预渲染复用双轨缓存；wgpu 完成视口缩放后同步回读，
//! 将 BGRA 结果写入 IOSurface 支撑的 CVPixelBuffer，交给 Flutter 合成。
//! 缓存命中时只复制已生成的视口像素，原图对比可旁路超分轨。

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::ambient::{sample_edge_palette, AmbientPalette};
use crate::enhance;
use crate::wgpu_resampler::WgpuResampler;
use anyhow::{anyhow, Context, Result};
use rossi_local_core::{
    compute_final_pipeline_keep_set, interleaved_prefetch_positions, LocalSource, PagePixels,
};

mod cache;
mod frame;
mod methods;

use cache::{CachedPage, PageCache};
use frame::{copy_pre_rendered_frame, PreRenderedFrame};

const PREFETCH_FORWARD: usize = 8; // 向前深度预取 8 页（对齐 mImageViewer 的 prefetch_forward）
const PREFETCH_BACK: usize = 4; // 向后预取 4 页（对齐 mImageViewer 的 prefetch_back）
const PREFETCH_POLL: Duration = Duration::from_millis(15);

#[derive(Debug, Clone, Copy, Default)]
pub struct PresentTimings {
    pub decode_ms: f64,
    pub render_ms: f64,
    pub total_ms: f64,
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

#[derive(Default, Clone)]
struct PrefetchView {
    anchor: Option<usize>,
    page_count: usize,
    last_show_at: Option<Instant>,
    epoch: u64,
    source: Option<Arc<LocalSource>>,
    target_width: u32,
    target_height: u32,
}

#[derive(Default)]
struct PrefetchShared {
    view: PrefetchView,
    anchors_posted: u64,
}

struct PrefetchHub {
    shared: Mutex<PrefetchShared>,
    cv: Condvar,
    stop: AtomicBool,
    enabled: AtomicBool,
}

impl PrefetchHub {
    fn new(target_width: u32, target_height: u32) -> Self {
        let mut shared = PrefetchShared::default();
        shared.view.target_width = target_width;
        shared.view.target_height = target_height;
        Self {
            shared: Mutex::new(shared),
            cv: Condvar::new(),
            stop: AtomicBool::new(false),
            enabled: AtomicBool::new(true),
        }
    }

    fn set_anchor(
        &self,
        anchor: usize,
        page_count: usize,
        epoch: u64,
        target_width: u32,
        target_height: u32,
        source: Option<Arc<LocalSource>>,
    ) {
        if let Ok(mut g) = self.shared.lock() {
            g.anchors_posted += 1;
            g.view.anchor = Some(anchor);
            g.view.page_count = page_count;
            g.view.last_show_at = Some(Instant::now());
            g.view.epoch = epoch;
            g.view.target_width = target_width;
            g.view.target_height = target_height;
            g.view.source = source;
        }
        self.cv.notify_all();
    }

    fn update_dimensions(&self, target_width: u32, target_height: u32) {
        if let Ok(mut g) = self.shared.lock() {
            g.view.target_width = target_width;
            g.view.target_height = target_height;
        }
        self.cv.notify_all();
    }

    fn clear_source(&self) {
        if let Ok(mut g) = self.shared.lock() {
            g.view.anchor = None;
            g.view.page_count = 0;
            g.view.source = None;
        }
        self.cv.notify_all();
    }

    fn snapshot(&self) -> Option<PrefetchView> {
        let g = self.shared.lock().ok()?;
        Some(g.view.clone())
    }

    fn epoch(&self) -> u64 {
        self.shared.lock().map(|g| g.view.epoch).unwrap_or(0)
    }
}

fn spawn_prefetch_worker(
    shared_cache: Arc<SharedCache>,
    hub: Arc<PrefetchHub>,
    resampler: Arc<Mutex<WgpuResampler>>,
) -> JoinHandle<()> {
    thread::Builder::new()
        .name("rossi-mac-prefetch".to_string())
        .spawn(move || prefetch_worker_loop(&shared_cache, &hub, &resampler))
        .expect("无法启动 macOS 预取线程")
}

fn prefetch_worker_loop(
    shared_cache: &SharedCache,
    hub: &PrefetchHub,
    resampler: &Arc<Mutex<WgpuResampler>>,
) {
    loop {
        {
            let Ok(guard) = hub.shared.lock() else { return };
            if hub.stop.load(Ordering::Relaxed) {
                return;
            }
            let _ = hub.cv.wait_timeout(guard, PREFETCH_POLL);
        }
        if hub.stop.load(Ordering::Relaxed) {
            return;
        }
        if !hub.enabled.load(Ordering::Relaxed) {
            continue;
        }

        let Some(view) = hub.snapshot() else { return };
        let (Some(anchor), Some(source)) = (view.anchor, view.source.clone()) else {
            continue;
        };
        if view.page_count == 0 {
            continue;
        }

        let mut candidates = Vec::with_capacity(PREFETCH_FORWARD + PREFETCH_BACK + 1);
        candidates.push(anchor); // 当前页最高优先级补齐预渲染！
        candidates.extend(interleaved_prefetch_positions(
            anchor,
            view.page_count,
            PREFETCH_FORWARD,
            PREFETCH_BACK,
        ));

        // 阶段 1：寻找下一个需要预取原图的目标页（按当前锚点深度优先：+1, +2, +3, +4, -1）
        let target = candidates.iter().copied().find(|index| {
            if let Ok(c) = shared_cache.cache.lock() {
                c.in_flight != Some(*index) && !c.has(*index, view.epoch)
            } else {
                false
            }
        });

        if let Some(index) = target {
            // 标记此页正在解码中
            if let Ok(mut c) = shared_cache.cache.lock() {
                c.in_flight = Some(index);
            }

            // 100% 全尺寸原图解码（带 zune-jpeg RGBA 原生直出加速）
            let decoded = source.page_pixels(index);

            let epoch_now = hub.epoch();
            if epoch_now == view.epoch {
                if let Ok(pixels) = decoded {
                    let pixels = Arc::new(pixels);
                    let mut pre_rendered = Vec::new();
                    if view.target_width > 0 && view.target_height > 0 {
                        let stride = view.target_width as usize * 4;
                        let mut bgra = vec![0u8; stride * view.target_height as usize];
                        if let Ok(mut r) = resampler.lock() {
                            if r.resample_to_buffer(
                                &pixels.rgba,
                                pixels.width,
                                pixels.height,
                                view.target_width,
                                view.target_height,
                                bgra.as_mut_ptr(),
                                stride,
                                false,
                            )
                            .is_ok()
                            {
                                pre_rendered.push(PreRenderedFrame {
                                    target_w: view.target_width,
                                    target_h: view.target_height,
                                    bgra: Arc::new(bgra),
                                    stride,
                                });
                            }
                        }
                    }

                    if let Ok(mut c) = shared_cache.cache.lock() {
                        c.in_flight = None;
                        let mut page = CachedPage::new_raw(index, view.epoch, Some(pixels));
                        page.pre_rendered_raw = pre_rendered;
                        c.insert(page);
                    }
                    // 唤醒可能正在等待该页的前台线程
                    shared_cache.cv.notify_all();
                    continue;
                }
            }

            // 失败或过期的处理
            if let Ok(mut c) = shared_cache.cache.lock() {
                c.in_flight = None;
                if epoch_now != view.epoch {
                    c.stale += 1;
                }
            }
            shared_cache.cv.notify_all();
            continue;
        }

        // 阶段 2：候选页的原图都已缓存，检查是否有页面尚未生成当前视口尺寸的预渲染帧
        if view.target_width > 0 && view.target_height > 0 {
            let need_render = candidates.iter().copied().find_map(|index| {
                let c = shared_cache.cache.lock().ok()?;
                let (pixels, enhanced) = c.get_unrendered_pixels(
                    index,
                    view.epoch,
                    view.target_width,
                    view.target_height,
                )?;
                Some((index, pixels, enhanced))
            });

            if let Some((index, pixels, enhanced)) = need_render {
                let stride = view.target_width as usize * 4;
                let mut bgra = vec![0u8; stride * view.target_height as usize];
                if let Ok(mut r) = resampler.lock() {
                    if r.resample_to_buffer(
                        &pixels.rgba,
                        pixels.width,
                        pixels.height,
                        view.target_width,
                        view.target_height,
                        bgra.as_mut_ptr(),
                        stride,
                        false,
                    )
                    .is_ok()
                    {
                        if let Ok(mut c) = shared_cache.cache.lock() {
                            // 存进**像素来源那一轨**：见 `get_unrendered_pixels` 的注释
                            // （存错桶会让原图对比显示超分图，并让这里每 15 ms 空转一次）。
                            let frame = PreRenderedFrame {
                                target_w: view.target_width,
                                target_h: view.target_height,
                                bgra: Arc::new(bgra),
                                stride,
                            };
                            if enhanced {
                                c.add_pre_rendered_enhanced(index, view.epoch, frame);
                            } else {
                                c.add_pre_rendered(index, view.epoch, frame);
                            }
                        }
                    }
                }
                continue;
            }
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
}
