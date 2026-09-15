//! Gate A / 带宽基准：把「每帧一次 GPU→GPU 拷贝」的真实成本单独量出来。
//!
//! # 为什么要另开一个基准，而不是接着看帧率
//!
//! 帧循环里的拷贝被 vsync 锁死在刷新率上（本机 160Hz），一帧只拷一张
//! 1264×487 的图（2.5MB）。这个量级离显存带宽差两三个数量级 ——
//! 量到的是**单次拷贝的延迟**，不是拷贝引擎的**持续吞吐**。
//! 用 160fps 反推出的 380MB/s 是被刷新率封顶的假数，不能用来判断
//! 「要不要为省掉这次拷贝去维护一个 wgpu-hal fork」。
//!
//! 所以这里把拷贝从帧循环里摘出来，在离屏状态下批量提交：
//!
//!   - 尺寸从 2.5MB 一路拉到 384MB，看吞吐是否随尺寸线性；
//!   - 用 GPU timestamp 量拷贝在 GPU 时间线上的**独占时长**，不掺墙钟；
//!   - 三组对照，把「shared 标志」和「barrier 往返」的代价分离出来。
//!
//! # 两个把带宽测歪的坑
//!
//! 1. **显存压缩**。第一版把源纹理留成未写入（内容全零），量到
//!    363~432 GB/s —— 超出这块卡 256 GB/s 的标称带宽 40% 以上。
//!    全零数据被 delta color compression 吃掉了，真实显存流量远小于
//!    名义值。漫画页是扫描件 / 照片，高熵、几乎不可压缩，所以现在
//!    源纹理改由 wgpu 渲染整数 hash 噪声生成。
//!
//! 2. **L2 缓存**。2.3MB（当前窗口尺寸）测出 444 GB/s，同样是虚高：
//!    它整个放得进 32MB 的 L2，读根本没落到显存。判断 Gate A 要看
//!    大图那几档；小尺寸的数字只说明「当前窗口这个量级的拷贝很便宜」。
//!
//! # 三组对照的意义
//!
//! | 组      | 目标堆            | dst barrier | 回答什么问题            |
//! |---------|-------------------|-------------|-------------------------|
//! | plain   | 普通 DEFAULT heap | 完整        | 显存带宽基线            |
//! | shared  | SHARED heap       | 完整        | 真实路径（判据用这组）   |
//! | nobar   | SHARED heap       | 省掉        | barrier 的净成本         |
//!
//! 本来担心 barrier 是隐性大头：真实路径里每次拷贝前后都要做
//! `RENDER_TARGET ⇄ COPY_SOURCE` / `COMMON ⇄ COPY_DEST`，看着就会让 GPU
//! 停等。实测 `shared - nobar` 差异在 2% 以内，可以忽略 —— 这条负结论
//! 省掉了为绕开 barrier 去做的那些冗余设计。
//!
//! # 计时口径
//!
//! 主口径是 GPU timestamp，不是墙钟。墙钟同时包含命令提交开销和 fence
//! 往返，而且 GPU 空闲时 CPU 等待会被记进去；timestamp 只测 GPU 真正
//! 在跑拷贝的那段时间。
//!
//! 但要注意：如果命令提交跟不上（GPU 跑完一块还在等下一块），
//! timestamp 会把 GPU 空转也算进去。所以这里用环形命令记录槽位
//! （`SLOT_COUNT` 个 allocator + list）先把活全提交出去，只在必须复用
//! 槽位时才回等 fence，从而把空转压到最小。

use std::ffi::c_void;
use std::mem::ManuallyDrop;
use std::time::Instant;

use wgpu::hal::api::Dx12;
use windows::core::{Interface, PCWSTR};
use windows::Win32::Foundation::{GENERIC_ALL, HANDLE, WAIT_OBJECT_0};
use windows::Win32::Graphics::Direct3D12::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::Win32::Graphics::Dxgi::IDXGIAdapter3;
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};

/// 与探针主体保持一致的格式。
///
/// 必须是 BGRA8：Flutter Windows 走 ANGLE / D3D11 打开共享纹理来合成，
/// D3D11 打不开 RGBA8 的共享纹理。基准要和真实路径同构，就不能换格式。
const FORMAT: DXGI_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM;

