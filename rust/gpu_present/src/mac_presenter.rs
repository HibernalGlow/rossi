//! Rossi macOS GPU 呈现器后端。
//!
//! 在 macOS 统一内存架构（UMA）下，通过与 `IOSurface` 支撑的 `CVPixelBuffer` 配合，
//! 实现真正的零额外拷贝上屏：
//!
//! 1. `LocalSource` 归档直读（CBZ / CBR / 散图文件夹）；
//! 2. 100% 全尺寸原图解码（无损画质，绝不降采样压缩原图）；
//! 3. 极速 zune-jpeg 原生直出 RGBA 像素矩阵，消除中间分配与单线程慢拷贝；
//! 4. 后台线程 0 延迟即时预取 + 前向 4 页深度流水线；
//! 5. 前后台 In-Flight 协同等待，杜绝并发磁盘 IO 争抢与重复解码；
//! 6. 采用 `fast_image_resize`（Lanczos3 滤波）高质量平滑抗锯齿缩放到视口；
//! 7. 转换 BGRA 零拷贝直接写入 `CVPixelBuffer` 物理内存；
//! 8. Flutter Impeller (Metal) 零拷贝直接作为 Metal 纹理硬件合成上屏。

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use crate::wgpu_resampler::WgpuResampler;
use rossi_local_core::{
    compute_final_pipeline_keep_set, interleaved_prefetch_positions, LocalSource, PagePixels,
};

/// 留白背景色：BGRA 字节顺序对应 0xFF05050A（Rossi 深黑底色）。
/// 小端序内存排布：B=0x0A, G=0x05, R=0x05, A=0xFF。
pub const BACKGROUND_BGRA: [u8; 4] = [0x0A, 0x05, 0x05, 0xFF];

const PREFETCH_CAPACITY: usize = 16; // 视口预渲染帧保留 16 页（约 80 MB 内存，对齐 mImageViewer）
const MAX_RAW_PIXELS_COUNT: usize = 3; // 240 MB 的全尺寸原图只保留最近 3 页，防内存溢出
const PREFETCH_MAX_BYTES: usize = 1024 * 1024 * 1024; // 1 GB 绝对安全上限
const PREFETCH_FORWARD: usize = 8; // 向前深度预取 8 页（对齐 mImageViewer 的 prefetch_forward）
const PREFETCH_BACK: usize = 4; // 向后预取 4 页（对齐 mImageViewer 的 prefetch_back）
const PREFETCH_POLL: Duration = Duration::from_millis(15);

#[derive(Debug, Clone, Copy, Default)]
pub struct PresentTimings {
    pub decode_ms: f64,
    pub render_ms: f64,
    pub total_ms: f64,
}

/// 预渲染的最终 Letterbox 视口帧（含留白背景）。
#[derive(Clone)]
pub struct PreRenderedFrame {
    pub target_w: u32,
    pub target_h: u32,
    pub bgra: Vec<u8>,
    pub stride: usize,
}

/// 缓存页面结构（对齐 mImageViewer 双轨缓存设计）。
///
/// 拥有原图（raw_pixels）与 AI 超分图（enhanced_pixels）双轨，
/// 以及各自对应的视口尺寸预渲染帧。
struct CachedPage {
    index: usize,
    epoch: u64,
    raw_pixels: Option<Arc<PagePixels>>,
    enhanced_pixels: Option<Arc<PagePixels>>,
    pre_rendered_raw: Vec<PreRenderedFrame>,
    pre_rendered_enhanced: Vec<PreRenderedFrame>,
}

impl CachedPage {
    fn new_raw(index: usize, epoch: u64, pixels: Option<Arc<PagePixels>>) -> Self {
        Self {
            index,
            epoch,
            raw_pixels: pixels,
            enhanced_pixels: None,
            pre_rendered_raw: Vec::new(),
            pre_rendered_enhanced: Vec::new(),
        }
    }

    /// 兼容性访问原图像素
    #[allow(dead_code)]
    fn pixels(&self) -> Option<Arc<PagePixels>> {
        self.raw_pixels.clone()
    }

    fn find_frame_in(frames: &[PreRenderedFrame], target_w: u32, target_h: u32) -> Option<PreRenderedFrame> {
        if let Some(f) = frames.iter().find(|f| f.target_w == target_w && f.target_h == target_h) {
            return Some(f.clone());
        }
        frames.iter().find(|f| {
            (f.target_w as i64 - target_w as i64).abs() <= 3
                && (f.target_h as i64 - target_h as i64).abs() <= 3
        }).cloned()
    }

    /// 级联解析视口预渲染帧（对齐 mImageViewer resolve_fs_display_tex 原版逻辑）：
    /// 1. 若 !bypass_enhanced 且存在 pre_rendered_enhanced，最优先命中！
    /// 2. 否则命中 pre_rendered_raw！
    fn resolve_display_frame(&self, target_w: u32, target_h: u32, bypass_enhanced: bool) -> Option<PreRenderedFrame> {
        if !bypass_enhanced {
            if let Some(f) = Self::find_frame_in(&self.pre_rendered_enhanced, target_w, target_h) {
                return Some(f);
            }
            if self.enhanced_pixels.is_some() {
                // 严禁在超分大图就绪时透出旧的原图预渲染视口帧！返回 None 触发现场从 enhanced_pixels 重新抗锯齿降采样
                return None;
            }
        }
        Self::find_frame_in(&self.pre_rendered_raw, target_w, target_h)
    }

    /// 这一页在当前模式下**会不会**用超分轨呈现。
    ///
    /// 单独抽出来（而不是内联进 [resolve_display_pixels]）是因为它还要当**证据**用：
    /// 「本次呈现用的是哪一轨」要能被外部核对，而证据只有和判定共用同一条规则才可信
    /// —— 各自写一遍，将来规则一改（比如加"只在放大倍率够时才用超分图"）就会出现
    /// 「画面是原图、证据说超分」的假证据，那正是这个 bug 的原形。
    fn prefers_enhanced(&self, bypass_enhanced: bool) -> bool {
        !bypass_enhanced && self.enhanced_pixels.is_some()
    }

    /// 级联解析像素（对齐 mImageViewer 原版逻辑）：
    /// 1. 若 !bypass_enhanced 且存在 enhanced_pixels，最优先命中！
    /// 2. 否则命中 raw_pixels！
    fn resolve_display_pixels(&self, bypass_enhanced: bool) -> Option<Arc<PagePixels>> {
        if self.prefers_enhanced(bypass_enhanced) {
            if let Some(ref enhanced) = self.enhanced_pixels {
                return Some(enhanced.clone());
            }
        }
        self.raw_pixels.clone()
    }

