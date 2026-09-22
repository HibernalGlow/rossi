//! GPU 呈现器：把本地核心解出的页**直接**画到一张 DXGI 共享纹理上，交给 Flutter 合成。
//!
//! # 这条路径替掉了什么
//!
//! 之前（CPU 兜底路径）是：
//!
//! ```text
//! 归档 → Rust 解码 → RGBA 过桥 → Dart Uint8List → ui.decodeImageFromPixels → CPU 上传 → 合成
//! ```
//!
//! 现在是：
//!
//! ```text
//! 归档 → Rust 解码 → wgpu 上传纹理 → wgpu 渲染(letterbox) → GPU→GPU CopyResource
//!      → D3D12 SHARED 纹理 → DXGI HANDLE → Flutter(D3D11/ANGLE) 打开合成
//! ```
//!
//! 关键差别不在于"少一次拷贝"，而在于**像素不再以 `Uint8List` 的形态跨语言边界**。
//! 44.8 MPix 的一页全尺寸位图是 179 MB，走 CPU 兜底路径时这 179 MB 要
//! 编码 → 过桥 → 再上传三次搬动（实测单页 1526 ms，其中解码只占 17%）；
//! 这条路径上它始终在显存里。
//!
//! # 为什么必须有那一次 GPU→GPU 拷贝
//!
//! 不能直接把 wgpu 的纹理导出成共享句柄：wgpu 建纹理时不会带
//! `D3D12_HEAP_FLAG_SHARED`，而 `CreateSharedHandle` 要求资源建在 SHARED 堆上。
//! 于是只能"自建一张 SHARED 目标 + 同 device/queue 上 `CopyResource` 过去"。
//! 这不是猜测，`new()` 里会**实测**一次直接对 wgpu 纹理调 `CreateSharedHandle`
//! 并把 HRESULT 记进 stats —— 证据留在运行时可查，而不是写在注释里当断言。
//!
//! 代价已实测：RTX 4060 Laptop 上该拷贝 ~190 GB/s，4K 单页 0.348 ms
//! （占 60fps 预算 2.1%）。依据与判据见 `docs/gate-a/copy-bandwidth.csv`。
//!
//! # 与 wgpu 的状态记账
//!
//! 我们拿原生命令列表碰了 wgpu 拥有的纹理（拷贝的源）。wgpu 内部记着它是
//! `RENDER_TARGET`，所以拷贝前后要**照它的认知**迁移并还原：
//! `RENDER_TARGET → COPY_SOURCE` 拷完再 `COPY_SOURCE → RENDER_TARGET`。
//! 这条不做的话，后面会变成很难查的花屏 / 校验层报错。

//! # 预取为什么要长在 Rust 侧
//!
//! 翻页的账几乎全是解码（实测 60 MPix 的 AVIF 页：合计 511 ms，其中解码 471–545 ms，
//! 上传 1.5 ms、渲染提交 2 ms）。所以**唯一的杠杆是在用户还没翻之前把下一页解出来**
//! —— 在 Dart 侧"提前解码"做不到：GPU 这条路上像素不跨语言边界，Dart 里根本没有
//! 一个解好的位图可以缓存（见 `docs/texture-bridge-integration.md` §6）。
//!
//! 于是预取的形态是：**后台一条线程解码，把 RGBA 按当前档位存进有界缓存**，
//! `show` 命中就直接上传。三条纪律都是为了不把翻页拖慢：
//!
//! 1. **只解一页、只留最新一个请求**（[`PrefetchSlot`]）—— 排队会积压，
//!    积压的解码与呈现线程抢核，这正是"预取了还慢"曾经的样子；
//! 2. **翻页就把在等的预取作废**（请求记着投递时的 `present_seq`）——
//!    用户已经在连翻时，预取下一页对他没用，只会抢核；
//! 3. **档位变了整批作废**（缓存记 `epoch`）—— 拖动窗口会改解码档位，
//!    旧档位的结果既不合观感也不再省时间。

use std::collections::HashMap;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::enhance;

use anyhow::{anyhow, Context, Result};
// 预取的**准入判决与目标次序都取自本地核心**，不在这边另立一套。
// 那两条策略是从 mImageViewer 搬来的纯函数（`rossi_local_core::prefetch_policy`），
// 而 Rossi 这边「滚动」= 翻页、「可见区待完成」= 当前页还没出图 —— 语义完全对上。
// 自己手搓一份「延迟 + 一个布尔」只会得到它的退化版，而且迟早两边不一致。
use rossi_local_core::{
    decide_prefetch_allowed, interleaved_prefetch_positions, LocalSource, PagePixels,
    PrefetchDecision,
};

