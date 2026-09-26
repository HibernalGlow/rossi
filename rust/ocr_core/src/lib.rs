//! Rossi 的 OCR 翻译流水线（ADR-0018）。
//!
//! 一期形态是**成品页**：检测 → 识别 → 翻译 → 擦字 → 译文回填，产物落盘缓存，
//! 渲染路径只读缓存。本 crate 负责其中**与像素和几何有关的部分**（检测 / 识别 / 擦字），
//! 文字排版与绘制留在 Dart 侧复用 Flutter 的 CJK 整形（见 ADR-0018 §决定 3）。
//!
//! 许可边界（ADR-0018 §决定 1）—— 本 crate 只允许 MIT / Apache-2.0 来源：
//! - 检测：PP-OCRv4 mobile det（apache-2.0）
//! - 识别：manga-ocr 的 ONNX 导出（apache-2.0）
//! - 擦字：LaMa 的 manga 导出（apache-2.0）
//! `comic-text-detector` / `manga-image-translator` / Yakuyomi 的权重**一律不得**进来。

pub mod detect;
pub mod group;
pub mod inpaint;
pub mod postprocess;
pub mod recognize;
pub mod session;
pub mod types;

pub use detect::{Detection, Detector};
pub use group::{GroupParams, TextBlock, group_boxes};
pub use inpaint::{Inpainted, Inpainter, mask_from_blocks};
pub use postprocess::Params as DetectorParams;
pub use recognize::{Recognition, Recognizer};
pub use session::{Ep, StageEpPlan, ep_available, stage_ep_plan};
pub use types::{Quad, TextBox};
