use super::*;

impl WgpuResampler {
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
        // 取 `floor(log2(1/scale))`：残余倍率因此恒在 [0.5, 1)，重建核宽度被钉在
        // `≤ ceil(3/0.5) = 6`（13×13）。
        //
        // # 这个数试过改，被实测否掉了，别再来一遍
        //
        // 曾经想过「能单级做就单级做」—— 直接在原级上用 `3/scale` 宽的核（最清晰的
        // 直觉），只在核宽超上限时才降 mip。理由是 mip 那一级的 2× 盒式平均在输出
        // Nyquist 处有 0.707 的衰减（`cos(π f)`）。方向听着对，实测相反：
        //
        // ```text
        // 9504×6336 → 2940×1608（scale 0.254）    渲染耗时     边缘跳变
        // 单级宽核（25×25 = 625 抽头）             221.9 ms     215
        // mip（残余 [0.5,1)，13×13 = 169 抽头）    100.5 ms     220   ← 又快又更锐
        // ```
        //
        // 两个原因：核窄了振铃少、边缘反而立得住；而盒式预滤丢的那点高频本来也在
        // 输出 Nyquist 附近、堆在 Lanczos 自己的滚降里看不出来。**2.2 倍速度换来
        // 0.5% 的锐度**（方向还是反的），所以维持在 floor。
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
        // 取完这一级之后还剩多少倍率 —— 重建核的宽度按它算，不按原始 scale 算。
        let residual_scale = (scale * (2.0f32).powf(sample_lod)).min(1.0);

        // 只有 Anime4K 是特殊路径；其余（放大、缩小）**都走 Lanczos3**，
        // 区别只在于它在哪一级 mip 上做（见 `sample_lod`）。
        //
        // 中间曾经有过一条「缩小走 mip 三线性」的分支：它确实抗锯齿，但明显比别的
        // 软件糊 —— 面积平均没有重建核，高频被抹平。所以撤掉了：抗锯齿交给 mip，
        // 锐度交给 Lanczos，两件事不能由同一个滤波器兼任。
        let filter_mode = if force_anime4k { 2u32 } else { 1u32 };

        // 采样几何必须与**实际读取的那一级**一致：
        // Lanczos 的 tap 间距、`max_w/max_h` 的钳制、anime4k 的 texel 步长
        // 全都按 `src_width/src_height` 算。传原始尺寸而读半尺寸的那一级，
        // 结果会是整幅画错位放大 —— 所以这里先按 lod 折算出该级的尺寸。
        let mip_shift = sample_lod.max(0.0) as u32;
        let mip_w = (src_w >> mip_shift).max(1);
        let mip_h = (src_h >> mip_shift).max(1);

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

        // 第 0 级刚写进去，紧接着把下游各级补出来 —— **但只在真的要读它们时**。
        // 单级宽核那条路（`sample_lod == 0`）根本不碰 mip，白生成一整条链
        // 在一张 9504×6336 上要一百多毫秒，是最容易漏掉的一笔纯浪费。
        if sample_lod > 0.0 {
            self.generate_mipmaps(src_w, src_h);
        }

        let src_view = src_texture.create_view(&wgpu::TextureViewDescriptor::default());

        // ② 准备 Uniforms
        let uniforms = ResampleUniforms {
            src_width: mip_w as f32,
            src_height: mip_h as f32,
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
            residual_scale,
            _pad3: 0.0,
            _pad5: 0.0,
        };

        let uniform_buffer = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
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
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
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
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
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
        let target_view = target
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

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
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
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

                    // ── 行跨步 Padding 安全填充（对齐 mimageviewer Stride Safety）──
                    // macOS CVPixelBuffer 常要求 64 字节行对齐，dst_stride > row_bytes
                    // 时行尾会有未写入的 Padding。Metal 双线性采样器在边缘可能渗入
                    // 这些未初始化的脏显存，表现为红黄绿假彩色块。统一清零为透明。
                    if dst_stride > row_bytes {
                        let pad_start = dst_row.add(row_bytes);
                        let pad_len = dst_stride - row_bytes;
                        std::ptr::write_bytes(pad_start, 0, pad_len);
                    }
                }
            }
        }

        target.staging_buffer.unmap();
        Ok(())
    }
}