use wgpu::hal::api::Dx12;
// `Interface` 必须在作用域内，否则 `ID3D12Resource::cast()` 找不到方法。
use windows::core::{Interface, PCWSTR};
use windows::Win32::Foundation::{CloseHandle, GENERIC_ALL, HANDLE, WAIT_OBJECT_0};
use windows::Win32::Graphics::Direct3D12::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::Win32::Graphics::Dxgi::IDXGIAdapter3;
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};

mod info;
mod init;
mod readback;
mod session;
mod show;
mod stats;
mod target;

pub use readback::*;

/// 呈现目标格式。
///
/// **必须是 BGRA8**：Flutter Windows 走 ANGLE / D3D11 打开这张共享纹理来合成，
/// 而 D3D11 打不开 RGBA8 的共享纹理。Gate A 风险 1 已经把这条验证过了。
const FORMAT: DXGI_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM;
const WGPU_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;

/// 页纹理格式。固定 RGBA8 —— 本地核心的解码产物就是 RGBA8，
/// 而 wgpu 的 `write_texture` 不做通道重排，用别的格式等于自己搬一遍。
const PAGE_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

/// 单边上限。引擎请求的尺寸理论上受窗口约束，但 SharedHandle 建纹理失败的成本很高，
/// 这里先夹一层，免得畸形请求把设备搞挂。
const MAX_EDGE: u32 = 8192;

/// 退休目标的上限。
///
/// 正常情况下靠 `release_callback` 回收（见 [`Presenter::notify_released`]）；
/// 这个硬上限是防"回调始终不来"时无限堆积 —— 有界总比泄漏好。
const MAX_RETIRED: usize = 4;

/// 预取缓存保留几页。
///
/// 3 = 当前页 + 前后各一档（`interleaved_prefetch_positions` 的 `+1, -1, +2`）。
/// **不是随手取的数**：这一层缓存的是**解码结果**，而解码结果按显示档位存 ——
/// 一页 1898×1265 的 RGBA 是 9.2 MB，全尺寸 60 MPix 页则是 179 MB。
/// 所以容量必须小，靠"最新者优先"而不是靠堆量。
const PREFETCH_CAPACITY: usize = 3;

/// 预取缓存的字节上限。
///
/// 与条数上限并列，因为条数与内存量级不是线性关系：可能是 500×500 的跨页图，
/// 也可能是 1898×2847。条数上限只管住"最多几页"，字节上限管住"最多多少 M"。
const PREFETCH_MAX_BYTES: usize = 48 * 1024 * 1024;

/// 预取朝前看几页、朝后看几页（交互次序 `+1, -1, +2, -2, …`）。
///
/// 朝前多一页是有道理的：阅读方向是向前的，往回翻是偶尔为之。
const PREFETCH_FORWARD: usize = 2;
const PREFETCH_BACK: usize = 1;

/// 预取线程的轮询间隔。
///
/// 用它而不是纯 `Condvar::wait`：循环里要重新评估"准入判决"，而判决依赖时间
/// （`PREFETCH_IDLE_THRESHOLD` 就是一个时间量）。靠定时醒来重判，比让每个
/// 状态变化点都记得去 notify 更不容易出错 —— 代价是 50 ms 的判定粒度，
/// 相对 400–500 ms 的解码量级可以忽略。
const PREFETCH_POLL: Duration = Duration::from_millis(50);

/// 全屏三角形 + letterbox 采样。
///
/// 图片内的 alpha 写 1.0，图片外透明；**不采样页纹理的 alpha**。原因：Flutter 合成按
/// 预乘 alpha 处理，而解码出来的 RGBA 不是预乘的；漫画页又都是不透明的。
/// 与其在这一层做一次预乘（多一遍每像素乘法，且对 JPEG 毫无意义），
/// 不如把 alpha 钉死 —— 以后真要支持带透明的图（PNG 分镜）再单独加一条路径。
const SHADER: &str = r#"
struct Params {
  // x = 页绘制宽(px), y = 页绘制高(px), z/w = 左上角原点(px)
  rect: vec4<f32>,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var page: texture_2d<f32>;
@group(0) @binding(2) var samp: sampler;

struct VsOut {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VsOut {
  var corners = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  let p = corners[idx];
  var out: VsOut;
  out.pos = vec4<f32>(p, 0.0, 1.0);
  // 片元里的 @builtin(position) 就是像素坐标（左上角原点），所以这里不需要 uv，
  // 留一个以免某些后端因为顶点输出为空而报错。
  out.uv = vec2<f32>(0.0, 0.0);
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  // 图片外透明，统一透出 Flutter 阅读器背景。
  let background = vec4<f32>(0.0);