/// 生成高熵噪声的全屏三角形 shader。
///
/// # 为什么必须用噪声，而不是 Clear 成纯色
///
/// 第一版基准把源纹理留成未写入（内容全零），实测读+写吞吐跑到
/// 363~432 GB/s，而这块卡（RTX 4060 Laptop，128-bit GDDR6）的标称
/// 显存带宽只有 256 GB/s —— **超出标称 40% 以上**，说明量到的不是
/// 真实显存流量：全零数据被 NVIDIA 的 delta color compression 吃掉了。
///
/// 漫画页是扫描件 / 照片，本身高熵、几乎不可压缩。用纯色去测等于把
/// 测量对象换成了一个真实场景里不存在的东西。
///
/// # 为什么用整数 hash
///
/// `fract(sin(dot(p, k)) * n)` 那类浮点 hash 在这里不能用：像素坐标最大
/// 到 12000，乘上系数后 `sin` 的输入已很大，float32 的 24 位尾数会把
/// 相邻像素算成几乎相同的值 —— 相关性一出来，显存压缩又能生效，白测。
/// 整数 bit-mix（下面的 xxhash 风格 finalizer）对任意坐标都是满熵的。
const NOISE_SHADER: &str = r#"
struct VsOut {
  @builtin(position) pos: vec4<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VsOut {
  var corners = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  var out: VsOut;
  out.pos = vec4<f32>(corners[idx], 0.0, 1.0);
  return out;
}

fn hash_u32(x: u32) -> u32 {
  var h = x;
  h ^= h >> 16u;
  h = h * 0x7feb352du;
  h ^= h >> 15u;
  h = h * 0x846ca68bu;
  h ^= h >> 16u;
  return h;
}

@fragment
fn fs_noise(in: VsOut) -> @location(0) vec4<f32> {
  let xy = vec2<u32>(in.pos.xy);
  let seed = xy.x + xy.y * 0x9E3779B9u;
  let r = hash_u32(seed);
  let g = hash_u32(seed ^ 0x85EBCA6Bu);
  let b = hash_u32(seed ^ 0xC2B2AE35u);
  return vec4<f32>(
    f32(r & 0xFFu) / 255.0,
    f32(g & 0xFFu) / 255.0,
    f32(b & 0xFFu) / 255.0,
    1.0,
  );
}
"#;

/// 环形命令记录槽位数量。
///
/// 取 16 是为了让「一块」的命令（`BLOCK_OPS` 条）提交速度明显快于 GPU
/// 执行速度，避免 GPU 跑完还得等 CPU 提交下一块 —— 那种空转会污染
/// timestamp 口径。正常情况下应当一次都不用等。
const SLOT_COUNT: usize = 16;

/// 单个命令列表里的拷贝次数上限。
const BLOCK_OPS: u32 = 256;

/// 每组对照的模式。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// 普通 DEFAULT 堆目标：显存带宽基线。
    Plain,
    /// SHARED 堆目标 + 完整 barrier 往返：真实路径，判据用这一组。
    Shared,
    /// SHARED 堆目标 + 省掉 dst 的 barrier（靠 COMMON 隐式提升）：
    /// 乐观下界，用来把 barrier 的成本单独扣出来。
    Nobar,
}

impl Mode {
    pub fn as_str(self) -> &'static str {
        match self {
            Mode::Plain => "plain",
            Mode::Shared => "shared",
            Mode::Nobar => "nobar",
        }
    }

    /// 给 CLI 用的中文说明。
    pub fn label(self) -> &'static str {
        match self {
            Mode::Plain => "默认堆·含barrier(带宽基线)",
            Mode::Shared => "共享堆·含barrier(真实路径)",
            Mode::Nobar => "共享堆·无dst-barrier(乐观下界)",
        }
    }

    pub fn parse(s: &str) -> Option<Mode> {
        match s.to_ascii_lowercase().as_str() {
            "plain" => Some(Mode::Plain),
            "shared" => Some(Mode::Shared),
            "nobar" => Some(Mode::Nobar),
            // real 是 shared 的旧名字，留着免得老命令失效。
            "real" => Some(Mode::Shared),
            _ => None,
        }
    }

    /// 所有模式，CLI 默认跑全量。
    pub fn all() -> [Mode; 3] {
        [Mode::Plain, Mode::Shared, Mode::Nobar]
    }
}

