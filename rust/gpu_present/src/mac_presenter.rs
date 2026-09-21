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

use crate::ambient::{sample_edge_palette, AmbientPalette};
use crate::enhance;
use crate::wgpu_resampler::WgpuResampler;
use anyhow::{anyhow, Context, Result};
use rossi_local_core::{
    compute_final_pipeline_keep_set, interleaved_prefetch_positions, LocalSource, PagePixels,
};

mod methods;


/// 图片外透明，由 Flutter 绘制阅读器背景；预渲染帧补边也遵守同一约定。
pub const BACKGROUND_BGRA: [u8; 4] = [0, 0, 0, 0];

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
    // 缓存命中只增加引用计数；不能在持缓存锁时深拷贝整张视口。
    pub bgra: Arc<Vec<u8>>,
    pub stride: usize,
}

/// 缓存页面结构（对齐 mImageViewer 双轨缓存设计）。
///
/// 拥有原图（raw_pixels）与 AI 超分图（enhanced_pixels）双轨，
/// 以及各自对应的视口尺寸预渲染帧。
struct CachedPage {
    index: usize,
    epoch: u64,
    // 原图像素可被淘汰，但布局仍需要这页的宽高，不能沿用上一页的统计值。
    source_size: Option<(u32, u32)>,
    raw_pixels: Option<Arc<PagePixels>>,
    enhanced_pixels: Option<Arc<PagePixels>>,
    pre_rendered_raw: Vec<PreRenderedFrame>,
    pre_rendered_enhanced: Vec<PreRenderedFrame>,

    /// 阅读背景「自适应取色」的调色板，**随原图像素一起算好存在这里**。
    ///
    /// # 为什么要存在页缓存里，而不是每次呈现时现算
    ///
    /// 现算一次也几乎不花钱（见 `ambient` 模块：采样量与图片尺寸无关，几十个字节），
    /// 但「每次翻页算一次」和「每页算一次」是两种量级 —— 前者在**翻页关键路径**上，
    /// 后者在预取线程上。这里选后者：插页缓存的就是预取线程。
    ///
    /// # 为什么不跟随超分轨重算
    ///
    /// 超分只改锐度与尺寸，不改颜色分布。拿超分图重采一遍是纯粹的浪费 ——
    /// 而且它落在 Dart 注入超分图那条路上，那条路已经在做几十 MB 的搬运了。
    palette: Option<AmbientPalette>,
}

