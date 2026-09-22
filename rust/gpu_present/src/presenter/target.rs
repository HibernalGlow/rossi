//! 共享呈现目标：建纹理、按尺寸确保、按 release 回执回收。
//!
//! `create_shared_target` / `reclaim` 只被本模块的入口调用，所以可以留在这里；
//! `draw_and_copy` 与 `free_retired` 还有父模块的调用方，因此留在 `presenter.rs`。

use super::*;

impl Presenter {
    /// 建一张 SHARED 的 BGRA8 纹理并导出句柄。
    fn create_shared_target(
        d3d_device: &ID3D12Device,
        width: u32,
        height: u32,
    ) -> Result<(ID3D12Resource, HANDLE)> {
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
            // ALLOW_RENDER_TARGET 不是必需的（我们只用它当 COPY_DEST），
            // 但留着它，以后要做"Rust 侧直接画 UI 叠加层"时不用重建纹理。
            // 它对拷贝路径没有额外开销。
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
                .map_err(|e| anyhow!("CreateCommittedResource(SHARED) 失败: {:?}", e.code().0))?;
        }
        let resource = resource.ok_or_else(|| anyhow!("CreateCommittedResource 返回空"))?;

        let child: ID3D12DeviceChild = resource
            .cast()
            .map_err(|e| anyhow!("ID3D12Resource -> ID3D12DeviceChild 失败: {e}"))?;

        // GENERIC_ALL 而非只读：D3D11 侧打开时需要完整的访问位。
        let handle = unsafe {
            d3d_device
                .CreateSharedHandle(&child, None, GENERIC_ALL.0, PCWSTR::null())
                .map_err(|e| anyhow!("CreateSharedHandle 失败: {:?}", e.code().0))?
        };

        Ok((resource, handle))
    }

    /// 确保呈现目标的尺寸与引擎请求一致；不一致就重建并导出新句柄。
    ///
    /// 这是 Gate A 风险 1 验证过的"销毁与重建"路径，现在接在了真实调用点上
    /// —— 拖动窗口边框就会走到这里。
    pub fn ensure_target(&mut self, width: u32, height: u32) -> Result<()> {
        let width = width.clamp(1, MAX_EDGE);
        let height = height.clamp(1, MAX_EDGE);

        if let Some(target) = &self.target {
            if target.width == width && target.height == height {
                return Ok(());
            }
        }

        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("rossi-gpu-present-target"),
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
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let (shared, handle) = Self::create_shared_target(&self.d3d_device, width, height)?;

        let generation = self.next_generation;
        self.next_generation += 1;

        if let Some(previous) = self.target.replace(Target {
            generation,
            width,
            height,
            texture,
            view,
            shared,
            handle,
        }) {
            self.retired.push(RetiredTarget {
                generation: previous.generation,
                resource: previous.shared,
                handle: previous.handle,
                released: false,
            });
        }

        self.recreates += 1;
        self.reclaim();

        // 尺寸变了就立刻按当前页重画一遍。
        //
        // 不重画的话，窗口一拖动就会看到底色（刚建的目标是干净的）—— 因为引擎
        // 只会来取"我们通知过的那一帧"。这里不调 `show` 而是直接 `draw_and_copy`：
        // 页纹理已经在上传着，重解一遍纯属浪费（44 MPix 页要几百毫秒）。
        if self.page.is_some() {
            let (width, height) = self.target_size();
            self.draw_and_copy(width, height)?;
        }

        Ok(())
    }

    /// 引擎通知"第 `generation` 代的句柄已经被打开"。
    ///
    /// 这是 PoC 那个"保留最近两个、靠猜"的薄弱点的正解：Flutter 的
    /// `release_callback` 语义就是**句柄已被打开**（见 `flutter_texture_registrar.h`），
    /// 所以那一刻之后我们可以安全地放掉那一代。
    pub fn notify_released(&mut self, generation: u64) {
        for entry in &mut self.retired {
            if entry.generation == generation {
                entry.released = true;
            }
        }
        self.reclaim();
    }

    /// 回收退休目标。
    ///
    /// 两条判据同时成立才释放：**回调已经来过**，且**至少有两代更新的目标存在**
    /// （"刚被换掉的那一代"可能还在引擎的合成链上，多留两代是廉价的保险：
    /// 一张 4K 目标约 33 MB，留两张总共 66 MB，比偶发一次花屏便宜）。
    /// 另外用 [`MAX_RETIRED`] 兜底，防回调始终不来导致无限堆积。
    fn reclaim(&mut self) {
        let newest = self.next_generation;
        let mut kept: Vec<RetiredTarget> = Vec::with_capacity(self.retired.len());
        let mut freed_now = 0u32;

        for entry in self.retired.drain(..) {
            let callback_came = entry.released;
            let two_generations_behind = newest.saturating_sub(entry.generation) >= 2;
            if callback_came && two_generations_behind {
                free_retired(entry);
                freed_now += 1;
            } else {
                kept.push(entry);
            }
        }
        self.retired = kept;

        while self.retired.len() > MAX_RETIRED {
            let oldest = self.retired.remove(0);
            free_retired(oldest);
            freed_now += 1;
        }

        self.released_total += freed_now as u64;
    }
}
