//! Rossi GPU 呈现器（Windows / D3D12）。
//!
//! 把「本地核心解出的页」直接画到一张 DXGI 共享纹理上，由 Flutter 合成上屏。
//! 详细设计见 `docs/texture-bridge-integration.md`，链路与代价见 [`presenter`] 的模块注释。
//!
//! # 为什么是一个独立 DLL 而不是并进 `windcore`
//!
//! 1. **依赖面完全不同**：这里要 wgpu + 裸 D3D12（`windows` crate），而 `windcore`
//!    不需要。并进去会让每次 Flutter 构建都多编一遍 wgpu/naga。
//! 2. **加载时机不同**：C++ 侧要在 Flutter engine 起来时就注册纹理，
//!    那一刻 Dart 还没跑、`windcore.dll` 还没被 FFI 加载。
//!    C++ 用 `LoadLibraryW` 显式加载本 DLL（与 Gate A 的 PoC 同一条路子，
//!    不走 import lib），不依赖任何加载顺序。
//!
//! # C ABI 契约
//!
//! - 所有函数都**不 panic 穿过边界**（内部 `catch_unwind`）。
//! - 返回指针的函数失败时返回 `NULL` 并写 `err_buf`；返回 `i32` 的函数失败时返回负数。
//! - `err_buf` 是调用方提供的 UTF-8 缓冲区，写完会补 `\0`。
//! - 线程契约见 [`presenter::Presenter`]：所有入口内部串行化，调用方不必自己加锁。
//!
//! 符号名一律以 `rossi_gpu_present_` 开头，方便 C++ 侧 `GetProcAddress` 时对齐。

#[cfg(target_os = "windows")]
mod presenter;

#[cfg(target_os = "windows")]
pub use presenter::{BACKGROUND_RGBA8, PresentTimings, Presenter};

#[cfg(all(target_os = "windows", feature = "probe"))]
pub use presenter::Readback;

// ───────────────────────── Windows 实现 ─────────────────────────

#[cfg(target_os = "windows")]
mod platform {
    use std::ffi::c_void;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::sync::Mutex;

    use super::Presenter;
    use windows::Win32::Foundation::HANDLE;

    /// C++ 侧持有的那个指针指向的东西。
    ///
    /// 包一层 `Mutex` 是**必要**的而不是保险：`SurfaceCallback`（raster 线程）
    /// 与 Dart 的 `show`/`open`（平台线程）会同时碰到它，
    /// 而 D3D12 的命令列表 / 分配器不允许并发使用。
    pub struct GpuPresenter {
        inner: Mutex<Presenter>,
    }

