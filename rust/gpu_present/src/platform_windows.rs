// 本文件由 lib.rs 的内联模块 `platform { … }` **整块原样**搬出：
// 不改一个字符（连缩进都不动），只把外层 `mod platform {}` 换成 `mod platform;`。
// 所以 `crate::platform::…` 这条路径与外部可见性都保持原样。
    use std::ffi::c_void;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::sync::{Arc, Mutex, MutexGuard};
    use std::thread::JoinHandle;

    use super::presenter::escape;
    use super::Presenter;
    use windows::Win32::Foundation::HANDLE;

    /// 呈现器创建的状态码。与 C++ 侧 `rossi_gpu_present_status` 的返回值一一对应。
    ///
    /// 抽成常量而不是裸数字：这三个值跨了语言边界，Rust 这边改一个数、
    /// C++ 那边的分支就会静默走错。
    pub const STATE_LOADING: i32 = 0;
    pub const STATE_READY: i32 = 1;
    pub const STATE_FAILED: i32 = 2;

    /// 就绪槽。
    ///
    /// # 为什么要显式区分「建中」与「建失败」
    ///
    /// 这两件事对调用方的含义**正好相反**：前者该等（并且在此期间走兜底路径），
    /// 后者该彻底放弃这条路。把两者都塞进一个"还没好"，调用方就只能在
    /// "一直等"和"直接报错"之间二选一 —— 而那正是这个枚举存在的理由。
    enum Slot {
        Loading,
        Ready(Box<Presenter>),
        Failed(String),
    }

    /// C++ 侧持有的那个指针指向的东西。
    pub struct GpuPresenter {
        /// 后台线程与调用方共享的就绪槽。
        ///
        /// 用 `Arc<Mutex<_>>` 而不是把整个 `GpuPresenter` 包进 `Arc`：线程只需要写这
        /// 一个槽，没必要让它续命整个对象 —— 一旦那样，析构时机就由引用计数决定，
        /// 而那个时机**必须由 C++ 掌握**（它得赶在 DLL 卸载之前）。
        slot: Arc<Mutex<Slot>>,
        /// 建呈现器的那个线程。`destroy` 必须 join 它 —— 见 [`rossi_gpu_present_destroy`]。
        worker: Mutex<Option<JoinHandle<()>>>,
    }

    fn lock_slot(slot: &Mutex<Slot>) -> MutexGuard<'_, Slot> {
        // 某个调用 panic 过会把锁标记为 poisoned。这里关心的是互斥，不是那次失败 ——
        // 而且拒绝继续服务会让"一次偶发 panic"升级成"整个 GPU 路径永久失效"。
        slot.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
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

    /// 在「已就绪」的前提下执行；未就绪时写下原因并返回 `failure`。
    ///
    /// 调用方应当先问 [`rossi_gpu_present_status`] 再决定要不要走这条路 ——
    /// 这里的未就绪分支是防竞态与防误用的兜底，不是主流程。
    fn with_ready<T>(
        holder: &GpuPresenter,
        err_buf: *mut u8,
        err_len: usize,
        failure: T,
        body: impl FnOnce(&mut Presenter) -> Result<T, String>,
    ) -> T {
        guard(err_buf, err_len, failure, || {
            let mut slot = lock_slot(&holder.slot);
            match &mut *slot {
                Slot::Ready(presenter) => body(presenter),
                Slot::Loading => Err(
                    "呈现器尚未就绪：后台仍在创建 wgpu device 与渲染管线（调用方应走兜底路径）"
                        .to_string(),
                ),
                Slot::Failed(message) => Err(format!("呈现器创建失败: {message}")),
            }
        })
    }

    /// 建呈现器**并立刻返回**，真正的创建在后台线程里进行。
    ///
    /// `adapter_luid` 由 C++ 侧从 `FlutterEngine::GetGraphicsAdapter()` 读出后传进来
    /// （**同一块卡是硬约束**，见 `presenter::Presenter::new`）。传 0 = 随便挑一块。
    ///
    /// 返回的指针**总是非空**，除非连对象都分配不出来 —— "呈现器建不出来"这种失败
    /// 现在通过 [`rossi_gpu_present_status`] 返回 `STATE_FAILED` 表达，而不是返回 NULL。
    /// 这个区别是有意的：NULL 是立刻可判定的，而"建不出来"要等 ~1 s 才知道，
    /// 用它当初返回值会逼 C++ 侧同步等。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_create(
        adapter_luid: u64,
        width: u32,
        height: u32,
        err_buf: *mut u8,
        err_len: usize,
    ) -> *mut c_void {
        guard(err_buf, err_len, std::ptr::null_mut(), || {
            let slot: Arc<Mutex<Slot>> = Arc::new(Mutex::new(Slot::Loading));
            let for_worker = Arc::clone(&slot);

            let spawned = std::thread::Builder::new()
                .name("rossi-gpu-present-init".to_string())
                .spawn(move || {
                    let outcome = Presenter::new(adapter_luid, width, height);
                    let mut slot = lock_slot(&for_worker);
                    *slot = match outcome {
                        Ok(presenter) => Slot::Ready(Box::new(presenter)),
                        Err(error) => Slot::Failed(format!("{error:#}")),
                    };
                });

            let worker = match spawned {
                Ok(handle) => Some(handle),
                Err(_) => {
                    // 起不了线程（资源耗尽之类）就退化成同步建：宁可启动多花那 ~1 s，
                    // 也好过整条 GPU 路径直接不可用。这条路上没有"并行"可言，
                    // 但功能与异步版完全一致。
                    let outcome = Presenter::new(adapter_luid, width, height);
                    let mut slot = lock_slot(&slot);
                    *slot = match outcome {
                        Ok(presenter) => Slot::Ready(Box::new(presenter)),
                        Err(error) => Slot::Failed(format!("{error:#}")),
                    };
                    None
                }
            };

            Ok(Box::into_raw(Box::new(GpuPresenter {
                slot,
                worker: Mutex::new(worker),
            })) as *mut c_void)
        })
    }

    /// 查后台创建的状态：`0` 建中 / `1` 就绪 / `2` 失败。
    ///
    /// 返回 `2` 时 `err_buf` 里是原因。**`0` 不是错误** —— 它意味着调用方此刻
    /// 应该走兜底路径，而不是把这条路径判死。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_status(
        presenter: *mut c_void,
        err_buf: *mut u8,
        err_len: usize,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            write_err(err_buf, err_len, "呈现器指针为空");
            return STATE_FAILED;
        };
        match &*lock_slot(&holder.slot) {
            Slot::Loading => STATE_LOADING,
            Slot::Ready(_) => STATE_READY,
            Slot::Failed(message) => {
                write_err(err_buf, err_len, message);
                STATE_FAILED
            }
        }
    }

    /// 释放呈现器。必须在 Flutter engine 仍然活着时调用 ——
    /// 它要先把纹理注销掉（注销由 C++ 侧负责，这里只管自己的资源）。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_destroy(presenter: *mut c_void) {
        if presenter.is_null() {
            return;
        }
        let _ = catch_unwind(AssertUnwindSafe(|| {
            let holder = unsafe { Box::from_raw(presenter as *mut GpuPresenter) };

            // 必须先等后台线程结束，再析构。
            //
            // 线程握着 `Arc<Mutex<Slot>>` 的一份克隆，而 `Slot::Ready` 里那个
            // `Presenter` 的析构函数**在本 DLL 里**。不等它的后果是：
            // destroy 返回 → C++ 卸载 DLL → 线程这时才写槽或释放 Presenter →
            // 跳进已卸下的代码页。
            //
            // 线程已经跑完时 join 立刻返回，所以正常路径上没有额外代价。
            if let Ok(mut guard) = holder.worker.lock() {
                if let Some(handle) = guard.take() {
                    let _ = handle.join();
                }
            }

            drop(holder);
        }));
    }

    /// 取当前共享句柄。尺寸变化后句柄会变，要重新取。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_handle(presenter: *mut c_void) -> *mut c_void {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return std::ptr::null_mut();
        };
        match &mut *lock_slot(&holder.slot) {
            Slot::Ready(inner) => inner.handle().0,
            // 未就绪就没有句柄。C++ 侧拿到空指针应当放弃这一帧，而不是把它
            // 当成一个合法句柄交给引擎。
            _ => std::ptr::null_mut(),
        }
    }

    /// 当前这一代的编号。C++ 侧把它当 `release_context` 交给引擎，
    /// 回调里再原样传回 [`rossi_gpu_present_notify_released`]。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_generation(presenter: *mut c_void) -> u64 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return 0;
        };
        match &mut *lock_slot(&holder.slot) {
            Slot::Ready(inner) => inner.generation(),
            _ => 0,
        }
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
            if let Slot::Ready(inner) = &mut *lock_slot(&holder.slot) {
                inner.notify_released(generation);
            }
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
        with_ready(holder, err_buf, err_len, std::ptr::null_mut(), |inner| {
            inner
                .ensure_target(width, height)
                .map_err(|e| format!("{e:#}"))?;
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
        with_ready(holder, err_buf, err_len, -1, |inner| {
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
        match &mut *lock_slot(&holder.slot) {
            Slot::Ready(inner) => inner.page_count() as i32,
            _ => -1,
        }
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
        with_ready(holder, err_buf, err_len, -1, |inner| {
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

    /// 开关预取。`enabled != 0` 打开。返回 0 成功、-1 表示还没就绪。
    ///
    /// 加这个入口是为了 **A/B**：同一份二进制、只差这一处，比"改代码前后各量一次"
    /// 少一个变量（代码漂移会混进数字里）。启动期的等价写法是环境变量
    /// `ROSSI_GPU_PREFETCH=0`。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_prefetch(presenter: *mut c_void, enabled: i32) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        match &mut *lock_slot(&holder.slot) {
            Slot::Ready(inner) => {
                inner.set_prefetch_enabled(enabled != 0);
                0
            }
            _ => -1,
        }
    }

    /// 诊断快照（JSON，UTF-8）。返回写入的字节数，失败返回 -1。
    ///
    /// 与别的入口不同，它在**未就绪时也能给出结果** —— 而且必须能，因为
    /// "现在到底是什么状态"正是调用方最想知道的那件事。未就绪时输出一个只含
    /// `state` 的最小对象；就绪时是 `Presenter` 的完整快照（那里的 `state`
    /// 恒为 `ready`，由 C++ 侧补上）。
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
        let json = catch_unwind(AssertUnwindSafe(|| match &mut *lock_slot(&holder.slot) {
            Slot::Ready(inner) => inner.stats_json(),
            Slot::Loading => "{\"state\":\"loading\"}".to_string(),
            Slot::Failed(message) => {
                format!("{{\"state\":\"failed\",\"error\":\"{}\"}}", escape(message))
            }
        }))
        .unwrap_or_else(|_| "{\"state\":\"failed\",\"error\":\"stats 内部 panic\"}".to_string());

        let bytes = json.as_bytes();
        let count = bytes.len().min(len - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, count);
            *buf.add(count) = 0;
        }
        count as i32
    }

    /// 注入一页的超分图。**读盘与解码放在锁外**，只有「装进增强轨」这一步持锁：
    /// `lock_slot` 是整条上屏路的总闸，把几百毫秒的解码放进去会连同 `show` 与
    /// `stats` 一起冻住（mac 侧同一个坑，纪律也写在那边）。
    ///
    /// `target_width` / `target_height` 只为与 mac 的签名对齐而保留，Windows 不读：
    /// 这条路径每帧都在 GPU 上重采样，没有「预渲染视口帧」可建。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_enhanced_image(
        presenter: *mut c_void,
        index: u32,
        path_utf8: *const u8,
        path_len: usize,
        _target_width: u32,
        _target_height: u32,
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
        let Ok(path_str) =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(path_utf8, path_len) })
        else {
            write_err(err_buf, err_len, "path 不是合法的 UTF-8");
            return -1;
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

        // ── ② 持锁：装进增强轨 ──
        let mut guard = lock_slot(&holder.slot);
        let Slot::Ready(inner) = &mut *guard else {
            write_err(err_buf, err_len, "呈现器尚未就绪");
            return -1;
        };
        match inner.set_enhanced_pixels(index as usize, pixels) {
            Ok(()) => 0,
            Err(e) => {
                write_err(err_buf, err_len, &format!("{e:#}"));
                -1
            }
        }
    }

    /// 开关原图对比旁路：`active != 0` 强制走原图轨，0 则按增强轨优先。
    /// 旁路期间增强图**保留**，关掉要能立刻换回去。
    #[no_mangle]
    pub extern "C" fn rossi_gpu_present_set_original_preview(
        presenter: *mut c_void,
        active: i32,
    ) -> i32 {
        let Some(holder) = (unsafe { borrow(presenter) }) else {
            return -1;
        };
        let mut guard = lock_slot(&holder.slot);
        if let Slot::Ready(inner) = &mut *guard {
            inner.set_original_preview(active != 0);
            0
        } else {
            -1
        }
    }

    /// 句柄类型在本 crate 之外的等价物 —— C ABI 直接用 `void*`。
    #[allow(dead_code)]
    fn _assert_handle_layout(handle: HANDLE) -> *mut c_void {
        handle.0
    }
