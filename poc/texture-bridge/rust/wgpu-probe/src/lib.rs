//! Gate A / 风险 2 探针：wgpu(DX12) 渲染结果 → DXGI shared handle → Flutter 合成。
//!
//! # 为什么不能一步到位
//!
//! wgpu 创建 texture 时不会带 `D3D12_HEAP_FLAG_SHARED`，而 D3D12 的
//! `CreateSharedHandle` 明确要求资源是在 SHARED heap 上创建的。
//! 也就是说：**没法直接把 wgpu 的 texture 导出成 shared handle。**
//!
//! 所以本探针是两步：
//!   1. wgpu 渲染到自己的 texture（走完整的 shader / PSO 管线，证明是真渲染）
//!   2. 在同一台 ID3D12Device 上自建一张 SHARED texture，用原生命令列表
//!      `CopyResource` 把结果搬过去，再 `CreateSharedHandle` 导出
//!
//! 第 2 步是纯 GPU→GPU 拷贝，**不产生 CPU 往返**（这正是 Gate A 的验收项之一：
//! 不发生不必要的 GPU→CPU→GPU 回读）。
//!
//! 为了把上面的结论钉死，`create` 里会**实测**一次「直接对 wgpu texture 调
//! CreateSharedHandle」并把 HRESULT 记进 stats，作为证据而不是断言。
//!
//! # 状态管理上的一个灰色地带
//!
//! 我们用原生命令列表碰了 wgpu 拥有的 texture（`CopyResource` 的源），
//! 而 wgpu 内部对这张 texture 的 resource state 有自己的记账。
//! 这里的处理是：拷贝前 `RENDER_TARGET → COPY_SOURCE`，拷贝后立刻
//! `COPY_SOURCE → RENDER_TARGET` 还原，使 wgpu 的认知与真实状态保持一致。
//!
//! 这条约束很要紧：一旦 wgpu 认为的状态与实际不符，后面会变成难查的
//! 花屏 / 校验层报错。正式实现应当把这段迁移封装住，而不是散在调用点。

use std::ffi::c_void;
use std::mem::ManuallyDrop;
use std::panic::{catch_unwind, AssertUnwindSafe};

// 离屏拷贝带宽基准。
//
// 它不参与 Flutter 合成链路，纯粹是为了把「每帧一次 GPU→GPU 拷贝到底
// 值多少 GPU 时间」量出来 —— 帧率口径被 vsync 封顶，量不出真实吞吐。
pub mod bench;

use wgpu::hal::api::Dx12;
// Interface trait 必须在作用域内，否则 ID3D12Resource::cast() 找不到方法。
use windows::core::{Interface, PCWSTR};
use windows::Win32::Foundation::{GENERIC_ALL, HANDLE, WAIT_OBJECT_0};
use windows::Win32::Graphics::Direct3D12::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::Win32::Graphics::Dxgi::IDXGIAdapter3;
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};

/// 渲染目标格式。
///
/// 必须是 BGRA8 而不是 RGBA8：Flutter Windows 走 ANGLE / D3D11 打开这张
/// shared texture 来合成，D3D11 打不开 RGBA8 的共享纹理。
/// 风险 1 已经把这条验证过了，这里保持一致。
const FORMAT: DXGI_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM;
const WGPU_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;