  let local = in.pos.xy - params.rect.zw;
  if (local.x < 0.0 || local.y < 0.0 || local.x >= params.rect.x || local.y >= params.rect.y) {
    return background;
  }
  let uv = local / params.rect.xy;
  let texel = textureSample(page, samp, uv);
  return vec4<f32>(texel.rgb, 1.0);
}
"#;

/// 已经退休（尺寸变了被替换掉）的呈现目标。
///
/// 不能立刻释放：引擎可能仍持有由旧 handle 打开出来的合成纹理。
/// `released` 由 `release_callback` 置位 —— 那是引擎在告诉我们"这个 handle 已经打开了"。
struct RetiredTarget {
    generation: u64,
    resource: ID3D12Resource,
    handle: HANDLE,
    released: bool,
}

/// 当前在用的呈现目标：尺寸 = 引擎请求的尺寸。
struct Target {
    generation: u64,
    width: u32,
    height: u32,
    /// wgpu 侧的渲染目标（Bgra8Unorm，RENDER_ATTACHMENT | COPY_SRC）。
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    /// 原生 D3D12 SHARED 纹理 —— 真正交给 Flutter 的那张。
    shared: ID3D12Resource,
    handle: HANDLE,
}

/// 当前页的纹理（解码产物上传到这里）。
///
/// 不保存 `TextureView` 本身：`BindGroup` 在 wgpu 内部持有它引用到的资源，
/// 多存一份只会变成一个"看起来在用、其实没人读"的字段。
struct PageTexture {
    texture: wgpu::Texture,
    bind_group: wgpu::BindGroup,
    width: u32,
    height: u32,
}

/// 一次呈现的分段墙钟耗时。
///
/// 口径说明：`draw` 与 `copy` 都只是"把命令提交进队列"，真正的 GPU 时间要靠
/// timestamp query 才量得准（PoC 的量具在 `poc/texture-bridge/rust/wgpu-probe`，
/// 结论是 4K 单页拷贝 0.348 ms）。这里给的是**端到端墙钟**，够用来判断
/// 「这一页为什么慢」发生在哪一段，不够用来做微基准。
#[derive(Debug, Clone, Copy, Default)]
pub struct PresentTimings {
    pub decode_ms: f64,
    pub upload_ms: f64,
    pub submit_ms: f64,
    /// 等 fence —— 拷贝真正在 GPU 上落地的时间。
    pub wait_ms: f64,
    pub total_ms: f64,
}

/// 预取缓存里的一页解码结果。
struct CachedPage {
    index: usize,
    /// 按哪个档位解出来的。
    ///
    /// 必须连档位一起存：目标尺寸一变（拖窗口），旧档位的结果就**不能**再用 ——
    /// 既不合观感（页会比目标大/小一截），省下的时间也白省。
    hint: u32,
    /// 来源代次。换来源（打开另一本）后旧结果整体作废。
    epoch: u64,
    pixels: PagePixels,
}

/// 解码结果缓存 + 命中统计。
///
/// 两条线程碰到它：呈现线程（`show` 来取走）、预取线程（解完来放）。
/// 统计不是装饰 —— 判据要回答的是「这一页为什么快」，而"命中预取"与"没命中"
/// 是两个完全不同的答案，分不开就说不清。
#[derive(Default)]
struct PageCache {
    entries: VecDeque<CachedPage>,
    hits: u64,
    misses: u64,
    /// 预取线程解出来并放进来的页数。
    prefetched: u64,
    /// 解完发现档位/来源已变而丢掉的页数。
    stale: u64,
    /// 被容量或字节上限挤掉的页数。
    evicted: u64,
    /// 预取线程此刻正在解哪一页（`None` = 闲着）。只用于诊断。
    in_flight: Option<usize>,
}

impl PageCache {
    fn bytes(&self) -> usize {
        self.entries.iter().map(|e| e.pixels.rgba.len()).sum()
    }

    /// 取走某一页（命中就把它从缓存里摘掉）。
    ///
    /// **取走而不是复制**：一页 9.2 MB，为了留在缓存里再复制一份，等于把
    /// "省下的解码"换成一次 memcpy 加一份常驻内存。页一旦上屏，它的正本就在
    /// 显存里了，缓存里那份没有理由再留着。
    fn take(&mut self, index: usize, hint: u32, epoch: u64) -> Option<PagePixels> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.hint == hint && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        Some(entry.pixels)
    }

