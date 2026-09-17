//! 基于 wgpu 与 WGSL 的跨平台高性能 GPU 图像重采样与视口呈现器。
//!
//! 统一承载：
//! 1. 毫秒级 GPU Lanczos3 / 双线性等比缩放（取代 CPU `fast_image_resize`）；
//! 2. 毫秒级 GPU Anime4K / 边缘锐化实时滤镜；
//! 3. 视口 Letterbox 居中对齐与深黑留白填充（ClearColor）；
//! 4. RGBA8 -> BGRA8 / RGBA16F 硬件格式转换；
//! 5. libplacebo 风格的实时 GPU 逆色调映射（Inverse Tone Mapping）：
//!    - SDR Boost (BGRA8)：暗部沉稳，高光动态扩展并软膝压缩进 [0, 1]，适度提亮；
//!    - Extended Linear HDR (RGBA16F / scRGB)：突破 1.0 SDR 白点极限，
//!      直通 macOS EDR / Windows scRGB 呈现 400~1000 nits 高光。

use std::sync::Arc;
use anyhow::{anyhow, Result};
use wgpu::util::DeviceExt;

/// 与 WGSL 对齐的 Uniform 结构（严格 64 字节对齐）
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
    pub filter_mode: u32, // 0: Bilinear, 1: Lanczos3, 2: Anime4K
    pub hdr_mode: u32,    // 0: Off, 1: Extended Linear (RGBA16F / scRGB), 2: SDR Boost (BGRA8)
    pub hdr_boost: f32,   // 白点与高光扩展倍率 (1.0 = 不扩展, 典型 1.5 ~ 3.0)
    pub hdr_peak: f32,    // 显示器可用峰值倍率 (SDR = 1.0, EDR / HDR = 2.0 ~ 10.0)
    /// 0: 输出 sRGB 编码的 8 位值（Bgra8Unorm）；1: 输出线性值且不钳上限（Rgba16Float）。
    pub output_encoding: u32,
    pub _pad1: f32,
    pub _pad2: f32,
}

const _: () = assert!(std::mem::size_of::<ResampleUniforms>() == 64);

pub const HDR_OFF: u32 = 0;
pub const HDR_EXTENDED_LINEAR: u32 = 1;
pub const HDR_SDR_BOOST: u32 = 2;

/// HDR 逆色调映射后处理配置
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HdrConfig {
    pub mode: u32,
    pub boost: f32,
    pub peak: f32,
}

impl Default for HdrConfig {
    fn default() -> Self {
        Self {
            mode: HDR_OFF,
            boost: 1.0,
            peak: 1.0,
        }
    }
}

impl HdrConfig {
    pub const OFF: Self = Self {
        mode: HDR_OFF,
        boost: 1.0,
        peak: 1.0,
    };

    pub fn extended_linear(boost: f32, peak: f32) -> Self {
        Self {
            mode: HDR_EXTENDED_LINEAR,
            boost,
            peak,
        }
        .sanitized()
    }

    pub fn sdr_boost(boost: f32) -> Self {
        Self {
            mode: HDR_SDR_BOOST,
            boost,
            peak: 1.0,
        }
        .sanitized()
    }

    pub fn is_off(&self) -> bool {
        self.mode == HDR_OFF
    }

    pub fn sanitized(self) -> Self {
        let mode = match self.mode {
            HDR_EXTENDED_LINEAR => HDR_EXTENDED_LINEAR,
            HDR_SDR_BOOST => HDR_SDR_BOOST,
            _ => HDR_OFF,
        };
        let boost = self.boost.clamp(1.0, 16.0);
        let peak = self.peak.clamp(1.0, 16.0);
        Self { mode, boost, peak }
    }

    /// 校验目标纹理格式是否满足当前 HDR 模式的要求
    pub fn validate_target_format(&self, format: wgpu::TextureFormat) -> Result<()> {
        if self.mode == HDR_EXTENDED_LINEAR {
            let is_float = matches!(
                format,
                wgpu::TextureFormat::Rgba16Float | wgpu::TextureFormat::Rgba32Float
            );
            if !is_float {
                return Err(anyhow!(
                    "HDR_EXTENDED_LINEAR 模式要求浮点渲染目标 (如 Rgba16Float)，当前为 {:?}",
                    format
                ));
            }
        }
        Ok(())
    }
}

