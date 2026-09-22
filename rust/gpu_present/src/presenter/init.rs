//! `Presenter::new` —— D3D12 / wgpu 设备与管线的一次性启动。
//!
//! 常量、数据结构与所有私有辅助函数都留在父模块 `presenter.rs`：兄弟模块之间引用不到
//! 彼此的私有项，所以**被调用的一侧必须在父模块**（子模块可以向上调用）。

use super::*;

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
            enhanced: enhance::EnhancedStore::default(),
            original_preview: enhance::Bypass::new(),
            last_used_enhanced: false,
            raw_source_sizes: HashMap::new(),
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
}