    fn has(&self, index: usize, hint: u32, epoch: u64) -> bool {
        self.entries
            .iter()
            .any(|e| e.index == index && e.hint == hint && e.epoch == epoch)
    }

    /// 放进一条，并按上限裁剪。
    fn insert(&mut self, page: CachedPage) {
        self.entries
            .retain(|e| !(e.index == page.index && e.hint == page.hint && e.epoch == page.epoch));
        self.entries.push_back(page);
        self.prefetched += 1;

        while self.entries.len() > PREFETCH_CAPACITY
            || (self.bytes() > PREFETCH_MAX_BYTES && self.entries.len() > 1)
        {
            self.entries.pop_front();
            self.evicted += 1;
        }
    }

    /// 换来源时整体作废。
    fn drop_range(&mut self, epoch: u64) {
        let before = self.entries.len();
        self.entries.retain(|e| e.epoch == epoch);
        self.evicted += (before - self.entries.len()) as u64;
    }
}

/// 预取线程要用的"呈现进度"快照。
#[derive(Clone, Default)]
struct PrefetchView {
    /// 用户现在停在哪一页 —— 预取围绕它展开。
    anchor: Option<usize>,
    page_count: usize,
    /// 当前的解码档位。
    hint: u32,
    /// 上一次翻页的时刻。
    ///
    /// 直接喂本地核心的 `decide_prefetch_allowed` 作为 `last_prefetch_scroll_at`：
    /// **它要的就是这个语义**（「滚动」在 Rossi 这儿就是翻页），见
    /// `rossi_local_core::prefetch_policy` 的模块文档。
    last_show_at: Option<Instant>,
    /// 当前页是不是还没出图（喂 `visible_state_pending`）：0 = 已出图。
    visible_pending: usize,
    /// 来源代次。
    epoch: u64,
    source: Option<Arc<LocalSource>>,
}

#[derive(Default)]
struct PrefetchShared {
    view: PrefetchView,
    /// 呈现线程投递过多少次锚点（诊断用）。
    anchors_posted: u64,
}

/// 预取线程与呈现线程之间共享的那一格。
///
/// 只有一格、且**只表达"用户现在在哪一页"**，不排任务队列。排队会积压：
/// 用户连翻 5 页就积 5 个解码任务，每个 400–500 ms，呈现线程随后要的解码会和
/// 这些积压抢核，把翻页拖成秒级 —— 这正是"预取了还慢"曾经的样子
/// （两个 auto=16 的并发预取把翻页饿到 ~1 核）。锚点式的表述没有积压可积。
struct PrefetchHub {
    shared: Mutex<PrefetchShared>,
    cv: Condvar,
    stop: AtomicBool,
    /// 开关。关掉时预取线程照旧活着，但不解任何页 ——
    /// A/B 要的就是"同一份二进制，只差一个开关"。
    enabled: AtomicBool,
}

/// GPU 呈现器。
///
/// # 线程契约（重要）
///
/// 它会同时被两条线程碰到：Flutter 的 raster 线程（`SurfaceCallback` 要尺寸、
/// 要句柄）与平台线程（Dart 侧 `show` / `open` 调用）。所以：
/// - 对外一律经过 [`crate::GpuPresenter`]（`Mutex<Presenter>`）串行化；
/// - 内部的原生命令列表 / 分配器在 D3D12 里本来就**不允许**并发使用，
///   那把锁同时满足了这一条。
pub struct Presenter {
    // ── wgpu 侧 ──
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::RenderPipeline,
    sampler: wgpu::Sampler,
    uniform: wgpu::Buffer,

    // ── 原生侧（与 wgpu 共用同一个 ID3D12Device / CommandQueue）──
    d3d_device: ID3D12Device,
    d3d_queue: ID3D12CommandQueue,
    allocator: ID3D12CommandAllocator,
    cmd_list: ID3D12GraphicsCommandList,
    fence: ID3D12Fence,
    fence_event: HANDLE,
    fence_value: u64,

    // ── 资源 ──
    target: Option<Target>,
    page: Option<PageTexture>,
    next_generation: u64,
    retired: Vec<RetiredTarget>,

    // ── 阅读状态 ──
    //
    // `Arc` 是有意的：预取线程也要拿着同一个来源去解码。`LocalSource` 只存
    // 「根路径 + 类型 + 页序列」，**不持有任何打开的文件/归档对象**
    // （每次读页重开归档），所以它跨线程用是安全的 —— 而且正因为不共享句柄，
    // 两条线程各读各的页不会互相干扰。
    source: Option<Arc<LocalSource>>,
    page_index: Option<usize>,