/// 一次基准测量的结果。
#[derive(Clone, Debug)]
pub struct Report {
    pub mode: &'static str,
    pub width: u32,
    pub height: u32,
    /// 单张纹理的字节数。
    pub bytes: u64,
    pub iterations: u32,
    /// GPU 时间线上的总耗时（timestamp 口径）。
    pub gpu_ms: f64,
    /// 墙钟总耗时，用于交叉验证 timestamp 是否可信。
    pub wall_ms: f64,
    /// 单次拷贝的 GPU 独占时长，单位微秒。这是判据要的那个数。
    pub us_per_copy: f64,
    /// 读 + 写合计吞吐（GB/s）。
    pub gbs_rw: f64,
    /// 换算成「GPU 时间占比」用的：在给定 FPS 下这次拷贝吃掉多少毫秒预算。
    pub mpix: f64,
}

/// 一个命令记录槽位。
struct Slot {
    allocator: ID3D12CommandAllocator,
    list: ID3D12GraphicsCommandList,
    /// 这个槽位最后一次被使用的 fence 值；复用它之前要确认 GPU 已经跑过。
    /// 不清空这个值就等于在 GPU 还在读命令缓冲时重置它 —— D3D12 会直接
    /// 报错，而且报错点在下一个 Reset 上，很难和真正的根因对上。
    last_fence: u64,
}

/// 离屏拷贝基准的执行环境。
///
/// 复用与探针主体相同的 adapter 选择逻辑（同 wgpu/hal 版本、同 DX12 后端），
/// 这样量出来的带宽才和真实路径可比。
pub struct Bench {
    // 保持 instance / device / queue 存活：底下的裸 D3D12 对象虽然各自
    // 持有引用计数，但 wgpu 侧的对象一旦被 drop，驱动层的隐式状态
    // （比如队列的同步点）就不一定还成立了。
    _instance: wgpu::Instance,
    device: wgpu::Device,
    queue: wgpu::Queue,

    /// 渲染高熵噪声用的管线。源纹理必须走真渲染，不能是 Clear 出来的纯色。
    noise_pipeline: wgpu::RenderPipeline,

    d3d_device: ID3D12Device,
    d3d_queue: ID3D12CommandQueue,

    slots: Vec<Slot>,
    next_slot: usize,

    fence: ID3D12Fence,
    fence_event: HANDLE,
    fence_value: u64,

    query_heap: ID3D12QueryHeap,
    readback: ID3D12Resource,
    readback_ptr: *mut u64,
    freq: u64,

    pub adapter_name: String,
    pub adapter_luid: u64,
    pub adapter_kind: String,
}

