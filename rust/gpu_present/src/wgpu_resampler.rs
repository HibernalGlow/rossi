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
    pub filter_mode: u32, // 0: Bilinear, 1: Lanczos3, 2: Anime4K
    pub _pad1: f32,
    pub _pad2: f32,
}

pub struct WgpuResampler {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pipeline: wgpu::RenderPipeline,
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
    texture: wgpu::Texture,
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

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("rossi_resample_pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
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
        });

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
                for y in 0..target_h as usize {
                    let src_row = &mapped[y * padded_stride..y * padded_stride + row_bytes];
                    let dst_row = dst_ptr.add(y * dst_stride);
                    std::ptr::copy_nonoverlapping(src_row.as_ptr(), dst_row, row_bytes);
                }
            }
        }

        target.staging_buffer.unmap();
        Ok(())
    }
}