    impl GpuPresenter {
        fn lock(&self) -> std::sync::MutexGuard<'_, Presenter> {
            // 某个调用 panic 过会把锁标记为 poisoned。这里关心的是互斥，不是那次失败 ——
            // 而且拒绝继续服务会让"一次偶发 panic"升级成"整个 GPU 路径永久失效"。
            self.inner
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
        }
    }

    /// 把错误写进调用方的缓冲区（UTF-8，补 `\0`）。
    fn write_err(buf: *mut u8, len: usize, message: &str) {
        if buf.is_null() || len == 0 {
            return;
        }
        let bytes = message.as_bytes();
        let count = bytes.len().min(len - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, count);
            *buf.add(count) = 0;
        }
    }

    /// 把 `catch_unwind` 的结果转成"C 侧看得懂"的形状，并把错误信息回填。
    fn guard<T>(
        err_buf: *mut u8,
        err_len: usize,
        failure: T,
        body: impl FnOnce() -> Result<T, String>,
    ) -> T {
        match catch_unwind(AssertUnwindSafe(body)) {
            Ok(Ok(value)) => value,
            Ok(Err(message)) => {
                write_err(err_buf, err_len, &message);
                failure
            }
            Err(_) => {
                write_err(err_buf, err_len, "GPU 呈现器内部 panic");
                failure
            }
        }
    }

    /// 把一个裸指针还原成 `&GpuPresenter`。空指针返回 `None`。
    ///
    /// # Safety
    /// 指针必须来自 [`rossi_gpu_present_create`] 且尚未被 [`rossi_gpu_present_destroy`] 释放。
    unsafe fn borrow<'a>(presenter: *mut c_void) -> Option<&'a GpuPresenter> {
        if presenter.is_null() {
            return None;
        }
        Some(&*(presenter as *const GpuPresenter))
    }

    /// 建呈现器。失败返回 `NULL`。
    ///
    /// `adapter_luid` 由 C++ 侧从 `FlutterEngine::GetGraphicsAdapter()` 读出后传进来
    /// （**同一块卡是硬约束**，见 `presenter::Presenter::new`）。传 0 = 随便挑一块。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_create(
        adapter_luid: u64,
        width: u32,
        height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> *mut c_void {
        guard(err_buf, err_len, std::ptr::null_mut(), || {
            let presenter = Presenter::new(adapter_luid, width, height).map_err(|e| format!("{e:#}"))?;
            Ok(Box::into_raw(Box::new(GpuPresenter {
                inner: Mutex::new(presenter),
            })) as *mut c_void)
        })
    }

    /// 释放呈现器。必须在 Flutter engine 仍然活着时调用 ——
    /// 它要先把纹理注销掉（注销由 C++ 侧负责，这里只管自己的资源）。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_destroy(presenter: *mut c_void) {
        if presenter.is_null() {
            return;
        }
        let _ = catch_unwind(AssertUnwindSafe(|| {
            drop(unsafe { Box::from_raw(presenter as *mut GpuPresenter) });
        }));
    }

    /// 取当前共享句柄。尺寸变化后句柄会变，要重新取。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_handle(presenter: *mut c_void) -> *mut c_void {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return std::ptr::null_mut();
        };
        holder.lock().handle().0
    }

    /// 当前这一代的编号。C++ 侧把它当 `release_context` 交给引擎，
    /// 回调里再原样传回 [`rossi_gpu_present_notify_released`]。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_generation(presenter: *mut c_void) -> u64 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return 0;
        };
        holder.lock().generation()
    }

    /// 引擎告诉我们"第 `generation` 代的句柄已经被打开了"，可以安全退休。
    ///
    /// 这是 Flutter `release_callback` 的正确用法：它的语义就是**句柄已被打开**
    /// （见 `flutter_texture_registrar.h`）。PoC 那里只能"保留最近两个靠猜"，
    /// 有了这个回调就不必猜。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_notify_released(presenter: *mut c_void, generation: u64) {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return;
        };
        let _ = catch_unwind(AssertUnwindSafe(|| {
            holder.lock().notify_released(generation);
        }));
    }

    /// 按引擎请求的尺寸确保呈现目标存在。返回新的共享句柄，失败返回 `NULL`。
    ///
    /// 引擎每次要 surface 都会调它（`SurfaceCallback`）。尺寸没变时是空操作，
    /// 所以它可以被高频调用。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_resize(
        presenter: *mut c_void,
        width: u32,
        height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> *mut c_void {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "呈现器指针为空");
            return std::ptr::null_mut();
        };
        guard(err_buf, err_len, std::ptr::null_mut(), || {
            let mut inner = holder.lock();
            inner.ensure_target(width, height).map_err(|e| format!("{e:#}"))?;
            Ok(inner.handle().0)
        })
    }

    /// 打开本地来源（散图文件夹 / CBZ / CBR）。返回页数，失败返回 -1。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_open(
        presenter: *mut c_void,
        path: *const u8,
        path_len: usize,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "呈现器指针为空");
            return -1;
        };
        if path.is_null() || path_len == 0 {
            write_err(err_buf, err_len, "路径为空");
            return -1;
        }
        let bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
        let Ok(path) = std::str::from_utf8(bytes) else {
            write_err(err_buf, err_len, "路径不是合法 UTF-8");
            return -1;
        };
        guard(err_buf, err_len, -1, || {
            let mut inner = holder.lock();
            match inner.open(path) {
                Ok(count) => Ok(count as i32),
                Err(error) => {
                    let message = format!("{error:#}");
                    inner.set_error(message.clone());
                    Err(message)
                }
            }
        })
    }

    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_page_count(presenter: *mut c_void) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        holder.lock().page_count() as i32
    }

    /// 呈现第 `index` 页。成功返回 0，失败返回 -1。
    ///
    /// 返回之后 C++ 侧必须调 `FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`，
    /// 引擎才会来取这一帧 —— 本函数只管把像素放好，不碰 Flutter。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_show(
        presenter: *mut c_void,
        index: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "呈现器指针为空");
            return -1;
        };
        guard(err_buf, err_len, -1, || {
            let mut inner = holder.lock();
            match inner.show(index as usize) {
                Ok(_) => Ok(0),
                Err(error) => {
                    let message = format!("{error:#}");
                    inner.set_error(message.clone());
                    Err(message)
                }
            }
        })
    }

    /// 诊断快照（JSON，UTF-8）。返回写入的字节数，失败返回 -1。
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
        let json = holder.lock().stats_json();
        let bytes = json.as_bytes();
        let count = bytes.len().min(len - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, count);
            *buf.add(count) = 0;
        }
        count as i32
    }

    /// 句柄类型在本 crate 之外的等价物 —— C ABI 直接用 `void*`。
    #[allow(dead_code)]
    fn _assert_handle_layout(handle: HANDLE) -> *mut c_void {
        handle.0
    }
}

#[cfg(target_os = "windows")]
pub use platform::*;
