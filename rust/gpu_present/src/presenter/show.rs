//! 呈现一页：解码 → 上传 → letterbox 渲染 → GPU 拷贝到共享纹理。
//!
//! `upload_page` 与 `publish_show_*` 只有 `show` 调用，所以跟它放在一起；
//! `draw_and_copy` 与 `current_epoch` 还有别的调用方，留在 `presenter.rs`。

use super::*;

impl Presenter {
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

        // ── 0) 增强轨优先 ──
        //
        // 有这一页的超分图、且不在「原图对比」，就直接用它。**不动解码缓存**：
        // `take` 会把原图那一份摘走，那样关掉对比时就得重新解码一遍。
        let use_enhanced = self
            .original_preview
            .prefers_enhanced(self.enhanced.has(index, epoch));
        // 判定与下面 `stats_json` 报的 `usedEnhanced` 是同一次取值，不是两处各算。
        self.last_used_enhanced = use_enhanced;

        let (pixels, cache_hit) = if use_enhanced {
            (
                self.enhanced
                    .get(index, epoch)
                    .ok_or_else(|| anyhow!("增强图刚查到却取不到: 第 {} 页", index + 1))?,
                false,
            )
        } else {
            let cached = self
                .cache
                .lock()
                .ok()
                .and_then(|mut c| c.take(index, hint, epoch));
            let hit = cached.is_some();
            let raw = match cached {
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
            (Arc::new(raw), hit)
        };
        // 命中时这里读到的是"从缓存取走"的耗时（微秒级），不是解码耗时 ——
        // 这正是要报出来的东西：`cacheHit` 会一起进 stats，两者一起看才不会误读。
        let decode_ms = t_decode.elapsed().as_secs_f64() * 1000.0;
        self.last_cache_hit = cache_hit;

        self.decoded_width = pixels.width;
        self.decoded_height = pixels.height;
        self.decoded_width = pixels.width;
        self.decoded_height = pixels.height;
        if use_enhanced {
            // 布局要的是**原图**尺寸。增强图是 4×，它的 `source_*` 就是放大后的值，
            // 拿它喂 `sourceSizeFor` 会让页被放大四倍 —— 所以一律取记着的原图尺寸；
            // 这一页从没按原图走过时（先注入后呈现）才退回自身尺寸。
            let (sw, sh) = self
                .raw_source_sizes
                .get(&index)
                .copied()
                .unwrap_or((pixels.source_width, pixels.source_height));
            self.decoded_source_width = sw;
            self.decoded_source_height = sh;
        } else {
            self.decoded_source_width = pixels.source_width;
            self.decoded_source_height = pixels.source_height;
            self.raw_source_sizes
                .insert(index, (pixels.source_width, pixels.source_height));
        }

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
}
