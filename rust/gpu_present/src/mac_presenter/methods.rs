use super::*;

impl MacPresenter {
    pub fn new(width: u32, height: u32) -> Result<Self> {
        let t0 = Instant::now();
        let target_width = width.max(1);
        let target_height = height.max(1);
        let shared_cache = Arc::new(SharedCache::new());
        let hub = Arc::new(PrefetchHub::new(target_width, target_height));

        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .context("无法获取 Metal / wgpu 图形适配器")?;

        // ── 纹理尺寸上限必须显式要 ──
        //
        // wgpu 的 `Limits::default()` 把 `max_texture_dimension_2d` 限在 8192，
        // 而漫画扫描件常见 8000–10000 px 宽（实测手上这本 AVIF 就是 9504）。
        // 超过上限时 `create_texture` 会走到 wgpu 的**默认错误处理器**，而它是
        // `panic!` —— 在 `extern "C"` 里面 panic 的结果是整个 App `abort`。
        //
        // 既然 8192 只是保守默认值而不是 Metal 的能力，就直接向适配器要它
        // 实际支持的上限。这里仍然取 `min(适配器, 16384)`：要超过适配器的值
        // 会让 `request_device` 直接失败，而 16384 已经盖住任何现实的漫画页。
        let wanted_texture_dimension = crate::wgpu_resampler::requested_texture_dimension(
            adapter.limits().max_texture_dimension_2d,
        );
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("rossi_mac_wgpu_device"),
            required_limits: wgpu::Limits {
                max_texture_dimension_2d: wanted_texture_dimension,
                ..wgpu::Limits::default()
            },
            ..Default::default()
        }))
        .context("无法初始化 wgpu 逻辑设备")?;

        let resampler = Arc::new(Mutex::new(WgpuResampler::new(
            Arc::new(device),
            Arc::new(queue),
        )?));
        let prefetch_thread = Some(spawn_prefetch_worker(
            shared_cache.clone(),
            hub.clone(),
            resampler.clone(),
        ));

        Ok(Self {
            target_width,
            target_height,
            source: None,
            source_path: None,
            source_epoch: 0,
            page_count: 0,
            current_index: None,
            generation: 1,
            shared_cache,
            hub,
            prefetch_thread,
            last_cache_hit: false,
            last_prerender_hit: false,
            last_used_enhanced: false,
            original_preview: enhance::Bypass::new(),
            resampler,
            last_source_width: 0,
            last_source_height: 0,
            last_decoded_width: 0,
            last_decoded_height: 0,
            last_ambient: None,
            init_ms: t0.elapsed().as_secs_f64() * 1000.0,
            presents: 0,
            last: PresentTimings::default(),
        })
    }

    pub fn open(&mut self, path: &Path) -> Result<usize> {
        let src = LocalSource::open(path)
            .with_context(|| format!("macOS 呈现器打开来源失败: {}", path.display()))?;
        let count = src.len();
        let arc = Arc::new(src);

        self.source_epoch = self.source_epoch.wrapping_add(1);
        self.source = Some(arc.clone());
        self.source_path = Some(path.to_path_buf());
        self.page_count = count;
        self.current_index = None;
        // 换了来源，页号的含义就变了：上一本书那一页的调色板不能留给这一本用。
        self.last_ambient = None;

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.entries.clear();
            c.in_flight = None;
        }
        self.hub.clear_source();
        Ok(count)
    }

    pub fn resize(&mut self, width: u32, height: u32) -> Result<()> {
        if width == 0 || height == 0 {
            return Err(anyhow!("尺寸不能为零: {}x{}", width, height));
        }
        if self.target_width != width || self.target_height != height {
            self.target_width = width;
            self.target_height = height;
            self.generation = self.generation.wrapping_add(1);
            self.hub.update_dimensions(width, height);
        }
        Ok(())
    }

    pub fn set_prefetch(&self, enabled: bool) {
        self.hub.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    /// 只「准备」某一页：解码 + 生成当前视口尺寸的预渲染帧，**不碰上屏缓冲区**。
    ///
    /// # 为什么需要它
    ///
    /// [`Self::show_into_buffer`] 把「解码」「渲染」「占住那张唯一的上屏纹理」三件事
    /// 捆在一次调用里，而 `ImageSurface` 是唯一会调它的东西。阅读器为了避免多个 slot
    /// 抢同一张纹理（Ping-Pong 拔河 → 红黄闪），只让当前页挂 `ImageSurface` ——
    /// 于是邻页从「已经解好、画在旁边的 slot 里」退化成「翻到它才开始解」，
    /// 观感就是预加载消失、每页都要等那 400–500 ms。
    ///
    /// 这个方法把前两件事单独拿出来给邻页用：照常解码、照常把预渲染帧放进缓存
    /// （翻过去时 `show` 就能 <1 ms 命中），但**不写用户的 display buffer**，
    /// 所以不会跟当前页抢纹理。
    ///
    /// 锚点**不动**：锚点表达的是「用户在哪」，由 `show` 推进；邻页只负责把自己
    /// 那一页准备好，顺着锚点继续往前铺的活仍然归后台预取线程。
    pub fn prepare(&mut self, index: usize, target_width: u32, target_height: u32) -> Result<()> {
        let source = self.source.clone().ok_or_else(|| anyhow!("尚未打开来源"))?;
        if index >= self.page_count {
            return Err(anyhow!("页索引越界: {} >= {}", index, self.page_count));
        }
        let target_width = target_width.max(1);
        let target_height = target_height.max(1);

        // 目标尺寸推进给后台线程，免得它对着一组旧尺寸做预渲染。
        self.hub.update_dimensions(target_width, target_height);

        // ① 已经为这个尺寸渲染过 → 直接返回。翻回上一页走的就是这条，代价接近 0。
        {
            let mut c = self
                .shared_cache
                .cache
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            if let Some((_, frame)) =
                c.get_raw(index, self.source_epoch, target_width, target_height)
            {
                if frame.is_some() {
                    return Ok(());
                }
            }
            // ② 已有别的线程在解这一页 → 交给它。重复解会争抢磁盘与 CPU，
            //    而它解完会自己预渲染（预取线程的阶段 2 就是干这个的）。
            if c.in_flight == Some(index) {
                return Ok(());
            }
            c.in_flight = Some(index);
        }

        // ③ 解码（缓存里有原图时只是取一份 Arc）
        let decoded = {
            let cached = {
                let mut c = self
                    .shared_cache
                    .cache
                    .lock()
                    .unwrap_or_else(|p| p.into_inner());
                c.get_raw(index, self.source_epoch, target_width, target_height)
                    .and_then(|(pixels, _)| pixels)
            };
            match cached {
                Some(p) => Ok(p),
                None => source.page_pixels(index).map(Arc::new),
            }
        };

        let pixels = match decoded {
            Ok(p) => p,
            Err(e) => {
                // 解码失败也必须清掉 in_flight，否则这一页永远没人再试。
                if let Ok(mut c) = self.shared_cache.cache.lock() {
                    c.in_flight = None;
                }
                return Err(anyhow!("解码第 {} 页失败: {e}", index));
            }
        };

        // ④ 渲染进一块临时缓冲（**不碰 dst_ptr**），再放进预渲染缓存
        let stride = target_width as usize * 4;
        let mut bgra = vec![0u8; stride * target_height as usize];
        let rendered = {
            let mut r = self.resampler.lock().unwrap_or_else(|p| p.into_inner());
            r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                bgra.as_mut_ptr(),
                stride,
                false,
            )
        };

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.in_flight = None;
            if c.has(index, self.source_epoch) {
                c.set_pixels(index, self.source_epoch, pixels);
            } else {
                c.insert(CachedPage::new_raw(index, self.source_epoch, Some(pixels)));
            }
        }
        rendered?;

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.add_pre_rendered(
                index,
                self.source_epoch,
                PreRenderedFrame {
                    target_w: target_width,
                    target_h: target_height,
                    bgra: Arc::new(bgra),
                    stride,
                },
            );
        }
        Ok(())
    }

    /// 解码并渲染当前页，直接写入 CVPixelBuffer 物理内存。
    pub fn show_into_buffer(
        &mut self,
        index: usize,
        dst_ptr: *mut u8,
        dst_stride: usize,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let t_total = Instant::now();
        if dst_ptr.is_null() {
            return Err(anyhow!("目标像素缓冲区指针为空"));
        }
        let source = self.source.clone().ok_or_else(|| anyhow!("尚未打开来源"))?;
        if index >= self.page_count {
            return Err(anyhow!("页索引越界: {} >= {}", index, self.page_count));
        }

        self.resize(target_width, target_height)?;

        // ① 检查预取缓存与 In-Flight 协同等待（彻底消除并发争抢）
        let t_decode = Instant::now();
        let mut decode_hit = false;
        let mut prerender_hit = false;

        let bypass_enhanced = self.is_original_preview();
        // 这一帧到底取自哪一轨。它在取缓存**同一个锁作用域里**顺手问掉：
        // 出了这个作用域，缓存就可能被超分注入或预取线程改写，证据与画面就不是
        // 同一件事了（见 `prefers_enhanced` 的注释）。
        let mut used_enhanced = false;
        let (pixels_opt, pre_rendered_opt) = {
            let mut c = self.shared_cache.cache.lock().unwrap();
            // 先尝试从缓存直接拿（对齐 mImageViewer 级联规则）
            if let Some((p, r)) = c.get(
                index,
                self.source_epoch,
                target_width,
                target_height,
                bypass_enhanced,
            ) {
                decode_hit = true;
                used_enhanced = c.prefers_enhanced(index, self.source_epoch, bypass_enhanced);
                (p, r)
            } else if c.in_flight == Some(index) {
                // 后台预取线程恰好正在解码这一页！等待后台完成，避免前台重复解引发 CPU/磁盘 IO 争抢
                let deadline = Instant::now() + Duration::from_millis(3000);
                while c.in_flight == Some(index) && Instant::now() < deadline {
                    let timeout = deadline.saturating_duration_since(Instant::now());
                    let (guard, _) = self.shared_cache.cv.wait_timeout(c, timeout).unwrap();
                    c = guard;
                }
                if let Some((p, r)) = c.get(
                    index,
                    self.source_epoch,
                    target_width,
                    target_height,
                    bypass_enhanced,
                ) {
                    decode_hit = true;
                    used_enhanced = c.prefers_enhanced(index, self.source_epoch, bypass_enhanced);
                    (p, r)
                } else {
                    c.misses += 1;
                    drop(c);
                    let pixels = Arc::new(source.page_pixels(index)?);
                    if let Ok(mut c2) = self.shared_cache.cache.lock() {
                        c2.insert(CachedPage::new_raw(
                            index,
                            self.source_epoch,
                            Some(pixels.clone()),
                        ));
                    }
                    (Some(pixels), None)
                }
            } else {
                c.misses += 1;
                drop(c);
                let pixels = Arc::new(source.page_pixels(index)?);
                if let Ok(mut c2) = self.shared_cache.cache.lock() {
                    c2.insert(CachedPage::new_raw(
                        index,
                        self.source_epoch,
                        Some(pixels.clone()),
                    ));
                }
                (Some(pixels), None)
            }
        };
        let decode_ms = t_decode.elapsed().as_secs_f64() * 1000.0;
        self.last_cache_hit = decode_hit;

        // ② 呈现阶段：优先使用后台已预渲染好的最终视口帧（< 0.5 ms 零开销内存直拷）
        let t_render = Instant::now();
        if let Some(ref frame) = pre_rendered_opt {
            if (frame.target_w as i64 - target_width as i64).abs() <= 3
                && (frame.target_h as i64 - target_height as i64).abs() <= 3
            {
                prerender_hit = true;
                unsafe {
                    copy_pre_rendered_frame(
                        frame,
                        dst_ptr,
                        dst_stride,
                        target_width,
                        target_height,
                    );
                }
            }
        }

        if !prerender_hit {
            // 未命中预渲染帧时（如刚调整窗口尺寸或超快连翻），现场使用自适应快速抗锯齿滤波渲染
            //
            // 这一帧是**哪一轨**，只能由「像素从哪来」决定：命中缓存来的像素按上面
            // 解析出的 `used_enhanced`；没命中就是刚解的原图。**不能回头去问缓存**
            // ——在"解引用（miss）→ 解码 → 回填"这段空隙里，超分注入可能刚插入
            // `enhanced_pixels`，回头问就会把这帧原图渲染的帧记成超分预渲染帧，
            // 于是超分轨被一张原图帧污染、证据也跟着骗人。
            let pixels_from_cache = pixels_opt.is_some();
            let rendered_enhanced = pixels_from_cache && used_enhanced;
            used_enhanced = rendered_enhanced;

            let pixels = match pixels_opt {
                Some(p) => p,
                None => {
                    let p = Arc::new(source.page_pixels(index)?);
                    if let Ok(mut c) = self.shared_cache.cache.lock() {
                        c.set_pixels(index, self.source_epoch, p.clone());
                    }
                    p
                }
            };

            self.last_source_width = pixels.source_width;
            self.last_source_height = pixels.source_height;
            self.last_decoded_width = pixels.width;
            self.last_decoded_height = pixels.height;

            let mut r = self.resampler.lock().unwrap_or_else(|p| p.into_inner());
            r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                dst_ptr,
                dst_stride,
                false,
            )?;
            // 现场渲染后，将当前视口尺寸保存到该页预渲染缓存中，后续再次访问即可瞬间命中
            let stride = target_width as usize * 4;
            let mut bgra = vec![0u8; stride * target_height as usize];
            if r.resample_to_buffer(
                &pixels.rgba,
                pixels.width,
                pixels.height,
                target_width,
                target_height,
                bgra.as_mut_ptr(),
                stride,
                false,
            )
            .is_ok()
            {
                if let Ok(mut c) = self.shared_cache.cache.lock() {
                    let frame = PreRenderedFrame {
                        target_w: target_width,
                        target_h: target_height,
                        bgra: Arc::new(bgra),
                        stride,
                    };
                    if rendered_enhanced {
                        c.add_pre_rendered_enhanced(index, self.source_epoch, frame);
                    } else {
                        c.add_pre_rendered(index, self.source_epoch, frame);
                    }
                }
            }
        } else if let Some(ref p) = pixels_opt {
            self.last_source_width = p.source_width;
            self.last_source_height = p.source_height;
            self.last_decoded_width = p.width;
            self.last_decoded_height = p.height;
        } else {
            // 只命中预渲染帧时原图可能已释放，尺寸元数据仍须属于当前页。
            let size = self.shared_cache.cache.lock().ok().and_then(|c| {
                c.entries
                    .iter()
                    .find(|e| e.index == index && e.epoch == self.source_epoch)
                    .and_then(|e| e.source_size)
            });
            (self.last_source_width, self.last_source_height) = size.unwrap_or_default();
            self.last_decoded_width = 0;
            self.last_decoded_height = 0;
        }
        let render_ms = t_render.elapsed().as_secs_f64() * 1000.0;
        self.last_prerender_hit = prerender_hit;
        // 「本次呈现用了超分轨」的最终结论。落在 `self` 上而不是只进日志，是为了让
        // Dart 侧能**核对**替换到底有没有生效（`stats.probe.usedEnhanced`）——
        // 只发一条"已触发替换"的日志、无从核对，就是虚报的温床。
        self.last_used_enhanced = used_enhanced;

        // 阅读背景「自适应取色」的调色板。
        //
        // 它读的是页缓存里**已经采好的**那一份 —— 采样在插页缓存时完成，
        // 而插页缓存的是预取线程。所以这里是一次纯读取，翻页关键路径上
        // 不新增任何采样开销，这也是「不额外解码」这条承诺在呈现侧的落点。
        //
        // 与 `self.current_index` 紧挨着写：Dart 侧要用 `currentIndex` 核对
        // 「这配色属于我刚 show 的那一页」。两者若差一拍，那条判据就形同虚设。
        //
        // 缓存里没有（这一页还没采过 / 原图像素已被淘汰且没留下调色板）就是
        // `None`：界面继续用静态底色，**不编一个颜色出来**。
        self.last_ambient = self
            .shared_cache
            .cache
            .lock()
            .ok()
            .and_then(|c| c.palette_for(index, self.source_epoch));

        // 探针里这一页的取色落地情况。带在既有日志里：用户报「背景没变化」时，
        // 这一行就能直接分辨是「呈现器没采到」（ambient=none）还是
        // 「采到了但上层没用」（ambient=#rrggbb）。
        let ambient_desc = match self.last_ambient.as_ref() {
            Some(p) => format!(
                "#{:02x}{:02x}{:02x}",
                p.average[0], p.average[1], p.average[2]
            ),
            None => "none".to_string(),
        };

        eprintln!(
            "[Rossi GPU] show_into_buffer: index={}, prerender_hit={}, decode_hit={}, bypass_enhanced={}, used_enhanced={}, source={}x{}, decoded={}x{}, ambient={}",
            index,
            prerender_hit,
            decode_hit,
            bypass_enhanced,
            used_enhanced,
            self.last_source_width,
            self.last_source_height,
            self.last_decoded_width,
            self.last_decoded_height,
            ambient_desc,
        );

        self.current_index = Some(index);
        self.generation = self.generation.wrapping_add(1);
        self.presents += 1;

        let total_ms = t_total.elapsed().as_secs_f64() * 1000.0;
        self.last = PresentTimings {
            decode_ms,
            render_ms,
            total_ms,
        };

        // ③ 投递新锚点与最新视口尺寸，驱动后续全尺寸原图预取与后台预渲染流水线
        self.hub.set_anchor(
            index,
            self.page_count,
            self.source_epoch,
            target_width,
            target_height,
            Some(source),
        );

        // ④ 呈现完成后，按 mImageViewer 原版保留集策略淘汰超出范围的超分大图
        self.evict_final_pipeline_cache_for_keep_set(index);

        Ok(())
    }

    /// 开关原图对比旁路（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）
    pub fn set_original_preview(&self, active: bool) {
        self.original_preview.set(active);
    }

    /// 查询当前是否处于原图对比旁路状态
    pub fn is_original_preview(&self) -> bool {
        self.original_preview.active()
    }

    /// 注入异步超分完成的像素并预渲染进缓存（对齐 mImageViewer FinalComposite 机制）
    pub fn set_enhanced_pixels(
        &mut self,
        index: usize,
        pixels: Arc<PagePixels>,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let stride = target_width as usize * 4;
        let mut bgra = vec![0u8; stride * target_height as usize];
        let mut prerendered = false;

        if target_width > 0 && target_height > 0 {
            if let Ok(mut r) = self.resampler.lock() {
                if r.resample_to_buffer(
                    &pixels.rgba,
                    pixels.width,
                    pixels.height,
                    target_width,
                    target_height,
                    bgra.as_mut_ptr(),
                    stride,
                    false,
                )
                .is_ok()
                {
                    prerendered = true;
                }
            }
        }

        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.set_enhanced_pixels(index, self.source_epoch, pixels.clone());
            if prerendered {
                c.add_pre_rendered_enhanced(
                    index,
                    self.source_epoch,
                    PreRenderedFrame {
                        target_w: target_width,
                        target_h: target_height,
                        bgra: Arc::new(bgra),
                        stride,
                    },
                );
            }
        }
        eprintln!(
            "[Rossi GPU] set_enhanced_pixels: index={}, prerendered={}, w={}, h={}",
            index, prerendered, pixels.width, pixels.height
        );
        Ok(())
    }

    /// 从图片文件（PNG/WebP/JPEG）加载超分后的大图，并生成预渲染视口帧存入双轨缓存
    pub fn set_enhanced_image(
        &mut self,
        index: usize,
        image_path: &str,
        target_width: u32,
        target_height: u32,
    ) -> Result<()> {
        let bytes = std::fs::read(image_path)?;
        let pixels = rossi_local_core::decode::decode_rgba(&bytes)?;
        eprintln!(
            "[Rossi GPU] set_enhanced_image: index={}, path={}, decoded {}x{}",
            index, image_path, pixels.width, pixels.height
        );
        self.set_enhanced_pixels(index, Arc::new(pixels), target_width, target_height)
    }

    /// 淘汰超出保留集的超分大图（对齐 mImageViewer evict_final_pipeline_cache_for_keep_set 原版函数）
    pub fn evict_final_pipeline_cache_for_keep_set(&mut self, current_idx: usize) {
        if self.page_count == 0 {
            return;
        }
        let keep_set = compute_final_pipeline_keep_set(current_idx, self.page_count, 1);
        if let Ok(mut c) = self.shared_cache.cache.lock() {
            c.evict_final_pipeline_cache_for_keep_set(&keep_set, self.source_epoch);
        }
    }

    pub fn stats_json(&self) -> String {
        let (hits, misses, prefetched, bytes) = self
            .shared_cache
            .cache
            .lock()
            .map(|c| (c.hits, c.misses, c.prefetched, c.bytes()))
            .unwrap_or((0, 0, 0, 0));

        format!(
            "{{\"backend\":\"macos/metal-uma\",\
              \"width\":{},\
              \"height\":{},\
              \"generation\":{},\
              \"presents\":{},\
              \"cacheHit\":{},\
              \"prerenderHit\":{},\
              \"currentIndex\":{},\
              \"usedEnhanced\":{},\
              \"cacheHits\":{},\
              \"cacheMisses\":{},\
              \"cachePrefetched\":{},\
              \"cacheBytes\":{},\
              \"sourceWidth\":{},\
              \"sourceHeight\":{},\
              \"decodedWidth\":{},\
              \"decodedHeight\":{},\
              \"ambient\":{},\
              \"initMs\":{:.2},\
              \"decodeMs\":{:.2},\
              \"renderMs\":{:.2},\
              \"submitMs\":{:.2},\
              \"totalMs\":{:.2}}}",
            self.target_width,
            self.target_height,
            self.generation,
            self.presents,
            if self.last_cache_hit { 1 } else { 0 },
            if self.last_prerender_hit { 1 } else { 0 },
            self.current_index.map(|i| i as i64).unwrap_or(-1),
            if self.last_used_enhanced { 1 } else { 0 },
            hits,
            misses,
            prefetched,
            bytes,
            self.last_source_width,
            self.last_source_height,
            self.last_decoded_width,
            self.last_decoded_height,
            // 没有就是字面量 `null`：Dart 侧把「这一页没采到」与「采到了一个黑」
            // 分开 —— 前者回落静态底色，后者是一份真实结论。
            self.last_ambient
                .as_ref()
                .map(AmbientPalette::to_probe_json)
                .unwrap_or_else(|| "null".to_string()),
            self.init_ms,
            self.last.decode_ms,
            self.last.render_ms,
            self.last.render_ms,
            self.last.total_ms,
        )
    }
}

impl Drop for MacPresenter {
    fn drop(&mut self) {
        self.hub.stop.store(true, Ordering::Relaxed);
        self.hub.cv.notify_all();
        if let Some(h) = self.prefetch_thread.take() {
            let _ = h.join();
        }
    }
}
