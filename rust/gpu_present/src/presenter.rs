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

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

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
/// 输出 alpha 一律写 1.0，**不采样页纹理的 alpha**。原因：Flutter 合成按
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
  // 画布底色：阅读器里页外的区域。近黑而不是纯黑，免得和"没渲染"混淆。
  let background = vec4<f32>(0.02, 0.02, 0.03, 1.0);

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
    /// 建呈现器。
    ///
    /// `adapter_luid` 由 C++ 侧从 `FlutterEngine::GetGraphicsAdapter()` 取来。
    /// **同一块卡是硬约束而不是优化**：跨 adapter 共享纹理要么建不出来，
    /// 要么掉进极慢的跨适配器拷贝路径。
    /// 传 0 表示"没有 LUID，随便挑一块高性能卡"（探针在无 Flutter 时用）。
    pub fn new(adapter_luid: u64, width: u32, height: u32) -> Result<Self> {
        let t0 = Instant::now();

        let mut idesc = wgpu::InstanceDescriptor::default();
        idesc.backends = wgpu::Backends::DX12;
        let instance = wgpu::Instance::new(&idesc);

        let adapters: Vec<wgpu::Adapter> = instance.enumerate_adapters(wgpu::Backends::DX12);
        if adapters.is_empty() {
            return Err(anyhow!("枚举不到任何 DX12 adapter"));
        }

        let mut picked: Option<(wgpu::Adapter, String, bool)> = None;
        let mut candidates: Vec<String> = Vec::new();
        for adapter in adapters {
            let name = adapter.get_info().name.clone();
            let mut luid = 0u64;
            // 从 dx12 后端的裸 IDXGIAdapter3 读真正的 LUID。
            // 单靠 `AdapterInfo` 无法可靠地对应到 Flutter 用的那块卡。
            if let Some(hal) = unsafe { adapter.as_hal::<Dx12>() } {
                let raw: &IDXGIAdapter3 = hal.as_raw();
                if let Ok(desc) = unsafe { raw.GetDesc() } {
                    luid = ((desc.AdapterLuid.HighPart as u32 as u64) << 32)
                        | desc.AdapterLuid.LowPart as u64;
                }
            }
            let matched = adapter_luid != 0 && luid == adapter_luid;
            candidates.push(format!(
                "{name}[{luid:#x}]{}",
                if matched { "*" } else { "" }
            ));
            if matched {
                picked = Some((adapter, name, true));
                break;
            }
            if picked.is_none() {
                picked = Some((adapter, name, false));
            }
        }

        let (adapter, adapter_name, adapter_matched) =
            picked.ok_or_else(|| anyhow!("没有可用的 adapter 候选"))?;
        if adapter_luid != 0 && !adapter_matched {
            return Err(anyhow!(
                "枚举到的 adapter 里没有 LUID {adapter_luid:#x}（候选: {}）",
                candidates.join(", ")
            ));
        }

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("rossi-gpu-present"),
            ..Default::default()
        }))
        .map_err(|e| anyhow!("request_device 失败: {e}"))?;

        // 取裸 D3D12 device / queue。两者都 Clone 出独立引用计数，
        // 这样后续不必一直握着借用 device 的 as_hal guard。
        let (d3d_device, d3d_queue) = {
            let hal = unsafe { device.as_hal::<Dx12>() }
                .ok_or_else(|| anyhow!("device 不是 DX12 后端"))?;
            let raw_device: ID3D12Device = hal.raw_device().clone();
            let raw_queue: ID3D12CommandQueue = hal.raw_queue().clone();
            (raw_device, raw_queue)
        };
        let t_device = Instant::now();

        // ── 着色器管线 ──
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("rossi-gpu-present-shader"),
            source: wgpu::ShaderSource::Wgsl(SHADER.into()),
        });

        let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("rossi-gpu-present-bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });

        // 线性的下采样质量要够：解码侧已经把页缩到接近显示尺寸，
        // 剩下的零头由采样器补，nearest 会出锯齿。
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("rossi-gpu-present-sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        let uniform = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rossi-gpu-present-uniform"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("rossi-gpu-present-layout"),
            bind_group_layouts: &[&bgl],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("rossi-gpu-present-pipeline"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: Default::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: WGPU_FORMAT,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });
        let t_pipeline = Instant::now();

        // ── 原生命令设施 ──
        //
        // 注意 windows-rs 0.58 里这两组方法的**风格正好相反**：
        //   CreateCommandAllocator / CreateCommandList / CreateFence 是返回值风格（Result<T>），
        //   CreateQueryHeap / CreateCommittedResource / Map 是 out 参数风格。
        // 写错的表现是"类型推断失败"，很难从报错看出是风格问题。
        let (allocator, cmd_list, fence, fence_event) = unsafe {
            let allocator = d3d_device
                .CreateCommandAllocator::<ID3D12CommandAllocator>(D3D12_COMMAND_LIST_TYPE_DIRECT)
                .context("CreateCommandAllocator 失败")?;

            let cmd_list = d3d_device
                .CreateCommandList::<_, _, ID3D12GraphicsCommandList>(
                    0,
                    D3D12_COMMAND_LIST_TYPE_DIRECT,
                    &allocator,
                    None::<&ID3D12PipelineState>,
                )
                .context("CreateCommandList 失败")?;
            cmd_list.Close().context("CommandList::Close 失败")?;

            let fence = d3d_device
                .CreateFence::<ID3D12Fence>(0, D3D12_FENCE_FLAG_NONE)
                .context("CreateFence 失败")?;

            let event = CreateEventW(None, false, false, None).context("CreateEventW 失败")?;
            (allocator, cmd_list, fence, event)
        };

        let direct_share = probe_direct_share(&device, &d3d_device);
        let t_end = Instant::now();

        let cache: Arc<Mutex<PageCache>> = Arc::new(Mutex::new(PageCache::default()));
        let hub: Arc<PrefetchHub> = Arc::new(PrefetchHub {
            shared: Mutex::new(PrefetchShared::default()),
            cv: Condvar::new(),
            stop: AtomicBool::new(false),
            enabled: AtomicBool::new(prefetch_enabled_from_env()),
        });

        let mut presenter = Self {
            device,
            queue,
            pipeline,
            sampler,
            uniform,
            d3d_device,
            d3d_queue,
            allocator,
            cmd_list,
            fence,
            fence_event,
            fence_value: 0,
            target: None,
            page: None,
            next_generation: 1,
            retired: Vec::new(),
            source: None,
            page_index: None,
            cache,
            hub,
            prefetch_thread: None,
            last_cache_hit: false,
            adapter_name,
            adapter_matched,
            adapter_luid,
            target_luid: adapter_luid,
            direct_share,
            init_ms: t0.elapsed().as_secs_f64() * 1000.0,
            init_device_ms: (t_device - t0).as_secs_f64() * 1000.0,
            init_pipeline_ms: (t_pipeline - t_device).as_secs_f64() * 1000.0,
            init_rest_ms: (t_end - t_pipeline).as_secs_f64() * 1000.0,
            presents: 0,
            recreates: 0,
            released_total: 0,
            decoded_width: 0,
            decoded_height: 0,
            decoded_source_width: 0,
            decoded_source_height: 0,
            last: PresentTimings::default(),
            last_error: String::new(),
        };

        // 预取线程随 Presenter 一起活。没打开来源、或开关关着的时候，它只是每
        // `PREFETCH_POLL` 醒一次看一眼，不解任何页。
        presenter.prefetch_thread = Some(spawn_prefetch_worker(
            Arc::clone(&presenter.cache),
            Arc::clone(&presenter.hub),
        ));

        if width > 0 && height > 0 {
            presenter.ensure_target(width, height)?;
        }

        Ok(presenter)
    }

    /// 建一张 SHARED 的 BGRA8 纹理并导出句柄。
    fn create_shared_target(
        d3d_device: &ID3D12Device,
        width: u32,
        height: u32,
    ) -> Result<(ID3D12Resource, HANDLE)> {
        let heap = D3D12_HEAP_PROPERTIES {
            Type: D3D12_HEAP_TYPE_DEFAULT,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 1,
            VisibleNodeMask: 1,
        };

        let desc = D3D12_RESOURCE_DESC {
            Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
            Alignment: 0,
            Width: width as u64,
            Height: height,
            DepthOrArraySize: 1,
            MipLevels: 1,
            Format: FORMAT,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
            // ALLOW_RENDER_TARGET 不是必需的（我们只用它当 COPY_DEST），
            // 但留着它，以后要做"Rust 侧直接画 UI 叠加层"时不用重建纹理。
            // 它对拷贝路径没有额外开销。
            Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
        };

        let mut clear = D3D12_CLEAR_VALUE::default();
        clear.Format = FORMAT;
        clear.Anonymous.Color = [0.0, 0.0, 0.0, 1.0];

        let mut resource: Option<ID3D12Resource> = None;
        unsafe {
            d3d_device
                .CreateCommittedResource(
                    &heap,
                    D3D12_HEAP_FLAG_SHARED,
                    &desc,
                    D3D12_RESOURCE_STATE_COMMON,
                    Some(&clear as *const _),
                    &mut resource,
                )
                .map_err(|e| anyhow!("CreateCommittedResource(SHARED) 失败: {:?}", e.code().0))?;
        }
        let resource = resource.ok_or_else(|| anyhow!("CreateCommittedResource 返回空"))?;

        let child: ID3D12DeviceChild = resource
            .cast()
            .map_err(|e| anyhow!("ID3D12Resource -> ID3D12DeviceChild 失败: {e}"))?;

        // GENERIC_ALL 而非只读：D3D11 侧打开时需要完整的访问位。
        let handle = unsafe {
            d3d_device
                .CreateSharedHandle(&child, None, GENERIC_ALL.0, PCWSTR::null())
                .map_err(|e| anyhow!("CreateSharedHandle 失败: {:?}", e.code().0))?
        };

        Ok((resource, handle))
    }

    /// 确保呈现目标的尺寸与引擎请求一致；不一致就重建并导出新句柄。
    ///
    /// 这是 Gate A 风险 1 验证过的"销毁与重建"路径，现在接在了真实调用点上
    /// —— 拖动窗口边框就会走到这里。
    pub fn ensure_target(&mut self, width: u32, height: u32) -> Result<()> {
        let width = width.clamp(1, MAX_EDGE);
        let height = height.clamp(1, MAX_EDGE);

        if let Some(target) = &self.target {
            if target.width == width && target.height == height {
                return Ok(());
            }
        }

        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("rossi-gpu-present-target"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: WGPU_FORMAT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let (shared, handle) = Self::create_shared_target(&self.d3d_device, width, height)?;

        let generation = self.next_generation;
        self.next_generation += 1;

        if let Some(previous) = self.target.replace(Target {
            generation,
            width,
            height,
            texture,
            view,
            shared,
            handle,
        }) {
            self.retired.push(RetiredTarget {
                generation: previous.generation,
                resource: previous.shared,
                handle: previous.handle,
                released: false,
            });
        }

        self.recreates += 1;
        self.reclaim();

        // 尺寸变了就立刻按当前页重画一遍。
        //
        // 不重画的话，窗口一拖动就会看到底色（刚建的目标是干净的）—— 因为引擎
        // 只会来取"我们通知过的那一帧"。这里不调 `show` 而是直接 `draw_and_copy`：
        // 页纹理已经在上传着，重解一遍纯属浪费（44 MPix 页要几百毫秒）。
        if self.page.is_some() {
            let (width, height) = self.target_size();
            self.draw_and_copy(width, height)?;
        }

        Ok(())
    }

    /// 引擎通知"第 `generation` 代的句柄已经被打开"。
    ///
    /// 这是 PoC 那个"保留最近两个、靠猜"的薄弱点的正解：Flutter 的
    /// `release_callback` 语义就是**句柄已被打开**（见 `flutter_texture_registrar.h`），
    /// 所以那一刻之后我们可以安全地放掉那一代。
    pub fn notify_released(&mut self, generation: u64) {
        for entry in &mut self.retired {
            if entry.generation == generation {
                entry.released = true;
            }
        }
        self.reclaim();
    }

    /// 回收退休目标。
    ///
    /// 两条判据同时成立才释放：**回调已经来过**，且**至少有两代更新的目标存在**
    /// （"刚被换掉的那一代"可能还在引擎的合成链上，多留两代是廉价的保险：
    /// 一张 4K 目标约 33 MB，留两张总共 66 MB，比偶发一次花屏便宜）。
    /// 另外用 [`MAX_RETIRED`] 兜底，防回调始终不来导致无限堆积。
    fn reclaim(&mut self) {
        let newest = self.next_generation;
        let mut kept: Vec<RetiredTarget> = Vec::with_capacity(self.retired.len());
        let mut freed_now = 0u32;

        for entry in self.retired.drain(..) {
            let callback_came = entry.released;
            let two_generations_behind = newest.saturating_sub(entry.generation) >= 2;
            if callback_came && two_generations_behind {
                free_retired(entry);
                freed_now += 1;
            } else {
                kept.push(entry);
            }
        }
        self.retired = kept;

        while self.retired.len() > MAX_RETIRED {
            let oldest = self.retired.remove(0);
            free_retired(oldest);
            freed_now += 1;
        }

        self.released_total += freed_now as u64;
    }

    /// 打开一个本地来源（散图文件夹 / CBZ / CBR）。
    pub fn open(&mut self, path: &str) -> Result<usize> {
        let source = LocalSource::open(path)?;
        let count = source.len();
        if count == 0 {
            return Err(anyhow!("这个来源里没有可显示的页: {path}"));
        }
        self.source = Some(Arc::new(source));
        self.page_index = None;

        // 换来源 = 缓存整体作废，并让预取线程改用新来源。
        {
            let mut shared = self.hub.shared.lock().expect("prefetch shared 中毒");
            shared.view.epoch += 1;
            shared.view.source = self.source.clone();
            shared.view.anchor = None;
            shared.view.page_count = count;
            // 刚打开还没显示任何页 —— 从这里起算"没有翻页过"是**对**的语义：
            // 准入判决的 `NoScrollYet` 分支本来就是给"启动/切来源之后"准备的。
            shared.view.last_show_at = None;
            shared.view.visible_pending = 1;
        }
        let epoch = self.current_epoch();
        if let Ok(mut cache) = self.cache.lock() {
            cache.drop_range(epoch);
        }
        self.hub.cv.notify_all();
        Ok(count)
    }

    fn current_epoch(&self) -> u64 {
        self.hub
            .shared
            .lock()
            .map(|s| s.view.epoch)
            .unwrap_or_default()
    }

    pub fn page_count(&self) -> usize {
        self.source.as_ref().map(|s| s.len()).unwrap_or(0)
    }

    pub fn page_index(&self) -> Option<usize> {
        self.page_index
    }

    /// 呈现第 `index` 页：解码 → 上传 → letterbox 渲染 → GPU 拷贝到共享纹理。
    ///
    /// 返回分段耗时。调用方拿到 return 之后必须调
    /// `FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`，
    /// 引擎才会来取这一帧（这个函数**不**碰 Flutter，只管把像素放好）。
    pub fn show(&mut self, index: usize) -> Result<PresentTimings> {
        let t_total = Instant::now();
        let target = self
            .target
            .as_ref()
            .ok_or_else(|| anyhow!("还没有呈现目标：引擎尚未用 SurfaceCallback 报过尺寸"))?;
        let (target_width, target_height) = (target.width, target.height);

        // 这里克隆一次 `Arc` 而不是借 `&self.source`：后面要改 `self` 的几个
        // 诊断字段，而借住 `self` 会挡住它们。`Arc` 的克隆不走文件系统。
        let source = self
            .source
            .clone()
            .ok_or_else(|| anyhow!("还没有打开任何本地来源"))?;
        if index >= source.len() {
            return Err(anyhow!("页下标越界: {index} / {}", source.len()));
        }

        // ── 1) 解码 ──
        //
        // 按**显示宽度**解，而不是原尺寸。这一步是这条路径省下大头的地方：
        // 44.8 MPix 的页全尺寸解码约 267 ms、位图 179 MB，而缩到显示尺寸后
        // 解码与上传都按面积等比下降（`docs/v0.1-local-core.md` §12）。
        // 解码器不会放大，所以传一个"过大"的宽度是安全的 —— 它自己会停在原宽。
        let hint = target_width.min(MAX_EDGE);

        // 先告诉预取线程"用户到这一页了、而且这一页还没出图"。顺序不能反：
        // 反过来的话，预取线程可能在这个窗口里按上一个锚点挑目标，
        // 而准入判决看到的还是"当前页已就绪"，于是正好在翻页的当口开始解码抢核。
        self.publish_show_start(index, hint, source.len());

        let t_decode = Instant::now();
        // 代次要**在拿缓存锁之前**读出来。两条线程的加锁顺序必须一致
        // （缓存 → 共享状态），反过来就有互锁的空间：这条路上是 `cache` 里再去
        // 锁 `shared`，而预取线程是 `shared` 解锁后去锁 `cache` —— 目前不会死，
        // 但那只是因为它恰好没有把两者嵌起来，不该指望这个巧合。
        let epoch = self.current_epoch();
        let cached = self
            .cache
            .lock()
            .ok()
            .and_then(|mut c| c.take(index, hint, epoch));
        let cache_hit = cached.is_some();
        let pixels = match cached {
            Some(pixels) => pixels,
            None => {
                if let Ok(mut c) = self.cache.lock() {
                    c.misses += 1;
                }
                source
                    .page_pixels_scaled(index, Some(hint))
                    .with_context(|| format!("第 {} 页解码失败", index + 1))?
            }
        };
        // 命中时这里读到的是"从缓存取走"的耗时（微秒级），不是解码耗时 ——
        // 这正是要报出来的东西：`cacheHit` 会一起进 stats，两者一起看才不会误读。
        let decode_ms = t_decode.elapsed().as_secs_f64() * 1000.0;
        self.last_cache_hit = cache_hit;

        self.decoded_width = pixels.width;
        self.decoded_height = pixels.height;
        self.decoded_source_width = pixels.source_width;
        self.decoded_source_height = pixels.source_height;

        if pixels.width == 0 || pixels.height == 0 {
            return Err(anyhow!("解码结果是 0×0"));
        }

        // ── 2) 上传到页纹理 ──
        let t_upload = Instant::now();
        self.upload_page(&pixels.rgba, pixels.width, pixels.height)?;
        let upload_ms = t_upload.elapsed().as_secs_f64() * 1000.0;

        // ── 3) 渲染 + GPU→GPU 拷贝 ──
        let t_submit = Instant::now();
        self.draw_and_copy(target_width, target_height)?;
        let submit_ms = t_submit.elapsed().as_secs_f64() * 1000.0;

        let timings = PresentTimings {
            decode_ms,
            upload_ms,
            submit_ms,
            wait_ms: 0.0,
            total_ms: t_total.elapsed().as_secs_f64() * 1000.0,
        };

        self.presents += 1;
        self.page_index = Some(index);
        self.last = timings;

        // 页确实上屏了才把锚点交出去。放在最后是有意的：预取的准入判决要读
        // "当前页已就绪"（`visible_pending == 0`），而这个事实到这一刻才成立。
        // 提前交锚点，等于告诉预取线程"可以开始抢核了"，而呈现线程还没画完。
        self.publish_show_end();
        Ok(timings)
    }

    /// 呈现线程：宣告"正在翻到第 `index` 页，而且它还没出图"。
    fn publish_show_start(&self, index: usize, hint: u32, page_count: usize) {
        if let Ok(mut shared) = self.hub.shared.lock() {
            shared.view.anchor = Some(index);
            shared.view.hint = hint;
            shared.view.page_count = page_count;
            shared.view.visible_pending = 1;
            shared.anchors_posted += 1;
        }
        self.hub.cv.notify_all();
    }

    /// 呈现线程：宣告"这一页确实出图了"，同时记下翻页时刻。
    ///
    /// 翻页时刻就是准入判决里的"滚动时刻"（`last_prefetch_scroll_at`）——
    /// 本地核心会在它之后 `PREFETCH_IDLE_THRESHOLD`（100 ms）内拦下所有预取。
    /// 记在 `show` **返回时**而不是开始时：`show` 自己就要几百毫秒，
    /// 从开始算的话这个"静默期"在翻页动作还没结束时就过期了，等于没有。
    fn publish_show_end(&self) {
        if let Ok(mut shared) = self.hub.shared.lock() {
            shared.view.last_show_at = Some(Instant::now());
            shared.view.visible_pending = 0;
        }
        self.hub.cv.notify_all();
    }

    /// 预取开关。默认开 —— 它就是修翻页延迟的那件事。
    ///
    /// 留这个开关是为了 A/B：**在同一份二进制上只改这一处**，才排得掉代码漂移
    /// 对数字的影响。环境变量 `ROSSI_GPU_PREFETCH=0` 是同一个开关的启动期写法。
    pub fn set_prefetch_enabled(&mut self, enabled: bool) {
        self.hub.enabled.store(enabled, Ordering::Relaxed);
        if let Ok(mut shared) = self.hub.shared.lock() {
            if !enabled {
                // 关掉时连锚点一起撤。不撤的话恢复时会先去解一页早就翻过去的页。
                shared.view.anchor = None;
            }
        }
        self.hub.cv.notify_all();
    }

    pub fn prefetch_enabled(&self) -> bool {
        self.hub.enabled.load(Ordering::Relaxed)
    }

    fn upload_page(&mut self, rgba: &[u8], width: u32, height: u32) -> Result<()> {
        let expected = width as usize * height as usize * 4;
        if rgba.len() < expected {
            return Err(anyhow!(
                "像素长度与尺寸不符: {} < {expected} ({width}×{height})",
                rgba.len()
            ));
        }

        let needs_new = match &self.page {
            Some(page) => page.width != width || page.height != height,
            None => true,
        };
        if needs_new {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("rossi-gpu-present-page"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: PAGE_FORMAT,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("rossi-gpu-present-page-bg"),
                layout: &self.pipeline.get_bind_group_layout(0),
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: self.uniform.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::TextureView(&view),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: wgpu::BindingResource::Sampler(&self.sampler),
                    },
                ],
            });
            self.page = Some(PageTexture {
                texture,
                bind_group,
                width,
                height,
            });
        }

        let page = self.page.as_ref().expect("刚刚保证过存在");
        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &page.texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            &rgba[..expected],
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(width * 4),
                rows_per_image: Some(height),
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );
        Ok(())
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
                            load: wgpu::LoadOp::Clear(wgpu::Color {
                                r: 0.02,
                                g: 0.02,
                                b: 0.03,
                                a: 1.0,
                            }),
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

    /// 当前共享句柄（尺寸变化后句柄会变，要在 `ensure_target` 之后再取）。
    pub fn handle(&self) -> HANDLE {
        self.target
            .as_ref()
            .map(|t| t.handle)
            .unwrap_or(HANDLE(std::ptr::null_mut()))
    }

    /// 当前正在用的那一代的编号 —— C++ 侧要把它交给 `release_callback`
    /// 作为 `release_context`，回调里再原样传回来。
    pub fn generation(&self) -> u64 {
        self.target.as_ref().map(|t| t.generation).unwrap_or(0)
    }

    pub fn target_size(&self) -> (u32, u32) {
        self.target
            .as_ref()
            .map(|t| (t.width, t.height))
            .unwrap_or((0, 0))
    }

    /// 呈现时实际用的**解码宽度提示**。
    ///
    /// 探针要用同一个值重新解码一遍作为基准 —— 否则两边落在不同的降采样档位，
    /// 比出来的差异会来自降采样而不是来自 GPU 路径，那就白比了。
    pub fn decode_hint(&self) -> u32 {
        self.target
            .as_ref()
            .map(|t| t.width.min(MAX_EDGE))
            .unwrap_or(0)
    }

    /// 这一页在目标里被画在哪个矩形 `(x, y, w, h)`（同样的 letterbox 算式）。
    pub fn expected_draw_rect(&self) -> Option<(f32, f32, f32, f32)> {
        let target = self.target.as_ref()?;
        let page = self.page.as_ref()?;
        let scale = f64::min(
            target.width as f64 / page.width as f64,
            target.height as f64 / page.height as f64,
        );
        let draw_w = (page.width as f64 * scale).round().max(1.0) as f32;
        let draw_h = (page.height as f64 * scale).round().max(1.0) as f32;
        let x = ((target.width as f32 - draw_w) * 0.5).max(0.0);
        let y = ((target.height as f32 - draw_h) * 0.5).max(0.0);
        Some((x, y, draw_w, draw_h))
    }

    pub fn adapter_name(&self) -> &str {
        &self.adapter_name
    }

    /// 「直接对 wgpu 纹理调 `CreateSharedHandle`」的实测结论。
    ///
    /// 它不是断言也不是常量，是**启动时真跑了一次**的结果（见 [`probe_direct_share`]）。
    /// 探针把它打印出来：如果哪天驱动放开了这条路，这个字符串会变成"成功(意外)"，
    /// 那就是"可以去掉那次拷贝"的信号。
    pub fn direct_share_verdict(&self) -> &str {
        &self.direct_share
    }

    /// 最近一次呈现时实际解出的尺寸（降采样之后）。
    pub fn decoded_size(&self) -> (u32, u32) {
        (self.decoded_width, self.decoded_height)
    }

    /// 最近一次呈现时解码器报告的**原始**尺寸（降采样之前）。
    pub fn source_size(&self) -> (u32, u32) {
        (self.decoded_source_width, self.decoded_source_height)
    }

    pub fn decoded_width(&self) -> u32 {
        self.decoded_width
    }

    pub fn decoded_height(&self) -> u32 {
        self.decoded_height
    }

    pub fn source_width(&self) -> u32 {
        self.decoded_source_width
    }

    pub fn source_height(&self) -> u32 {
        self.decoded_source_height
    }

    pub fn set_error(&mut self, message: String) {
        self.last_error = message;
    }

    pub fn last_error(&self) -> &str {
        &self.last_error
    }

    pub fn last_timings(&self) -> PresentTimings {
        self.last
    }

    /// 诊断快照（JSON）。
    ///
    /// 用 JSON 而不是固定结构体，是为了让 C++ 侧不必跟着改字段定义 ——
    /// 它原样透传给 Dart，Dart 侧按 key 取。代价是"字段名即接口"，改名前要 grep。
    pub fn stats_json(&self) -> String {
        let (width, height) = self.target_size();
        let timings = self.last;

        // 缓存统计要先取出来：`format!` 的参数位里写不了语句。
        let (hits, misses, cache_bytes, decoded, stale, evicted, in_flight) = self
            .cache
            .lock()
            .map(|c| {
                (
                    c.hits,
                    c.misses,
                    c.bytes() as u64,
                    c.prefetched,
                    c.stale,
                    c.evicted,
                    c.in_flight.map(|i| i as i64).unwrap_or(-1),
                )
            })
            .unwrap_or((0, 0, 0, 0, 0, 0, -1));
        let prefetch_on = self.prefetch_enabled();

        format!(
            concat!(
                "{{",
                "\"backend\":\"wgpu/dx12\",",
                "\"adapter\":\"{}\",",
                "\"adapterMatched\":{},",
                "\"adapterLuid\":\"{:#x}\",",
                "\"targetLuid\":\"{:#x}\",",
                "\"directShareOfWgpuTexture\":\"{}\",",
                "\"copyPath\":\"GPU->GPU CopyResource\",",
                "\"initMs\":{:.1},",
                "\"initDeviceMs\":{:.1},",
                "\"initPipelineMs\":{:.1},",
                "\"initRestMs\":{:.1},",
                "\"width\":{},",
                "\"height\":{},",
                "\"presents\":{},",
                "\"recreates\":{},",
                "\"retired\":{},",
                "\"releasedTotal\":{},",
                "\"generation\":{},",
                "\"handle\":{},",
                "\"pageCount\":{},",
                "\"pageIndex\":{},",
                "\"decodedWidth\":{},",
                "\"decodedHeight\":{},",
                "\"sourceWidth\":{},",
                "\"sourceHeight\":{},",
                "\"decodeMs\":{:.1},",
                "\"uploadMs\":{:.1},",
                "\"submitMs\":{:.1},",
                "\"totalMs\":{:.1},",
                "\"cacheHit\":{},",
                "\"cacheHits\":{},",
                "\"cacheMisses\":{},",
                "\"cacheBytes\":{},",
                "\"prefetchEnabled\":{},",
                "\"prefetchDecoded\":{},",
                "\"prefetchStale\":{},",
                "\"prefetchEvicted\":{},",
                "\"prefetchInFlight\":{},",
                "\"error\":\"{}\"",
                "}}"
            ),
            escape(&self.adapter_name),
            self.adapter_matched,
            self.adapter_luid,
            self.target_luid,
            escape(&self.direct_share),
            self.init_ms,
            self.init_device_ms,
            self.init_pipeline_ms,
            self.init_rest_ms,
            width,
            height,
            self.presents,
            self.recreates,
            self.retired.len(),
            self.released_total,
            self.generation(),
            self.handle().0 as usize,
            self.page_count(),
            self.page_index.map(|i| i as i64).unwrap_or(-1),
            self.decoded_width,
            self.decoded_height,
            self.decoded_source_width,
            self.decoded_source_height,
            timings.decode_ms,
            timings.upload_ms,
            timings.submit_ms,
            timings.total_ms,
            self.last_cache_hit,
            hits,
            misses,
            cache_bytes,
            prefetch_on,
            decoded,
            stale,
            evicted,
            in_flight,
            escape(&self.last_error),
        )
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

/// 画布底色（与着色器里的常量、以及 `LoadOp::Clear` 的值必须一致）。
///
/// 三处写的是同一个颜色，改一处就要改三处 —— 这是这个设计里最容易腐化的地方，
/// 所以它只作为 **UNORM8 下的比较基准** 出现在这里（探针用），
/// 真正的来源是着色器常量。
pub const BACKGROUND_RGBA8: [u8; 4] = [5, 5, 8, 255];

/// 判定"这个像素就是底色"的容差。
///
/// GPU 的 clear 值到 UNORM8 是**舍入**而不是截断，不同驱动可能差 1；
/// 再加上 `LoadOp::Clear` 与片元输出底色两条路径，容差 4 足够安全。
/// 只在探针里用到（回读比对），所以跟着 feature 走。
#[cfg(feature = "probe")]
const BACKGROUND_TOLERANCE: i32 = 4;

/// 从共享纹理回读下来的一帧。
///
/// 只在 `probe` feature 下存在。它存在的意义是：**在没有 Flutter 的情况下**证明
/// 「解码 → 上传 → 渲染 → 拷贝到共享纹理」真的产出了正确的像素。
/// 没有它，这条链路的正确性只能靠"打开 App 看一眼"，那不是可回归的验证。
#[cfg(feature = "probe")]
#[derive(Debug, Clone)]
pub struct Readback {
    pub width: u32,
    pub height: u32,
    /// BGRA8，行已去掉 256 字节对齐填充。
    pub bgra: Vec<u8>,
}

#[cfg(feature = "probe")]
impl Readback {
    pub fn pixel(&self, x: u32, y: u32) -> [u8; 4] {
        let offset = ((y * self.width + x) * 4) as usize;
        [
            self.bgra[offset],
            self.bgra[offset + 1],
            self.bgra[offset + 2],
            self.bgra[offset + 3],
        ]
    }

    /// 这个像素是不是画布底色。
    pub fn is_background(&self, x: u32, y: u32) -> bool {
        let [b, g, r, _] = self.pixel(x, y);
        (r as i32 - BACKGROUND_RGBA8[0] as i32).abs() <= BACKGROUND_TOLERANCE
            && (g as i32 - BACKGROUND_RGBA8[1] as i32).abs() <= BACKGROUND_TOLERANCE
            && (b as i32 - BACKGROUND_RGBA8[2] as i32).abs() <= BACKGROUND_TOLERANCE
    }

    /// 底色像素占比。letterbox 的上下（或左右）黑边就体现在这个数上。
    pub fn background_ratio(&self) -> f64 {
        let mut count = 0u64;
        for y in 0..self.height {
            for x in 0..self.width {
                if self.is_background(x, y) {
                    count += 1;
                }
            }
        }
        count as f64 / (self.width as f64 * self.height as f64)
    }

    /// 非底色像素的包围盒 `(x0, y0, x1, y1)`（右下开区间）。全底色时返回 `None`。
    pub fn content_bounds(&self) -> Option<(u32, u32, u32, u32)> {
        let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
        for y in 0..self.height {
            for x in 0..self.width {
                if !self.is_background(x, y) {
                    x0 = x0.min(x);
                    y0 = y0.min(y);
                    x1 = x1.max(x + 1);
                    y1 = y1.max(y + 1);
                }
            }
        }
        if x0 == u32::MAX {
            None
        } else {
            Some((x0, y0, x1, y1))
        }
    }

    /// 平均亮度（0..255）。用来把"全黑"和"有内容"分开 —— 这一条不看颜色构成。
    pub fn mean_luma(&self) -> f64 {
        let mut sum = 0u64;
        for pixel in self.bgra.chunks_exact(4) {
            let (b, g, r) = (pixel[0] as u64, pixel[1] as u64, pixel[2] as u64);
            // Rec.601 权重，只为判断"有没有内容"，不需要精确。
            sum += (r * 299 + g * 587 + b * 114) / 1000;
        }
        sum as f64 / (self.width as f64 * self.height as f64)
    }
}

#[cfg(feature = "probe")]
impl Presenter {
    /// 把当前共享纹理回读到 CPU。
    ///
    /// 路径：共享纹理 `COPY_SOURCE` → READBACK 堆缓冲（行距按 256 对齐）→ `Map`。
    /// 全程在**我们自己的 device** 上，所以不需要跟 Flutter 抢任何东西。
    pub fn readback_bgra(&mut self) -> Result<Readback> {
        let (width, height) = self.target_size();
        if width == 0 || height == 0 {
            return Err(anyhow!("还没有呈现目标，无法回读"));
        }
        let target = self
            .target
            .as_ref()
            .ok_or_else(|| anyhow!("还没有呈现目标，无法回读"))?;
        let shared = target.shared.clone();

        // D3D12 要求 placed footprint 的行距按 256 字节对齐。
        let row_pitch = (width * 4).div_ceil(256) * 256;
        let buffer_size = row_pitch as u64 * height as u64;

        let heap = D3D12_HEAP_PROPERTIES {
            Type: D3D12_HEAP_TYPE_READBACK,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 1,
            VisibleNodeMask: 1,
        };
        let desc = D3D12_RESOURCE_DESC {
            Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
            Alignment: 0,
            Width: buffer_size,
            Height: 1,
            DepthOrArraySize: 1,
            MipLevels: 1,
            Format: DXGI_FORMAT_UNKNOWN,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Layout: D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
            Flags: D3D12_RESOURCE_FLAG_NONE,
        };

        let mut staging: Option<ID3D12Resource> = None;
        unsafe {
            self.d3d_device
                .CreateCommittedResource(
                    &heap,
                    D3D12_HEAP_FLAG_NONE,
                    &desc,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                    None,
                    &mut staging,
                )
                .map_err(|e| anyhow!("CreateCommittedResource(READBACK) 失败: {e:?}"))?;
        }
        let staging = staging.ok_or_else(|| anyhow!("READBACK 资源为空"))?;

        let destination = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::ManuallyDrop::new(Some(staging.clone())),
            Type: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                PlacedFootprint: D3D12_PLACED_SUBRESOURCE_FOOTPRINT {
                    Offset: 0,
                    Footprint: D3D12_SUBRESOURCE_FOOTPRINT {
                        Format: FORMAT,
                        Width: width,
                        Height: height,
                        Depth: 1,
                        RowPitch: row_pitch,
                    },
                },
            },
        };
        let source = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::ManuallyDrop::new(Some(shared.clone())),
            Type: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                SubresourceIndex: 0,
            },
        };

        unsafe {
            self.allocator
                .Reset()
                .map_err(|e| anyhow!("Allocator::Reset 失败: {e}"))?;
            self.cmd_list
                .Reset(&self.allocator, None)
                .map_err(|e| anyhow!("CommandList::Reset 失败: {e}"))?;

            let mut into = [transition(
                &shared,
                D3D12_RESOURCE_STATE_COMMON,
                D3D12_RESOURCE_STATE_COPY_SOURCE,
            )];
            self.cmd_list.ResourceBarrier(&into);
            release_barriers(&mut into);

            self.cmd_list
                .CopyTextureRegion(&destination, 0, 0, 0, &source, None);

            let mut back = [transition(
                &shared,
                D3D12_RESOURCE_STATE_COPY_SOURCE,
                D3D12_RESOURCE_STATE_COMMON,
            )];
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

            // 与呈现路径共用同一个严格单调递增的 fence 值。
            self.fence_value += 1;
            let value = self.fence_value;
            self.d3d_queue
                .Signal(&self.fence, value)
                .map_err(|e| anyhow!("Queue::Signal 失败: {e}"))?;
            if self.fence.GetCompletedValue() < value {
                self.fence
                    .SetEventOnCompletion(value, self.fence_event)
                    .map_err(|e| anyhow!("SetEventOnCompletion 失败: {e}"))?;
                let wait = WaitForSingleObject(self.fence_event, 4000);
                if wait != WAIT_OBJECT_0 {
                    return Err(anyhow!("等待回读完成超时: {wait:?}"));
                }
            }
        }

        // union 里的那份 COM 引用不会自动释放，手动放掉（与 release_barriers 同一个理由）。
        unsafe {
            let held: std::mem::ManuallyDrop<Option<ID3D12Resource>> =
                std::ptr::read(&destination.pResource);
            drop(std::mem::ManuallyDrop::into_inner(held));
            let held: std::mem::ManuallyDrop<Option<ID3D12Resource>> =
                std::ptr::read(&source.pResource);
            drop(std::mem::ManuallyDrop::into_inner(held));
        }

        let mut raw: *mut std::ffi::c_void = std::ptr::null_mut();
        unsafe {
            staging
                .Map(0, None, Some(&mut raw))
                .map_err(|e| anyhow!("READBACK Map 失败: {e}"))?;
        }
        if raw.is_null() {
            return Err(anyhow!("READBACK Map 返回空指针"));
        }

        let mut bgra = vec![0u8; (width * height * 4) as usize];
        unsafe {
            let base = raw as *const u8;
            for y in 0..height {
                let src = base.add((y * row_pitch) as usize);
                let dst = bgra.as_mut_ptr().add((y * width * 4) as usize);
                std::ptr::copy_nonoverlapping(src, dst, (width * 4) as usize);
            }
            staging.Unmap(0, None);
        }

        Ok(Readback {
            width,
            height,
            bgra,
        })
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
