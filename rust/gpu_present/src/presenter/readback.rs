//! 探针用的回读：把共享纹理读回 CPU，并给出「画了多少内容」的判据。
//!
//! 这里只有 `pub` 项与 `Readback` 自己的私有常量，`readback_bgra` 向上调用父模块的
//! 私有渲染辅助，所以不需要放宽任何可见性。

use super::*;
/// 画布底色（与着色器里的常量、以及 `LoadOp::Clear` 的值必须一致）。
///
/// 三处写的是同一个颜色，改一处就要改三处 —— 这是这个设计里最容易腐化的地方，
/// 所以它只作为 **UNORM8 下的比较基准** 出现在这里（探针用），
/// 真正的来源是着色器常量。
pub const BACKGROUND_RGBA8: [u8; 4] = [0, 0, 0, 0];

/// 判定"这个像素就是底色"的容差。
///
/// GPU 的 clear 值到 UNORM8 是**舍入**而不是截断，不同驱动可能差 1；
/// 再加上 `LoadOp::Clear` 与片元输出底色两条路径，容差 4 足够安全。
/// 只在探针里用到（回读比对），所以跟着 feature 走。
#[cfg(feature = "probe")]
const BACKGROUND_TOLERANCE: i32 = 4;

/// 从共享纹理回读下来的一帧。
///
/// 只在 `probe` feature 下存在。它存在的意义是：**在没有 Flutter 的情况下**证明
/// 「解码 → 上传 → 渲染 → 拷贝到共享纹理」真的产出了正确的像素。
/// 没有它，这条链路的正确性只能靠"打开 App 看一眼"，那不是可回归的验证。
#[cfg(feature = "probe")]
#[derive(Debug, Clone)]
pub struct Readback {
    pub width: u32,
    pub height: u32,
    /// BGRA8，行已去掉 256 字节对齐填充。
    pub bgra: Vec<u8>,
}

#[cfg(feature = "probe")]
impl Readback {
    pub fn pixel(&self, x: u32, y: u32) -> [u8; 4] {
        let offset = ((y * self.width + x) * 4) as usize;
        [
            self.bgra[offset],
            self.bgra[offset + 1],
            self.bgra[offset + 2],
            self.bgra[offset + 3],
        ]
    }

    /// 这个像素是不是画布底色。
    pub fn is_background(&self, x: u32, y: u32) -> bool {
        let [b, g, r, a] = self.pixel(x, y);
        (r as i32 - BACKGROUND_RGBA8[0] as i32).abs() <= BACKGROUND_TOLERANCE
            && (g as i32 - BACKGROUND_RGBA8[1] as i32).abs() <= BACKGROUND_TOLERANCE
            && (b as i32 - BACKGROUND_RGBA8[2] as i32).abs() <= BACKGROUND_TOLERANCE
            && (a as i32 - BACKGROUND_RGBA8[3] as i32).abs() <= BACKGROUND_TOLERANCE
    }

    /// 透明像素占比。letterbox 的上下（或左右）留白就体现在这个数上。
    pub fn background_ratio(&self) -> f64 {
        let mut count = 0u64;
        for y in 0..self.height {
            for x in 0..self.width {
                if self.is_background(x, y) {
                    count += 1;
                }
            }
        }
        count as f64 / (self.width as f64 * self.height as f64)
    }

    /// 非底色像素的包围盒 `(x0, y0, x1, y1)`（右下开区间）。全底色时返回 `None`。
    pub fn content_bounds(&self) -> Option<(u32, u32, u32, u32)> {
        let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
        for y in 0..self.height {
            for x in 0..self.width {
                if !self.is_background(x, y) {
                    x0 = x0.min(x);
                    y0 = y0.min(y);
                    x1 = x1.max(x + 1);
                    y1 = y1.max(y + 1);
                }
            }
        }
        if x0 == u32::MAX {
            None
        } else {
            Some((x0, y0, x1, y1))
        }
    }

    /// 平均亮度（0..255）。用来把"全黑"和"有内容"分开 —— 这一条不看颜色构成。
    pub fn mean_luma(&self) -> f64 {
        let mut sum = 0u64;
        for pixel in self.bgra.chunks_exact(4) {
            let (b, g, r) = (pixel[0] as u64, pixel[1] as u64, pixel[2] as u64);
            // Rec.601 权重，只为判断"有没有内容"，不需要精确。
            sum += (r * 299 + g * 587 + b * 114) / 1000;
        }
        sum as f64 / (self.width as f64 * self.height as f64)
    }
}