/// 全屏三角形 + 片段着色器画色带。
///
/// 视觉约定与风险 1 的纯 Clear 版本刻意保持一致，这样同一套截屏像素校验
/// （左红 / 中绿 / 右蓝）可以直接复用，两条路径的输出可比对。
const SHADER: &str = r#"
struct VsOut {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var<uniform> params: vec4<f32>;

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
  out.uv = vec2<f32>((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let uv = in.uv;
  let phase = params.x;

  // 顶部 1/3：红 / 绿 / 蓝三条纯色带。
  // 屏幕上从左到右是红绿蓝 => 通道顺序正确；红蓝互换 => 被当成 RGBA 解释了。
  if (uv.y < 0.3333) {
    if (uv.x < 0.3333) { return vec4<f32>(1.0, 0.0, 0.0, 1.0); }
    if (uv.x < 0.6667) { return vec4<f32>(0.0, 1.0, 0.0, 1.0); }
    return vec4<f32>(0.0, 0.0, 1.0, 1.0);
  }

  // 中部横带里左右往返的白色方块：证明帧在持续更新，不是只画一次。
  if (uv.y >= 0.45 && uv.y < 0.55) {
    let box_w = 0.08;
    let x0 = phase * (1.0 - box_w);
    if (uv.x >= x0 && uv.x < x0 + box_w) {
      return vec4<f32>(1.0, 1.0, 1.0, 1.0);
    }
  }

  // 底部 1/3：随 phase 变色的横条。
  if (uv.y >= 0.6667) {
    return vec4<f32>(phase, 1.0 - phase, 0.5, 1.0);
  }

  return vec4<f32>(0.05, 0.06, 0.09, 1.0);
}
"#;

/// 尺寸变化时延迟释放的旧资源。
///
/// 引擎可能仍持有由旧 handle 打开的合成纹理，立刻释放会让它拿到失效资源。
/// 这是 PoC 的已知薄弱点，正式实现应改为基于 release_callback 的引用计数。
struct Retired {
    resource: ID3D12Resource,
    handle: HANDLE,
}

struct Probe {
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    uniform: wgpu::Buffer,

    // 尺寸相关：wgpu 侧渲染目标
    wgpu_texture: wgpu::Texture,
    wgpu_view: wgpu::TextureView,

    // 尺寸相关：原生共享纹理（真正交给 Flutter 的那张）
    shared: ID3D12Resource,
    handle: HANDLE,

    // 纯 GPU→GPU 拷贝用的原生命令设施（与 wgpu 共用同一个 device / queue）
    d3d_device: ID3D12Device,
    d3d_queue: ID3D12CommandQueue,
    allocator: ID3D12CommandAllocator,
    cmd_list: ID3D12GraphicsCommandList,
    fence: ID3D12Fence,
    fence_event: HANDLE,
    fence_value: u64,

    width: u32,
    height: u32,

    retired: Vec<Retired>,
    // 累计真正释放掉的旧资源数。
    //
    // 必须和 `retired`（延迟释放队列的当前深度，故意限制在 2 以内）分开统计：
    // 只看队列深度会得到一个恒等于 2 的数，无法判断有没有泄漏 —— 压测时就
    // 因为这个把「队列深度」误读成「累计退役数」，报了一次假泄漏。
    released_total: u64,

    // ── GPU 计时（timestamp query）──
    //
    // 墙钟帧时间同时包含「引擎合成 + Flutter raster + 平台通道往返」，无法把
    // copy 的代价单独归因出来。所以这里在 GPU 时间线上打三个点：
    //   T0 = 本帧开始（wgpu 渲染之前）
    //   T1 = 渲染结束 / 拷贝开始
    //   T2 = 拷贝结束
    // 于是 render_ms = T1-T0、copy_ms = T2-T1，都是纯 GPU 执行时间。
    //
    // 时序可靠性来自「同一个 ID3D12CommandQueue 上的命令按提交顺序执行」：
    // 我们先把只写 T0 的命令列表执行掉，再让 wgpu 提交渲染，最后提交带
    // T1 / T2 / Resolve 的列表。三者同队列，顺序有保障。
    //
    // 注意每帧末尾都会等 fence（GPU 空转后才记下一帧），所以量到的是 copy
    // 的**独占时长**，不是它在流水线里的边际成本。这个口径更严格，也正好是
    // 「次拷贝到底值多少 GPU 时间」这个问题要的数。
    query_heap: Option<ID3D12QueryHeap>,
    readback: Option<ID3D12Resource>,
    // 常驻映射的指针：READBACK 堆允许长期 Map，避免每帧 Map/Unmap 抖动。
    readback_ptr: *mut u64,
    ts_freq: u64,
    // 打 T0 的那个列表要独立 allocator：D3D12 禁止在命令列表仍在执行时
    // Reset 它所属的 allocator，而同一帧里两个列表是连续提交的。
    ts_allocator: Option<ID3D12CommandAllocator>,
    ts_list: Option<ID3D12GraphicsCommandList>,
    ts_supported: bool,
    ts_note: String,

    // 帧内容开关，用来做差分实验（见 set_mode）
    render_enabled: bool,
    copy_enabled: bool,

    // 窗口统计：reset_stats 清零，供基准脚本按固定窗口取均值 / 峰值。
    // 用窗口而不是指数滑动平均，是为了让「重置 → 稳定跑 N 秒 → 读」这套
    // 流程拿到的数字可复现。
    window_frames: u64,
    window_render_ms_total: f64,
    window_render_ms_max: f64,
    window_copy_ms_total: f64,
    window_copy_ms_max: f64,
    last_render_ms: f64,
    last_copy_ms: f64,

    // 诊断
    adapter_name: String,
    adapter_matched: bool,
    adapter_luid: u64,
    direct_share: String,
    init_ms: f64,
    frames: u64,
    copies: u64,
    recreates: u32,
    last_error: String,
}

impl Probe {
    /// 建一张 SHARED 的 BGRA8 渲染目标并导出 handle。
    fn create_shared_target(
        d3d_device: &ID3D12Device,
        width: u32,
        height: u32,
    ) -> Result<(ID3D12Resource, HANDLE), String> {
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
                .map_err(|e| {
                    format!("CreateCommittedResource(SHARED) 失败: {:?}", e.code().0)
                })?;
        }
        let resource = resource.ok_or_else(|| "CreateCommittedResource 返回空".to_string())?;

        let child: ID3D12DeviceChild = resource
            .cast()
            .map_err(|e| format!("ID3D12Resource -> ID3D12DeviceChild 失败: {e}"))?;

        // GENERIC_ALL 而非只读：D3D11 侧打开时需要完整的访问位。
        let handle = unsafe {
            d3d_device
                .CreateSharedHandle(&child, None, GENERIC_ALL.0, PCWSTR::null())
                .map_err(|e| format!("CreateSharedHandle 失败: {:?}", e.code().0))?
        };

        Ok((resource, handle))
    }

    fn build_render_targets(
        device: &wgpu::Device,
        d3d_device: &ID3D12Device,
        width: u32,
        height: u32,
    ) -> Result<(wgpu::Texture, wgpu::TextureView, ID3D12Resource, HANDLE), String> {
        let wgpu_texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("probe-wgpu-target"),
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
        let wgpu_view = wgpu_texture.create_view(&wgpu::TextureViewDescriptor::default());
        let (shared, handle) = Probe::create_shared_target(d3d_device, width, height)?;
        Ok((wgpu_texture, wgpu_view, shared, handle))
    }

    fn new(target_luid: u64, width: u32, height: u32) -> Result<Probe, String> {
        let t0 = std::time::Instant::now();

        let mut idesc = wgpu::InstanceDescriptor::default();
        idesc.backends = wgpu::Backends::DX12;
        let instance = wgpu::Instance::new(&idesc);

        // 优先挑 Flutter 自己正在用的那块 adapter。
        // 跨 adapter 共享 texture 在多数机器上会失败或掉进极慢的拷贝路径，
        // 所以「选中同一块卡」是硬约束，不是优化。
        let adapters: Vec<wgpu::Adapter> = instance.enumerate_adapters(wgpu::Backends::DX12);
        if adapters.is_empty() {
            return Err("枚举不到任何 DX12 adapter".to_string());
        }

        let mut picked: Option<(wgpu::Adapter, String, bool)> = None;
        let mut candidates: Vec<String> = Vec::new();
        for adapter in adapters {
            let name = adapter.get_info().name.clone();
            let mut luid = 0u64;
            // as_hal 拿到 dx12 后端的裸 IDXGIAdapter3，用它读真正的 LUID。
            // 单靠 AdapterInfo 无法可靠地对应到 Flutter 的适配器。
            if let Some(hal) = unsafe { adapter.as_hal::<Dx12>() } {
                let raw: &IDXGIAdapter3 = hal.as_raw();
                if let Ok(desc) = unsafe { raw.GetDesc() } {
                    luid = ((desc.AdapterLuid.HighPart as u64) << 32)
                        | (desc.AdapterLuid.LowPart as u64);
                }
            }
            let matched = luid == target_luid;
            candidates.push(format!("{name}[{luid:#x}]{}", if matched { "*" } else { "" }));
            if matched {
                picked = Some((adapter, name, true));
                break;
            }
            if picked.is_none() {
                picked = Some((adapter, name, false));
            }
        }

        let (adapter, adapter_name, adapter_matched) = picked.unwrap();

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("wgpu-probe"),
            ..Default::default()
        }))
        .map_err(|e| format!("request_device 失败: {e}"))?;

        // 取裸 D3D12 device / queue。两者都 Clone 出独立引用计数，
        // 这样后续不必一直握着借用 device 的 as_hal guard。
        let hal_device = unsafe { device.as_hal::<Dx12>() }
            .ok_or_else(|| "device 不是 DX12 后端".to_string())?;
        let d3d_device: ID3D12Device = hal_device.raw_device().clone();
        let d3d_queue: ID3D12CommandQueue = hal_device.raw_queue().clone();
        drop(hal_device);

        let (wgpu_texture, wgpu_view, shared, handle) =
            Probe::build_render_targets(&device, &d3d_device, width, height)?;

        // ── 关键证据：直接对 wgpu 的 texture 调 CreateSharedHandle ──
        // 预期失败（E_INVALIDARG），因为 wgpu 没用 SHARED heap 建它。
        // 这条记录就是「为什么必须多走一次 GPU 拷贝」的硬证据。
        let direct_share = unsafe {
            let raw = wgpu_texture
                .as_hal::<Dx12>()
                .map(|t| t.raw_resource().clone());
            match raw {
                None => "wgpu texture 取不到裸资源".to_string(),
                Some(res) => match res.cast::<ID3D12DeviceChild>() {
                    Err(e) => format!("cast 失败: {e}"),
                    Ok(child) => match d3d_device.CreateSharedHandle(
                        &child,
                        None,
                        GENERIC_ALL.0,
                        PCWSTR::null(),
                    ) {
                        Ok(h) => {
                            // 居然成功了（例如某些驱动/未来版本放开）。
                            // 关掉它，我们仍然走拷贝路径以保证行为一致。
                            let _ = windows::Win32::Foundation::CloseHandle(h);
                            "成功(意外)".to_string()
                        }
                        Err(e) => format!("失败 {:?}", e.code().0),
                    },
                },
            }
        };

        // 着色器管线
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("probe-shader"),
            source: wgpu::ShaderSource::Wgsl(SHADER.into()),
        });

        let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("probe-bgl"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        let uniform = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("probe-uniform"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("probe-bg"),
            layout: &bgl,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform.as_entire_binding(),
            }],
        });

        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("probe-layout"),
            bind_group_layouts: &[&bgl],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("probe-pipeline"),
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

        // 同步大法：每帧拷贝后要等它在 GPU 上真正落地，
        // 否则 handle 交出去时数据可能还没写完。
        // 注意这几个方法在 windows-rs 里是**返回值风格**（Result<T>），
        // 不是 out 参数风格；接口类型要靠 turbofish 指定，否则 T 无法推断。
        let (allocator, cmd_list, fence, fence_event) = unsafe {
            let allocator = d3d_device
                .CreateCommandAllocator::<ID3D12CommandAllocator>(D3D12_COMMAND_LIST_TYPE_DIRECT)
                .map_err(|e| format!("CreateCommandAllocator 失败: {e}"))?;

            let cmd_list = d3d_device
                .CreateCommandList::<_, _, ID3D12GraphicsCommandList>(
                    0,
                    D3D12_COMMAND_LIST_TYPE_DIRECT,
                    &allocator,
                    None::<&ID3D12PipelineState>,
                )
                .map_err(|e| format!("CreateCommandList 失败: {e}"))?;
            cmd_list
                .Close()
                .map_err(|e| format!("CommandList::Close 失败: {e}"))?;

            let fence = d3d_device
                .CreateFence::<ID3D12Fence>(0, D3D12_FENCE_FLAG_NONE)
                .map_err(|e| format!("CreateFence 失败: {e}"))?;

            let event = CreateEventW(None, false, false, None)
                .map_err(|e| format!("CreateEventW 失败: {e}"))?;
            (allocator, cmd_list, fence, event)
        };

        // ── GPU 计时设施 ──
        // 任何一环不可用都只降级为「没有 GPU 时间」，不能让整个探针起不来：
        // 墙钟数据仍然有效，只是无法归因。
        let mut ts_note = String::new();
        let mut query_heap: Option<ID3D12QueryHeap> = None;
        let mut readback: Option<ID3D12Resource> = None;
        let mut readback_ptr: *mut u64 = std::ptr::null_mut();
        let mut ts_allocator: Option<ID3D12CommandAllocator> = None;
        let mut ts_list: Option<ID3D12GraphicsCommandList> = None;
        let mut ts_freq = 0u64;

        unsafe {
            match d3d_queue.GetTimestampFrequency() {
                Ok(f) if f > 0 => ts_freq = f,
                Ok(_) => ts_note = "队列时间戳频率为 0".to_string(),
                Err(e) => ts_note = format!("GetTimestampFrequency 失败: {e}"),
            }

            if ts_freq > 0 {
                let heap_desc = D3D12_QUERY_HEAP_DESC {
                    Type: D3D12_QUERY_HEAP_TYPE_TIMESTAMP,
                    Count: 3,
                    NodeMask: 0,
                };
                // 注意 windows-rs 这里是 **out 参数风格**（Result<()> + 末尾
                // 的 *mut Option<T>），不是返回值风格 —— 和
                // CreateCommandAllocator / CreateFence 的写法正好相反。
                let mut qh: Option<ID3D12QueryHeap> = None;
                match d3d_device.CreateQueryHeap(&heap_desc, &mut qh) {
                    Ok(()) => match qh {
                        Some(h) => query_heap = Some(h),
                        None => ts_note = "CreateQueryHeap 返回空".to_string(),
                    },
                    Err(e) => ts_note = format!("CreateQueryHeap 失败: {e}"),
                }
            }

            if query_heap.is_some() {
                // READBACK 堆：GPU 写、CPU 读。宽度取 256 满足 D3D12 的
                // 行距对齐要求，实际只用前 24 字节（3 × u64）。
                let rb_desc = D3D12_RESOURCE_DESC {
                    Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
                    Alignment: 0,
                    Width: 256,
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
                let rb_heap = D3D12_HEAP_PROPERTIES {
                    Type: D3D12_HEAP_TYPE_READBACK,
                    CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
                    MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
                    CreationNodeMask: 1,
                    VisibleNodeMask: 1,
                };
                let mut rb_opt: Option<ID3D12Resource> = None;
                match d3d_device.CreateCommittedResource(
                    &rb_heap,
                    D3D12_HEAP_FLAG_NONE,
                    &rb_desc,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                    None,
                    &mut rb_opt,
                ) {
                    Ok(()) => match rb_opt {
                        Some(rb) => {
                            // Map 的第三个参数是 *mut *mut c_void（out），
                            // 不能直接传 *mut u64 —— 类型对不上，要先接一个
                            // c_void 的中转再 cast。
                            let mut raw: *mut c_void = std::ptr::null_mut();
                            match rb.Map(0, None, Some(&mut raw)) {
                                Ok(()) => {
                                    readback_ptr = raw as *mut u64;
                                    readback = Some(rb);
                                }
                                Err(e) => ts_note = format!("readback Map 失败: {e}"),
                            }
                        }
                        None => ts_note = "readback 资源为空".to_string(),
                    },
                    Err(e) => ts_note = format!("CreateCommittedResource(readback) 失败: {e}"),
                }
            }

            if readback.is_some() {
                match d3d_device.CreateCommandAllocator::<ID3D12CommandAllocator>(
                    D3D12_COMMAND_LIST_TYPE_DIRECT,
                ) {
                    Ok(a) => match d3d_device.CreateCommandList::<_, _, ID3D12GraphicsCommandList>(
                        0,
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                        &a,
                        None::<&ID3D12PipelineState>,
                    ) {
                        Ok(l) => {
                            let _ = l.Close();
                            ts_allocator = Some(a);
                            ts_list = Some(l);
                        }
                        Err(e) => ts_note = format!("计时用 CreateCommandList 失败: {e}"),
                    },
                    Err(e) => ts_note = format!("计时用 CreateCommandAllocator 失败: {e}"),
                }
            }
        }

        let ts_supported = query_heap.is_some()
            && readback.is_some()
            && ts_allocator.is_some()
            && ts_list.is_some()
            && ts_freq > 0;
        if !ts_supported && ts_note.is_empty() {
            ts_note = "未知原因".to_string();
        }

        Ok(Probe {
            device,
            queue,
            pipeline,
            bind_group,
            uniform,
            wgpu_texture,
            wgpu_view,
            shared,
            handle,
            d3d_device,
            d3d_queue,
            allocator,
            cmd_list,
            fence,
            fence_event,
            fence_value: 0,
            query_heap,
            readback,
            readback_ptr,
            ts_freq,
            ts_allocator,
            ts_list,
            ts_supported,
            ts_note,
            render_enabled: true,
            copy_enabled: true,
            window_frames: 0,
            window_render_ms_total: 0.0,
            window_render_ms_max: 0.0,
            window_copy_ms_total: 0.0,
            window_copy_ms_max: 0.0,
            last_render_ms: 0.0,
            last_copy_ms: 0.0,
            width,
            height,
            retired: Vec::new(),
            released_total: 0,
            adapter_name,
            adapter_matched,
            adapter_luid: target_luid,
            direct_share,
            init_ms: t0.elapsed().as_secs_f64() * 1000.0,
            frames: 0,
            copies: 0,
            recreates: 0,
            last_error: String::new(),
        })
    }

    /// 在给定列表上写一个时间戳点；计时不可用时静默跳过。
    unsafe fn stamp(&self, list: &ID3D12GraphicsCommandList, slot: u32) {
        if let Some(heap) = &self.query_heap {
            list.EndQuery(heap, D3D12_QUERY_TYPE_TIMESTAMP, slot);
        }
    }

    /// 把 T0 写进 GPU 时间线并立刻执行。
    ///
    /// 必须排在 wgpu 提交渲染**之前**：两者提交到同一个 D3D12 队列，
    /// 同队列的命令按提交顺序执行，所以 T0 一定先于渲染落笔。
    fn stamp_frame_start(&mut self) -> Result<(), String> {
        if !self.ts_supported {
            return Ok(());
        }
        let (alloc, list) = match (&self.ts_allocator, &self.ts_list) {
            (Some(a), Some(l)) => (a, l),
            _ => return Ok(()),
        };
        unsafe {
            alloc
                .Reset()
                .map_err(|e| format!("计时 allocator Reset 失败: {e}"))?;
            list.Reset(alloc, None)
                .map_err(|e| format!("计时列表 Reset 失败: {e}"))?;
            self.stamp(list, 0);
            list.Close()
                .map_err(|e| format!("计时列表 Close 失败: {e}"))?;
            let raw: ID3D12CommandList = list
                .cast()
                .map_err(|e| format!("计时列表 cast 失败: {e}"))?;
            self.d3d_queue.ExecuteCommandLists(&[Some(raw)]);
        }
        Ok(())
    }

    /// 本帧收尾：可选地做 GPU→GPU 拷贝，并在 GPU 时间线上落 T1 / T2 两个点。
    ///
    /// `do_copy = false` 时仍会提交一个只写时间戳的空列表：差分实验里
    /// 「不拷贝」那一组必须走同一套时序，否则量到的差值会混进别的东西。
    fn finish_frame(&mut self, do_copy: bool) -> Result<(), String> {
        // guard 必须在取得之后立刻释放：下面要可变借用 self.allocator /
        // self.cmd_list，如果 as_hal 的 guard 活到那个时候，就会和
        // &mut self 冲突。原写法用 Option::map 会 move 掉 guard，
        // 导致 drop(src_hal) 变成 use-after-move。
        let src: Option<ID3D12Resource> = if do_copy {
            let guard = unsafe { self.wgpu_texture.as_hal::<Dx12>() }
                .ok_or_else(|| "wgpu texture 取不到 dx12 句柄".to_string())?;
            Some(unsafe { guard.raw_resource().clone() })
        } else {
            None
        };

        unsafe {
            self.allocator
                .Reset()
                .map_err(|e| format!("Allocator::Reset 失败: {e}"))?;
            self.cmd_list
                .Reset(&self.allocator, None)
                .map_err(|e| format!("CommandList::Reset 失败: {e}"))?;

            // T1 = 渲染结束 / 拷贝开始
            self.stamp(&self.cmd_list, 1);

            if let Some(src) = &src {
                // wgpu 提交渲染后，它记账里这张 texture 是 RENDER_TARGET。
                // 我们照它的认知做迁移，拷完再还原回去，避免两边状态分叉。
                let mut barriers = [
                    transition(src, D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_SOURCE),
                    transition(&self.shared, D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST),
                ];
                self.cmd_list.ResourceBarrier(&barriers);
                release_barriers(&mut barriers);

                self.cmd_list.CopyResource(&self.shared, src);

                let mut back = [
                    transition(src, D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_RENDER_TARGET),
                    transition(&self.shared, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COMMON),
                ];
                self.cmd_list.ResourceBarrier(&back);
                release_barriers(&mut back);
            }

            // T2 = 拷贝结束（含 barrier 与状态迁移）
            self.stamp(&self.cmd_list, 2);
            if let (Some(heap), Some(rb)) = (&self.query_heap, &self.readback) {
                self.cmd_list.ResolveQueryData(
                    heap,
                    D3D12_QUERY_TYPE_TIMESTAMP,
                    0,
                    3,
                    rb,
                    0,
                );
            }

            self.cmd_list
                .Close()
                .map_err(|e| format!("CommandList::Close 失败: {e}"))?;

            let list: ID3D12CommandList = self
                .cmd_list
                .cast()
                .map_err(|e| format!("cast 到 ID3D12CommandList 失败: {e}"))?;
            self.d3d_queue.ExecuteCommandLists(&[Some(list)]);

            self.fence_value += 1;
            self.d3d_queue
                .Signal(&self.fence, self.fence_value)
                .map_err(|e| format!("Queue::Signal 失败: {e}"))?;
            if self.fence.GetCompletedValue() < self.fence_value {
                self.fence
                    .SetEventOnCompletion(self.fence_value, self.fence_event)
                    .map_err(|e| format!("SetEventOnCompletion 失败: {e}"))?;
                let wait = WaitForSingleObject(self.fence_event, 2000);
                if wait != WAIT_OBJECT_0 {
                    return Err(format!("等待拷贝完成超时: {wait:?}"));
                }
            }
        }

        if src.is_some() {
            self.copies += 1;
        }
        // fence 已经等到，resolve 的结果此刻一定在 readback 内存里。
        self.read_timestamps();
        Ok(())
    }

    /// 取出 T0 / T1 / T2 并累计到当前窗口。
    ///
    /// 必须在 fence 等待之后调用：等到了就说明 resolve 已经落内存。
    fn read_timestamps(&mut self) {
        if !self.ts_supported || self.readback_ptr.is_null() {
            return;
        }
        let scale = 1000.0 / self.ts_freq as f64;
        let (t0, t1, t2) = unsafe {
            (
                *self.readback_ptr,
                *self.readback_ptr.add(1),
                *self.readback_ptr.add(2),
            )
        };
        // t0 == 0 说明这一轮没打上点（例如首帧或计时列表未执行），丢弃样本。
        if t0 == 0 || t2 <= t0 {
            return;
        }
        let render_ms = t1.saturating_sub(t0) as f64 * scale;
        let copy_ms = t2.saturating_sub(t1) as f64 * scale;
        self.last_render_ms = render_ms;
        self.last_copy_ms = copy_ms;
        self.window_render_ms_total += render_ms;
        self.window_copy_ms_total += copy_ms;
        if render_ms > self.window_render_ms_max {
            self.window_render_ms_max = render_ms;
        }
        if copy_ms > self.window_copy_ms_max {
            self.window_copy_ms_max = copy_ms;
        }
    }

    /// 设置帧内容开关，供差分实验使用。
    ///
    /// 「换不换方案」取决于 copy 在帧时间里的占比，而墙钟帧时间混着引擎合成 /
    /// Flutter raster / 平台通道往返。差分是把它剥离出来的唯一办法：
    ///   render+copy  vs  render-only  → 一次 copy 的墙钟代价
    /// 拿这个值和 GPU 实测的 copy_ms 对齐，就能判断引擎内部有没有多出一次拷贝。
    fn set_mode(&mut self, render: bool, copy: bool) {
        self.render_enabled = render;
        self.copy_enabled = copy;
    }

    /// 清零窗口统计。基准脚本按「重置 → 稳定跑 N 秒 → 读」取数，
    /// 避免把初始化阶段和预热抖动算进均值。
    fn reset_stats(&mut self) {
        self.window_frames = 0;
        self.window_render_ms_total = 0.0;
        self.window_render_ms_max = 0.0;
        self.window_copy_ms_total = 0.0;
        self.window_copy_ms_max = 0.0;
        self.last_render_ms = 0.0;
        self.last_copy_ms = 0.0;
        self.frames = 0;
        self.copies = 0;
        self.recreates = 0;
    }

    fn render(&mut self, phase: f32) -> Result<(), String> {
        // T0 必须排在 wgpu 提交之前。
        self.stamp_frame_start()?;

        if self.render_enabled {
            let mut bytes = [0u8; 16];
            bytes[0..4].copy_from_slice(&phase.to_le_bytes());
            self.queue.write_buffer(&self.uniform, 0, &bytes);

            let mut encoder = self
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("probe-encoder"),
                });
            {
                let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("probe-pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &self.wgpu_view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color {
                                r: 0.05,
                                g: 0.06,
                                b: 0.09,
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
                pass.set_bind_group(0, &self.bind_group, &[]);
                pass.draw(0..3, 0..1);
            }
            self.queue.submit([encoder.finish()]);
        }

        // wgpu 的 submit 是同步写进同一个 D3D12 queue 的，
        // 所以紧随其后的拷贝命令天然排在渲染之后，顺序有保障。
        self.finish_frame(self.copy_enabled)?;
        self.frames += 1;
        self.window_frames += 1;
        Ok(())
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<(), String> {
        self.resize_impl(width, height, false)
    }

    /// 强制按当前尺寸重建，用于验证销毁 / 重建路径。
    fn recreate(&mut self) -> Result<(), String> {
        let (width, height) = (self.width, self.height);
        self.resize_impl(width, height, true)
    }

    fn resize_impl(&mut self, width: u32, height: u32, force: bool) -> Result<(), String> {
        if width == 0 || height == 0 {
            return Err("非法尺寸".to_string());
        }
        if !force && width == self.width && height == self.height {
            return Ok(());
        }

        let (wgpu_texture, wgpu_view, shared, handle) =
            Probe::build_render_targets(&self.device, &self.d3d_device, width, height)?;

        // 旧资源挪进 retired_，等后续几帧再回收：
        // 引擎可能还持有由旧 handle 打开出来的合成纹理。
        let old_shared = std::mem::replace(&mut self.shared, shared);
        let old_handle = std::mem::replace(&mut self.handle, handle);
        self.wgpu_texture = wgpu_texture;
        self.wgpu_view = wgpu_view;
        self.retired.push(Retired {
            resource: old_shared,
            handle: old_handle,
        });

        // 保留最近两个，更早的可以安全释放。
        while self.retired.len() > 2 {
            let oldest = self.retired.remove(0);
            unsafe {
                let _ = windows::Win32::Foundation::CloseHandle(oldest.handle);
            }
            drop(oldest.resource);
            self.released_total += 1;
        }

        self.width = width;
        self.height = height;
        self.recreates += 1;
        Ok(())
    }

    fn stats_json(&self) -> String {
        format!(
            concat!(
                "{{",
                "\"backend\":\"wgpu/dx12\",",
                "\"adapter\":\"{}\",",
                "\"adapterLuid\":\"{:#x}\",",
                "\"targetLuid\":\"{:#x}\",",
                "\"adapterMatched\":{},",
                "\"directShareOfWgpuTexture\":\"{}\",",
                "\"copyPath\":\"GPU->GPU CopyResource\",",
                "\"initMs\":{:.1},",
                "\"width\":{},",
                "\"height\":{},",
                "\"frames\":{},",
                "\"copies\":{},",
                "\"recreates\":{},",
                "\"retired\":{},",
                "\"releasedTotal\":{},",
                "\"handle\":{},",
                "\"error\":\"{}\"",
                "}}"
            ),
            escape(&self.adapter_name),
            self.adapter_luid,
            self.adapter_luid,
            self.adapter_matched,
            escape(&self.direct_share),
            self.init_ms,
            self.width,
            self.height,
            self.frames,
            self.copies,
            self.recreates,
            self.retired.len(),
            self.released_total,
            self.handle.0 as usize,
            escape(&self.last_error),
        )
    }
}

