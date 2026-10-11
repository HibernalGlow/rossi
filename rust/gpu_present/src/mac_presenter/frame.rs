use std::sync::Arc;

/// 预渲染的最终 Letterbox 视口帧（含留白背景）。
#[derive(Clone)]
pub struct PreRenderedFrame {
    pub target_w: u32,
    pub target_h: u32,
    // 缓存命中只增加引用计数；不能在持缓存锁时深拷贝整张视口。
    pub bgra: Arc<Vec<u8>>,
    pub stride: usize,
}

impl PreRenderedFrame {
    /// 保存刚完成的显示结果，不重复上传、滤波或 GPU 回读；缓存只保留有效像素。
    ///
    /// # Safety
    /// `src_ptr` 必须可读至少 `src_stride * target_h` 字节，跨步须覆盖每行有效像素。
    pub(super) unsafe fn capture(
        src_ptr: *const u8,
        src_stride: usize,
        target_w: u32,
        target_h: u32,
    ) -> Self {
        let stride = target_w as usize * 4;
        let mut bgra = vec![0; stride * target_h as usize];
        if src_stride == stride {
            std::ptr::copy_nonoverlapping(src_ptr, bgra.as_mut_ptr(), bgra.len());
        } else {
            for y in 0..target_h as usize {
                std::ptr::copy_nonoverlapping(
                    src_ptr.add(y * src_stride),
                    bgra.as_mut_ptr().add(y * stride),
                    stride,
                );
            }
        }
        Self {
            target_w,
            target_h,
            bgra: Arc::new(bgra),
            stride,
        }
    }
}

/// 将缓存视口复制到显示缓冲，尺寸差异部分填充透明背景。
/// 支持目标微小尺寸差异（<= 3 像素容差）时的裁切与留白填补，避免因微小抖动产生昂贵的重新渲染。
pub(super) unsafe fn copy_pre_rendered_frame(
    frame: &PreRenderedFrame,
    dst_ptr: *mut u8,
    dst_stride: usize,
    target_w: u32,
    target_h: u32,
) {
    let copy_w = frame.target_w.min(target_w) as usize;
    let copy_h = frame.target_h.min(target_h) as usize;
    let copy_bytes = copy_w * 4;
    let src_stride = frame.stride;

    if frame.target_w == target_w
        && frame.target_h == target_h
        && src_stride == dst_stride
        && src_stride == copy_bytes
    {
        // 尺寸与跨步完全一致且连续对齐，直接整块单次 memcpy
        std::ptr::copy_nonoverlapping(frame.bgra.as_ptr(), dst_ptr, src_stride * copy_h);
    } else {
        for y in 0..target_h as usize {
            let dst_row = dst_ptr.add(y * dst_stride);
            if y < copy_h {
                let src_row = frame.bgra.as_ptr().add(y * src_stride);
                std::ptr::copy_nonoverlapping(src_row, dst_row, copy_bytes);
                if (target_w as usize) > copy_w {
                    std::ptr::write_bytes(
                        dst_row.add(copy_bytes),
                        0,
                        target_w as usize * 4 - copy_bytes,
                    );
                }
            } else {
                std::ptr::write_bytes(dst_row, 0, target_w as usize * 4);
            }
            if dst_stride > target_w as usize * 4 {
                std::ptr::write_bytes(
                    dst_row.add(target_w as usize * 4),
                    0,
                    dst_stride - target_w as usize * 4,
                );
            }
        }
    }
}