impl Bench {
    pub fn new() -> Result<Bench, String> {
        let mut idesc = wgpu::InstanceDescriptor::default();
        idesc.backends = wgpu::Backends::DX12;
        let instance = wgpu::Instance::new(&idesc);

        let adapters = instance.enumerate_adapters(wgpu::Backends::DX12);
        if adapters.is_empty() {
            return Err("枚举不到任何 DX12 adapter".to_string());
        }

        // 离屏基准没有 Flutter 告诉我们该用哪块卡，所以按类型挑：
        // 独显优先。集显的显存带宽和真实渲染卡不是一个量级，
        // 拿它的数字去判断 Gate A 会得出完全错误的结论。
        let mut picked: Option<(wgpu::Adapter, String, u64, String)> = None;
        let mut best_rank = -1i32;
        for adapter in adapters {
            let info = adapter.get_info();
            let mut luid = 0u64;
            if let Some(hal) = unsafe { adapter.as_hal::<Dx12>() } {
                let raw: &IDXGIAdapter3 = hal.as_raw();
                if let Ok(desc) = unsafe { raw.GetDesc() } {
                    luid = ((desc.AdapterLuid.HighPart as u64) << 32)
                        | (desc.AdapterLuid.LowPart as u64);
                }
            }
            let rank = match info.device_type {
                wgpu::DeviceType::DiscreteGpu => 3,
                wgpu::DeviceType::IntegratedGpu => 2,
                wgpu::DeviceType::VirtualGpu => 1,
                _ => 0,
            };
            if rank > best_rank {
                best_rank = rank;
                picked = Some((
                    adapter,
                    info.name.clone(),
                    luid,
                    format!("{:?}", info.device_type),
                ));
            }
        }

        let (adapter, adapter_name, adapter_luid, adapter_kind) =
            picked.ok_or_else(|| "没有可用的 adapter".to_string())?;

        // 请求 adapter 的全部 limits，而不是默认值：wgpu 默认的
        // max_texture_dimension_2d 只有 8192，而最大那一档是
        // 8000x12000 —— 用默认 limits 会在这里就直接创建失败，
        // 报出来的错还是「超出限制」，很容易误判成硬件不支持。
        let limits = adapter.limits();
        let (device, queue) =
            pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
                label: Some("wgpu-probe-bench"),
                required_limits: limits,
                ..Default::default()
            }))
            .map_err(|e| format!("request_device 失败: {e}"))?;

        let hal_device = unsafe { device.as_hal::<Dx12>() }
            .ok_or_else(|| "device 不是 DX12 后端".to_string())?;
        let d3d_device: ID3D12Device = hal_device.raw_device().clone();
        let d3d_queue: ID3D12CommandQueue = hal_device.raw_queue().clone();
        drop(hal_device);

        // 噪声管线：只画一个全屏三角形，不要顶点缓冲、不要绑定组 ——
        // 着色器全部从内置的 position 推导，避免为了喂参数再引一套状态。
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("bench-noise"),
            source: wgpu::ShaderSource::Wgsl(NOISE_SHADER.into()),
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("bench-noise-layout"),
            bind_group_layouts: &[],
            push_constant_ranges: &[],
        });
        let noise_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("bench-noise-pipeline"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: Default::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_noise"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: wgpu::TextureFormat::Bgra8Unorm,
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

        let mut slots: Vec<Slot> = Vec::with_capacity(SLOT_COUNT);
        let (fence, fence_event, query_heap, readback, readback_ptr, freq) = unsafe {
            for _ in 0..SLOT_COUNT {
                let allocator = d3d_device
                    .CreateCommandAllocator::<ID3D12CommandAllocator>(
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                    )
                    .map_err(|e| format!("CreateCommandAllocator 失败: {e}"))?;
                let list = d3d_device
                    .CreateCommandList::<_, _, ID3D12GraphicsCommandList>(
                        0,
                        D3D12_COMMAND_LIST_TYPE_DIRECT,
                        &allocator,
                        None::<&ID3D12PipelineState>,
                    )
                    .map_err(|e| format!("CreateCommandList 失败: {e}"))?;
                list.Close()
                    .map_err(|e| format!("CommandList::Close 失败: {e}"))?;
                slots.push(Slot {
                    allocator,
                    list,
                    last_fence: 0,
                });
            }

            let fence = d3d_device
                .CreateFence::<ID3D12Fence>(0, D3D12_FENCE_FLAG_NONE)
                .map_err(|e| format!("CreateFence 失败: {e}"))?;
            let fence_event = CreateEventW(None, false, false, None)
                .map_err(|e| format!("CreateEventW 失败: {e}"))?;

            let freq = d3d_queue
                .GetTimestampFrequency()
                .map_err(|e| format!("GetTimestampFrequency 失败: {e}"))?;
            if freq == 0 {
                return Err("队列时间戳频率为 0，无法做 GPU 计时".to_string());
            }

            // 两个 timestamp 点：循环开始 / 循环结束。
            let heap_desc = D3D12_QUERY_HEAP_DESC {
                Type: D3D12_QUERY_HEAP_TYPE_TIMESTAMP,
                Count: 2,
                NodeMask: 0,
            };
            // out 参数风格（Result<()> + 末尾 *mut Option<T>），
            // 不要写成 CreateQueryHeap::<T>(&desc) 的返回值风格。
            let mut qh: Option<ID3D12QueryHeap> = None;
            d3d_device
                .CreateQueryHeap(&heap_desc, &mut qh)
                .map_err(|e| format!("CreateQueryHeap 失败: {e}"))?;
            let query_heap = qh.ok_or_else(|| "CreateQueryHeap 返回空".to_string())?;

            let rb_desc = D3D12_RESOURCE_DESC {
                Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
                Alignment: 0,
                // 256 是为了满足 D3D12 的行距对齐要求；实际只用前 16 字节。
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
            d3d_device
                .CreateCommittedResource(
                    &rb_heap,
                    D3D12_HEAP_FLAG_NONE,
                    &rb_desc,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                    None,
                    &mut rb_opt,
                )
                .map_err(|e| format!("CreateCommittedResource(readback) 失败: {e}"))?;
            let readback =
                rb_opt.ok_or_else(|| "readback 资源为空".to_string())?;
            // Map 的第三参是 *mut *mut c_void（out），不能直接给 *mut u64。
            let mut raw: *mut c_void = std::ptr::null_mut();
            readback
                .Map(0, None, Some(&mut raw))
                .map_err(|e| format!("readback Map 失败: {e}"))?;
            let ptr = raw as *mut u64;

            (fence, fence_event, query_heap, readback, ptr, freq)
        };

        Ok(Bench {
            _instance: instance,
            device,
            queue,
            noise_pipeline,
            d3d_device,
            d3d_queue,
            slots,
            next_slot: 0,
            fence,
            fence_event,
            fence_value: 0,
            query_heap,
            readback,
            readback_ptr,
            freq,
            adapter_name,
            adapter_luid,
            adapter_kind,
        })
    }

    /// 用 wgpu 渲染一张高熵噪声纹理。
    ///
    /// 返回纹理本体和它的裸 D3D12 资源。纹理本体必须由调用方保活：
    /// 裸资源只是 Clone 出来的一份引用，纹理一被 drop，wgpu 就可能把
    /// 底层资源还回池子，而 GPU 那边还在读它。
    fn render_noise(
        &mut self,
        width: u32,
        height: u32,
    ) -> Result<(wgpu::Texture, ID3D12Resource), String> {
        let tex = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("bench-src-noise"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = tex.create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("bench-noise-encoder"),
                });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("bench-noise-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.noise_pipeline);
            pass.draw(0..3, 0..1);
        }
        // submit 是同步写进同一个 D3D12 queue 的，所以后面紧随的原生
        // barrier / CopyResource 天然排在这次渲染之后。
        self.queue.submit([encoder.finish()]);

        let raw = {
            let guard = unsafe { tex.as_hal::<Dx12>() }
                .ok_or_else(|| "噪声纹理取不到 dx12 句柄".to_string())?;
            unsafe { guard.raw_resource().clone() }
        };

        Ok((tex, raw))
    }

    /// 跑一档：`iterations` 次拷贝，返回单次拷贝的 GPU 时长与吞吐。
    pub fn run(
        &mut self,
        mode: Mode,
        width: u32,
        height: u32,
        iterations: u32,
    ) -> Result<Report, String> {
        if width == 0 || height == 0 || iterations == 0 {
            return Err("尺寸与次数必须为正".to_string());
        }

        // 源纹理交给 wgpu 渲染噪声生成。这一步同时解决两件事：
        //   1. 数据必须高熵 —— 全零/纯色会被显存压缩，带宽测出来虚高 40%+；
        //   2. src 必须与真实路径同构 —— 真实场景里它就是 wgpu 渲染出来的
        //      那张纹理，对 wgpu 而言处于 RENDER_ATTACHMENT 状态。
        let (_src_tex, src) = self.render_noise(width, height)?;

        // 目标纹理：真实场景里是共享纹理。初始状态统一给 COMMON ——
        // 含 barrier 的组显式迁到 COPY_DEST，nobar 组靠隐式提升，
        // 两种在 D3D12 里都合法。
        let dst_shared = mode != Mode::Plain;
        let (dst, dst_handle) = make_texture(
            &self.d3d_device,
            width,
            height,
            dst_shared,
            D3D12_RESOURCE_STATE_COMMON,
        )?;

        let bytes = width as u64 * height as u64 * 4;

        // 预热：让驱动把物理页真正分配出来。不预热的话第一次拷贝会吃
        // 缺页开销，在 384MB 这种尺寸上足以把均值拉歪。
        //
        // fence 值必须在这之后**继续递增**，不能重新从 self.fence_value 起算：
        // D3D12 的 Signal/SetEventOnCompletion 是以「值达到」为条件的，
        // 重复用同一个值会变成空操作 —— 等待立刻返回，纹理还没拷完就被
        // 释放，GPU 读已释放内存，设备直接 removed。
        let mut fv = self.fence_value;
        fv = self.submit_block(mode, &src, &dst, 4, fv, false, false)?;
        self.wait_fence(fv)?;

        // ── 正式测量 ──
        let wall_start = Instant::now();
        let blocks = iterations.div_ceil(BLOCK_OPS);
        for b in 0..blocks {
            let this = (iterations - b * BLOCK_OPS).min(BLOCK_OPS);
            fv = self.submit_block(
                mode,
                &src,
                &dst,
                this,
                fv,
                b == 0,
                b == blocks - 1,
            )?;
        }
        self.wait_fence(fv)?;
        let wall_ms = wall_start.elapsed().as_secs_f64() * 1000.0;
        self.fence_value = fv;

        // fence 已经等到，resolve 的结果此刻一定落在 readback 内存里。
        let (t_begin, t_end) = unsafe { (*self.readback_ptr, *self.readback_ptr.add(1)) };
        let gpu_ms = if t_end > t_begin {
            (t_end - t_begin) as f64 * 1000.0 / self.freq as f64
        } else {
            return Err(format!(
                "时间戳无效 (begin={t_begin}, end={t_end})，GPU 计时不可用"
            ));
        };

        let us_per_copy = gpu_ms * 1000.0 / iterations as f64;
        let gbs_rw = (bytes as f64 * 2.0 * iterations as f64) / (gpu_ms / 1000.0) / 1e9;

        // 共享句柄用完即关：基准不交给 Flutter 合成，句柄留着只是占内核对象。
        if let Some(h) = dst_handle {
            unsafe {
                let _ = windows::Win32::Foundation::CloseHandle(h);
            }
        }

        Ok(Report {
            mode: mode.as_str(),
            width,
            height,
            bytes,
            iterations,
            gpu_ms,
            wall_ms,
            us_per_copy,
            gbs_rw,
            mpix: (width as f64 * height as f64) / 1e6,
        })
    }

    /// 提交一块拷贝命令。
    ///
    /// `stamp_begin` / `stamp_end` 控制时间戳打点位置：T0 落在第一块最前面，
    /// T1 落在最后一块最后面，于是两个点之间就是全部拷贝的 GPU 时长。
    fn submit_block(
        &mut self,
        mode: Mode,
        src: &ID3D12Resource,
        dst: &ID3D12Resource,
        count: u32,
        fence_value: u64,
        stamp_begin: bool,
        stamp_end: bool,
    ) -> Result<u64, String> {
        // 把要用的 COM 对象先克隆出来（AddRef，很轻），避免同时可变借用
        // self.slots 和不可变借用 self.fence 造成的借用冲突。
        let fence = self.fence.clone();
        let event = self.fence_event;
        let heap = self.query_heap.clone();
        let readback = self.readback.clone();
        let queue = self.d3d_queue.clone();

        let idx = self.next_slot;
        let slot = &mut self.slots[idx];

        // 复用槽位前确认 GPU 已经跑完它上一次的活。正常情况下这里不该
        // 触发等待（SLOT_COUNT 足够深），一旦触发就说明 CPU 提交跟不上，
        // 那次测量的 timestamp 会混进 GPU 空转。
        if slot.last_fence > 0 {
            let done = unsafe { fence.GetCompletedValue() };
            if done < slot.last_fence {
                unsafe {
                    fence
                        .SetEventOnCompletion(slot.last_fence, event)
                        .map_err(|e| format!("SetEventOnCompletion 失败: {e}"))?;
                }
                let w = unsafe { WaitForSingleObject(event, 30000) };
                if w != WAIT_OBJECT_0 {
                    return Err(format!("等待槽位空闲超时: {w:?}"));
                }
            }
        }

        unsafe {
            slot.allocator
                .Reset()
                .map_err(|e| format!("Allocator::Reset 失败: {e}"))?;
            slot.list
                .Reset(&slot.allocator, None)
                .map_err(|e| format!("CommandList::Reset 失败: {e}"))?;

            if stamp_begin {
                slot.list
                    .EndQuery(&heap, D3D12_QUERY_TYPE_TIMESTAMP, 0);
            }

            emit_ops(&slot.list, mode, src, dst, count);

            if stamp_end {
                slot.list
                    .EndQuery(&heap, D3D12_QUERY_TYPE_TIMESTAMP, 1);
                slot.list.ResolveQueryData(
                    &heap,
                    D3D12_QUERY_TYPE_TIMESTAMP,
                    0,
                    2,
                    &readback,
                    0,
                );
            }

            slot.list
                .Close()
                .map_err(|e| format!("CommandList::Close 失败: {e}"))?;
            let raw: ID3D12CommandList = slot
                .list
                .cast()
                .map_err(|e| format!("cast 到 ID3D12CommandList 失败: {e}"))?;
            queue.ExecuteCommandLists(&[Some(raw)]);

            let next = fence_value + 1;
            queue
                .Signal(&fence, next)
                .map_err(|e| format!("Queue::Signal 失败: {e}"))?;
            slot.last_fence = next;
            self.next_slot = (idx + 1) % self.slots.len();
            Ok(next)
        }
    }

    fn wait_fence(&self, value: u64) -> Result<(), String> {
        if value == 0 {
            return Ok(());
        }
        if unsafe { self.fence.GetCompletedValue() } >= value {
            return Ok(());
        }
        unsafe {
            self.fence
                .SetEventOnCompletion(value, self.fence_event)
                .map_err(|e| format!("SetEventOnCompletion 失败: {e}"))?;
        }
        let w = unsafe { WaitForSingleObject(self.fence_event, 60000) };
        if w != WAIT_OBJECT_0 {
            return Err(format!("等待基准完成超时: {w:?}"));
        }
        Ok(())
    }

    /// 按目标总字节数推算每档该跑多少次，避免小尺寸档位数太少、
    /// 大尺寸档位时间太短 —— 两种都会让均值不稳。
    pub fn iterations_for(&self, bytes: u64, target_bytes: u64) -> u32 {
        ((target_bytes / bytes.max(1)) as u32).clamp(16, 20000)
    }
}

