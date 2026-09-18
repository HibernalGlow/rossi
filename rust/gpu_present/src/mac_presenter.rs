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
use rossi_local_core::{interleaved_prefetch_positions, LocalSource, PagePixels};

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

struct CachedPage {
    index: usize,
    epoch: u64,
    pixels: Option<Arc<PagePixels>>,
    pre_rendered: Vec<PreRenderedFrame>,
}

impl CachedPage {
    fn find_frame(&self, target_w: u32, target_h: u32) -> Option<PreRenderedFrame> {
        // 1. 优先精确匹配
        if let Some(f) = self.pre_rendered.iter().find(|f| f.target_w == target_w && f.target_h == target_h) {
            return Some(f.clone());
        }
        // 2. 容差匹配：宽高差距 <= 3 像素以内视为有效命中（避免视口亚像素抖动）
        self.pre_rendered.iter().find(|f| {
            (f.target_w as i64 - target_w as i64).abs() <= 3
                && (f.target_h as i64 - target_h as i64).abs() <= 3
        }).cloned()
    }

    fn add_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered.retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered.push(frame);
        if self.pre_rendered.len() > 3 {
            self.pre_rendered.remove(0);
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
                let p_len = e.pixels.as_ref().map(|p| p.rgba.len()).unwrap_or(0);
                let r_len: usize = e.pre_rendered.iter().map(|f| f.bgra.len()).sum();
                p_len + r_len
            })
            .sum()
    }

    /// 获取缓存页面的原图与匹配尺寸的预渲染帧引用（不掏空缓存，移至 LRU 队列尾部）
    fn get(
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
        let frame = entry.find_frame(target_w, target_h);
        let pixels = entry.pixels.clone();
        self.entries.push_back(entry);
        Some((pixels, frame))
    }

    fn has(&self, index: usize, epoch: u64) -> bool {
        self.entries
            .iter()
            .any(|e| e.index == index && e.epoch == epoch)
    }

    fn insert(&mut self, page: CachedPage) {
        self.entries
            .retain(|e| !(e.index == page.index && e.epoch == page.epoch));
        self.entries.push_back(page);
        self.prefetched += 1;

        // 1. 如果带 raw pixels 的页面超过 MAX_RAW_PIXELS_COUNT，从最旧的页面卸载原图，保留视口预渲染帧！
        let raw_count = self.entries.iter().filter(|e| e.pixels.is_some()).count();
        if raw_count > MAX_RAW_PIXELS_COUNT {
            let to_drop = raw_count - MAX_RAW_PIXELS_COUNT;
            let mut dropped = 0;
            for entry in self.entries.iter_mut() {
                if entry.pixels.is_some() && !entry.pre_rendered.is_empty() {
                    entry.pixels = None;
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

    /// 查找已缓存像素但尚未对当前视口尺寸（含容差）预渲染的页面
    fn get_unrendered_pixels(
        &self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
    ) -> Option<Arc<PagePixels>> {
        let entry = self.entries.iter().find(|e| e.index == index && e.epoch == epoch)?;
        if entry.find_frame(target_w, target_h).is_some() {
            None
        } else {
            entry.pixels.clone()
        }
    }

    /// 追加或更新页面的预渲染视口帧
    fn add_pre_rendered(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.add_frame(frame);
        }
    }

    /// 回填原图像素
    fn set_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.index == index && e.epoch == epoch) {
            entry.pixels = Some(pixels);
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
                        c.insert(CachedPage {
                            index,
                            epoch: view.epoch,
                            pixels: Some(pixels),
                            pre_rendered,
                        });
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
                let pixels = c.get_unrendered_pixels(
                    index,
                    view.epoch,
                    view.target_width,
                    view.target_height,
                )?;
                Some((index, pixels))
            });

            if let Some((index, pixels)) = need_render {
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
                            c.add_pre_rendered(index, view.epoch, PreRenderedFrame {
                                target_w: view.target_width,
                                target_h: view.target_height,
                                bgra,
                                stride,
                            });
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
            if c.get(index, self.source_epoch, target_width, target_height).is_some() {
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
                c.get(index, self.source_epoch, target_width, target_height)
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
                c.insert(CachedPage {
                    index,
                    epoch: self.source_epoch,
                    pixels: Some(pixels),
                    pre_rendered: Vec::new(),
                });
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

        let (pixels_opt, pre_rendered_opt) = {
            let mut c = self.shared_cache.cache.lock().unwrap();
            // 先尝试从缓存直接拿
            if let Some((p, r)) = c.get(index, self.source_epoch, target_width, target_height) {
                decode_hit = true;
                (p, r)
            } else if c.in_flight == Some(index) {
                // 后台预取线程恰好正在解码这一页！等待后台完成，避免前台重复解引发 CPU/磁盘 IO 争抢
                let deadline = Instant::now() + Duration::from_millis(3000);
                while c.in_flight == Some(index) && Instant::now() < deadline {
                    let timeout = deadline.saturating_duration_since(Instant::now());
                    let (guard, _) = self.shared_cache.cv.wait_timeout(c, timeout).unwrap();
                    c = guard;
                }
                if let Some((p, r)) = c.get(index, self.source_epoch, target_width, target_height) {
                    decode_hit = true;
                    (p, r)
                } else {
                    c.misses += 1;
                    drop(c);
                    let pixels = Arc::new(source.page_pixels(index)?);
                    if let Ok(mut c2) = self.shared_cache.cache.lock() {
                        c2.insert(CachedPage {
                            index,
                            epoch: self.source_epoch,
                            pixels: Some(pixels.clone()),
                            pre_rendered: Vec::new(),
                        });
                    }
                    (Some(pixels), None)
                }
            } else {
                c.misses += 1;
                drop(c);
                let pixels = Arc::new(source.page_pixels(index)?);
                if let Ok(mut c2) = self.shared_cache.cache.lock() {
                    c2.insert(CachedPage {
                        index,
                        epoch: self.source_epoch,
                        pixels: Some(pixels.clone()),
                        pre_rendered: Vec::new(),
                    });
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
                    c.add_pre_rendered(index, self.source_epoch, PreRenderedFrame {
                        target_w: target_width,
                        target_h: target_height,
                        bgra,
                        stride,
                    });
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

        Ok(())
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
}