    #[allow(dead_code)]
    fn add_frame(&mut self, frame: PreRenderedFrame) {
        self.add_raw_frame(frame);
    }

    fn add_raw_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered_raw.retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered_raw.push(frame);
        if self.pre_rendered_raw.len() > 3 {
            self.pre_rendered_raw.remove(0);
        }
    }

    fn add_enhanced_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered_enhanced.retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered_enhanced.push(frame);
        if self.pre_rendered_enhanced.len() > 3 {
            self.pre_rendered_enhanced.remove(0);
        }
    }
}

#[derive(Default)]
struct PageCache {
    entries: VecDeque<CachedPage>,
    hits: u64,
    misses: u64,
    prefetched: u64,
    stale: u64,
    evicted: u64,
    in_flight: Option<usize>,
}

impl PageCache {
    fn bytes(&self) -> usize {
        self.entries
            .iter()
            .map(|e| {
                let p_len = e.raw_pixels.as_ref().map(|p| p.rgba.len()).unwrap_or(0);
                let ep_len = e.enhanced_pixels.as_ref().map(|p| p.rgba.len()).unwrap_or(0);
                let r_len: usize = e.pre_rendered_raw.iter().map(|f| f.bgra.len()).sum();
                let er_len: usize = e.pre_rendered_enhanced.iter().map(|f| f.bgra.len()).sum();
                p_len + ep_len + r_len + er_len
            })
            .sum()
    }

    /// 获取缓存页面（按级联规则解析像素与预渲染帧，不掏空缓存，移至 LRU 队列尾部）
    fn get(
        &mut self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
        bypass_enhanced: bool,
    ) -> Option<(Option<Arc<PagePixels>>, Option<PreRenderedFrame>)> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        let frame = entry.resolve_display_frame(target_w, target_h, bypass_enhanced);
        let pixels = entry.resolve_display_pixels(bypass_enhanced);
        self.entries.push_back(entry);
        Some((pixels, frame))
    }

    fn has(&self, index: usize, epoch: u64) -> bool {
        self.entries
            .iter()
            .any(|e| e.index == index && e.epoch == epoch)
    }

    /// 插入页面（按 `(index, epoch)` 去重：重复时替换旧条目并移到 LRU 尾部）。
    ///
    /// # 它写的是「原图轨」，但**不能顺手把「超分轨」抹掉**
    ///
    /// 三处调用写的都是原图：后台预取线程解完原图、`show_into_buffer` 的缓存未命中
    /// 与 in-flight 回填。而超分图是**另一条线程**异步填进**同一个 `(index, epoch)`
    /// 条目**的（Dart 侧超分跑完 → `set_enhanced_pixels`）。两边并发时会出现这个时序：
    ///
    /// 1. 预取线程选中第 7 页，`in_flight = Some(7)`，开始解原图（几百毫秒）；
    /// 2. 超分注入完成，页 7 条目带上 `enhanced_pixels` + `pre_rendered_enhanced`；
    /// 3. 预取线程解完，`insert(CachedPage::new_raw(7, …))`。
    ///
    /// 早先的实现是无条件 `retain` 掉旧条目再 push 新条目，第 3 步就把第 2 步刚注入的
    /// 超分轨**整条抹掉**：下一次 `show` 静默渲染回原图。后果还不止画面 ——
    /// Dart 侧已经按「注入成功」记了账（`_enhancedIndices`），这一页整场都不会再重试，
    /// 于是表现成「日志说超分成功、画面一直是原图」（虚报替换成功）。
    ///
    /// 所以替换时要把旧条目的超分轨**搬**到新条目上：`take` 而非 clone（超分大图
    /// 是几十 MB 的 `Arc`，视口帧也是几十 MB 的 BGRA，没必要复制）；新条目自带超分轨
    /// 时以新的为准。
    fn insert(&mut self, mut page: CachedPage) {
        if let Some(at) = self
            .entries
            .iter()
            .position(|e| e.index == page.index && e.epoch == page.epoch)
        {
            if let Some(mut prev) = self.entries.remove(at) {
                if page.enhanced_pixels.is_none() {
                    page.enhanced_pixels = prev.enhanced_pixels.take();
                }
                if page.pre_rendered_enhanced.is_empty() {
                    page.pre_rendered_enhanced = std::mem::take(&mut prev.pre_rendered_enhanced);
                }
            }
        }
        self.entries.push_back(page);
        self.prefetched += 1;

        // 1. 如果带 raw pixels 的页面超过 MAX_RAW_PIXELS_COUNT，从最旧的页面卸载原图，保留视口预渲染帧！
        let raw_count = self.entries.iter().filter(|e| e.raw_pixels.is_some()).count();
        if raw_count > MAX_RAW_PIXELS_COUNT {
            let to_drop = raw_count - MAX_RAW_PIXELS_COUNT;
            let mut dropped = 0;
            for entry in self.entries.iter_mut() {
                if entry.raw_pixels.is_some() && !entry.pre_rendered_raw.is_empty() {
                    entry.raw_pixels = None;
                    dropped += 1;
                    if dropped >= to_drop {
                        break;
                    }
                }
            }
        }

        // 2. 如果总页数超过 PREFETCH_CAPACITY 或字节超过上限，pop_front 驱逐最老条目
        while self.entries.len() > PREFETCH_CAPACITY || self.bytes() > PREFETCH_MAX_BYTES {
            if self.entries.pop_front().is_some() {
                self.evicted += 1;
            }
        }
    }

    /// 查找已缓存像素但尚未对当前视口尺寸（含容差）预渲染的页面，
    /// 并**说明这些像素来自哪一轨**。
    ///
    /// 返回的 `bool` 不能省：超分轨的像素必须回填进 `pre_rendered_enhanced`。
    /// 存错桶有两个后果，都属于"画面不是它该有的样子"：
    /// - **原图对比会显示超分图**：旁路态下 `resolve_display_frame` 会去翻
    ///   `pre_rendered_raw`，那里躺着一张由超分像素缩出来的帧；
    /// - **每 15 ms 重采样一次当前页**：`resolve_display_frame` 对超分轨有
    ///   「宁可现场重画、也不透出旧帧」的判据（`enhanced_pixels.is_some()` 时返回
    ///   `None`），所以存错桶之后预取线程每次轮询都认为"这一页还没预渲染"，
    ///   于是不停地重采样 —— 白白烧 CPU，还一直抢那个 resampler 锁。
    fn get_unrendered_pixels(
        &self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
    ) -> Option<(Arc<PagePixels>, bool)> {
        let entry = self.entries.iter().find(|e| e.index == index && e.epoch == epoch)?;
        if entry.resolve_display_frame(target_w, target_h, false).is_some() {
            None
        } else {
            let enhanced = entry.prefers_enhanced(false);
            entry.resolve_display_pixels(false).map(|p| (p, enhanced))
        }
    }

    /// 追加或更新页面的原图预渲染视口帧
    fn add_pre_rendered(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.add_raw_frame(frame);
        }
    }

    /// 追加或更新页面的超分增强预渲染视口帧
    fn add_pre_rendered_enhanced(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.add_enhanced_frame(frame);
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.add_enhanced_frame(frame);
            self.insert(page);
        }
    }

    /// 回填原图像素
    fn set_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.raw_pixels = Some(pixels);
        }
    }

    /// 回填超分增强像素
    fn set_enhanced_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.enhanced_pixels = Some(pixels);
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.enhanced_pixels = Some(pixels);
            self.insert(page);
        }
    }

    /// 这一页当前会不会用超分轨呈现。没有这一页时 `false`。
    ///
    /// 呈现路径**不得**用它来反推"我刚渲染的那一帧是哪一轨"：缓存里的状态可以在
    /// 「解引用」与「回填」之间被超分注入改掉，回头问缓存会把"刚插入的超分轨"
    /// 当成"这一帧的来源"，而那帧其实是用原图像素渲染的。要判断已渲染帧的轨，
    /// 只看**像素从哪来**（见 `show_into_buffer` 的 `rendered_enhanced`）。
    fn prefers_enhanced(&self, index: usize, epoch: u64, bypass_enhanced: bool) -> bool {
        self.entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)
            .map(|e| e.prefers_enhanced(bypass_enhanced))
            .unwrap_or(false)
    }

    /// 淘汰超出保留集的超分大图（对齐 mImageViewer evict_final_pipeline_cache_for_keep_set 原版函数）
    fn evict_final_pipeline_cache_for_keep_set(&mut self, keep_set: &[usize], epoch: u64) {
        for entry in self.entries.iter_mut() {
            if entry.epoch == epoch && !keep_set.contains(&entry.index) {
                entry.enhanced_pixels = None;
                entry.pre_rendered_enhanced.clear();
            }
        }
    }
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
                                    bgra,
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
                                bgra,
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

    /// 原图预览对比旁路标志（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）
    original_preview_active: AtomicBool,

    resampler: Arc<Mutex<WgpuResampler>>,

    last_source_width: u32,
    last_source_height: u32,
    last_decoded_width: u32,
    last_decoded_height: u32,

    init_ms: f64,
    presents: u64,
    last: PresentTimings,
}