impl Drop for Probe {
    fn drop(&mut self) {
        // 直接释放，不做延迟：此刻引擎已经不再持有 texture。
        for r in self.retired.drain(..) {
            unsafe {
                let _ = windows::Win32::Foundation::CloseHandle(r.handle);
            }
            drop(r.resource);
        }
        unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(self.handle);
            let _ = windows::Win32::Foundation::CloseHandle(self.fence_event);
        }
    }
}

/// 构造一个资源状态迁移 barrier。
///
/// windows crate 把 union 里的 COM 字段包在 ManuallyDrop 里（而且 union 字段
/// 自身也再包一层），不会自动 Release，所以必须配合 `release_barriers` 手动释放，
/// 否则每帧都漏一个引用计数。
///
/// 这里整体构造而不是逐字段赋值：Rust 现在禁止对 ManuallyDrop 包裹的 union
/// 字段做路径赋值（会隐式 DerefMut），逐项写会直接编译不过。
unsafe fn transition(
    res: &ID3D12Resource,
    before: D3D12_RESOURCE_STATES,
    after: D3D12_RESOURCE_STATES,
) -> D3D12_RESOURCE_BARRIER {
    D3D12_RESOURCE_BARRIER {
        Type: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
        Flags: D3D12_RESOURCE_BARRIER_FLAG_NONE,
        Anonymous: D3D12_RESOURCE_BARRIER_0 {
            Transition: ManuallyDrop::new(D3D12_RESOURCE_TRANSITION_BARRIER {
                pResource: ManuallyDrop::new(Some(res.clone())),
                Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                StateBefore: before,
                StateAfter: after,
            }),
        },
    }
}

