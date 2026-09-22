// 本文件由 lib.rs 的内联模块 `mac_platform { … }` **整块原样**搬出：
// 不改一个字符（连缩进都不动），只把外层 `mod mac_platform {}` 换成 `mod mac_platform;`。
// 所以 `crate::mac_platform::…` 这条路径与外部可见性都保持原样。
    use std::ffi::c_void;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::path::Path;
    use std::sync::{Arc, Mutex, MutexGuard};
    use std::thread::JoinHandle;

    use super::mac_presenter::MacPresenter;

    pub const STATE_LOADING: i32 = 0;
    pub const STATE_READY: i32 = 1;
    pub const STATE_FAILED: i32 = 2;

    enum Slot {
        Loading,
        Ready(Box<MacPresenter>),
        Failed(String),
    }

    pub struct GpuPresenter {
        slot: Arc<Mutex<Slot>>,
        worker: Mutex<Option<JoinHandle<()>>>,
    }

    fn lock_slot(slot: &Mutex<Slot>) -> MutexGuard<'_, Slot> {
        slot.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write_err(buf: *mut u8, len: usize, message: &str) {
        if buf.is_null() || len == 0 {
            return;
        }
        let bytes = message.as_bytes();
        let copy_len = bytes.len().min(len - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, copy_len);
            *buf.add(copy_len) = 0;
        }
    }

    unsafe fn borrow<'a>(ptr: *mut c_void) -> Option<&'a GpuPresenter> {
        if ptr.is_null() {
            None
        } else {
            Some(&*(ptr as *const GpuPresenter))
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_create(
        width: u32,
        height: u32,
        _err_buf: *mut u8,
        _err_len: usize,
    ) -> *mut c_void {
        let slot = Arc::new(Mutex::new(Slot::Loading));
        let slot_clone = slot.clone();

        let worker = std::thread::Builder::new()
            .name("rossi-gpu-present-mac-init".to_string())
            .spawn(move || {
                let res = catch_unwind(AssertUnwindSafe(|| MacPresenter::new(width, height)));
                let mut guard = lock_slot(&slot_clone);
                match res {
                    Ok(Ok(p)) => *guard = Slot::Ready(Box::new(p)),
                    Ok(Err(e)) => *guard = Slot::Failed(format!("MacPresenter 初始化失败: {e:#}")),
                    Err(_) => *guard = Slot::Failed("MacPresenter 初始化 panic".to_string()),
                }
            })
            .expect("起不了 macOS 呈现器构建线程");

        let holder = Box::new(GpuPresenter {
            slot,
            worker: Mutex::new(Some(worker)),
        });
        Box::into_raw(holder) as *mut c_void
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_status(
        presenter: *mut c_void,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return STATE_FAILED;
        };
        let guard = lock_slot(&holder.slot);
        match &*guard {
            Slot::Loading => STATE_LOADING,
            Slot::Ready(_) => STATE_READY,
            Slot::Failed(msg) => {
                write_err(err_buf, err_len, msg);
                STATE_FAILED
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_open(
        presenter: *mut c_void,
        path_utf8: *const u8,
        path_len: usize,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return -1;
        };
        if path_utf8.is_null() || path_len == 0 {
            write_err(err_buf, err_len, "path 为空");
            return -1;
        }
        let path_str =
            match std::str::from_utf8(unsafe { std::slice::from_raw_parts(path_utf8, path_len) }) {
                Ok(s) => s,
                Err(e) => {
                    write_err(err_buf, err_len, &format!("path 不是合法的 UTF-8: {e}"));
                    return -1;
                }
            };

        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };

        match inner.open(Path::new(path_str)) {
            Ok(count) => count as i32,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    /// 只预取某一页：解码 + 生成当前视口尺寸的预渲染帧，**不碰上屏缓冲区**。
    ///
    /// 给阅读器的「邻页 slot」用。它以前是靠自己挂一个 `ImageSurface` 去调 `show`
    /// 来把下一页提前解好的，但那样会和当前页抢唯一那张上屏纹理（Ping-Pong →
    /// 红黄闪），于是改成只让当前页 `show`；副作用是邻页没人解，翻页变成现场等
    /// 400–500 ms。这个入口把「准备」与「上屏」拆开，两者都回到位。
    ///
    /// 成功返回 0；失败返回 -1 并写 `err_buf`。失败**不影响画面**（它本来就不上屏），
    /// 所以调用方不需要为它做降级。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_prepare(
        presenter: *mut c_void,
        index: u32,
        target_width: u32,
        target_height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return -1;
        };
        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };
        match inner.prepare(index as usize, target_width, target_height) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_show_into_buffer(
        presenter: *mut c_void,
        index: u32,
        dst_ptr: *mut u8,
        dst_stride: usize,
        target_width: u32,
        target_height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return -1;
        };
        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };

        match inner.show_into_buffer(
            index as usize,
            dst_ptr,
            dst_stride,
            target_width,
            target_height,
        ) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_resize(
        presenter: *mut c_void,
        width: u32,
        height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return -1;
        };
        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };
        match inner.resize(width, height) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_prefetch(presenter: *mut c_void, enabled: i32) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        let guard = lock_slot(&holder.slot);
        if let Slot::Ready(inner) = &*guard {
            inner.set_prefetch(enabled != 0);
            0
        } else {
            -1
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_generation(presenter: *mut c_void) -> u64 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return 0;
        };
        let guard = lock_slot(&holder.slot);
        if let Slot::Ready(inner) = &*guard {
            inner.generation()
        } else {
            0
        }
    }

    /// 开关原图对比旁路（对齐 mImageViewer fs_display_bypasses_final_pipeline 原版机制）。
    /// active != 0 时强制旁路超分图，瞬时直出 raw 原图；0 时正常显示超分图。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_original_preview(
        presenter: *mut c_void,
        active: i32,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        let guard = lock_slot(&holder.slot);
        if let Slot::Ready(inner) = &*guard {
            inner.set_original_preview(active != 0);
            0
        } else {
            -1
        }
    }

    /// 注入超分图片文件并预渲染进缓存（对齐 mImageViewer FinalComposite 机制）
    ///
    /// # 读盘与解码必须放在锁**外**
    ///
    /// 一页超分图是几十到上百 MB 的 PNG/WebP，`fs::read` + `decode_rgba` 要
    /// 几百毫秒到几秒；而 `lock_slot` 是整条上屏路的**总闸** —— `show`（翻页）、
    /// `stats`（诊断轮询）、`prepare` 全都要过它。把解码放在锁里，注入一开始就等于
    /// 把翻页和轮询一起冻住：用户看到的是长时间卡住，而卡住期间到达的 `show` 只能
    /// 排队等着，等它终于跑完时呈现的仍是旧内容。
    ///
    /// 所以这里分两段：**① 锁外读盘解码 → ② 持锁把像素装进双轨缓存**。
    /// 第二段里的重采样只是一个量级更便宜的操作，放在锁里可以接受。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_enhanced_image(
        presenter: *mut c_void,
        index: u32,
        path_utf8: *const u8,
        path_len: usize,
        target_width: u32,
        target_height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "presenter 指针为空");
            return -1;
        };
        if path_utf8.is_null() || path_len == 0 {
            write_err(err_buf, err_len, "path 为空");
            return -1;
        }
        let path_str =
            match std::str::from_utf8(unsafe { std::slice::from_raw_parts(path_utf8, path_len) }) {
                Ok(s) => s,
                Err(e) => {
                    write_err(err_buf, err_len, &format!("path 不是合法的 UTF-8: {e}"));
                    return -1;
                }
            };

        // ── ① 锁外：读盘 + 解码 ──
        let pixels = match std::fs::read(path_str) {
            Ok(bytes) => match rossi_local_core::decode::decode_rgba(&bytes) {
                Ok(pixels) => {
                    eprintln!(
                        "[Rossi GPU] set_enhanced_image: index={}, path={}, file_bytes={}, decoded={}x{}, source={}x{}",
                        index,
                        path_str,
                        bytes.len(),
                        pixels.width,
                        pixels.height,
                        pixels.source_width,
                        pixels.source_height,
                    );
                    Arc::new(pixels)
                }
                Err(e) => {
                    write_err(err_buf, err_len, &format!("解码超分图失败: {e:#}"));
                    return -1;
                }
            },
            Err(e) => {
                write_err(err_buf, err_len, &format!("读取超分图失败: {e}"));
                return -1;
            }
        };

        // ── ② 持锁：装进缓存（顺带按视口尺寸预渲染一帧）──
        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };

        match inner.set_enhanced_pixels(index as usize, pixels, target_width, target_height) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_stats(
        presenter: *mut c_void,
        buf: *mut u8,
        len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        if buf.is_null() || len == 0 {
            return -1;
        }
        let guard = lock_slot(&holder.slot);
        let json = match &*guard {
            Slot::Ready(inner) => inner.stats_json(),
            Slot::Loading => "{\"state\":\"loading\"}".to_string(),
            Slot::Failed(msg) => format!(
                "{{\"state\":\"failed\",\"error\":\"{}\"}}",
                msg.replace('"', "\\\"")
            ),
        };
        let bytes = json.as_bytes();
        let count = bytes.len().min(len - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, count);
            *buf.add(count) = 0;
        }
        count as i32
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_destroy(presenter: *mut c_void) {
        if presenter.is_null() {
            return;
        }
        let holder = unsafe { Box::from_raw(presenter as *mut GpuPresenter) };
        let worker_handle = holder.worker.lock().ok().and_then(|mut w| w.take());
        if let Some(h) = worker_handle {
            let _ = h.join();
        }
    }