pub struct WgpuResampler {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pipeline: wgpu::RenderPipeline,
    pipeline_layout: wgpu::PipelineLayout,
    shader: wgpu::ShaderModule,
    bind_group_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,

    pub target_format: wgpu::TextureFormat,
    hdr: HdrConfig,

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
    texture: wgpu::Texture,
}

/// 计算指定纹理格式单像素所占字节数
pub fn format_bytes_per_pixel(format: wgpu::TextureFormat) -> u32 {
    match format {
        wgpu::TextureFormat::Rgba16Float => 8,
        wgpu::TextureFormat::Rgba32Float => 16,
        wgpu::TextureFormat::Bgra8Unorm | wgpu::TextureFormat::Rgba8Unorm => 4,
        _ => 4,
    }
}

/// 该格式是不是“线性浮点”目标。
///
/// 它决定了着色器最后一步：
/// - 浮点目标 → 直接写线性值且不钳上限，1.0 = SDR 参考白，> 1.0 交给 EDR；
/// - 8 位目标 → 必须压回 [0,1] 并 sRGB 编码，物理上不可能超出 SDR 白点。
fn is_linear_float_format(format: wgpu::TextureFormat) -> bool {
    matches!(
        format,
        wgpu::TextureFormat::Rgba16Float | wgpu::TextureFormat::Rgba32Float
    )
}