unsafe fn release_barriers(barriers: &mut [D3D12_RESOURCE_BARRIER]) {
    for barrier in barriers.iter_mut() {
        // 两层 ManuallyDrop 都要用 ptr::read 搬出来再 into_inner，
        // 才会真正调用那份 ID3D12Resource 的 Drop（即 Release）。
        // 直接取 &mut 字段路径会触发
        // "not automatically applying DerefMut on ManuallyDrop union field"。
        let outer: ManuallyDrop<D3D12_RESOURCE_TRANSITION_BARRIER> =
            std::ptr::read(&barrier.Anonymous.Transition);
        let inner = ManuallyDrop::into_inner(outer);
        drop(ManuallyDrop::into_inner(inner.pResource));
    }
}

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn write_err(buf: *mut u8, len: usize, msg: &str) {
    if buf.is_null() || len == 0 {
        return;
    }
    let bytes = msg.as_bytes();
    let n = bytes.len().min(len - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
        *buf.add(n) = 0;
    }
}

// ───────────────────────── C ABI ─────────────────────────

#[no_mangle]
pub extern "C" fn wgpu_probe_create(
    adapter_luid: u64,
    width: u32,
    height: u32,
    err_buf: *mut u8,
    err_len: usize,
) -> *mut c_void {
    let result = catch_unwind(AssertUnwindSafe(|| Probe::new(adapter_luid, width, height)));
    match result {
        Ok(Ok(probe)) => Box::into_raw(Box::new(probe)) as *mut c_void,
        Ok(Err(e)) => {
            write_err(err_buf, err_len, &e);
            std::ptr::null_mut()
        }
        Err(_) => {
            write_err(err_buf, err_len, "wgpu 探针初始化时 panic");
            std::ptr::null_mut()
        }
    }
}