    // ── 预取 ──
    /// 解码结果缓存（`show` 来取，预取线程来放）。
    cache: Arc<Mutex<PageCache>>,
    /// 与预取线程共享的一格状态。
    hub: Arc<PrefetchHub>,
    prefetch_thread: Option<JoinHandle<()>>,
    /// 最近一轮 `show` 有没有命中预取缓存。诊断/判据要用
    /// —— "这一页为什么快"和"这一页为什么慢"的答案往往就差这一个布尔。
    last_cache_hit: bool,

    // ── 超分增强轨 ──
    /// AI 超分产物，按 `(index, epoch)` 存。选轨规则与证据口径都取自 `enhance`，
    /// 与 mac 侧同源 —— 理由见该模块注释里的「假证据」一段。
    enhanced: enhance::EnhancedStore,
    /// 「原图对比」旁路：置位期间增强轨不参显，但**不删除**，关掉要能立刻换回去。
    original_preview: enhance::Bypass,
    /// 本次呈现实际用了哪一轨，作为 `usedEnhanced` 报给 Dart 核对。
    last_used_enhanced: bool,
    /// 每页**原图**的像素尺寸。增强图是 4× 的，它的 `source_width` 是放大后的值，
    /// 拿它喂布局会让页被放大四倍，所以布局一律用这里记着的原图尺寸。
    raw_source_sizes: HashMap<usize, (u32, u32)>,

    // ── 诊断 ──
    adapter_name: String,
    adapter_matched: bool,
    adapter_luid: u64,
    target_luid: u64,
    /// 直接对 wgpu 纹理调 `CreateSharedHandle` 的实测结果。预期是失败，
    /// 这条记录就是"为什么要多走一次拷贝"的运行时可查证据。
    direct_share: String,
    init_ms: f64,
    /// `init_ms` 的三个分段。分开记是因为它们的**可优化性完全不同**：
    /// device 那一段是适配器枚举与驱动的事，管线那一段是 WGSL → DXIL 的编译
    /// （可预热），剩下的是我们自己的建资源加一次句柄探测。
    /// 合成一个数字看不出"还能不能省、该往哪省"。
    init_device_ms: f64,
    init_pipeline_ms: f64,
    init_rest_ms: f64,
    presents: u64,
    recreates: u32,
    released_total: u64,
    /// 最近一次解码请求的宽度 vs 实际解出的宽度 —— 用来证明降采样真的生效了。
    decoded_width: u32,
    decoded_height: u32,
    decoded_source_width: u32,
    decoded_source_height: u32,
    last: PresentTimings,
    last_error: String,
}

// SAFETY: windows-rs 生成的 COM 接口默认不是 Send/Sync（它们没有编译期线程保证）。
// 这里手工声明是安全的，理由是三条具体的约束，而不是"一般没问题"：
//   1. `Presenter` 从不由两条线程同时访问 —— 所有 C ABI 入口都先拿
//      `crate::GpuPresenter` 的互斥锁；
//   2. D3D12 的 device / queue 本身是自由线程的；真正**不允许**并发的是
//      命令列表与分配器（Reset / ExecuteCommandLists），而第 1 条已经把它们串起来了；
//   3. wgpu 的 Device / Queue 本来就是 Send + Sync。
// COM 的引用计数操作是原子的，跨线程 drop 不会被撕裂。
unsafe impl Send for Presenter {}

impl Presenter {
    fn current_epoch(&self) -> u64 {
        self.hub
            .shared
            .lock()
            .map(|s| s.view.epoch)
            .unwrap_or_default()
    }

