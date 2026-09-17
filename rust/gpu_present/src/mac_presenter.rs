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
use fast_image_resize::images::{Image, ImageRef};
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use rossi_local_core::{interleaved_prefetch_positions, LocalSource, PagePixels};

/// 留白背景色：BGRA 字节顺序对应 0xFF05050A（Rossi 深黑底色）。
/// 小端序内存排布：B=0x0A, G=0x05, R=0x05, A=0xFF。
pub const BACKGROUND_BGRA: [u8; 4] = [0x0A, 0x05, 0x05, 0xFF];

const PREFETCH_CAPACITY: usize = 8;
const PREFETCH_MAX_BYTES: usize = 512 * 1024 * 1024; // 512 MB，容纳超高清多页原图
const PREFETCH_FORWARD: usize = 4; // 向前深度预取 4 页
const PREFETCH_BACK: usize = 1; // 保留后退 1 页
const PREFETCH_POLL: Duration = Duration::from_millis(20);

#[derive(Debug, Clone, Copy, Default)]
pub struct PresentTimings {
    pub decode_ms: f64,
    pub render_ms: f64,
    pub total_ms: f64,
}

struct CachedPage {
    index: usize,
    epoch: u64,
    pixels: PagePixels,
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
        self.entries.iter().map(|e| e.pixels.rgba.len()).sum()
    }

    fn take(&mut self, index: usize, epoch: u64) -> Option<PagePixels> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        Some(entry.pixels)
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
        while self.entries.len() > PREFETCH_CAPACITY || self.bytes() > PREFETCH_MAX_BYTES {
            if self.entries.pop_front().is_some() {
                self.evicted += 1;
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

#[derive(Default)]
struct PrefetchView {
    anchor: Option<usize>,
    page_count: usize,
    last_show_at: Option<Instant>,
    epoch: u64,
    source: Option<Arc<LocalSource>>,
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
    fn new() -> Self {
        Self {
            shared: Mutex::new(PrefetchShared::default()),
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
        source: Option<Arc<LocalSource>>,
    ) {
        if let Ok(mut g) = self.shared.lock() {
            g.anchors_posted += 1;
            g.view.anchor = Some(anchor);
            g.view.page_count = page_count;
            g.view.last_show_at = Some(Instant::now());
            g.view.epoch = epoch;
            g.view.source = source;
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
        Some(PrefetchView {
            anchor: g.view.anchor,
            page_count: g.view.page_count,
            last_show_at: g.view.last_show_at,
            epoch: g.view.epoch,
            source: g.view.source.clone(),
        })
    }

    fn epoch(&self) -> u64 {
        self.shared.lock().map(|g| g.view.epoch).unwrap_or(0)
    }
}

fn spawn_prefetch_worker(
    shared_cache: Arc<SharedCache>,
    hub: Arc<PrefetchHub>,
) -> JoinHandle<()> {
    thread::Builder::new()
        .name("rossi-mac-prefetch".to_string())
        .spawn(move || prefetch_worker_loop(&shared_cache, &hub))
        .expect("无法启动 macOS 预取线程")
}

fn prefetch_worker_loop(shared_cache: &SharedCache, hub: &PrefetchHub) {
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

        // 寻找下一个需要预取的目标页（按当前锚点深度优先：+1, +2, +3, +4, -1）
        let target = interleaved_prefetch_positions(
            anchor,
            view.page_count,
            PREFETCH_FORWARD,
            PREFETCH_BACK,
        )
        .into_iter()
        .find(|index| {
            if let Ok(c) = shared_cache.cache.lock() {
                c.in_flight != Some(*index) && !c.has(*index, view.epoch)
            } else {
                false
            }
        });
        let Some(index) = target else { continue };

        // 标记此页正在解码中
        if let Ok(mut c) = shared_cache.cache.lock() {
            c.in_flight = Some(index);
        }

        // 100% 全尺寸原图解码（带 zune-jpeg RGBA 原生直出加速）
        let decoded = source.page_pixels(index);

        let epoch_now = hub.epoch();
        if let Ok(mut c) = shared_cache.cache.lock() {
            c.in_flight = None;
            match decoded {
                Ok(pixels) if epoch_now == view.epoch => c.insert(CachedPage {
                    index,
                    epoch: view.epoch,
                    pixels,
                }),
                Ok(_) => c.stale += 1,
                Err(_) => {}
            }
        }
        // 唤醒可能正在等待该页的前台线程
        shared_cache.cv.notify_all();
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

    resizer: Mutex<Resizer>,

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
        let shared_cache = Arc::new(SharedCache::new());
        let hub = Arc::new(PrefetchHub::new());
        let prefetch_thread = Some(spawn_prefetch_worker(shared_cache.clone(), hub.clone()));

        Ok(Self {
            target_width: width.max(1),
            target_height: height.max(1),
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
            resizer: Mutex::new(Resizer::new()),
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
        }
        Ok(())
    }

    pub fn set_prefetch(&self, enabled: bool) {
        self.hub.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn generation(&self) -> u64 {
        self.generation
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
        let mut hit = false;
        let pixels = {
            let mut c = self.shared_cache.cache.lock().unwrap();
            // 先尝试从缓存直接拿
            if let Some(p) = c.take(index, self.source_epoch) {
                hit = true;
                p
            } else if c.in_flight == Some(index) {
                // 后台预取线程恰好正在解码这一页！等待后台完成，避免前台重复解引发磁盘 IO 争抢
                let deadline = Instant::now() + Duration::from_millis(500);
                while c.in_flight == Some(index) && Instant::now() < deadline {
                    let timeout = deadline.saturating_duration_since(Instant::now());
                    let (guard, _) = self.shared_cache.cv.wait_timeout(c, timeout).unwrap();
                    c = guard;
                }
                if let Some(p) = c.take(index, self.source_epoch) {
                    hit = true;
                    p
                } else {
                    c.misses += 1;
                    drop(c);
                    source.page_pixels(index)?
                }
            } else {
                c.misses += 1;
                drop(c);
                source.page_pixels(index)?
            }
        };
        let decode_ms = t_decode.elapsed().as_secs_f64() * 1000.0;
        self.last_cache_hit = hit;

        self.last_source_width = pixels.source_width;
        self.last_source_height = pixels.source_height;
        self.last_decoded_width = pixels.width;
        self.last_decoded_height = pixels.height;

        // ② 使用 fast_image_resize（Lanczos3 滤波）高质量等比重采样并转换为 BGRA 填入目标缓冲区
        let t_render = Instant::now();
        let mut resizer = self.resizer.lock().unwrap_or_else(|p| p.into_inner());
        unsafe {
            render_rgba_to_bgra_letterbox(
                &pixels,
                dst_ptr,
                dst_stride,
                target_width,
                target_height,
                &mut resizer,
            )?;
        }
        let render_ms = t_render.elapsed().as_secs_f64() * 1000.0;

        self.current_index = Some(index);
        self.generation = self.generation.wrapping_add(1);
        self.presents += 1;

        let total_ms = t_total.elapsed().as_secs_f64() * 1000.0;
        self.last = PresentTimings {
            decode_ms,
            render_ms,
            total_ms,
        };

        // ③ 投递新锚点，驱动后续全尺寸原图预取（0ms 延迟立即触发）
        self.hub.set_anchor(
            index,
            self.page_count,
            self.source_epoch,
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
              \"totalMs\":{:.2}}}",
            self.target_width,
            self.target_height,
            self.generation,
            self.presents,
            if self.last_cache_hit { 1 } else { 0 },
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

/// 将 RGBA 像素进行 100% 原始尺寸或 Lanczos3 高质量等比重采样，并在视口中 Letterbox 居中写入 CVPixelBuffer (BGRA)。
unsafe fn render_rgba_to_bgra_letterbox(
    src: &PagePixels,
    dst_ptr: *mut u8,
    dst_stride: usize,
    target_w: u32,
    target_h: u32,
    resizer: &mut Resizer,
) -> Result<()> {
    let src_w = src.width.max(1);
    let src_h = src.height.max(1);

    if target_w == 0 || target_h == 0 {
        return Ok(());
    }

    // 计算等比缩放目标尺寸 (Contain / Letterbox 模式)
    let scale_x = target_w as f64 / src_w as f64;
    let scale_y = target_h as f64 / src_h as f64;
    let scale = scale_x.min(scale_y);

    let render_w = ((src_w as f64 * scale).round() as u32).clamp(1, target_w);
    let render_h = ((src_h as f64 * scale).round() as u32).clamp(1, target_h);

    let offset_x = (target_w.saturating_sub(render_w)) / 2;
    let offset_y = (target_h.saturating_sub(render_h)) / 2;

    let bg_pixel = u32::from_ne_bytes(BACKGROUND_BGRA);

    // ① 填充上留白
    for y in 0..offset_y {
        let row_ptr = dst_ptr.add(y as usize * dst_stride) as *mut u32;
        std::slice::from_raw_parts_mut(row_ptr, target_w as usize).fill(bg_pixel);
    }

    // 辅助闭包：将 render_w * render_h 的 RGBA 切片按行转换并写入 CVPixelBuffer (BGRA)
    let draw_rows = |rgba_slice: &[u8], row_bytes: usize| {
        for y in 0..render_h {
            let dst_y = offset_y + y;
            if dst_y >= target_h {
                break;
            }
            let row_ptr = dst_ptr.add(dst_y as usize * dst_stride) as *mut u32;

            // 左留白
            if offset_x > 0 {
                std::slice::from_raw_parts_mut(row_ptr, offset_x as usize).fill(bg_pixel);
            }

            // 图像像素：从 RGBA 转换为 BGRA 并写入
            let src_row = &rgba_slice[y as usize * row_bytes..];
            let dst_row = row_ptr.add(offset_x as usize);
            for x in 0..render_w as usize {
                let r = src_row[x * 4];
                let g = src_row[x * 4 + 1];
                let b = src_row[x * 4 + 2];
                let a = src_row[x * 4 + 3];
                *dst_row.add(x) = u32::from_ne_bytes([b, g, r, a]);
            }

            // 右留白
            let right_start = offset_x + render_w;
            if right_start < target_w {
                std::slice::from_raw_parts_mut(
                    row_ptr.add(right_start as usize),
                    (target_w - right_start) as usize,
                )
                .fill(bg_pixel);
            }
        }
    };

    // ② 绘制图像区域
    if render_w == src_w && render_h == src_h {
        // 1:1 原尺寸，直接转换上屏
        draw_rows(&src.rgba, src_w as usize * 4);
    } else {
        // 使用 fast_image_resize + Lanczos3 高质量平滑抗锯齿滤波
        let src_image = ImageRef::new(src_w, src_h, &src.rgba, PixelType::U8x4)
            .map_err(|e| anyhow!("创建源图像 ImageRef 失败: {e:?}"))?;
        let mut dst_image = Image::new(render_w, render_h, PixelType::U8x4);

        let opts = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Lanczos3));
        resizer
            .resize(&src_image, &mut dst_image, &opts)
            .map_err(|e| anyhow!("Lanczos3 图像重采样失败: {e:?}"))?;

        draw_rows(dst_image.buffer(), render_w as usize * 4);
    }

    // ③ 填充下留白
    for y in (offset_y + render_h)..target_h {
        let row_ptr = dst_ptr.add(y as usize * dst_stride) as *mut u32;
        std::slice::from_raw_parts_mut(row_ptr, target_w as usize).fill(bg_pixel);
    }

    Ok(())
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
    }

    #[test]
    fn test_render_rgba_to_bgra_letterbox() {
        let mut resizer = Resizer::new();
        // 2x1 横图放入 4x4 目标，上下各有 1 像素留白
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

        unsafe {
            render_rgba_to_bgra_letterbox(
                &pixels,
                buffer.as_mut_ptr(),
                stride as usize,
                target_w,
                target_h,
                &mut resizer,
            )
            .expect("渲染失败");
        }

        let bg = BACKGROUND_BGRA;
        // y=0 行是上留白
        assert_eq!(&buffer[0..4], &bg);

        // y=3 行是下留白
        let bottom_bg_offset = (3 * stride) as usize;
        assert_eq!(&buffer[bottom_bg_offset..bottom_bg_offset + 4], &bg);
    }
}