impl MacPresenter {
    pub fn new(width: u32, height: u32) -> Result<Self> {
        let t0 = Instant::now();
        let target_width = width.max(1);
        let target_height = height.max(1);
        let shared_cache = Arc::new(SharedCache::new());
        let hub = Arc::new(PrefetchHub::new(target_width, target_height));

        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .context("无法获取 Metal / wgpu 图形适配器")?;

        // ── 纹理尺寸上限必须显式要 ──
        //
        // wgpu 的 `Limits::default()` 把 `max_texture_dimension_2d` 限在 8192，
        // 而漫画扫描件常见 8000–10000 px 宽（实测手上这本 AVIF 就是 9504）。
        // 超过上限时 `create_texture` 会走到 wgpu 的**默认错误处理器**，而它是
        // `panic!` —— 在 `extern "C"` 里面 panic 的结果是整个 App `abort`。
        //
        // 既然 8192 只是保守默认值而不是 Metal 的能力，就直接向适配器要它
        // 实际支持的上限。这里仍然取 `min(适配器, 16384)`：要超过适配器的值
        // 会让 `request_device` 直接失败，而 16384 已经盖住任何现实的漫画页。
        let adapter_limit = adapter.limits().max_texture_dimension_2d;
        let wanted_texture_dimension = adapter_limit.min(16384);
        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("rossi_mac_wgpu_device"),
                required_limits: wgpu::Limits {
                    max_texture_dimension_2d: wanted_texture_dimension,
                    ..wgpu::Limits::default()
                },
                ..Default::default()
            },
        ))
        .context("无法初始化 wgpu 逻辑设备")?;

        let resampler = Arc::new(Mutex::new(WgpuResampler::new(Arc::new(device), Arc::new(queue))?));
        let prefetch_thread = Some(spawn_prefetch_worker(shared_cache.clone(), hub.clone(), resampler.clone()));

        Ok(Self {
            target_width,
            target_height,
            source: None,
            source_path: None,
            source_epoch: 0,
            page_count: 0,
            current_index: None,
            generation: 1,
            shared_cache,
            hub,
            prefetch_thread,
            last_cache_hit: false,
            last_prerender_hit: false,
            last_used_enhanced: false,
            original_preview_active: AtomicBool::new(false),
            resampler,
            last_source_width: 0,
            last_source_height: 0,
            last_decoded_width: 0,
            last_decoded_height: 0,
            init_ms: t0.elapsed().as_secs_f64() * 1000.0,
            presents: 0,
            last: PresentTimings::default(),
        })
    }

    pub fn open(&mut self, path: &Path) -> Result<usize> {
        let src = LocalSource::open(path)
            .with_context(|| format!("macOS 呈现器打开来源失败: {}", path.display()))?;
        let count = src.len();
        let arc = Arc::new(src);

        self.source_epoch = self.source_epoch.wrapping_add(1);
        self.source = Some(arc.clone());
        self.source_path = Some(path.to_path_buf());
        self.page_count = count;
        self.current_index = None;

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.entries.clear();
            c.in_flight = None;
        }
        self.hub.clear_source();
        Ok(count)
    }

    pub fn resize(&mut self, width: u32, height: u32) -> Result<()> {
        if width == 0 || height == 0 {
            return Err(anyhow!("尺寸不能为零: {}x{}", width, height));
        }
        if self.target_width != width || self.target_height != height {
            self.target_width = width;
            self.target_height = height;
            self.generation = self.generation.wrapping_add(1);
            self.hub.update_dimensions(width, height);
        }
        Ok(())
    }

    pub fn set_prefetch(&self, enabled: bool) {
        self.hub.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    /// 只「准备」某一页：解码 + 生成当前视口尺寸的预渲染帧，**不碰上屏缓冲区**。
    ///
    /// # 为什么需要它
    ///
    /// [`Self::show_into_buffer`] 把「解码」「渲染」「占住那张唯一的上屏纹理」三件事
    /// 捆在一次调用里，而 `ImageSurface` 是唯一会调它的东西。阅读器为了避免多个 slot
    /// 抢同一张纹理（Ping-Pong 拔河 → 红黄闪），只让当前页挂 `ImageSurface` ——
    /// 于是邻页从「已经解好、画在旁边的 slot 里」退化成「翻到它才开始解」，
    /// 观感就是预加载消失、每页都要等那 400–500 ms。
    ///
    /// 这个方法把前两件事单独拿出来给邻页用：照常解码、照常把预渲染帧放进缓存
    /// （翻过去时 `show` 就能 <1 ms 命中），但**不写用户的 display buffer**，
    /// 所以不会跟当前页抢纹理。
    ///
    /// 锚点**不动**：锚点表达的是「用户在哪」，由 `show` 推进；邻页只负责把自己
    /// 那一页准备好，顺着锚点继续往前铺的活仍然归后台预取线程。
    pub fn prepare(&mut self, index: usize, target_width: u32, target_height: u32) -> Result<()> {
        let source = self.source.clone().ok_or_else(|| anyhow!("尚未打开来源"))?;
        if index >= self.page_count {
            return Err(anyhow!("页索引越界: {} >= {}", index, self.page_count));
        }
        let target_width = target_width.max(1);
        let target_height = target_height.max(1);

        // 目标尺寸推进给后台线程，免得它对着一组旧尺寸做预渲染。
        self.hub.update_dimensions(target_width, target_height);

        // ① 已经为这个尺寸渲染过 → 直接返回。翻回上一页走的就是这条，代价接近 0。
        {
            let mut c = self.shared_cache.cache.lock().unwrap_or_else(|p| p.into_inner());
            if c.get(index, self.source_epoch, target_width, target_height, false).is_some() {
                return Ok(());
            }
            // ② 已有别的线程在解这一页 → 交给它。重复解会争抢磁盘与 CPU，
            //    而它解完会自己预渲染（预取线程的阶段 2 就是干这个的）。
            if c.in_flight == Some(index) {
                return Ok(());
            }
            c.in_flight = Some(index);
        }

        // ③ 解码（缓存里有原图时只是取一份 Arc）
        let decoded = {
            let cached = {
                let mut c = self.shared_cache.cache.lock().unwrap_or_else(|p| p.into_inner());
                c.get(index, self.source_epoch, target_width, target_height, false)
                    .and_then(|(pixels, _)| pixels)
            };
            match cached {
                Some(p) => Ok(p),
                None => source.page_pixels(index).map(Arc::new),
            }
        };

        let pixels = match decoded {
            Ok(p) => p,
            Err(e) => {
                // 解码失败也必须清掉 in_flight，否则这一页永远没人再试。
                if let Ok(mut c) = self.shared_cache.cache.lock() {
                    c.in_flight = None;
                }
                return Err(anyhow!("解码第 {} 页失败: {e}", index));
            }
        };

        // ④ 渲染进一块临时缓冲（**不碰 dst_ptr**），再放进预渲染缓存
        let stride = target_width as usize * 4;
        let mut bgra = vec![0u8; stride * target_height as usize];
        let rendered = {
            let mut r = self.resampler.lock().unwrap_or_else(|p| p.into_inner());
            r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                bgra.as_mut_ptr(),
                stride,
                false,
            )
        };

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.in_flight = None;
            if c.has(index, self.source_epoch) {
                c.set_pixels(index, self.source_epoch, pixels);
            } else {
                c.insert(CachedPage::new_raw(index, self.source_epoch, Some(pixels)));
            }
        }
        rendered?;

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.add_pre_rendered(
                index,
                self.source_epoch,
                PreRenderedFrame {
                    target_w: target_width,
                    target_h: target_height,
                    bgra,
                    stride,
                },
            );
        }
        Ok(())
    }

    /// 解码并渲染当前页，直接写入 CVPixelBuffer 物理内存。
    pub fn show_into_buffer(
        &mut self,
        index: usize,
        dst_ptr: *mut u8,
        dst_stride: usize,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let t_total = Instant::now();
        if dst_ptr.is_null() {
            return Err(anyhow!("目标像素缓冲区指针为空"));
        }
        let source = self.source.clone().ok_or_else(|| anyhow!("尚未打开来源"))?;
        if index >= self.page_count {
            return Err(anyhow!("页索引越界: {} >= {}", index, self.page_count));
        }

        self.resize(target_width, target_height)?;

        // ① 检查预取缓存与 In-Flight 协同等待（彻底消除并发争抢）
        let t_decode = Instant::now();
        let mut decode_hit = false;
        let mut prerender_hit = false;

        let bypass_enhanced = self.is_original_preview();
        // 这一帧到底取自哪一轨。它在取缓存**同一个锁作用域里**顺手问掉：
        // 出了这个作用域，缓存就可能被超分注入或预取线程改写，证据与画面就不是
        // 同一件事了（见 `prefers_enhanced` 的注释）。
        let mut used_enhanced = false;
        let (pixels_opt, pre_rendered_opt) = {
            let mut c = self.shared_cache.cache.lock().unwrap();
            // 先尝试从缓存直接拿（对齐 mImageViewer 级联规则）
            if let Some((p, r)) = c.get(index, self.source_epoch, target_width, target_height, bypass_enhanced) {
                decode_hit = true;
                used_enhanced = c.prefers_enhanced(index, self.source_epoch, bypass_enhanced);
                (p, r)
            } else if c.in_flight == Some(index) {
                // 后台预取线程恰好正在解码这一页！等待后台完成，避免前台重复解引发 CPU/磁盘 IO 争抢
                let deadline = Instant::now() + Duration::from_millis(3000);
                while c.in_flight == Some(index) && Instant::now() < deadline {
                    let timeout = deadline.saturating_duration_since(Instant::now());
                    let (guard, _) = self.shared_cache.cv.wait_timeout(c, timeout).unwrap();
                    c = guard;
                }
                if let Some((p, r)) = c.get(index, self.source_epoch, target_width, target_height, bypass_enhanced) {
                    decode_hit = true;
                    used_enhanced = c.prefers_enhanced(index, self.source_epoch, bypass_enhanced);
                    (p, r)
                } else {
                    c.misses += 1;
                    drop(c);
                    let pixels = Arc::new(source.page_pixels(index)?);
                    if let Ok(mut c2) = self.shared_cache.cache.lock() {
                        c2.insert(CachedPage::new_raw(index, self.source_epoch, Some(pixels.clone())));
                    }
                    (Some(pixels), None)
                }
            } else {
                c.misses += 1;
                drop(c);
                let pixels = Arc::new(source.page_pixels(index)?);
                if let Ok(mut c2) = self.shared_cache.cache.lock() {
                    c2.insert(CachedPage::new_raw(index, self.source_epoch, Some(pixels.clone())));
                }
                (Some(pixels), None)
            }
        };
        let decode_ms = t_decode.elapsed().as_secs_f64() * 1000.0;
        self.last_cache_hit = decode_hit;

        // ② 呈现阶段：优先使用后台已预渲染好的最终视口帧（< 0.5 ms 零开销内存直拷）
        let t_render = Instant::now();
        if let Some(ref frame) = pre_rendered_opt {
            if (frame.target_w as i64 - target_width as i64).abs() <= 3
                && (frame.target_h as i64 - target_height as i64).abs() <= 3
            {
                prerender_hit = true;
                unsafe {
                    copy_pre_rendered_frame(frame, dst_ptr, dst_stride, target_width, target_height);
                }
            }
        }

        if !prerender_hit {
            // 未命中预渲染帧时（如刚调整窗口尺寸或超快连翻），现场使用自适应快速抗锯齿滤波渲染
            //
            // 这一帧是**哪一轨**，只能由「像素从哪来」决定：命中缓存来的像素按上面
            // 解析出的 `used_enhanced`；没命中就是刚解的原图。**不能回头去问缓存**
            // ——在"解引用（miss）→ 解码 → 回填"这段空隙里，超分注入可能刚插入
            // `enhanced_pixels`，回头问就会把这帧原图渲染的帧记成超分预渲染帧，
            // 于是超分轨被一张原图帧污染、证据也跟着骗人。
            let pixels_from_cache = pixels_opt.is_some();
            let rendered_enhanced = pixels_from_cache && used_enhanced;
            used_enhanced = rendered_enhanced;

            let pixels = match pixels_opt {
                Some(p) => p,
                None => {
                    let p = Arc::new(source.page_pixels(index)?);
                    if let Ok(mut c) = self.shared_cache.cache.lock() {
                        c.set_pixels(index, self.source_epoch, p.clone());
                    }
                    p
                }
            };

            self.last_source_width = pixels.source_width;
            self.last_source_height = pixels.source_height;
            self.last_decoded_width = pixels.width;
            self.last_decoded_height = pixels.height;

            let mut r = self.resampler.lock().unwrap_or_else(|p| p.into_inner());
            r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                dst_ptr,
                dst_stride,
                false,
            )?;
            // 现场渲染后，将当前视口尺寸保存到该页预渲染缓存中，后续再次访问即可瞬间命中
            let stride = target_width as usize * 4;
            let mut bgra = vec![0u8; stride * target_height as usize];
            if r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                bgra.as_mut_ptr(),
                stride,
                false,
            ).is_ok() {
                if let Ok(mut c) = self.shared_cache.cache.lock() {
                    let frame = PreRenderedFrame {
                        target_w: target_width,
                        target_h: target_height,
                        bgra,
                        stride,
                    };
                    if rendered_enhanced {
                        c.add_pre_rendered_enhanced(index, self.source_epoch, frame);
                    } else {
                        c.add_pre_rendered(index, self.source_epoch, frame);
                    }
                }
            }
        } else if let Some(ref p) = pixels_opt {
            self.last_source_width = p.source_width;
            self.last_source_height = p.source_height;
            self.last_decoded_width = p.width;
            self.last_decoded_height = p.height;
        }
        let render_ms = t_render.elapsed().as_secs_f64() * 1000.0;
        self.last_prerender_hit = prerender_hit;
        // 「本次呈现用了超分轨」的最终结论。落在 `self` 上而不是只进日志，是为了让
        // Dart 侧能**核对**替换到底有没有生效（`stats.probe.usedEnhanced`）——
        // 只发一条"已触发替换"的日志、无从核对，就是虚报的温床。
        self.last_used_enhanced = used_enhanced;

        eprintln!(
            "[Rossi GPU] show_into_buffer: index={}, prerender_hit={}, decode_hit={}, bypass_enhanced={}, used_enhanced={}",
            index, prerender_hit, decode_hit, bypass_enhanced, used_enhanced
        );

        self.current_index = Some(index);
        self.generation = self.generation.wrapping_add(1);
        self.presents += 1;

        let total_ms = t_total.elapsed().as_secs_f64() * 1000.0;
        self.last = PresentTimings {
            decode_ms,
            render_ms,
            total_ms,
        };

        // ③ 投递新锚点与最新视口尺寸，驱动后续全尺寸原图预取与后台预渲染流水线
        self.hub.set_anchor(
            index,
            self.page_count,
            self.source_epoch,
            target_width,
            target_height,
            Some(source),
        );

        // ④ 呈现完成后，按 mImageViewer 原版保留集策略淘汰超出范围的超分大图
        self.evict_final_pipeline_cache_for_keep_set(index);

        Ok(())
    }

    /// 开关原图对比旁路（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）
    pub fn set_original_preview(&self, active: bool) {
        self.original_preview_active.store(active, Ordering::Relaxed);
    }

    /// 查询当前是否处于原图对比旁路状态
    pub fn is_original_preview(&self) -> bool {
        self.original_preview_active.load(Ordering::Relaxed)
    }

    /// 注入异步超分完成的像素并预渲染进缓存（对齐 mImageViewer FinalComposite 机制）
    pub fn set_enhanced_pixels(
        &mut self,
        index: usize,
        pixels: Arc<PagePixels>,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let stride = target_width as usize * 4;
        let mut bgra = vec![0u8; stride * target_height as usize];
        let mut prerendered = false;

        if target_width > 0 && target_height > 0 {
            if let Ok(mut r) = self.resampler.lock() {
                if r.resample_to_buffer(
                    &pixels.rgba,
                    pixels.width,
                    pixels.height,
                    target_width,
                    target_height,
                    bgra.as_mut_ptr(),
                    stride,
                    false,
                )
                .is_ok()
                {
                    prerendered = true;
                }
            }
        }

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.set_enhanced_pixels(index, self.source_epoch, pixels.clone());
            if prerendered {
                c.add_pre_rendered_enhanced(
                    index,
                    self.source_epoch,
                    PreRenderedFrame {
                        target_w: target_width,
                        target_h: target_height,
                        bgra,
                        stride,
                    },
                );
            }
        }
        eprintln!(
            "[Rossi GPU] set_enhanced_pixels: index={}, prerendered={}, w={}, h={}",
            index, prerendered, pixels.width, pixels.height
        );
        Ok(())
    }

    /// 从图片文件（PNG/WebP/JPEG）加载超分后的大图，并生成预渲染视口帧存入双轨缓存
    pub fn set_enhanced_image(
        &mut self,
        index: usize,
        image_path: &str,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let bytes = std::fs::read(image_path)?;
        let pixels = rossi_local_core::decode::decode_rgba(&bytes)?;
        eprintln!(
            "[Rossi GPU] set_enhanced_image: index={}, path={}, decoded {}x{}",
            index, image_path, pixels.width, pixels.height
        );
        self.set_enhanced_pixels(index, Arc::new(pixels), target_width, target_height)
    }

    /// 淘汰超出保留集的超分大图（对齐 mImageViewer evict_final_pipeline_cache_for_keep_set 原版函数）
    pub fn evict_final_pipeline_cache_for_keep_set(&mut self, current_idx: usize) {
        if self.page_count == 0 {
            return;
        }
        let keep_set = compute_final_pipeline_keep_set(current_idx, self.page_count, 1);
        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.evict_final_pipeline_cache_for_keep_set(&keep_set, self.source_epoch);
        }
    }

    pub fn stats_json(&self) -> String {
        let (hits, misses, prefetched, bytes) = self
            .shared_cache
            .cache
            .lock()
            .map(|c| (c.hits, c.misses, c.prefetched, c.bytes()))
            .unwrap_or((0, 0, 0, 0));

        format!(
            "{{\"backend\":\"macos/metal-uma\",\
              \"width\":{},\
              \"height\":{},\
              \"generation\":{},\
              \"presents\":{},\
              \"cacheHit\":{},\
              \"prerenderHit\":{},\
              \"currentIndex\":{},\
              \"usedEnhanced\":{},\
              \"cacheHits\":{},\
              \"cacheMisses\":{},\
              \"cachePrefetched\":{},\
              \"cacheBytes\":{},\
              \"sourceWidth\":{},\
              \"sourceHeight\":{},\
              \"decodedWidth\":{},\
              \"decodedHeight\":{},\
              \"initMs\":{:.2},\
              \"decodeMs\":{:.2},\
              \"renderMs\":{:.2},\
              \"submitMs\":{:.2},\
              \"totalMs\":{:.2}}}",
            self.target_width,
            self.target_height,
            self.generation,
            self.presents,
            if self.last_cache_hit { 1 } else { 0 },
            if self.last_prerender_hit { 1 } else { 0 },
            self.current_index.map(|i| i as i64).unwrap_or(-1),
            if self.last_used_enhanced { 1 } else { 0 },
            hits,
            misses,
            prefetched,
            bytes,
            self.last_source_width,
            self.last_source_height,
            self.last_decoded_width,
            self.last_decoded_height,
            self.init_ms,
            self.last.decode_ms,
            self.last.render_ms,
            self.last.render_ms,
            self.last.total_ms,
        )
    }
}

