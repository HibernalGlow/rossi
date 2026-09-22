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
//! # 创建是异步的
//!
//! [`rossi_gpu_present_create`] **不建 wgpu device**，它只记下参数并起一个线程，
//! 立刻返回。调用方用 [`rossi_gpu_present_status`] 查进度。
//!
//! 这不是为了好看：本函数在 `FlutterWindow::OnCreate` 里被调，而 wgpu device +
//! 管线实测要 ~1 s。同步做就是把它压在第一帧之前、直接吃冷启动预算（判据 B）。
//! 拆开之后启动期只剩"起线程"的开销，那 ~1 s 与 UI 首帧并行发生；
//! 在此期间调用方走 CPU 兜底路径，就绪后再切到本路径。
//!
//! # C ABI 契约
//!
//! - 所有函数都**不 panic 穿过边界**（内部 `catch_unwind`）。
//! - 返回指针的函数失败时返回 `NULL` 并写 `err_buf`；返回 `i32` 的函数失败时返回负数。
//! - `err_buf` 是调用方提供的 UTF-8 缓冲区，写完会补 `\0`。
//! - 线程契约见 [`presenter::Presenter`]：所有入口内部串行化，调用方不必自己加锁。
//! - **呈现器就绪之前，除了 `status` / `stats` / `destroy` 之外的所有入口都会失败**，
//!   错误文本里带原因。调用方应当先用 `status` 判断，而不是靠捕获失败来探测状态。
//!
//! 符号名一律以 `rossi_gpu_present_` 开头，方便 C++ 侧 `GetProcAddress` 时对齐。

/// 超分增强轨的公共部分（选轨规则 / 旁路 / 证据字段名）。**不带 cfg**：
/// mac 与 Windows 两份呈现器都从这里取同一套规则，见模块注释里的理由。
mod enhance;

#[cfg(target_os = "windows")]
mod presenter;

#[cfg(target_os = "windows")]
pub use presenter::{PresentTimings, Presenter, BACKGROUND_RGBA8};

#[cfg(all(target_os = "windows", feature = "probe"))]
pub use presenter::Readback;

// ───────────────────────── Windows 实现 ─────────────────────────

#[cfg(target_os = "windows")]
mod platform;

#[cfg(target_os = "windows")]
pub use platform::*;

pub mod wgpu_resampler;

/// 阅读背景「自适应取色」的采样器（从已解码像素里顺手采边色）。
///
/// 与 `wgpu_resampler` 同样不带平台 cfg，但要跟 `rossi_local_core` 走：
/// 它吃的是 `PagePixels`，而那份依赖在 wasm32 上不存在。
#[cfg(not(target_arch = "wasm32"))]
pub mod ambient;

#[cfg(target_os = "macos")]
mod mac_presenter;

#[cfg(target_os = "macos")]
pub use mac_presenter::MacPresenter;

#[cfg(target_os = "macos")]
mod mac_platform;

#[cfg(target_os = "macos")]
pub use mac_platform::*;

#[cfg(target_arch = "wasm32")]
pub mod web_presenter;

#[cfg(target_arch = "wasm32")]
pub use web_presenter::RossiWebPresenter;
