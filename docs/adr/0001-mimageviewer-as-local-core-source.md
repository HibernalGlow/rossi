# 以 mImageViewer 为 Rossi 本地核心的来源

`MikageSawatari/mimageviewer` 是 Windows 11 独占的成熟查看器应用（MIT / v3.10.0 / 16 crate workspace /
5,586 commits），但它在架构上是**单体应用**而非可依赖的库——`src/lib.rs` 虽是 crate root，
却声明了全部模块（含全部 `ui_*` 与 WIC / Shell / DPAPI / WASAPI 平台专属代码），
依赖树里带 ffmpeg / pdfium / ort / tantivy 与三个被 `[patch.crates-io]` 替换过的 egui。
我们仍决定**源码级 fork 它**：Windows 端的本地能力（归档直读、解码、缩略图缓存、双页拆分、ONNX 超分）
以其实现为来源，抽出不含 UI 与平台专属代码的瘦 lib crate 供 Rossi 依赖；
macOS / Linux 参照同一份实现重建可移植子集。理由是它是唯一真实存在、且已把 Windows 本地阅读做完整的实现，
而「最少自己写的代码」是既定取向。

## Considered Options

- **只作行为标杆、完全独立实现**：自己写的行数最多，与「最少自己写的代码」冲突。
- **进程级复用**（当外部程序调用）：跨进程传图必然引入 CPU 往返，与 Gate A-W 的核心约束正面冲突。
- **不 vendor、只抄写具体算法**：可行，但放弃随上游更新的能力，而这个上游仍在活跃提交。

## Consequences

- Rossi 的 Rust 侧不再是单 crate `windcore`，需要一个 fork 仓库加一个瘦 lib crate。
- **显示管线不照抄**。它是 decode → CPU RGBA → `ctx.load_texture`（20MP 26–58 ms/张、每帧限 1 张纹理），
  与 Rossi「禁止 GPU→CPU→GPU 往返」的方向相反。可复用范围限定在归档 / 解码 / 缓存 / 超分。
- 上游没有任何 macOS / Linux 移植计划，`wgpu-hal` 只开 `dx12` feature。可移植子集必须逐模块判定，
  且解码器（`wic_decoder`）在非 Windows 平台必然要换。
- 超分模型（Real-ESRGAN / Real-CUGAN / NMKD-Siax，ONNX）以 `include_bytes!` 内嵌在它的 exe 中，
  取用需要另行搬运，不能靠下载脚本。
- 抽瘦 lib 时的最大未知是 egui 耦合深度：`src/` 未文档化「核心逻辑 / UI 层」边界，
  需要先做一次探针测量（多少模块实际引用 egui 类型）才敢定工作量。