impl Drop for MacPresenter {
    fn drop(&mut self) {
        self.hub.stop.store(true, Ordering::Relaxed);
        self.hub.cv.notify_all();
        if let Some(h) = self.prefetch_thread.take() {
            let _ = h.join();
        }
    }
}

/// 极速内存直拷：将预渲染好的视口帧直接写入 CVPixelBuffer 物理内存（< 0.5 ms 零开销）。
/// 支持目标微小尺寸差异（<= 3 像素容差）时的裁切与留白填补，避免因微小抖动产生昂贵的重新渲染。
unsafe fn copy_pre_rendered_frame(
    frame: &PreRenderedFrame,
    dst_ptr: *mut u8,
    dst_stride: usize,
    target_w: u32,
    target_h: u32,
) {
    let copy_w = frame.target_w.min(target_w) as usize;
    let copy_h = frame.target_h.min(target_h) as usize;
    let copy_bytes = copy_w * 4;
    let src_stride = frame.stride;

    if frame.target_w == target_w
        && frame.target_h == target_h
        && src_stride == dst_stride
        && src_stride == copy_bytes
    {
        // 尺寸与跨步完全一致且连续对齐，直接整块单次 memcpy
        std::ptr::copy_nonoverlapping(
            frame.bgra.as_ptr(),
            dst_ptr,
            src_stride * copy_h,
        );
    } else {
        let bg_pixel = u32::from_ne_bytes(BACKGROUND_BGRA);
        for y in 0..target_h as usize {
            let dst_row = dst_ptr.add(y * dst_stride);
            if y < copy_h {
                let src_row = frame.bgra.as_ptr().add(y * src_stride);
                std::ptr::copy_nonoverlapping(src_row, dst_row, copy_bytes);
                if (target_w as usize) > copy_w {
                    let fill_ptr = (dst_row as *mut u32).add(copy_w);
                    std::slice::from_raw_parts_mut(fill_ptr, (target_w as usize) - copy_w).fill(bg_pixel);
                }
            } else {
                let fill_ptr = dst_row as *mut u32;
                std::slice::from_raw_parts_mut(fill_ptr, target_w as usize).fill(bg_pixel);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mac_presenter_init_and_stats() {
        let presenter = MacPresenter::new(800, 600).expect("创建 MacPresenter 失败");
        let stats = presenter.stats_json();
        assert!(stats.contains("\"backend\":\"macos/metal-uma\""));
        assert!(stats.contains("\"width\":800"));
        assert!(stats.contains("\"height\":600"));
        assert!(stats.contains("\"prerenderHit\":0"));
    }

    #[test]
    fn test_wgpu_resample_letterbox() {
        let presenter = MacPresenter::new(4, 4).expect("创建 MacPresenter 失败");
        let mut r = presenter.resampler.lock().unwrap();

        // 2x1 横图放入 4x4 目标，上下留白
        let pixels = PagePixels {
            width: 2,
            height: 1,
            source_width: 2,
            source_height: 1,
            rgba: vec![
                255, 0, 0, 255, // (0,0) 红
                0, 255, 0, 255, // (1,0) 绿
            ],
        };

        let target_w = 4;
        let target_h = 4;
        let stride = target_w * 4;
        let mut buffer = vec![0u8; (target_h * stride) as usize];

        r.resample_to_buffer(
            &pixels.rgba,
            pixels.width,
            pixels.height,
            target_w,
            target_h,
            buffer.as_mut_ptr(),
            stride as usize,
            false,
        )
        .expect("GPU 重采样失败");

        let bg = BACKGROUND_BGRA;
        // y=0 行是上留白
        assert_eq!(&buffer[0..4], &bg);

        // y=3 行是下留白
        let bottom_bg_offset = (3 * stride) as usize;
        assert_eq!(&buffer[bottom_bg_offset..bottom_bg_offset + 4], &bg);
    }

    #[test]
    fn test_copy_with_tolerance_diff() {
        let frame = PreRenderedFrame {
            target_w: 10,
            target_h: 10,
            bgra: vec![123u8; 10 * 10 * 4],
            stride: 40,
        };

        // 模拟 1 像素微差（例如 10x10 拷入 10x9，或者 10x10 拷入 10x11）
        let target_w = 10;
        let target_h = 11;
        let stride = 40;
        let mut dst = vec![0u8; (target_h * stride) as usize];

        unsafe {
            copy_pre_rendered_frame(&frame, dst.as_mut_ptr(), stride as usize, target_w, target_h);
        }

        // 前 10 行应当完全匹配
        assert_eq!(&dst[0..400], &frame.bgra);
        // 第 11 行应当填充背景色
        let bg = BACKGROUND_BGRA;
        assert_eq!(&dst[400..404], &bg);
    }

    /// 验证对齐 mImageViewer 原版设计的级联解析、原图对比旁路与保留集显存淘汰
    #[test]
    fn test_cascade_resolution_and_original_preview_and_keep_set() {
        let epoch = 1;
        let red_raw = Arc::new(PagePixels {
            width: 1,
            height: 1,
            source_width: 1,
            source_height: 1,
            rgba: vec![255, 0, 0, 255],
        });
        let blue_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 0, 255, 255].repeat(4),
        });

        // 1. 只有原图时：级联解析必定命中原图（原图秒开保底）
        let mut page0 = CachedPage::new_raw(0, epoch, Some(red_raw.clone()));
        assert_eq!(page0.resolve_display_pixels(false).unwrap().rgba, red_raw.rgba);

        // 2. 超分增强图生成后：普通模式下优先命中超分图（平滑替换）
        page0.enhanced_pixels = Some(blue_enhanced.clone());
        assert_eq!(page0.resolve_display_pixels(false).unwrap().rgba, blue_enhanced.rgba);

        // 3. 原图对比旁路模式（bypass_enhanced = true）：瞬时绕过超分图，返回原图
        assert_eq!(page0.resolve_display_pixels(true).unwrap().rgba, red_raw.rgba);

        // 4. Keep-Set 显存控制测试：超出保留集的超分大图自动被淘汰，原图完好保留
        let mut page4 = CachedPage::new_raw(4, epoch, Some(red_raw.clone()));
        page4.enhanced_pixels = Some(blue_enhanced.clone());

        let mut cache = PageCache::default();
        cache.insert(page0);
        cache.insert(page4);

        // 当前位于第 0 页，保留集为 [0, 1]
        let keep_set = compute_final_pipeline_keep_set(0, 5, 1);
        assert_eq!(keep_set, vec![0, 1]);

        cache.evict_final_pipeline_cache_for_keep_set(&keep_set, epoch);

        // 页 0 在保留集中：超分增强图完整保留
        let (p0, _) = cache.get(0, epoch, 800, 600, false).unwrap();
        assert_eq!(p0.unwrap().rgba, blue_enhanced.rgba);

        // 页 4 超出保留集：超分增强图被释放，降级回退至原图，显存安全释放
        let (p4, _) = cache.get(4, epoch, 800, 600, false).unwrap();
        assert_eq!(p4.unwrap().rgba, red_raw.rgba);
    }

    /// 回归：**原图回填不得抹掉超分轨**（「虚报替换成功」的根因）。
    ///
    /// 真实时序：预取线程先开始解第 7 页原图 → 超分注入完成（页 7 带上超分轨）
    /// → 预取线程解完，`insert(CachedPage::new_raw(7, …))` 回填原图。
    /// 旧实现在这里把超分轨整条抹掉，于是下一次 `show` 渲染回原图，而 Dart 侧那条
    /// 「超分成功 / 已替换呈现」的日志早就发出去了 —— 画面与日志各说各话。
    #[test]
    fn test_insert_raw_keeps_enhanced_track() {
        let epoch = 7;
        let red_raw = Arc::new(PagePixels {
            width: 1,
            height: 1,
            source_width: 1,
            source_height: 1,
            rgba: vec![255, 0, 0, 255],
        });
        let blue_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 0, 255, 255].repeat(4),
        });

        let mut cache = PageCache::default();

        // ① 超分先注入：条目只有超分轨（此时还没有原图像素）
        cache.set_enhanced_pixels(7, epoch, blue_enhanced.clone());
        cache.add_pre_rendered_enhanced(
            7,
            epoch,
            PreRenderedFrame {
                target_w: 100,
                target_h: 100,
                bgra: vec![0u8; 100 * 4 * 100],
                stride: 400,
            },
        );
        assert!(cache.prefers_enhanced(7, epoch, false));

        // ② 预取线程随后回填原图（走的是 insert，不是 set_pixels）
        cache.insert(CachedPage::new_raw(7, epoch, Some(red_raw.clone())));

        // ③ 超分轨必须还在：呈现仍应当取超分图，而不是静默退回原图
        let (pixels, frame) = cache.get(7, epoch, 100, 100, false).unwrap();
        assert_eq!(
            pixels.unwrap().rgba,
            blue_enhanced.rgba,
            "原图回填把超分张量抹掉了：画面会退回原图，而 Dart 侧仍报「替换成功」"
        );
        assert!(frame.is_some(), "原图回填把超分预渲染帧抹掉了");

        // ④ 反方向：新条目自带超分轨时，以新的为准（不能把回填的原图覆盖上去）
        let green_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 255, 0, 255].repeat(4),
        });
        cache.set_enhanced_pixels(7, epoch, green_enhanced.clone());
        assert_eq!(
            cache.get(7, epoch, 100, 100, false).unwrap().0.unwrap().rgba,
            green_enhanced.rgba
        );

        // ⑤ 原图对比旁路仍然要能瞬切回原图（超分轨在、但不参与呈现）
        assert!(!cache.prefers_enhanced(7, epoch, true));
    }

    /// 回归：**预渲染帧要进对桶**，以及"超分图已在、镜像尺寸变了"时不再空转。
    ///
    /// 预取线程阶段 2 的输入来自 `get_unrendered_pixels`。它拿到的可能是**超分轨**
    /// 的像素（超分图已注入、但当前视口尺寸还没有匹配的预渲染帧），那时帧必须进
    /// `pre_rendered_enhanced`：
    /// - 进错桶 → 原图对比（旁路）会把超分图当原图显示出来；
    /// - 进错桶 → `resolve_display_frame` 因为"超分图在、不许透出旧原图帧"仍返回
    ///   `None`，阶段 2 于是每次轮询（15 ms）都判定"还没渲染" → **持续空转**。
    #[test]
    fn test_unrendered_pixels_report_their_track() {
        let epoch = 3;
        let raw = Arc::new(PagePixels {
            width: 4,
            height: 4,
            source_width: 4,
            source_height: 4,
            rgba: vec![255, 0, 0, 255].repeat(16),
        });
        let enhanced = Arc::new(PagePixels {
            width: 8,
            height: 8,
            source_width: 4,
            source_height: 4,
            rgba: vec![0, 0, 255, 255].repeat(64),
        });

        let mut cache = PageCache::default();
        cache.insert(CachedPage::new_raw(0, epoch, Some(raw)));
        // 只有原图、且当前尺寸没有预渲染帧 → 要渲染，且来源是原图轨
        let (pixels, enhanced_flag) = cache.get_unrendered_pixels(0, epoch, 100, 100).unwrap();
        assert_eq!(pixels.rgba[0], 255);
        assert!(!enhanced_flag, "原图像素被报成了超分轨");

        // 注入超分图：现在来源是超分轨，桶也得跟着换
        cache.set_enhanced_pixels(0, epoch, enhanced.clone());
        let (pixels, enhanced_flag) = cache.get_unrendered_pixels(0, epoch, 100, 100).unwrap();
        assert_eq!(pixels.rgba, enhanced.rgba);
        assert!(enhanced_flag, "超分像素被报成了原图轨 —— 原图对比会显示超分图");

        // 按这个标志回填之后，同一尺寸就"已渲染"了 —— 预取线程不会再空转重采样
        cache.add_pre_rendered_enhanced(
            0,
            epoch,
            PreRenderedFrame {
                target_w: 100,
                target_h: 100,
                bgra: vec![0u8; 400 * 100],
                stride: 400,
            },
        );
        assert!(
            cache.get_unrendered_pixels(0, epoch, 100, 100).is_none(),
            "回填到正确的那一轨之后，同一尺寸不该再判定为'待渲染'（否则每 15ms 重采样一次）"
        );
    }

    #[test]
    fn test_set_enhanced_image_from_file() {
        let mut presenter = MacPresenter::new(100, 100).expect("初始化 MacPresenter 失败");
        let temp_dir = std::env::temp_dir();
        let png_path = temp_dir.join("test_sr_enhanced.png");

        let mut img = image::RgbaImage::new(4, 4);
        for pixel in img.pixels_mut() {
            *pixel = image::Rgba([0, 255, 0, 255]); // 绿色
        }
        img.save(&png_path).expect("保存测试 PNG 失败");

        // 注入超分图
        let res = presenter.set_enhanced_image(0, png_path.to_str().unwrap(), 100, 100);
        assert!(res.is_ok());

        // 清理临时文件
        let _ = std::fs::remove_file(png_path);
    }

    #[test]
    fn test_show_into_buffer_after_set_enhanced() {
        let mut presenter = MacPresenter::new(100, 100).expect("初始化 MacPresenter 失败");
        let temp_dir = std::env::temp_dir().join("test_rossi_comic_folder");
        let _ = std::fs::remove_dir_all(&temp_dir);
        std::fs::create_dir_all(&temp_dir).expect("创建测试文件夹失败");

        // 创建原图 000.png (红色)
        let raw_png = temp_dir.join("000.png");
        let mut red_img = image::RgbaImage::new(4, 4);
        for pixel in red_img.pixels_mut() {
            *pixel = image::Rgba([255, 0, 0, 255]); // 红色
        }
        red_img.save(&raw_png).expect("保存原图失败");

        // 打开来源
        presenter.open(&temp_dir).expect("打开来源失败");

        // 1. 第一次 show：上屏原图（红色）
        let mut dst = vec![0u8; 100 * 4 * 100];
        let show_raw = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_raw.is_ok());
        let idx = (50 * 100 + 50) * 4;
        println!("Initial raw: B={}, G={}, R={}, A={}", dst[idx], dst[idx+1], dst[idx+2], dst[idx+3]);
        assert_eq!(dst[idx+2], 255, "初次呈现应当为原图红色");
        // 证据必须是"没用超分轨"：Dart 侧就是靠它判断替换有没有生效
        assert!(
            presenter.stats_json().contains("\"usedEnhanced\":0"),
            "原图呈现时 usedEnhanced 应为 0，实际: {}",
            presenter.stats_json()
        );

        // 2. 模拟超分 Worker 生成了绿色超分大图并注入
        let sr_png = temp_dir.join("sr_000.png");
        let mut green_img = image::RgbaImage::new(8, 8);
        for pixel in green_img.pixels_mut() {
            *pixel = image::Rgba([0, 255, 0, 255]); // 绿色
        }
        green_img.save(&sr_png).expect("保存超分图失败");

        let res = presenter.set_enhanced_image(0, sr_png.to_str().unwrap(), 100, 100);
        assert!(res.is_ok());

        // 3. 再次 show（模拟 Swift handleShow 重新上屏）：应当原子替换为绿色！
        let show_sr = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_sr.is_ok());
        println!("After enhanced: B={}, G={}, R={}, A={}", dst[idx], dst[idx+1], dst[idx+2], dst[idx+3]);
        assert_eq!(dst[idx+1], 255, "G 通道应当为 255（超分绿色）");
        assert_eq!(dst[idx+2], 0, "R 通道应当为 0（原图红色已被平滑替换）");
        // 证据必须与画面一致：这一帧确实取自超分轨
        let stats = presenter.stats_json();
        assert!(
            stats.contains("\"currentIndex\":0") && stats.contains("\"usedEnhanced\":1"),
            "超分替换上屏后证据应当是 currentIndex=0 + usedEnhanced=1，实际: {stats}"
        );

        // 4. 原图对比旁路切换：应当毫秒级瞬切回红色
        presenter.set_original_preview(true);
        let show_orig_bypass = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_orig_bypass.is_ok());
        println!("After bypass: B={}, G={}, R={}, A={}", dst[idx], dst[idx+1], dst[idx+2], dst[idx+3]);
        assert_eq!(dst[idx+1], 0, "G 通道应当为 0");
        assert_eq!(dst[idx+2], 255, "R 通道应当为 255（瞬切回原图红色）");
        // 旁路态下证据也必须是 0，否则 Dart 侧会把"用户正在看原图"读成"替换生效"
        assert!(
            presenter.stats_json().contains("\"usedEnhanced\":0"),
            "旁路呈现时 usedEnhanced 应为 0，实际: {}",
            presenter.stats_json()
        );

        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}