impl Drop for Bench {
    fn drop(&mut self) {
        // 先等 GPU 把手上的活干完，再释放资源：否则命令列表还引用着
        // 纹理，Release 会让命令缓冲指向已释放的内存（校验层会报）。
        let _ = self.wait_fence(self.fence_value);
        unsafe {
            let _ = self.readback.Unmap(0, None);
            let _ = windows::Win32::Foundation::CloseHandle(self.fence_event);
        }
    }
}

/// 往命令列表里写 `count` 次拷贝。
///
/// `Mode::Plain` / `Mode::Shared` 完全复制真实路径的时序：拷前
/// `RENDER_TARGET → COPY_SOURCE` 与 `COMMON → COPY_DEST`，拷后立刻切回来。
/// 这不是多余动作 —— 探针主体就是这么干的，因为 wgpu 对那张源纹理的
/// 状态有自己的记账，不还原会和真实状态分叉。
unsafe fn emit_ops(
    list: &ID3D12GraphicsCommandList,
    mode: Mode,
    src: &ID3D12Resource,
    dst: &ID3D12Resource,
    count: u32,
) {
    for _ in 0..count {
        match mode {
            Mode::Plain | Mode::Shared => {
                let mut before = [
                    transition(
                        src,
                        D3D12_RESOURCE_STATE_RENDER_TARGET,
                        D3D12_RESOURCE_STATE_COPY_SOURCE,
                    ),
                    transition(
                        dst,
                        D3D12_RESOURCE_STATE_COMMON,
                        D3D12_RESOURCE_STATE_COPY_DEST,
                    ),
                ];
                list.ResourceBarrier(&before);
                release_barriers(&mut before);

                list.CopyResource(dst, src);

                let mut after = [
                    transition(
                        src,
                        D3D12_RESOURCE_STATE_COPY_SOURCE,
                        D3D12_RESOURCE_STATE_RENDER_TARGET,
                    ),
                    transition(
                        dst,
                        D3D12_RESOURCE_STATE_COPY_DEST,
                        D3D12_RESOURCE_STATE_COMMON,
                    ),
                ];
                list.ResourceBarrier(&after);
                release_barriers(&mut after);
            }
            Mode::Nobar => {
                // 只同步 src。dst 第一次被写时 D3D12 会把它从 COMMON
                // 隐式提升到 COPY_DEST，之后一直保持该状态，不需要 barrier。
                let mut before = [transition(
                    src,
                    D3D12_RESOURCE_STATE_RENDER_TARGET,
                    D3D12_RESOURCE_STATE_COPY_SOURCE,
                )];
                list.ResourceBarrier(&before);
                release_barriers(&mut before);

                list.CopyResource(dst, src);

                let mut after = [transition(
                    src,
                    D3D12_RESOURCE_STATE_COPY_SOURCE,
                    D3D12_RESOURCE_STATE_RENDER_TARGET,
                )];
                list.ResourceBarrier(&after);
                release_barriers(&mut after);
            }
        }
    }
}

