# Rossi 技术调研

> 本文记录将 Rossi（Breeze fork）改造成高性能、跨平台漫画阅读器前的技术结论。当前阶段以“验证后再重构”为原则，不提前假设 Flutter GPU 路径一定等价于 mImageViewer。

## 1. 项目定位

Rossi 基于上游 `deretame/Breeze`，目标不是重新制作一个漫画客户端，而是在已有的 Flutter + Rust + QuickJS + 超分基础上，逐步形成：

- Windows / macOS / Linux / Web 共用尽可能多的 Reader/UI 逻辑
- 在线漫画源插件继续可用
- 本地漫画阅读能力补齐
- AI 超分作为阅读链路的一等能力
- 漫画图片尽可能走 GPU-resident / low-copy pipeline
- 后续能够作为 Xiranite 中的漫画工具/Reader 使用

## 2. 上游现状

Breeze 是 Flutter 跨平台漫画阅读器，插件提供漫画源。当前上游文档明确包含 Flutter、Rust、QuickJS、`flutter_rust_bridge`；Rust crate 为 `windcore`。阅读图片目前使用 Flutter 图片显示链路，工程中存在 `photo_view` 依赖。

上游已经存在多套超分实现：

- Apple：`packages/coreml_upscale`，基于 CoreML，使用 Neural Engine / GPU / CPU；
- 桌面 RealSR：`lib/util/real_sr/real_sr_super_resolution.dart` + Rust API；
- Android：ncnn/Vulkan/waifu2x CLI 路线；
- `aidoku-upscale-cli`：从 Aidoku 拆出的 CoreML 超分测试工具。

这意味着 Rossi 不应该重新发明“超分配置/模型下载”体系，而应该先统一其上层接口，再逐步统一后端。

## 3. Flutter 性能判断

Flutter 本身不是 WebView UI。桌面端使用 Flutter engine/Impeller，并可以使用 Texture / GPU 相关能力；因此它具备承担高性能 Reader UI 的底层条件。

但不能直接得出“Flutter = mImageViewer 性能”。真正的性能关键是图片是否避免重复的 CPU↔GPU 拷贝，以及超分输出如何进入最终显示纹理。

目标路径：

```text
Archive / HTTP
    ↓
Decode
    ↓
Native image buffer
    ↓
GPU upload（尽量一次）
    ↓
AI upscale / shader（尽量 GPU 内完成）
    ↓
GPU texture / surface
    ↓
Flutter compositor
```

需要避免：

```text
GPU → CPU → Dart → Flutter bitmap → GPU
```

这种路径会严重削弱大图、双页、连续缩放和超分场景下的性能。

## 4. GPU Texture 参考实现

重点参考：`flowsai/flutter_wgpu_texture`

该项目已经实现 Rust/wgpu → Flutter 的 GPU 渲染路径，覆盖：

- macOS / Metal
- Windows / D3D12
- Linux / Vulkan + dma-buf
- Web / WebGPU（并有 WebGL2 fallback）

并且使用 `flutter_rust_bridge`。它的价值主要是验证“Flutter 作为 UI/compositor，Rust/wgpu 作为实际 GPU renderer”这条技术路线，而不是直接复制其 3D renderer。

## 5. Web 端结论

Flutter Web 与桌面不能共享同一张 native texture。合理的抽象是共享 `ImageSurface` / `RenderSurface` 接口，而在平台层分别实现：

- Native：Metal / D3D12 / Vulkan
- Web：WebGPU（必要时 WebGL2 fallback）

Reader、页面布局、手势状态、缓存策略、源协议等应该尽可能跨平台共享。

## 6. 插件体系

Rossi 保留 Breeze 插件运行时作为第一优先级，因为 Breeze 已经具备在线图源生态与 QuickJS runtime。

Mangayomi 与 Breeze 插件协议不是直接兼容的，后续可以考虑：

```text
Universal ComicSource API
    ├── Breeze Adapter
    └── Mangayomi Adapter
```

插件兼容层不是第一阶段工作，避免在 GPU Reader 验证之前扩大改造范围。

## 7. 主要风险

### R1：External texture / GPU interop

Flutter 不同桌面平台的 native texture 共享路径并不完全一致。必须通过实际 PoC 证明：

- 是否需要额外 copy
- texture 生命周期如何管理
- resize / device lost 如何处理
- 双页时是否能稳定维持目标帧率

### R2：超分的 GPU 位置

不同模型的后端不同。CoreML、Vulkan/ncnn、ONNX/WebGPU 等不能强行共用同一实现，但可以共用统一的 `Upscaler` API。

### R3：超大图内存

例如 7000×11000 RGBA 原图约 293 MiB。Reader 不能简单长期持有多张完整 bitmap。需要 tile、LRU、邻页预取和按 viewport 的处理策略。

### R4：Flutter Web 的 AI SR

桌面可用 native GPU/AI backend；Web 端需要单独验证 WebGPU compute / WASM / ONNX Runtime Web 等方案。Web 端不应影响桌面端架构决策。

## 8. 验证标准

第一版 PoC 至少测试：

- 4K、8K 漫画页
- 单页与双页
- 连续缩放/平移
- 10 页邻页预取
- AI 超分开/关
- 统计 CPU、GPU、显存、Dart heap
- Windows / macOS 各一套

只要 GPU texture 路径出现明显多余 copy，立即调整架构，而不是继续在 Flutter Image widget 上堆优化。

## 9. 当前结论

**Rossi 继续以 Flutter 为 UI 基座是可行的，但 Reader 图片引擎必须独立于普通 Flutter Image widget。**

优先级：

1. 验证 Flutter + Rust + wgpu GPU surface/texture。
2. 用真实漫画大图做压力测试。
3. 接入现有超分实现，测量 copy 与 latency。
4. 再替换现有 Reader 图片显示组件。
5. 最后扩展 WebGPU 与多模型超分。
