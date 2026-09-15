# 以「外部 fork 源码 + rossi 内薄适配 crate」复用 mImageViewer

> **⚠️ 对象回到 mImageViewer（ADR-0011，2026-09-16）。** ADR-0010 曾把 `vendor/` 下的封装对象换成
> ComicRD（那里的封装是**映射**而不是抽瘦），该决定已撤销 —— 原因是 ComicRD 的 RAR 走整章落盘，
> 与 Rossi 的读取模型直接冲突。本 ADR 描述的 mImageViewer 形态**按原文生效**。
> **`use egui` 探针已于 2026-09-16 跑完**，结论见 `docs/phase0-vendor-spike.md` 与下方 Consequences
> ——「薄」成立，但方式是**剪 9 条反向依赖边**，不是排除 `ui_*` 目录。

Rossi 需要 mImageViewer 的本地能力（归档直读、解码、缩略图缓存、双页拆分、ONNX 超分，后续还有视频），
但它是一个 16 crate 的 egui 单体应用、文档里没有任何 macOS/Linux 计划、依赖树里带
ffmpeg / pdfium / ort / tantivy。我们决定：**它的源码以独立 fork 存在**（便于 `git merge upstream/main`
持续吃上游更新），**rossi 侧只新增一个薄的适配 crate**，把它的能力暴露成 Rossi 需要的接口；
它的 UI 层与平台专属代码（WIC / Shell / DPAPI / WASAPI）不进入 rossi。

## Considered Options

- **直接依赖它的 lib target**：Cargo 技术上可行（`src/lib.rs` 存在，会生成 lib target），
  但会把 ffmpeg / pdfium / ort / tantivy 与三个被 `[patch.crates-io]` 替换成 `vendor/` 的 egui
  一起拖进 rossi 的构建。
- **进程级复用**（把它当外部程序调用）：跨进程传图必然引入 CPU 往返，与 Gate A-W 的核心结论正面冲突。
- **整仓库 vendor 进 rossi**：每次同步上游都会变成跨仓库的大 diff，与 ADR-0002 的「可同步」相悖。
- **源码的挂载方式**（vendor 目录 / git submodule / Cargo `git` 依赖）：已由 **ADR-0007** 定案 ——
  `vendor/mimageviewer/` 内的独立 git 检出 + 父仓库 gitlink + 适配层 `path` 依赖。

## Consequences

- rossi 的 Rust 侧从单 crate `windcore` 变为 workspace（现有 FRB crate + 适配 crate + 后续的 renderer crate）。
- **「薄」是设计目标，不是已成立的事实** —— 这一点被实测证实了，但结论比预期好：
  1. **「核心 vs UI」按名字切不出来**：`src/` 467 个 `.rs` 里 **183 个碰 egui**，
     其中 **92 个名字完全不像 UI**（`books` / `keymap` / `ime_focus` / `settings` / `thumb_loader`…）。
     所以「排除 `ui_*` 目录」这条路不存在。
  2. **但切集很小**：v0.1 要复用的 11 个种子里 **8 个完全干净**，脏的 3 个都是个位数行数；
     逐种子的直接脏依赖去重后只有 **9 个模块**要处理（`ui_helpers` 252 行、`displayed_image_transform` 292 行
     是仅有的两个大件）。**不剪边**才会滚成 301 个模块的闭包。
  → 工作量口径因此改为「**逐个种子模块剪反向依赖**」，而不是「一次性统计」；数据见 `docs/phase0-vendor-spike.md`。
- **patch 传递性：不要依赖外部那份 `[patch.crates-io]`**（ADR-0007 已实测）：它不传递且**静默失效**，
  父 workspace 会拿到 crates.io 上的未打补丁版本。→ 让适配层**不依赖任何被 patch 的 crate**
  （`egui` / `eframe` / `egui-wgpu`），比在 rossi 根再抄一份 patch 表更干净。
- 上游只保证 Windows（`wgpu-hal` 只开 `dx12` feature），macOS / Linux 的可移植子集需要逐模块判定。
- **复用范围以 v0.1 冻结线为界**（ADR-0008）：v0.1 只用到归档 / 解码 / 超分；视频等一并推迟。
- 它是 MIT，可原文拷入，保留版权声明即可。
- 它自己的显示管线（decode → CPU RGBA → egui `load_texture`，20MP 26–58 ms/张）**不可照抄**，
  可复用范围限定在归档 / 解码 / 缓存 / 超分。