fn create_pipeline(
    device: &wgpu::Device,
    layout: &wgpu::PipelineLayout,
    shader: &wgpu::ShaderModule,
    format: wgpu::TextureFormat,
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
            entry_point: Some("fs_main"),
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

        let pipeline = create_pipeline(&device, &pipeline_layout, &shader, target_format);

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("rossi_resample_sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        Ok(Self {
            device,
            queue,
            pipeline,
            pipeline_layout,
            shader,
            bind_group_layout,
            sampler,
            target_format,
            hdr: HdrConfig::default(),
            target_cache: None,
            source_cache: None,
        })
    }

    /// 获取当前 HDR 设置
    pub fn hdr(&self) -> HdrConfig {
        self.hdr
    }

    /// 当前目标纹理格式下单像素字节数 (Bgra8: 4, Rgba16Float: 8)
    pub fn output_bytes_per_pixel(&self) -> usize {
        format_bytes_per_pixel(self.target_format) as usize
    }

    /// 更新 HDR 模式与参数。
    ///
    /// **不碰目标格式**：走哪条输出通路（8 位 Flutter 纹理 / 半精度浮点 EDR 图层）
    /// 由 [`Self::set_target_format`] 单独决定。两者必须分开，因为同一组色调映射
    /// 参数在两条通路上都合法 —— 只是在 8 位通路上最后会被压回 SDR 白点。
    pub fn set_hdr(&mut self, config: HdrConfig) -> Result<()> {
        self.hdr = config.sanitized();
        Ok(())
    }

    /// 切换目标纹理输出格式。
    ///
    /// `Rgba16Float` = 线性浮点通路（数值可以超过 1.0，真 HDR 的唯一前提）；
    /// `Bgra8Unorm` = 8 位 SDR 通路（物理上不可能超过 1.0）。
    pub fn set_target_format(&mut self, format: wgpu::TextureFormat) -> Result<()> {
        if self.target_format == format {
            return Ok(());
        }
        let pipeline = create_pipeline(
            &self.device,
            &self.pipeline_layout,
            &self.shader,
            format,
        );
        self.pipeline = pipeline;
        self.target_format = format;
        self.target_cache = None; // 格式变更，必须废弃旧缓存纹理
        Ok(())
    }

    /// 启用 Extended Linear HDR 扩展线性模式（目标自动切换为 Rgba16Float）
    pub fn enable_extended_linear_hdr(&mut self, boost: f32, peak: f32) -> Result<()> {
        self.set_target_format(wgpu::TextureFormat::Rgba16Float)?;
        self.set_hdr(HdrConfig::extended_linear(boost, peak))
    }

    /// 启用 SDR Boost 画质增强模式（不改目标格式）
    pub fn enable_sdr_boost(&mut self, boost: f32) -> Result<()> {
        self.set_hdr(HdrConfig::sdr_boost(boost))
    }

    /// 关闭 HDR 与增强（不改目标格式）
    pub fn disable_hdr(&mut self) -> Result<()> {
        self.set_hdr(HdrConfig::OFF)
    }

    /// 获取或创建匹配尺寸的源纹理
    fn get_or_create_source_texture(&mut self, width: u32, height: u32) -> &wgpu::Texture {
        let need_recreate = match &self.source_cache {
            Some(c) => c.width != width || c.height != height,
            None => true,
        };

        if need_recreate {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("rossi_source_texture"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8Unorm,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            self.source_cache = Some(CachedSource {
                width,
                height,
                texture,
            });
        }

        &self.source_cache.as_ref().unwrap().texture
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
                format: self.target_format,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });

            let bpp = format_bytes_per_pixel(self.target_format);
            let bytes_per_row = width * bpp;
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
        let filter_mode = if force_anime4k {
            2u32
        } else if scale < 0.35 {
            0u32
        } else {
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
            hdr_mode: self.hdr.mode,
            hdr_boost: self.hdr.boost,
            hdr_peak: self.hdr.peak,
            output_encoding: if is_linear_float_format(self.target_format) { 1 } else { 0 },
            _pad1: 0.0,
            _pad2: 0.0,
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
                        // 留白初始填充深黑底色 0xFF05050A
                        load: wgpu::LoadOp::Clear(if self.hdr.mode == HDR_EXTENDED_LINEAR {
                            wgpu::Color {
                                r: 0.0015,
                                g: 0.0015,
                                b: 0.0030,
                                a: 1.0,
                            }
                        } else {
                            wgpu::Color {
                                r: 5.0 / 255.0,
                                g: 5.0 / 255.0,
                                b: 10.0 / 255.0,
                                a: 1.0,
                            }
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

        // ── 行跨步守住（安全下限，不是在挑刺）──
        //
        // 目标格式决定了每行要写多少字节：Bgra8Unorm 是 `宽 × 4`，
        // Rgba16Float 是 `宽 × 8`。而 `dst_stride` 是**调用方**给的。
        // 两者不一致时以前会直接 `copy_nonoverlapping` 写过去 —— 那是堆越界，
        // 症状是隔很久某个不相干的分配崩掉，最难查的一类。
        //
        // 不一致本身就是个明确的配置错误（输出通路与上屏端缓冲区格式对不上），
        // 所以这里直接报错并把两个数都写出来，让它一眼能定位。
        let required_row_bytes = (target_w as usize) * format_bytes_per_pixel(self.target_format) as usize;
        if dst_stride < required_row_bytes {
            return Err(anyhow!(
                "目标缓冲区行跨步不足：输出格式 {:?} 每行需要 {} 字节，但只给了 {} 字节。\
                 这通常意味着输出通路（8 位 / 浮点）与上屏端分配的缓冲区格式不一致。",
                self.target_format,
                required_row_bytes,
                dst_stride
            ));
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
            let bpp = format_bytes_per_pixel(self.target_format) as usize;
            let row_bytes = (target_w as usize) * bpp;
            let padded_stride = target.padded_bytes_per_row as usize;

            unsafe {
                // 深黑底色 0xFF05050A (BGRA little-endian: B=0x0A G=0x05 R=0x05 A=0xFF)
                // 的单像素 4 字节表示，用于安全填充行尾 Padding。
                const BG_PIXEL_BGRA: [u8; 4] = [0x0A, 0x05, 0x05, 0xFF];

                for y in 0..target_h as usize {
                    let src_row = &mapped[y * padded_stride..y * padded_stride + row_bytes];
                    let dst_row = dst_ptr.add(y * dst_stride);
                    std::ptr::copy_nonoverlapping(src_row.as_ptr(), dst_row, row_bytes);

                    // ── 行跨步 Padding 安全填充（对齐 mimageviewer Stride Safety）──
                    // macOS CVPixelBuffer 常要求 64 字节行对齐，dst_stride > row_bytes
                    // 时行尾会有未写入的 Padding。Metal 双线性采样器在边缘可能渗入
                    // 这些未初始化的脏显存，表现为红黄绿假彩色块。逐像素填充底色。
                    if dst_stride > row_bytes {
                        let pad_start = dst_row.add(row_bytes);
                        let pad_len = dst_stride - row_bytes;
                        if self.target_format == wgpu::TextureFormat::Bgra8Unorm {
                            let full_pixels = pad_len / 4;
                            for p in 0..full_pixels {
                                std::ptr::copy_nonoverlapping(
                                    BG_PIXEL_BGRA.as_ptr(),
                                    pad_start.add(p * 4),
                                    4,
                                );
                            }
                            let remainder = pad_len % 4;
                            if remainder > 0 {
                                std::ptr::copy_nonoverlapping(
                                    BG_PIXEL_BGRA.as_ptr(),
                                    pad_start.add(full_pixels * 4),
                                    remainder,
                                );
                            }
                        } else {
                            // 浮点格式（如 Rgba16Float）安全清零填充
                            std::ptr::write_bytes(pad_start, 0, pad_len);
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

    /// IEEE 754 半精度浮点数 (f16) 解码为单精度 (f32)
    fn f16_to_f32(h: u16) -> f32 {
        let sign = (h >> 15) & 0x0001;
        let exp = (h >> 10) & 0x001f;
        let mant = h & 0x03ff;

        if exp == 0 {
            if mant == 0 {
                return if sign != 0 { -0.0 } else { 0.0 };
            }
            let val = (mant as f32) / 1024.0 * (2.0f32).powi(-14);
            return if sign != 0 { -val } else { val };
        } else if exp == 31 {
            return if mant == 0 {
                if sign != 0 {
                    f32::NEG_INFINITY
                } else {
                    f32::INFINITY
                }
            } else {
                f32::NAN
            };
        }
        let val = (1.0 + (mant as f32) / 1024.0) * (2.0f32).powi(exp as i32 - 15);
        if sign != 0 {
            -val
        } else {
            val
        }
    }

    #[test]
    fn test_hdr_config_sanitization() {
        let cfg = HdrConfig {
            mode: 99,
            boost: 0.2,
            peak: 0.5,
        };
        let sanitized = cfg.sanitized();
        assert_eq!(sanitized.mode, HDR_OFF);
        assert_eq!(sanitized.boost, 1.0);
        assert_eq!(sanitized.peak, 1.0);

        let valid_hdr = HdrConfig::extended_linear(3.0, 5.0);
        assert_eq!(valid_hdr.mode, HDR_EXTENDED_LINEAR);
        assert_eq!(valid_hdr.boost, 3.0);
        assert_eq!(valid_hdr.peak, 5.0);

        let valid_sdr = HdrConfig::sdr_boost(2.0);
        assert_eq!(valid_sdr.mode, HDR_SDR_BOOST);
        assert_eq!(valid_sdr.boost, 2.0);
        assert_eq!(valid_sdr.peak, 1.0);
    }

    #[test]
    fn test_hdr_format_validation() {
        let hdr_cfg = HdrConfig::extended_linear(3.0, 5.0);
        assert!(hdr_cfg
            .validate_target_format(wgpu::TextureFormat::Rgba16Float)
            .is_ok());
        assert!(hdr_cfg
            .validate_target_format(wgpu::TextureFormat::Bgra8Unorm)
            .is_err());

        let sdr_cfg = HdrConfig::sdr_boost(2.0);
        assert!(sdr_cfg
            .validate_target_format(wgpu::TextureFormat::Bgra8Unorm)
            .is_ok());
    }

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

    #[test]
    fn test_hdr_extended_linear_white_exceeds_sdr_limit() {
        let Some((device, queue)) = init_test_device() else {
            eprintln!("无可用 GPU 适配器，跳过硬件着色器测试");
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Rgba16Float,
        )
        .expect("初始化 Rgba16Float resampler 失败");

        // 设定白点倍率 3.0，峰值 4.0
        resampler
            .set_hdr(HdrConfig::extended_linear(3.0, 4.0))
            .expect("设置 HDR 失败");

        // 1x1 纯白源像素 (RGBA: 255, 255, 255, 255)
        let white_rgba = [255u8, 255, 255, 255];
        let target_w = 1u32;
        let target_h = 1u32;
        let _bpp = 8; // Rgba16Float: 4 个 f16 = 8 字节
        let stride = 256; // 满足 wgpu 256 字节对齐约束
        let mut out_buffer = vec![0u8; stride * target_h as usize];

        resampler
            .resample_to_buffer(
                &white_rgba,
                1,
                1,
                target_w,
                target_h,
                out_buffer.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        // 读取像素 (0,0) 的 RGBA16F 编码
        let r_u16 = u16::from_le_bytes([out_buffer[0], out_buffer[1]]);
        let g_u16 = u16::from_le_bytes([out_buffer[2], out_buffer[3]]);
        let b_u16 = u16::from_le_bytes([out_buffer[4], out_buffer[5]]);
        let a_u16 = u16::from_le_bytes([out_buffer[6], out_buffer[7]]);

        let r_f32 = f16_to_f32(r_u16);
        let g_f32 = f16_to_f32(g_u16);
        let b_f32 = f16_to_f32(b_u16);
        let a_f32 = f16_to_f32(a_u16);

        println!("HDR 扩展线性白点输出: R={r_f32}, G={g_f32}, B={b_f32}, A={a_f32}");

        // 核心断言：扩展线性 HDR 使得白点合法超越 SDR 1.0 限制，进入 ~3.0 (300 nits) 范围！
        assert!(
            r_f32 > 2.0,
            "红色通道应该超越 SDR 白点 (> 2.0)，实测: {r_f32}"
        );
        assert!(
            g_f32 > 2.0,
            "绿色通道应该超越 SDR 白点 (> 2.0)，实测: {g_f32}"
        );
        assert!(
            b_f32 > 2.0,
            "蓝色通道应该超越 SDR 白点 (> 2.0)，实测: {b_f32}"
        );
        assert!((a_f32 - 1.0).abs() < 0.05, "Alpha 应该保持为 1.0");
    }

    #[test]
    fn test_hdr_extended_linear_peak_rolloff() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Rgba16Float,
        )
        .expect("初始化 Rgba16Float resampler 失败");

        // 设定白点倍率 8.0，但显示峰值上限限制在 4.0 (测试 soft shoulder 软肩平滑压缩)
        resampler
            .set_hdr(HdrConfig::extended_linear(8.0, 4.0))
            .expect("设置 HDR 失败");

        let white_rgba = [255u8, 255, 255, 255];
        let stride = 256;
        let mut out_buffer = vec![0u8; stride];

        resampler
            .resample_to_buffer(
                &white_rgba,
                1,
                1,
                1,
                1,
                out_buffer.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        let r_u16 = u16::from_le_bytes([out_buffer[0], out_buffer[1]]);
        let r_f32 = f16_to_f32(r_u16);

        println!("HDR 峰值软肩压缩输出: R={r_f32}, peak=4.0");

        // 软肩应该平滑收敛在 peak (4.0) 之下，既不发生硬截断，也不超过显示器峰值
        assert!(
            r_f32 <= 4.0,
            "输出不应超过目标峰值 (4.0)，实测: {r_f32}"
        );
        assert!(
            r_f32 > 3.8,
            "输出应平滑逼近目标峰值 (> 3.8)，实测: {r_f32}"
        );
    }

    #[test]
    fn test_hdr_float_target_outputs_linear_not_srgb() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Rgba16Float,
        )
        .expect("初始化 Rgba16Float resampler 失败");

        // 模式 0（关闭色调映射）+ 浮点目标：仍必须把 sRGB 解开成线性，
        // 否则整幅画面在 EDR 图层上会明显偏暗。
        resampler.set_hdr(HdrConfig::OFF).expect("设置失败");

        // 中灰 128/255 = 0.502 sRGB ⇒ 线性约 0.2158
        let gray_rgba = [128u8, 128, 128, 255];
        let stride = 256;
        let mut out = vec![0u8; stride];
        resampler
            .resample_to_buffer(&gray_rgba, 1, 1, 1, 1, out.as_mut_ptr(), stride, false)
            .expect("渲染失败");

        let r = f16_to_f32(u16::from_le_bytes([out[0], out[1]]));
        println!("浮点目标 + 关闭色调映射：中灰线性值 = {r}");
        assert!(
            (r - 0.2158).abs() < 0.01,
            "中灰应被解开成线性 0.2158（sRGB 会得到 0.502），实测: {r}"
        );
    }

    #[test]
    fn test_hdr_sdr_boost_on_float_target_is_linear_and_bounded() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Rgba16Float,
        )
        .expect("初始化 Rgba16Float resampler 失败");

        resampler
            .set_hdr(HdrConfig::sdr_boost(2.0))
            .expect("设置 SDR 增强失败");

        let white_rgba = [255u8, 255, 255, 255];
        let stride = 256;
        let mut out = vec![0u8; stride];
        resampler
            .resample_to_buffer(&white_rgba, 1, 1, 1, 1, out.as_mut_ptr(), stride, false)
            .expect("渲染失败");

        let r = f16_to_f32(u16::from_le_bytes([out[0], out[1]]));
        println!("浮点目标 + SDR 增强：白点线性值 = {r}");

        // 浮点目标下 SDR 增强输出的是**线性**值（不是 sRGB 编码值），
        // 且必须收敛在 1.0 以内：1.0 = SDR 参考白。
        assert!(r <= 1.001, "SDR 增强不应超过 SDR 白点，实测: {r}");
        assert!(r > 0.9, "SDR 增强的白点应接近 SDR 白，实测: {r}");
    }

    #[test]
    fn test_hdr_extended_linear_black_stays_black() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Rgba16Float,
        )
        .expect("初始化 Rgba16Float resampler 失败");

        resampler
            .set_hdr(HdrConfig::extended_linear(3.0, 4.0))
            .expect("设置 HDR 失败");

        // 1x1 纯黑源像素 (RGBA: 0, 0, 0, 255)
        let black_rgba = [0u8, 0, 0, 255];
        let stride = 256;
        let mut out_buffer = vec![0u8; stride];

        resampler
            .resample_to_buffer(
                &black_rgba,
                1,
                1,
                1,
                1,
                out_buffer.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        let r_f32 = f16_to_f32(u16::from_le_bytes([out_buffer[0], out_buffer[1]]));
        let g_f32 = f16_to_f32(u16::from_le_bytes([out_buffer[2], out_buffer[3]]));
        let b_f32 = f16_to_f32(u16::from_le_bytes([out_buffer[4], out_buffer[5]]));

        assert!(
            r_f32 < 0.005,
            "纯黑墨迹不应该被抬高 (R < 0.005)，实测: {r_f32}"
        );
        assert!(
            g_f32 < 0.005,
            "纯黑墨迹不应该被抬高 (G < 0.005)，实测: {g_f32}"
        );
        assert!(
            b_f32 < 0.005,
            "纯黑墨迹不应该被抬高 (B < 0.005)，实测: {b_f32}"
        );
    }

    #[test]
    fn test_hdr_sdr_boost_stays_within_sdr_bounds() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let mut resampler = WgpuResampler::new_with_format(
            device,
            queue,
            wgpu::TextureFormat::Bgra8Unorm,
        )
        .expect("初始化 Bgra8Unorm resampler 失败");

        resampler
            .set_hdr(HdrConfig::sdr_boost(2.0))
            .expect("设置 SDR 增强失败");

        let white_rgba = [255u8, 255, 255, 255];
        let stride = 256;
        let mut out_buffer = vec![0u8; stride];

        resampler
            .resample_to_buffer(
                &white_rgba,
                1,
                1,
                1,
                1,
                out_buffer.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        // 在 Bgra8Unorm 格式下，单像素输出为 B, G, R, A (每个 1 字节)
        let b = out_buffer[0];
        let g = out_buffer[1];
        let r = out_buffer[2];
        let a = out_buffer[3];

        // 白点应自然收敛于上限，且不溢出或回卷
        assert!(r >= 250, "SDR Boost 模式下白点应保持明亮: R={r}");
        assert!(g >= 250, "SDR Boost 模式下白点应保持明亮: G={g}");
        assert!(b >= 250, "SDR Boost 模式下白点应保持明亮: B={b}");
        assert_eq!(a, 255);
    }
}