/// 取当前共享句柄。尺寸变化后句柄会变，需要重新取。
#[no_mangle]
pub extern "C" fn wgpu_probe_handle(probe: *mut c_void) -> *mut c_void {
    if probe.is_null() {
        return std::ptr::null_mut();
    }
    let probe = unsafe { &*(probe as *const Probe) };
    probe.handle.0
}

#[no_mangle]
pub extern "C" fn wgpu_probe_render(probe: *mut c_void, phase: f32) -> i32 {
    if probe.is_null() {
        return -1;
    }
    let probe = unsafe { &mut *(probe as *mut Probe) };
    match catch_unwind(AssertUnwindSafe(|| probe.render(phase))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            probe.last_error = e;
            -2
        }
        Err(_) => {
            probe.last_error = "渲染时 panic".to_string();
            -3
        }
    }
}

/// 重建尺寸相关资源。返回新的共享句柄，失败返回 null。
#[no_mangle]
pub extern "C" fn wgpu_probe_resize(probe: *mut c_void, width: u32, height: u32) -> *mut c_void {
    if probe.is_null() {
        return std::ptr::null_mut();
    }
    let probe = unsafe { &mut *(probe as *mut Probe) };
    match catch_unwind(AssertUnwindSafe(|| probe.resize(width, height))) {
        Ok(Ok(())) => probe.handle.0,
        Ok(Err(e)) => {
            probe.last_error = e;
            std::ptr::null_mut()
        }
        Err(_) => {
            probe.last_error = "resize 时 panic".to_string();
            std::ptr::null_mut()
        }
    }
}