    /// 提交这一帧：wgpu 渲染（letterbox）→ 原生命令列表 `CopyResource` 到共享纹理 → 等落地。
    fn draw_and_copy(&mut self, target_width: u32, target_height: u32) -> Result<()> {
        let page = self.page.as_ref().ok_or_else(|| anyhow!("页纹理不存在"))?;
        let target = self
            .target
            .as_ref()
            .ok_or_else(|| anyhow!("呈现目标不存在"))?;

        // letterbox：等比放进目标，居中，两侧/上下留底色。
        let scale = f64::min(
            target_width as f64 / page.width as f64,
            target_height as f64 / page.height as f64,
        );
        let draw_w = (page.width as f64 * scale).round().max(1.0) as f32;
        let draw_h = (page.height as f64 * scale).round().max(1.0) as f32;
        let origin_x = ((target_width as f32 - draw_w) * 0.5).max(0.0);
        let origin_y = ((target_height as f32 - draw_h) * 0.5).max(0.0);

        self.queue.write_buffer(
            &self.uniform,
            0,
            &uniform_bytes(draw_w, draw_h, origin_x, origin_y),
        );

        // 目标纹理的裸资源。guard 必须先取到再释放，不能跨 &mut self 借用的边界。
        let dst: ID3D12Resource = target.shared.clone();
        let src: ID3D12Resource = {
            let guard = unsafe { target.texture.as_hal::<Dx12>() }
                .ok_or_else(|| anyhow!("呈现目标取不到 dx12 裸资源"))?;
            unsafe { guard.raw_resource().clone() }
        };

        {
            let mut encoder = self
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("rossi-gpu-present-encoder"),
                });
            {
                let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("rossi-gpu-present-pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &target.view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                            store: wgpu::StoreOp::Store,
                        },
                        depth_slice: None,
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                });
                pass.set_pipeline(&self.pipeline);
                pass.set_bind_group(0, &page.bind_group, &[]);
                pass.draw(0..3, 0..1);
            }
            self.queue.submit([encoder.finish()]);
        }

        // wgpu 的 submit 是同步写进同一个 D3D12 队列的，所以下面这段拷贝命令
        // 天然排在渲染之后，顺序有保障（不需要额外同步）。
        unsafe {
            self.allocator
                .Reset()
                .map_err(|e| anyhow!("Allocator::Reset 失败: {e}"))?;
            self.cmd_list
                .Reset(&self.allocator, None)
                .map_err(|e| anyhow!("CommandList::Reset 失败: {e}"))?;

            let mut forward = [
                transition(
                    &src,
                    D3D12_RESOURCE_STATE_RENDER_TARGET,
                    D3D12_RESOURCE_STATE_COPY_SOURCE,
                ),
                transition(
                    &dst,
                    D3D12_RESOURCE_STATE_COMMON,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                ),
            ];
            self.cmd_list.ResourceBarrier(&forward);
            release_barriers(&mut forward);

            self.cmd_list.CopyResource(&dst, &src);

            let mut back = [
                transition(
                    &src,
                    D3D12_RESOURCE_STATE_COPY_SOURCE,
                    D3D12_RESOURCE_STATE_RENDER_TARGET,
                ),
                transition(
                    &dst,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                    D3D12_RESOURCE_STATE_COMMON,
                ),
            ];
            self.cmd_list.ResourceBarrier(&back);
            release_barriers(&mut back);

            self.cmd_list
                .Close()
                .map_err(|e| anyhow!("CommandList::Close 失败: {e}"))?;

            let list: ID3D12CommandList = self
                .cmd_list
                .cast()
                .map_err(|e| anyhow!("cast 到 ID3D12CommandList 失败: {e}"))?;
            self.d3d_queue.ExecuteCommandLists(&[Some(list)]);
        }

        // 等拷贝真正落地再把句柄交出去。
        //
        // 这一步能不能省？不能：`MarkExternalTextureFrameAvailable` 之后引擎随时可能
        // 打开句柄读像素，而 D3D12 的拷贝是异步的。4K 单页拷贝实测 0.348 ms，
        // 所以"等一下"的代价远小于"读到半张图"。
        //
        // fence 值必须**严格单调递增**：重置计数器会让 Signal 变成空操作、
        // 等待立即返回，随后表现为 `DXGI_ERROR_DEVICE_REMOVED`（这个坑在
        // PoC 的 bench 里踩过一次）。
        self.fence_value += 1;
        let value = self.fence_value;
        unsafe {
            self.d3d_queue
                .Signal(&self.fence, value)
                .map_err(|e| anyhow!("Queue::Signal 失败: {e}"))?;
            if self.fence.GetCompletedValue() < value {
                self.fence
                    .SetEventOnCompletion(value, self.fence_event)
                    .map_err(|e| anyhow!("SetEventOnCompletion 失败: {e}"))?;
                let wait = WaitForSingleObject(self.fence_event, 2000);
                if wait != WAIT_OBJECT_0 {
                    return Err(anyhow!("等待拷贝完成超时: {wait:?}"));
                }
            }
        }
        Ok(())
    }
}

/// 从环境变量读预取的默认开关。
///
/// 只认 `0` / `false` / `off` 为关，其余（含未设置）都当开。默认开是对的默认值：
/// 它就是修翻页延迟的那件事，默认关会让人以为没做。
fn prefetch_enabled_from_env() -> bool {
    match std::env::var("ROSSI_GPU_PREFETCH") {
        Ok(raw) => {
            let v = raw.trim().to_ascii_lowercase();
            !(v == "0" || v == "false" || v == "off")
        }
        Err(_) => true,
    }
}

