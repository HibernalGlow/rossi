//! 页面内容区检测（自动去余白）的过桥入口。
//!
//! 算法本身是 mImageViewer `src/margin_fit.rs` 的逐字移植，住在
//! `rossi_local_core::margin_fit`（登记见 `script/sync_vendored_modules.py` 的 `PORTS`）。
//! 这一层只做两件事：把解码后的 RGBA 缓冲喂进去，把结果换成与 UI 框架无关的
//! 归一化矩形交给 Dart。
//!
//! **这条链路是非破坏式的**：全程不改动任何像素，也不写缓存文件。它只回答
//! 「这一页的内容矩形在哪」，怎么画是渲染层的责任。因此它既不会污染超分的输入，
//! 也不会污染 OCR 读到的原图。

use flutter_rust_bridge::frb;
use rossi_local_core::margin_fit::{
    DEFAULT_TOLERANCE, detect_content_bbox, egui_compat::ColorImage,
};

/// 归一化 (0..1) 的内容区矩形：源图里「不是余白」的那一块。
///
/// 与上游 `egui::Rect` 的 `min`/`max` 等价，只是摊平成四个边，方便 Dart 直接
/// 拿去算源矩形。**四个值都是相对原图宽高的比例**，与原图实际像素尺寸无关。
#[derive(Debug, Clone, Copy)]
pub struct ContentBBox {
    /// 内容左边界占原图宽度的比例。
    pub left: f32,
    /// 内容上边界占原图高度的比例。
    pub top: f32,
    /// 内容右边界占原图宽度的比例（不含）。
    pub right: f32,
    /// 内容下边界占原图高度的比例（不含）。
    pub bottom: f32,
}

/// 检测一页 RGBA 的内容区矩形，返回 `None` 表示**不要裁**。
///
/// `None` 是有意的结果而不是失败：满版出血页、灰色（中间调）背景、余白太少、
/// 或者检测自己不可靠时，上游算法一律回答「切不动」，宁可整页显示也不切掉画面。
/// 调用方**必须**把 `None` 当作「按原样显示」处理，不许回退成任何猜测的矩形。
///
/// 走 `async` 是为了让这几百万像素的分析**不落在 UI 线程上**；结果按页缓存由
/// Dart 侧负责（见 `lib/reader/margin_fit_cache.dart`），每页只分析一次。
///
/// [tolerance] 是 luma 容差（0..255），留空用上游默认值
/// [`DEFAULT_TOLERANCE`]。
#[frb]
pub async fn detect_page_content_bbox(
    rgba: Vec<u8>,
    width: u32,
    height: u32,
    tolerance: Option<u8>,
) -> Option<ContentBBox> {
    let image = ColorImage::from_rgba(&rgba, width as usize, height as usize)?;
    let rect = detect_content_bbox(&image, tolerance.unwrap_or(DEFAULT_TOLERANCE))?;
    Some(ContentBBox {
        left: rect.min.x,
        top: rect.min.y,
        right: rect.max.x,
        bottom: rect.max.y,
    })
}
