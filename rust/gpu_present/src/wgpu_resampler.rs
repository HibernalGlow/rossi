//! 基于 wgpu 与 WGSL 的跨平台高性能 GPU 图像重采样与视口呈现器。
//!
//! 统一承载：
//! 1. 毫秒级 GPU Lanczos3 / 双线性等比缩放（取代 CPU `fast_image_resize`）；
//! 2. 毫秒级 GPU Anime4K / 边缘锐化实时滤镜；
//! 3. 视口 Letterbox 居中对齐与深黑留白填充（ClearColor）；
//! 4. RGBA8 -> BGRA8 硬件格式无开销自动转换。

use std::sync::Arc;
use anyhow::{anyhow, Result};
use wgpu::util::DeviceExt;

/// 与 WGSL 对齐的 Uniform 结构
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ResampleUniforms {
    pub src_width: f32,
    pub src_height: f32,
    pub render_offset_x: f32,
    pub render_offset_y: f32,
    pub render_width: f32,
    pub render_height: f32,
    pub target_width: f32,
    pub target_height: f32,
    pub scale: f32,
    pub filter_mode: u32, // 0: 缩小（mip 采样）, 1: Lanczos3, 2: Anime4K
    pub _pad1: f32,
    pub _pad2: f32,
    /// 缩小路径使用的 mip 等级，由 Rust 侧按 `log2(1/scale)` 算好。
    pub sample_lod: f32,
    // 补齐到 64 字节。WGSL 会把 uniform 结构体补到 16 的整数倍，
    // 而 Rust 侧不会 —— 少写两个 f32 就会让后面所有字段错位，
    // 表现出来是「参数明明传了却不生效」（实测：sample_lod 被读成 0，
    // 缩小又退回单点采样，锯齿照旧）。下面那条断言就是为了让这种错位
    // 在编译期就炸，而不是等到画面对不上。
    pub _pad3: f32,
    pub _pad4: f32,
    pub _pad5: f32,
}

const _: () = assert!(std::mem::size_of::<ResampleUniforms>() == 64);

pub struct WgpuResampler {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pipeline: wgpu::RenderPipeline,
    /// 只用来生成 mip 链（片元入口 `fs_mip`）。
    mip_pipeline: wgpu::RenderPipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,

    // 缓存的目标纹理与读取缓冲（按 target_w x target_h 复用）
    target_cache: Option<CachedTarget>,
    // 缓存的源纹理（按 src_w x src_h 复用）
    source_cache: Option<CachedSource>,
}

struct CachedTarget {
    width: u32,
    height: u32,
    texture: wgpu::Texture,
    staging_buffer: wgpu::Buffer,
    padded_bytes_per_row: u32,
}

struct CachedSource {
    width: u32,
    height: u32,
    mip_levels: u32,
    texture: wgpu::Texture,
}

/// 一个纹理最大能有多少级 mip（完整链）。
fn full_mip_levels(width: u32, height: u32) -> u32 {
    let max_dim = width.max(height).max(1);
    32 - max_dim.leading_zeros()
}

/// 建一条全屏三角形管线。
///
/// `fragment_entry` 区分用途：`fs_main` 是正常重采样，`fs_mip` 是生成 mip 链。
/// 两条管线共用同一套 bind group 布局，所以它们能直接互换 bind group。
fn create_pipeline(
    device: &wgpu::Device,
    layout: &wgpu::PipelineLayout,
    shader: &wgpu::ShaderModule,
    format: wgpu::TextureFormat,
    fragment_entry: &str,
) -> wgpu::RenderPipeline {
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("rossi_resample_pipeline"),
        layout: Some(layout),
        vertex: wgpu::VertexState {
            module: shader,
            entry_point: Some("vs_main"),
            buffers: &[],
            compilation_options: Default::default(),
        },
        fragment: Some(wgpu::FragmentState {
            module: shader,
            entry_point: Some(fragment_entry),
            targets: &[Some(wgpu::ColorTargetState {
                format,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })],
            compilation_options: Default::default(),
        }),
        primitive: wgpu::PrimitiveState {
            topology: wgpu::PrimitiveTopology::TriangleList,
            strip_index_format: None,
            front_face: wgpu::FrontFace::Ccw,
            cull_mode: None,
            unclipped_depth: false,
            polygon_mode: wgpu::PolygonMode::Fill,
            conservative: false,
        },
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
        cache: None,
    })
}