fn spawn_prefetch_worker(cache: Arc<Mutex<PageCache>>, hub: Arc<PrefetchHub>) -> JoinHandle<()> {
    thread::Builder::new()
        .name("rossi-prefetch".to_string())
        .spawn(move || prefetch_worker_loop(&cache, &hub))
        .expect("起不了预取线程")
}

/// 预取线程主体。
///
/// 一轮 = 醒来看一眼「用户在哪一页 / 现在该不该预取 / 下一个目标是谁」，最多解一页。
/// **没有任务队列**：积压就是抢核的源头，见 [`PrefetchHub`]。
fn prefetch_worker_loop(cache: &Mutex<PageCache>, hub: &PrefetchHub) {
    loop {
        // ① 睡到下轮判定（或被 `notify_all` 提前叫醒）。
        //
        // 这里必须用 `wait_timeout` 而不是 `wait`：循环里要重新评估的准入判决本身
        // 就含时间量（`PREFETCH_IDLE_THRESHOLD` = 100 ms），靠定时醒来重判，
        // 比让每个状态变化点都记得去 notify 更不容易漏。
        {
            let Ok(guard) = hub.shared.lock() else {
                // 锁中毒 = 进程状态已不可信。静默退出好过在解码线程里 panic。
                return;
            };
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

        // ② 取一份"当前进度"快照。
        let Some(view) = hub.snapshot() else { return };
        let (Some(anchor), Some(source)) = (view.anchor, view.source.clone()) else {
            continue; // 还没打开来源 / 还没显示过任何页
        };
        if view.page_count == 0 {
            continue;
        }

        // ③ 准入判决 —— 直接问本地核心，不在这边另立一套。
        if let PrefetchDecision::Block { .. } =
            decide_prefetch_allowed(Instant::now(), view.last_show_at, view.visible_pending)
        {
            continue;
        }

        // ④ 挑目标：交互次序（`+1, -1, +2, …`）里第一个"还没缓存、也不在解"的。
        let target = interleaved_prefetch_positions(
            anchor,
            view.page_count,
            PREFETCH_FORWARD,
            PREFETCH_BACK,
        )
        .into_iter()
        .find(|index| {
            cache
                .lock()
                .map(|c| c.in_flight != Some(*index) && !c.has(*index, view.hint, view.epoch))
                .unwrap_or(false)
        });
        let Some(index) = target else {
            continue; // 这一圈该预取的都齐了
        };

        if let Ok(mut c) = cache.lock() {
            c.in_flight = Some(index);
        }

        // ⑤ 解码。**慢**（真页几百毫秒），所以全程**不持锁** ——
        //    持着锁解一页，呈现线程来取缓存时会被挡掉整整一页的时间。
        let decoded = source.page_pixels_scaled(index, Some(view.hint));

        let epoch_now = hub.epoch();
        if let Ok(mut c) = cache.lock() {
            c.in_flight = None;
            match decoded {
                Ok(pixels) if epoch_now == view.epoch => c.insert(CachedPage {
                    index,
                    hint: view.hint,
                    epoch: view.epoch,
                    pixels,
                }),
                // 解完发现来源已经换了：这条数据属于另一本，丢掉。
                Ok(_) => c.stale += 1,
                // 预取失败**不是错误**：真需要这一页时 `show` 会再解一次，
                // 错误会在那条路径上被报出来。这里吞掉，免得扰乱错误通道。
                Err(_) => {}
            }
        }
    }
}

impl PrefetchHub {
    fn snapshot(&self) -> Option<PrefetchView> {
        self.shared.lock().ok().map(|s| s.view.clone())
    }

    fn epoch(&self) -> u64 {
        self.shared.lock().map(|s| s.view.epoch).unwrap_or_default()
    }
}

impl Drop for Presenter {
    fn drop(&mut self) {
        // 先把预取线程收掉，而且**必须 join**（等它真的退出）。
        //
        // 不是"顺手清理"：预取线程手里可能正握着 `Arc<LocalSource>` 和一份
        // 解码缓冲，而它一旦跑过 `device` 的析构点还活着，就会在进程退出时
        // 与 D3D12 的释放顺序打架（表现是偶发崩溃，且复现不了）。
        // 代价是最多等一页解码的时间（几百毫秒），只发生在关窗/换呈现器时。
        self.hub.stop.store(true, Ordering::Relaxed);
        self.hub.cv.notify_all();
        if let Some(handle) = self.prefetch_thread.take() {
            let _ = handle.join();
        }

        // 直接释放，不做延迟：此刻引擎已经不再持有 texture（C++ 侧先注销再析构）。
        for entry in self.retired.drain(..) {
            free_retired(entry);
        }
        self.target = None;
        self.page = None;
        unsafe {
            if !self.fence_event.is_invalid() {
                let _ = CloseHandle(self.fence_event);
            }
        }
    }
}

/// 把 `[f32; 4]` 拼成 uniform 的字节。
///
/// 用 `to_le_bytes` 而不是 `from_raw_parts`：不引入 `unsafe`，
/// 而且 32 字节的常量折叠在编译期就完成了。
fn uniform_bytes(draw_w: f32, draw_h: f32, origin_x: f32, origin_y: f32) -> [u8; 16] {
    let mut out = [0u8; 16];
    for (index, value) in [draw_w, draw_h, origin_x, origin_y].into_iter().enumerate() {
        out[index * 4..index * 4 + 4].copy_from_slice(&value.to_le_bytes());
    }
    out
}

/// 释放一个退休目标：先关句柄再放资源。
fn free_retired(entry: RetiredTarget) {
    unsafe {
        if !entry.handle.is_invalid() {
            let _ = CloseHandle(entry.handle);
        }
    }
    drop(entry.resource);
}

/// 实测「直接对 wgpu 的纹理调 `CreateSharedHandle`」的结果。
///
/// 预期失败（`E_INVALIDARG`），因为 wgpu 没用 SHARED 堆建它。
/// 这条记录留在这里，是为了让"为什么要多走一次拷贝"在运行时**可查**，
/// 而不是只能相信注释。若某天某些驱动放开了，这条会变成"成功(意外)"，
/// 那时就可以考虑去掉拷贝 —— 判据是它，不是我们的假设。
fn probe_direct_share(device: &wgpu::Device, d3d_device: &ID3D12Device) -> String {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("rossi-gpu-present-direct-share-probe"),
        size: wgpu::Extent3d {
            width: 4,
            height: 4,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: WGPU_FORMAT,
        usage: wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });

    unsafe {
        let raw = texture.as_hal::<Dx12>().map(|t| t.raw_resource().clone());
        match raw {
            None => "wgpu 纹理取不到裸资源".to_string(),
            Some(resource) => match resource.cast::<ID3D12DeviceChild>() {
                Err(e) => format!("cast 失败: {e}"),
                Ok(child) => {
                    match d3d_device.CreateSharedHandle(&child, None, GENERIC_ALL.0, PCWSTR::null())
                    {
                        Ok(handle) => {
                            let _ = CloseHandle(handle);
                            "成功(意外)".to_string()
                        }
                        Err(e) => format!("失败 {:?}", e.code().0),
                    }
                }
            },
        }
    }
}