/// 把 HRESULT 转成可读名字。
///
/// 不加这个的话报错只有一串负数，像 `-2005270523`。那是
/// `DXGI_ERROR_DEVICE_REMOVED`（0x887A0005）—— 含义完全不同：
/// 它不是「这次分配失败」，而是「整个设备已经不可用了，后面所有操作
/// 都会失败」。分辨不出这一点会把排查方向带偏。
fn hr_name(code: i32) -> &'static str {
    match code as u32 {
        0x887A0005 => "DXGI_ERROR_DEVICE_REMOVED(设备已移除，后续操作都会失败)",
        0x887A0006 => "DXGI_ERROR_DEVICE_HUNG",
        0x887A0007 => "DXGI_ERROR_DEVICE_RESET",
        0x887A0020 => "DXGI_ERROR_DRIVER_INTERNAL_ERROR",
        0x8007000E => "E_OUTOFMEMORY(显存不足)",
        0x80070057 => "E_INVALIDARG",
        _ => "",
    }
}

/// 建一张 BGRA8 纹理；`shared = true` 时走 SHARED 堆并导出句柄。
fn make_texture(
    device: &ID3D12Device,
    width: u32,
    height: u32,
    shared: bool,
    initial: D3D12_RESOURCE_STATES,
) -> Result<(ID3D12Resource, Option<HANDLE>), String> {
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

    let flags = if shared {
        D3D12_HEAP_FLAG_SHARED
    } else {
        D3D12_HEAP_FLAG_NONE
    };

    let mut opt: Option<ID3D12Resource> = None;
    unsafe {
        device
            .CreateCommittedResource(
                &heap,
                flags,
                &desc,
                initial,
                Some(&clear as *const _),
                &mut opt,
            )
            .map_err(|e| {
                let code = e.code().0;
                format!(
                    "CreateCommittedResource 失败 ({width}x{height}, shared={shared}, {:.1}MB): {:#010x} {}",
                    width as f64 * height as f64 * 4.0 / 1048576.0,
                    code as u32,
                    hr_name(code)
                )
            })?;
    }
    let res = opt.ok_or_else(|| "CreateCommittedResource 返回空".to_string())?;

    let handle = if shared {
        let child: ID3D12DeviceChild = res
            .cast()
            .map_err(|e| format!("ID3D12Resource -> ID3D12DeviceChild 失败: {e}"))?;
        Some(unsafe {
            device
                .CreateSharedHandle(&child, None, GENERIC_ALL.0, PCWSTR::null())
                .map_err(|e| format!("CreateSharedHandle 失败: {:?}", e.code().0))?
        })
    } else {
        None
    };

    Ok((res, handle))
}

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
        // 两层 ManuallyDrop 都要 ptr::read 搬出来再 into_inner，才会真正
        // 调用那份 ID3D12Resource 的 Drop（即 Release）。直接走字段路径
        // 会触发 "not automatically applying DerefMut on ManuallyDrop
        // union field"。
        let outer: ManuallyDrop<D3D12_RESOURCE_TRANSITION_BARRIER> =
            std::ptr::read(&barrier.Anonymous.Transition);
        let inner = ManuallyDrop::into_inner(outer);
        drop(ManuallyDrop::into_inner(inner.pResource));
    }
}
