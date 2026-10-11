use super::*;

pub(super) struct CachedSource {
    pub(super) width: u32,
    pub(super) height: u32,
    pub(super) mip_levels: u32,
    pub(super) generated_mip_levels: u32,
    pub(super) texture: wgpu::Texture,
}

/// 渲染器当前源纹理的 mip 容量与最近一次绘制准备的级数。
/// 后台预取也可更新源纹理；它不保证对应显示页。字节数只按 RGBA8 texel 计算，
/// 不含 GPU 驱动对齐、分配器及纹理元数据，不代表系统测得的显存常驻量。
#[derive(Debug, Clone, Copy, Default)]
pub struct SourceTextureInfo {
    pub mip_levels: u32,
    pub generated_mip_levels: u32,
    pub texel_bytes: u64,
}

pub(super) fn texel_bytes(width: u32, height: u32, levels: u32) -> u64 {
    (0..levels.min(full_mip_levels(width, height)))
        .map(|level| u64::from((width >> level).max(1)) * u64::from((height >> level).max(1)) * 4)
        .sum()
}

impl WgpuResampler {
    pub fn source_texture_info(&self) -> SourceTextureInfo {
        self.source_cache
            .as_ref()
            .map(|source| SourceTextureInfo {
                mip_levels: source.mip_levels,
                generated_mip_levels: source.generated_mip_levels,
                texel_bytes: texel_bytes(source.width, source.height, source.mip_levels),
            })
            .unwrap_or_default()
    }

    /// 只分配本次需要的 mip；已有同尺寸纹理的容量足够时继续复用。
    pub(super) fn get_or_create_source_texture(
        &mut self,
        width: u32,
        height: u32,
        required_mip_levels: u32,
    ) -> &wgpu::Texture {
        let mip_levels = required_mip_levels.clamp(1, full_mip_levels(width, height));
        let need_recreate = match &self.source_cache {
            Some(c) => c.width != width || c.height != height || c.mip_levels < mip_levels,
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
                // Lanczos 只读一个整数 mip，保留第 0 级到实际读取级的链。
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
                generated_mip_levels: 1,
                texture,
            });
        }

        &self.source_cache.as_ref().unwrap().texture
    }

    /// 把第 0 级逐级降采样到本次读取的等级，不生成更小的无用等级。
    ///
    /// # 为什么必须有这一步
    ///
    /// 缩小（`scale < 1`）本质上要问「一个输出像素盖住了源上哪一块，那块的平均值是多少」。
    /// 只在第 0 级上取一两个点回答这个问题就是**欠采样** —— 结果就是锯齿与闪烁。
    /// mip 链把预滤做成金字塔，按 `floor(log2(1/scale))` 取整数级，
    /// 再由该级上的 Lanczos 重建，减少大幅缩小时所需的采样量。
    ///
    /// 每级的输入仍是前一级，保持原有 2×2 盒式预滤与重建结果。
    pub(super) fn generate_mipmaps(&self, width: u32, height: u32, last_level: u32) {
        let Some(source) = self.source_cache.as_ref() else {
            return;
        };
        let last_level = last_level.min(source.mip_levels.saturating_sub(1));
        if last_level == 0 {
            return;
        }

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("rossi_mipgen_encoder"),
            });

        let mut level = 1u32;
        while level <= last_level {
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
                residual_scale: 0.5,
                _pad3: 0.0,
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
}