/// 构造一个资源状态迁移 barrier。
///
/// windows crate 把 union 里的 COM 字段包在 `ManuallyDrop` 里（而且 union 字段
/// 自身再包一层），不会自动 Release，所以必须配合 [`release_barriers`] 手动释放，
/// 否则每帧都漏一个引用计数。
///
/// 整体构造而不是逐字段赋值：Rust 禁止对 `ManuallyDrop` 包裹的 union 字段做路径赋值
/// （会隐式 DerefMut），逐项写编译不过。
unsafe fn transition(
    resource: &ID3D12Resource,
    before: D3D12_RESOURCE_STATES,
    after: D3D12_RESOURCE_STATES,
) -> D3D12_RESOURCE_BARRIER {
    D3D12_RESOURCE_BARRIER {
        Type: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        Flags: D3D12_RESOURCE_BARRIER_FLAG_NONE,
        Anonymous: D3D12_RESOURCE_BARRIER_0 {
            Transition: std::mem::ManuallyDrop::new(D3D12_RESOURCE_TRANSITION_BARRIER {
                pResource: std::mem::ManuallyDrop::new(Some(resource.clone())),
                Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore: before,
                StateAfter: after,
            }),
        },
    }
}

unsafe fn release_barriers(barriers: &mut [D3D12_RESOURCE_BARRIER]) {
    for barrier in barriers.iter_mut() {
        // 两层 ManuallyDrop 都要 `ptr::read` 搬出来再 `into_inner`，
        // 才会真正调用那份 ID3D12Resource 的 Drop（即 Release）。
        let outer: std::mem::ManuallyDrop<D3D12_RESOURCE_TRANSITION_BARRIER> =
            std::ptr::read(&barrier.Anonymous.Transition);
        let inner = std::mem::ManuallyDrop::into_inner(outer);
        drop(std::mem::ManuallyDrop::into_inner(inner.pResource));
    }
}

pub fn escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"")
}