#[cfg(feature = "probe")]
impl Presenter {
    /// 把当前共享纹理回读到 CPU。
    ///
    /// 路径：共享纹理 `COPY_SOURCE` → READBACK 堆缓冲（行距按 256 对齐）→ `Map`。
    /// 全程在**我们自己的 device** 上，所以不需要跟 Flutter 抢任何东西。
    pub fn readback_bgra(&mut self) -> Result<Readback> {
        let (width, height) = self.target_size();
        if width == 0 || height == 0 {
            return Err(anyhow!("还没有呈现目标，无法回读"));
        }
        let target = self
            .target
            .as_ref()
            .ok_or_else(|| anyhow!("还没有呈现目标，无法回读"))?;
        let shared = target.shared.clone();

        // D3D12 要求 placed footprint 的行距按 256 字节对齐。
        let row_pitch = (width * 4).div_ceil(256) * 256;
        let buffer_size = row_pitch as u64 * height as u64;

        let heap = D3D12_HEAP_PROPERTIES {
            Type: D3D12_HEAP_TYPE_READBACK,
            CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
            CreationNodeMask: 1,
            VisibleNodeMask: 1,
        };
        let desc = D3D12_RESOURCE_DESC {
            Dimension: D3D12_RESOURCE_DIMENSION_BUFFER,
            Alignment: 0,
            Width: buffer_size,
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

        let mut staging: Option<ID3D12Resource> = None;
        unsafe {
            self.d3d_device
                .CreateCommittedResource(
                    &heap,
                    D3D12_HEAP_FLAG_NONE,
                    &desc,
                    D3D12_RESOURCE_STATE_COPY_DEST,
                    None,
                    &mut staging,
                )
                .map_err(|e| anyhow!("CreateCommittedResource(READBACK) 失败: {e:?}"))?;
        }
        let staging = staging.ok_or_else(|| anyhow!("READBACK 资源为空"))?;

        let destination = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::ManuallyDrop::new(Some(staging.clone())),
            Type: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                PlacedFootprint: D3D12_PLACED_SUBRESOURCE_FOOTPRINT {
                    Offset: 0,
                    Footprint: D3D12_SUBRESOURCE_FOOTPRINT {
                        Format: FORMAT,
                        Width: width,
                        Height: height,
                        Depth: 1,
                        RowPitch: row_pitch,
                    },
                },
            },
        };
        let source = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::ManuallyDrop::new(Some(shared.clone())),
            Type: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                SubresourceIndex: 0,
            },
        };

        unsafe {
            self.allocator
                .Reset()
                .map_err(|e| anyhow!("Allocator::Reset 失败: {e}"))?;
            self.cmd_list
                .Reset(&self.allocator, None)
                .map_err(|e| anyhow!("CommandList::Reset 失败: {e}"))?;

            let mut into = [transition(
                &shared,
                D3D12_RESOURCE_STATE_COMMON,
                D3D12_RESOURCE_STATE_COPY_SOURCE,
            )];
            self.cmd_list.ResourceBarrier(&into);
            release_barriers(&mut into);

            self.cmd_list
                .CopyTextureRegion(&destination, 0, 0, 0, &source, None);

            let mut back = [transition(
                &shared,
                D3D12_RESOURCE_STATE_COPY_SOURCE,
                D3D12_RESOURCE_STATE_COMMON,
            )];
            self.cmd_list.ResourceBarrier(&back);
            release_barriers(&mut back);

            self.cmd_list
                .Close()
                .map_err(|e| anyhow!("CommandList::Close 失败: {e}"))?;
            let list: ID3D12CommandList = self
                .cmd_list
                .cast()
                .map_err(|e| anyhow!("cast 到 ID3D12CommandList 失败: {e}"))?;
            self.d3d_queue.ExecuteCommandLists(&[Some(list)]);

            // 与呈现路径共用同一个严格单调递增的 fence 值。
            self.fence_value += 1;
            let value = self.fence_value;
            self.d3d_queue
                .Signal(&self.fence, value)
                .map_err(|e| anyhow!("Queue::Signal 失败: {e}"))?;
            if self.fence.GetCompletedValue() < value {
                self.fence
                    .SetEventOnCompletion(value, self.fence_event)
                    .map_err(|e| anyhow!("SetEventOnCompletion 失败: {e}"))?;
                let wait = WaitForSingleObject(self.fence_event, 4000);
                if wait != WAIT_OBJECT_0 {
                    return Err(anyhow!("等待回读完成超时: {wait:?}"));
                }
            }
        }

        // union 里的那份 COM 引用不会自动释放，手动放掉（与 release_barriers 同一个理由）。
        unsafe {
            let held: std::mem::ManuallyDrop<Option<ID3D12Resource>> =
                std::ptr::read(&destination.pResource);
            drop(std::mem::ManuallyDrop::into_inner(held));
            let held: std::mem::ManuallyDrop<Option<ID3D12Resource>> =
                std::ptr::read(&source.pResource);
            drop(std::mem::ManuallyDrop::into_inner(held));
        }

        let mut raw: *mut std::ffi::c_void = std::ptr::null_mut();
        unsafe {
            staging
                .Map(0, None, Some(&mut raw))
                .map_err(|e| anyhow!("READBACK Map 失败: {e}"))?;
        }
        if raw.is_null() {
            return Err(anyhow!("READBACK Map 返回空指针"));
        }

        let mut bgra = vec![0u8; (width * height * 4) as usize];
        unsafe {
            let base = raw as *const u8;
            for y in 0..height {
                let src = base.add((y * row_pitch) as usize);
                let dst = bgra.as_mut_ptr().add((y * width * 4) as usize);
                std::ptr::copy_nonoverlapping(src, dst, (width * 4) as usize);
            }
            staging.Unmap(0, None);
        }

        Ok(Readback {
            width,
            height,
            bgra,
        })
    }
}