impl WgpuResampler {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Result<Self> {
        Self::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm)
    }

    pub fn new_with_format(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Result<Self> {
        let shader_src = include_str!("shaders/gpu_lanczos.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("rossi_wgpu_resample_shader"),
            source: wgpu::ShaderSource::Wgsl(shader_src.into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("rossi_resample_bgl"),
            entries: &[
                // Binding 0: source_texture
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                // Binding 1: source_sampler
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                // Binding 2: uniforms
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("rossi_resample_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline =
            create_pipeline(&device, &pipeline_layout, &shader, target_format, "fs_main");
        // Mip 生成那一趟与主渲染**共用同一套 bind group 布局**（纹理 / 采样器 / uniform），
        // 只是换一个片元入口 —— 于是它可以直接复用主渲染建好的 bind group，
        // 不需要第二套布局，也不需要第二份 uniform 结构。
        let mip_pipeline = create_pipeline(
            &device,
            &pipeline_layout,
            &shader,
            wgpu::TextureFormat::Rgba8Unorm,
            "fs_mip",
        );

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("rossi_resample_sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            // **Linear 而不是 Nearest**：缩小路径靠它在相邻两级 mip 之间插值，
            // 等效于在整块覆盖区域上做面积平均。Nearest 会出现明显的「档位跳变」，
            // 扫线密集的画面会看到一层一层的色块。
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        Ok(Self {
            device,
            queue,
            pipeline,
            mip_pipeline,
            bind_group_layout,
            sampler,
            target_cache: None,
            source_cache: None,
        })
    }

    /// 获取或创建匹配尺寸的源纹理
    fn get_or_create_source_texture(&mut self, width: u32, height: u32) -> &wgpu::Texture {
        let need_recreate = match &self.source_cache {
            Some(c) => c.width != width || c.height != height,
            None => true,
        };

        if need_recreate {
            let mip_levels = full_mip_levels(width, height);
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("rossi_source_texture"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                // 完整的 mip 链：缩小时的正确重建全靠它。
                mip_level_count: mip_levels,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8Unorm,
                usage: wgpu::TextureUsages::TEXTURE_BINDING
                    | wgpu::TextureUsages::COPY_DST
                    // 逐级降采样是渲染进它的第 1..n 级，所以要有 RENDER_ATTACHMENT。
                    | wgpu::TextureUsages::RENDER_ATTACHMENT,
                view_formats: &[],
            });
            self.source_cache = Some(CachedSource {
                width,
                height,
                mip_levels,
                texture,
            });
        }

        &self.source_cache.as_ref().unwrap().texture
    }

    /// 把已上传到第 0 级的源纹理逐级降采样，补全整条 mip 链。
    ///
    /// # 为什么必须有这一步
    ///
    /// 缩小（`scale < 1`）本质上要问「一个输出像素盖住了源上哪一块，那块的平均值是多少」。
    /// 只在第 0 级上取一两个点回答这个问题就是**欠采样** —— 结果就是锯齿与闪烁。
    /// mip 链把「平均」这件事提前做成金字塔，采样时按 `log2(1/scale)` 取级，
    /// 就变成硬件本来就擅长、而且正确的面积平均。
    ///
    /// 每级只做一次 2×2 盒式降采样并渲染进下一级，成本是整条链加起来约等于
    /// 一级的 1/3 个全尺寸 pass —— 相对于每个页面只跑一次，可以忽略。
    fn generate_mipmaps(&self, width: u32, height: u32) {
        let Some(source) = self.source_cache.as_ref() else {
            return;
        };
        if source.mip_levels <= 1 {
            return;
        }

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("rossi_mipgen_encoder"),
        });

        let mut level = 1u32;
        while level < source.mip_levels {
            let src_view = source.texture.create_view(&wgpu::TextureViewDescriptor {
                label: Some("rossi_mip_src_view"),
                base_mip_level: level - 1,
                mip_level_count: Some(1),
                ..Default::default()
            });
            let dst_view = source.texture.create_view(&wgpu::TextureViewDescriptor {
                label: Some("rossi_mip_dst_view"),
                base_mip_level: level,
                mip_level_count: Some(1),
                ..Default::default()
            });

            // `fs_mip` 依据 `uniforms.src_width/src_height` 算 ±0.5 texel 的偏移，
            // 所以这里给的是**上一级**的尺寸。
            let prev_w = (width >> (level - 1)).max(1);
            let prev_h = (height >> (level - 1)).max(1);
            let uniforms = ResampleUniforms {
                src_width: prev_w as f32,
                src_height: prev_h as f32,
                render_offset_x: 0.0,
                render_offset_y: 0.0,
                render_width: prev_w as f32,
                render_height: prev_h as f32,
                target_width: prev_w as f32,
                target_height: prev_h as f32,
                scale: 0.5,
                filter_mode: 0,
                _pad1: 0.0,
                _pad2: 0.0,
                sample_lod: 0.0,
                _pad3: 0.0,
                _pad4: 0.0,
                _pad5: 0.0,
            };
            let uniform_buffer =
                self.device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: Some("rossi_mip_uniform_buf"),
                        contents: bytemuck::bytes_of(&uniforms),
                        usage: wgpu::BufferUsages::UNIFORM,
                    });
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("rossi_mip_bg"),
                layout: &self.bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::TextureView(&src_view),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::Sampler(&self.sampler),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: uniform_buffer.as_entire_binding(),
                    },
                ],
            });

            {
                let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("rossi_mipgen_pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &dst_view,
                        resolve_target: None,
                        depth_slice: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                });
                pass.set_pipeline(&self.mip_pipeline);
                pass.set_bind_group(0, &bind_group, &[]);
                pass.draw(0..3, 0..1);
            }

            level += 1;
        }

        self.queue.submit(std::iter::once(encoder.finish()));
    }

    /// 获取或创建匹配目标视口尺寸的 Target 纹理和读取 Staging Buffer
    fn get_or_create_target(&mut self, width: u32, height: u32) -> &CachedTarget {
        let need_recreate = match &self.target_cache {
            Some(c) => c.width != width || c.height != height,
            None => true,
        };

        if need_recreate {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("rossi_target_texture"),
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

            let bytes_per_row = width * 4;
            // wgpu copy 要求 bytes_per_row 必须为 256 的整数倍
            let padded_bytes_per_row = (bytes_per_row + 255) & !255;
            let staging_size = (padded_bytes_per_row * height) as wgpu::BufferAddress;

            let staging_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("rossi_staging_read_buffer"),
                size: staging_size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });

            self.target_cache = Some(CachedTarget {
                width,
                height,
                texture,
                staging_buffer,
                padded_bytes_per_row,
            });
        }

        self.target_cache.as_ref().unwrap()
    }

    /// 核心 GPU 着色器渲染函数：在 GPU 上完成等比缩放、Letterbox 居中对齐、着色器滤波，输出到任意给定的 TextureView（支持 WebGPU Surface / 离屏纹理）
    pub fn render_to_view(
        &mut self,
        src_rgba: &[u8],
        src_w: u32,
        src_h: u32,
        target_view: &wgpu::TextureView,
        target_w: u32,
        target_h: u32,
        force_anime4k: bool,
    ) -> Result<()> {
        if target_w == 0 || target_h == 0 {
            return Ok(());
        }

        let src_w = src_w.max(1);
        let src_h = src_h.max(1);

        // ── 源图尺寸必须先自己校验（这一步是在防 Abort）──
        //
        // 超上限时 wgpu 的 `create_texture` 会走它的**默认错误处理器**，而那个
        // 处理器是 `panic!`；panic 穿过 `extern "C"` 的结果是整个 App `abort`。
        // 换句话说：一张超宽的扫描件本来只应该“这页走 CPU 兜底”，却会把进程带走。
        // 所以这里先自己算，超了就返回一个普通错误 —— 让 Dart 侧平稳回落。
        let max_dim = self.device.limits().max_texture_dimension_2d;
        if src_w > max_dim || src_h > max_dim {
            return Err(anyhow!(
                "源图尺寸 {}x{} 超出 GPU 纹理上限 {}（这张页请走 CPU 兜底路径）",
                src_w,
                src_h,
                max_dim
            ));
        }

        // 计算等比居中 (Letterbox / Contain) 坐标与尺寸
        let scale_x = target_w as f32 / src_w as f32;
        let scale_y = target_h as f32 / src_h as f32;
        let scale = scale_x.min(scale_y);

        let render_w = ((src_w as f32 * scale).round() as u32).clamp(1, target_w);
        let render_h = ((src_h as f32 * scale).round() as u32).clamp(1, target_h);

        let offset_x = (target_w.saturating_sub(render_w)) / 2;
        let offset_y = (target_h.saturating_sub(render_h)) / 2;

        // 滤波模式选择：
        // 如果强制开启 Anime4K -> 2
        // 大比例下采样（缩放到 1/3 以下）采用快速自然双线性滤波 -> 0
        // 其余采用高质量 Lanczos3 滤波 -> 1
        // ── 缩小重建：先把采样率降到合适档位，再做重建 ──
        //
        // 这里以前是 `scale < 0.35 → 单点双线性`，而那是欠采样：一个输出像素只读源上
        // 一个点，被它盖住的其余像素直接丢掉。9504 px 宽的扫描件缩到 3200（ratio ≈ 0.34）
        // 正好落进那条分支，结果就是肉眼可见的锯齿。
        //
        // 现在：`lod = floor(log2(1/scale))` 先把倍率压到 [0.5, 1)，这一步由 mip 链
        // 用面积平均完成（正确的抗锯齿）；剩下的 [0.5, 1) 再交给 mip 采样器插值。
        // 放大（scale ≥ 1）时 lod = 0，走原来的 Lanczos3，画质不变。
        let mip_lod = if scale < 1.0 {
            (1.0 / scale).log2().floor().max(0.0)
        } else {
            0.0
        };
        // 上限**按尺寸直接算**，不要去读 `source_cache`：
        // 那段「取或建源纹理」在本函数里发生在这之后，首次渲染时缓存还是空的，
        // 于是 max_lod 会被算成 0、lod 被夹成 0，缩小又退回单点采样 ——
        // 而且只在第一张图上错，最难查的那种。
        let max_lod = full_mip_levels(src_w, src_h).saturating_sub(1) as f32;
        let sample_lod = mip_lod.min(max_lod);

        let filter_mode = if force_anime4k {
            2u32
        } else if sample_lod >= 1.0 {
            // **只有真的要跨 mip 级才走 mip 采样**（scale < 0.5）。
            // 判据用 lod 而不是 scale，是因为决定「单点采样够不够」的是
            // 「有没有降到下一级」，两者在这里是同一件事的两种写法，但用 lod
            // 不会出现「改了 lod 公式、模式选择忘了跟着改」这种错位。
            0u32
        } else {
            // 放大、以及轻度缩小（footprint ≤ 2 px，5×5 的 Lanczos 核盖得住）：
            // 继续用 Lanczos3，画质与从前一致。
            1u32
        };

        // ① 上传源图像到 GPU 纹理
        self.get_or_create_source_texture(src_w, src_h);
        let src_texture = &self.source_cache.as_ref().unwrap().texture;
        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: src_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            src_rgba,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(src_w * 4),
                rows_per_image: Some(src_h),
            },
            wgpu::Extent3d {
                width: src_w,
                height: src_h,
                depth_or_array_layers: 1,
            },
        );

        // 第 0 级刚写进去，紧接着把下游各级补出来 —— 缩小路径要读它们。
        self.generate_mipmaps(src_w, src_h);

        let src_view = src_texture.create_view(&wgpu::TextureViewDescriptor::default());

        // ② 准备 Uniforms
        let uniforms = ResampleUniforms {
            src_width: src_w as f32,
            src_height: src_h as f32,
            render_offset_x: offset_x as f32,
            render_offset_y: offset_y as f32,
            render_width: render_w as f32,
            render_height: render_h as f32,
            target_width: target_w as f32,
            target_height: target_h as f32,
            scale,
            filter_mode,
            _pad1: 0.0,
            _pad2: 0.0,
            sample_lod,
            _pad3: 0.0,
            _pad4: 0.0,
            _pad5: 0.0,
        };

        let uniform_buffer = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("rossi_resample_uniform_buf"),
            contents: bytemuck::bytes_of(&uniforms),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("rossi_resample_bg"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&src_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: uniform_buffer.as_entire_binding(),
                },
            ],
        });

        // ③ 执行 GPU RenderPass，输出到传入的 target_view
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("rossi_resample_encoder"),
        });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("rossi_resample_render_pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target_view,
                    resolve_target: None,
                    depth_slice: None,
                    ops: wgpu::Operations {
                        // 初始填充深黑底色 0xFF05050A
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: 5.0 / 255.0,
                            g: 5.0 / 255.0,
                            b: 10.0 / 255.0,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.draw(0..3, 0..1); // 绘制全屏三角形
        }

        self.queue.submit(std::iter::once(encoder.finish()));
        Ok(())
    }

    /// 离屏重采样：在 GPU 上渲染完成后，将结果写出到内存缓冲区（如 CVPixelBuffer / 共享内存）
    pub fn resample_to_buffer(
        &mut self,
        src_rgba: &[u8],
        src_w: u32,
        src_h: u32,
        target_w: u32,
        target_h: u32,
        dst_ptr: *mut u8,
        dst_stride: usize,
        force_anime4k: bool,
    ) -> Result<()> {
        if target_w == 0 || target_h == 0 {
            return Ok(());
        }

        let target = self.get_or_create_target(target_w, target_h);
        let target_view = target.texture.create_view(&wgpu::TextureViewDescriptor::default());

        self.render_to_view(
            src_rgba,
            src_w,
            src_h,
            &target_view,
            target_w,
            target_h,
            force_anime4k,
        )?;

        // ④ 从 GPU target_texture 拷入 staging_buffer
        let target = self.target_cache.as_ref().unwrap();
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("rossi_staging_copy_encoder"),
        });
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &target.texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &target.staging_buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(target.padded_bytes_per_row),
                    rows_per_image: Some(target_h),
                },
            },
            wgpu::Extent3d {
                width: target_w,
                height: target_h,
                depth_or_array_layers: 1,
            },
        );

        self.queue.submit(std::iter::once(encoder.finish()));

        // ⑤ 映射 staging_buffer 并高速写入目标 CVPixelBuffer 内存（Apple Silicon UMA 物理总线极速直通）
        let buffer_slice = target.staging_buffer.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |res| {
            let _ = tx.send(res);
        });

        let _ = self.device.poll(wgpu::PollType::wait_indefinitely());

        rx.recv()
            .map_err(|e| anyhow!("接收 buffer map 信号失败: {e}"))?
            .map_err(|e| anyhow!("映射 staging buffer 失败: {e:?}"))?;

        {
            let mapped = buffer_slice.get_mapped_range();
            let row_bytes = (target_w * 4) as usize;
            let padded_stride = target.padded_bytes_per_row as usize;

            unsafe {
                // 深黑底色 0xFF05050A (BGRA little-endian: B=0x0A G=0x05 R=0x05 A=0xFF)
                // 的单像素 4 字节表示，用于安全填充行尾 Padding。
                const BG_PIXEL: [u8; 4] = [0x0A, 0x05, 0x05, 0xFF];

                for y in 0..target_h as usize {
                    let src_row = &mapped[y * padded_stride..y * padded_stride + row_bytes];
                    let dst_row = dst_ptr.add(y * dst_stride);
                    std::ptr::copy_nonoverlapping(src_row.as_ptr(), dst_row, row_bytes);

                    // ── 行跨步 Padding 安全填充（对齐 mimageviewer Stride Safety）──
                    // macOS CVPixelBuffer 常要求 64 字节行对齐，dst_stride > row_bytes
                    // 时行尾会有未写入的 Padding。Metal 双线性采样器在边缘可能渗入
                    // 这些未初始化的脏显存，表现为红黄绿假彩色块。逐像素填充深黑底色。
                    if dst_stride > row_bytes {
                        let pad_start = dst_row.add(row_bytes);
                        let pad_len = dst_stride - row_bytes;
                        // 按 4 字节（单像素）填充
                        let full_pixels = pad_len / 4;
                        for p in 0..full_pixels {
                            std::ptr::copy_nonoverlapping(
                                BG_PIXEL.as_ptr(),
                                pad_start.add(p * 4),
                                4,
                            );
                        }
                        // 不足一个完整像素的尾部字节也填充
                        let remainder = pad_len % 4;
                        if remainder > 0 {
                            std::ptr::copy_nonoverlapping(
                                BG_PIXEL.as_ptr(),
                                pad_start.add(full_pixels * 4),
                                remainder,
                            );
                        }
                    }
                }
            }
        }

        target.staging_buffer.unmap();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn init_test_device() -> Option<(Arc<wgpu::Device>, Arc<wgpu::Queue>)> {
        let instance = wgpu::Instance::default();
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .ok()?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("test_resampler_device"),
            ..Default::default()
        }))
        .ok()?;
        Some((Arc::new(device), Arc::new(queue)))
    }

    /// 缩小必须是「面积平均」，不能是「取一个点」。
    ///
    /// 16×16 的单像素棋盘格缩到 3×3（ratio = 0.1875，lod = 2）：
    /// 棋盘格里任何 4×4 块的平均值都是中灰，所以正确重建的结果应当处处约等于 128，
    /// 而且**方差接近 0**。
    ///
    /// 尺寸是特意挑的，不是随手写的：`3` 让采样点落在非整数 texel 位置上。
    /// 早先试过 8×8 → 2×2，那个尺寸**分不出好坏** —— 采样点正好落在 texel 边界，
    /// 双线性在那里恰好把相邻两个反色像素各取一半，也能得到中灰，
    /// 于是「单点采样」和「面积平均」的断言同时通过。挑尺寸这件事本身就是要写进
    /// 注释的，否则下一个人会以为随便选都行。
    #[test]
    fn test_downscale_averages_instead_of_point_sampling() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let src_w = 16u32;
        let src_h = 16u32;
        let mut rgba = vec![0u8; (src_w * src_h * 4) as usize];
        for y in 0..src_h {
            for x in 0..src_w {
                let v: u8 = if (x + y) % 2 == 0 { 255 } else { 0 };
                let i = ((y * src_w + x) * 4) as usize;
                rgba[i] = v;
                rgba[i + 1] = v;
                rgba[i + 2] = v;
                rgba[i + 3] = 255;
            }
        }

        let mut resampler =
            WgpuResampler::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm)
                .expect("初始化 resampler 失败");

        let target_w = 3u32;
        let target_h = 3u32;
        let stride = 256usize;
        let mut out = vec![0u8; stride * target_h as usize];
        resampler
            .resample_to_buffer(
                &rgba,
                src_w,
                src_h,
                target_w,
                target_h,
                out.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        for y in 0..target_h as usize {
            for x in 0..target_w as usize {
                let b = out[y * stride + x * 4] as i32;
                assert!(
                    (110..=145).contains(&b),
                    "输出像素 ({x},{y}) 应约为中灰 128（面积平均），实测 {b} —— \
                     说明缩小又退回了单点采样，锯齿会跟着回来"
                );
            }
        }
    }
}