/// 按当前尺寸强制重建资源，返回新的共享句柄。
///
/// 和 resize 的区别：resize 在尺寸没变时是空操作，这个一定重建，
/// 用来单独验证「销毁旧纹理 → 建新纹理 → 导出新句柄」这条路径。
#[no_mangle]
pub extern "C" fn wgpu_probe_recreate(probe: *mut c_void) -> *mut c_void {
    if probe.is_null() {
        return std::ptr::null_mut();
    }
    let probe = unsafe { &mut *(probe as *mut Probe) };
    match catch_unwind(AssertUnwindSafe(|| probe.recreate())) {
        Ok(Ok(())) => probe.handle.0,
        Ok(Err(e)) => {
            probe.last_error = e;
            std::ptr::null_mut()
        }
        Err(_) => {
            probe.last_error = "recreate 时 panic".to_string();
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn wgpu_probe_stats(probe: *mut c_void, buf: *mut u8, len: usize) -> i32 {    if probe.is_null() || buf.is_null() || len == 0 {
        return -1;
    }
    let probe = unsafe { &*(probe as *const Probe) };
    let json = probe.stats_json();
    let bytes = json.as_bytes();
    let n = bytes.len().min(len - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
        *buf.add(n) = 0;
    }
    n as i32
}

#[no_mangle]
pub extern "C" fn wgpu_probe_destroy(probe: *mut c_void) {
    if probe.is_null() {
        return;
    }
    // 与 Flutter engine 的销毁顺序相关：必须在 engine 还活着时调用。
    let _ = catch_unwind(AssertUnwindSafe(|| {
        drop(unsafe { Box::from_raw(probe as *mut Probe) });
    }));
}