impl CachedPage {
    fn new_raw(index: usize, epoch: u64, pixels: Option<Arc<PagePixels>>) -> Self {
        Self {
            index,
            epoch,
            source_size: pixels.as_ref().map(|p| (p.source_width, p.source_height)),
            // 采样点就在这里：像素已经在手上，取色是**顺手**做的，不是另开一趟活。
            palette: pixels.as_deref().map(sample_edge_palette),
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

    fn find_frame_in(
        frames: &[PreRenderedFrame],
        target_w: u32,
        target_h: u32,
    ) -> Option<PreRenderedFrame> {
        if let Some(f) = frames
            .iter()
            .find(|f| f.target_w == target_w && f.target_h == target_h)
        {
            return Some(f.clone());
        }
        frames
            .iter()
            .find(|f| {
                (f.target_w as i64 - target_w as i64).abs() <= 3
                    && (f.target_h as i64 - target_h as i64).abs() <= 3
            })
            .cloned()
    }

    /// 级联解析视口预渲染帧（对齐 mImageViewer resolve_fs_display_tex 原版逻辑）：
    /// 1. 若 !bypass_enhanced 且存在 pre_rendered_enhanced，最优先命中！
    /// 2. 否则命中 pre_rendered_raw！
    fn resolve_display_frame(
        &self,
        target_w: u32,
        target_h: u32,
        bypass_enhanced: bool,
    ) -> Option<PreRenderedFrame> {
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
        // 规则本身在 `enhance` 里，与 Windows 侧、与 `stats` 报出的证据同源。
        enhance::prefers_enhanced(self.enhanced_pixels.is_some(), bypass_enhanced)
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
        self.pre_rendered_raw
            .retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered_raw.push(frame);
        if self.pre_rendered_raw.len() > 3 {
            self.pre_rendered_raw.remove(0);
        }
    }

    fn add_enhanced_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered_enhanced
            .retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
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
                let ep_len = e
                    .enhanced_pixels
                    .as_ref()
                    .map(|p| p.rgba.len())
                    .unwrap_or(0);
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

    /// 获取原图轨缓存，不参与超分轨选择。
    ///
    /// 邻页预取只负责准备原图。若这里复用普通的 [get]，超分图存在时会把
    /// enhanced_pixels 当成预取输入，随后又写回 raw 预渲染桶，导致两条轨相互污染，
    /// 并让预取线程反复重采样当前页。
    fn get_raw(
        &mut self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
    ) -> Option<(Option<Arc<PagePixels>>, Option<PreRenderedFrame>)> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        let frame = CachedPage::find_frame_in(&entry.pre_rendered_raw, target_w, target_h);
        let pixels = entry.raw_pixels.clone();
        self.entries.push_back(entry);
        Some((pixels, frame))
    }

    fn has(&self, index: usize, epoch: u64) -> bool {
        self.entries
            .iter()
            .any(|e| e.index == index && e.epoch == epoch)
    }

    /// 读某一页已采好的调色板。
    ///
    /// **只读**：不动 LRU 顺序，也不碰任何计数 —— 与 `get` / `get_raw` 是两回事。
    /// 它是**诊断/呈现的旁路**，不该因为被读了一次就把某一页挪到队尾，
    /// 那会让真正的预取淘汰顺序被读取行为带偏。
    fn palette_for(&self, index: usize, epoch: u64) -> Option<AmbientPalette> {
        self.entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)
            .and_then(|e| e.palette.clone())
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
                page.source_size = page.source_size.or(prev.source_size);
                if page.enhanced_pixels.is_none() {
                    page.enhanced_pixels = prev.enhanced_pixels.take();
                }
                if page.pre_rendered_enhanced.is_empty() {
                    page.pre_rendered_enhanced = std::mem::take(&mut prev.pre_rendered_enhanced);
                }
                // 调色板只由原图像素决定，而重插的条目常常是「只带预渲染帧、没带像素」
                // （`add_pre_rendered_enhanced` / `set_enhanced_pixels` 那条路）。
                // 不搬的话，已经被采过的那一页会在重插之后变成"没有背景色"——
                // 界面上表现为背景在翻页时闪回默认底色。
                if page.palette.is_none() {
                    page.palette = prev.palette.take();
                }
            }
        }
        self.entries.push_back(page);
        self.prefetched += 1;

        // 1. 如果带 raw pixels 的页面超过 MAX_RAW_PIXELS_COUNT，从最旧的页面卸载原图，保留视口预渲染帧！
        let raw_count = self
            .entries
            .iter()
            .filter(|e| e.raw_pixels.is_some())
            .count();
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
        let entry = self
            .entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)?;
        if entry
            .resolve_display_frame(target_w, target_h, false)
            .is_some()
        {
            None
        } else {
            let enhanced = entry.prefers_enhanced(false);
            entry.resolve_display_pixels(false).map(|p| (p, enhanced))
        }
    }

    /// 追加或更新页面的原图预渲染视口帧
    fn add_pre_rendered(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.add_raw_frame(frame);
        }
    }

    /// 追加或更新页面的超分增强预渲染视口帧
    fn add_pre_rendered_enhanced(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.add_enhanced_frame(frame);
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.add_enhanced_frame(frame);
            self.insert(page);
        }
    }

    /// 回填原图像素
    fn set_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            // 先补采再搬所有权：`raw_pixels` 那一行会把 `pixels` 移走。
            // 这里补的是「条目先被预渲染帧建出来、像素后到」的那条路
            // （`add_pre_rendered` → 预取线程回填），不补就等于这一页永远没有背景色。
            if entry.palette.is_none() {
                entry.palette = Some(sample_edge_palette(&pixels));
            }
            entry.source_size = Some((pixels.source_width, pixels.source_height));
            entry.raw_pixels = Some(pixels);
        }
    }

    /// 回填超分增强像素
    fn set_enhanced_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
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
        std::ptr::copy_nonoverlapping(frame.bgra.as_ptr(), dst_ptr, src_stride * copy_h);
    } else {
        let bg_pixel = u32::from_ne_bytes(BACKGROUND_BGRA);
        for y in 0..target_h as usize {
            let dst_row = dst_ptr.add(y * dst_stride);
            if y < copy_h {
                let src_row = frame.bgra.as_ptr().add(y * src_stride);
                std::ptr::copy_nonoverlapping(src_row, dst_row, copy_bytes);
                if (target_w as usize) > copy_w {
                    let fill_ptr = (dst_row as *mut u32).add(copy_w);
                    std::slice::from_raw_parts_mut(fill_ptr, (target_w as usize) - copy_w)
                        .fill(bg_pixel);
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

    mod gpu_cases;
}
