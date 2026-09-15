# Rossi 技术调研

> 本文记录将 Rossi（Breeze fork）改造成高性能、跨平台漫画阅读器前的技术结论。当前阶段以“验证后再重构”为原则，不提前假设 Flutter GPU 路径一定等价于 mImageViewer。

## 1. 项目定位

Rossi 基于上游 `deretame/Breeze`，目标是在已有 Flutter + Rust + QuickJS + 超分基础上，逐步形成：

- Windows / macOS / Linux / Web 共用尽可能多的 Reader/UI 逻辑
- 在线漫画源插件继续可用
- 本地漫画阅读能力补齐
- AI 超分作为阅读链路的一等能力
- 漫画图片尽可能走 GPU-resident / low-copy pipeline
- 后续能够作为 Xiranite 中的漫画工具/Reader 使用

## 2. 上游现状

Breeze 是 Flutter 跨平台漫画阅读器，插件提供漫画源。当前工程包含 Flutter、Rust、QuickJS、`flutter_rust_bridge`；Rust 主 crate 为 `windcore`。当前图片阅读显示链包含 `photo_view`。

上游已经存在多套超分实现：

- Apple：`packages/coreml_upscale`，基于 CoreML，使用 Neural Engine / GPU / CPU；
- 桌面 RealSR：`lib/util/real_sr/real_sr_super_resolution.dart` + Rust API；
- Android：ncnn/Vulkan/waifu2x CLI 路线；
- `aidoku-upscale-cli`：从 Aidoku 拆出的 CoreML 超分测试工具。

因此 Rossi 不应该重新发明“模型下载/超分配置”，而应该先统一上层 `Upscaler` 接口，再逐步统一后端。

## 3. Flutter 性能判断

Flutter 本身可以承担高性能 Reader UI；桌面端有 Flutter engine/Impeller，并提供 Texture/GPU 相关能力。但“Flutter 有 GPU”不等于“默认 Flutter Image 就达到 mImageViewer”。

真正关键的是图片是否避免不必要的 CPU↔GPU 拷贝，以及 AI 超分输出如何进入最终显示纹理。

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

## 4. GPU Texture 参考实现

重点参考 `flowsai/flutter_wgpu_texture`：该项目已经实现 Rust/wgpu → Flutter 的 GPU 渲染路径，覆盖 macOS/Metal、Windows/D3D12、Linux/Vulkan + dma-buf、Web/WebGPU，并使用 `flutter_rust_bridge`。

它最有价值的地方是证明：Flutter 可以作为 UI/compositor，Rust/wgpu 可以作为实际 GPU renderer。Rossi 不要求直接复制其 3D 场景代码，而是借用其 surface/texture bridge 思路。

## 5. Web 端结论

Flutter Web 与桌面不能共享同一张 native GPU texture。合理的抽象应是共享 `ImageSurface` / `RenderSurface`，然后按平台使用：

- Native：Metal / D3D12 / Vulkan
- Web：WebGPU（必要时 WebGL2 fallback）

Reader、页面布局、手势状态、缓存策略、源协议等尽可能共享。

## 6. 插件体系

Rossi 第一阶段继续使用 Breeze 插件运行时与现有插件生态。Mangayomi 与 Breeze 的插件协议不是直接兼容的；后续可以建立：

```text
Universal ComicSource API
    ├── Breeze Adapter
    └── Mangayomi Adapter
```

插件兼容层不是第一阶段任务。

## 7. 主要风险

### R1：External texture / GPU interop

Flutter 各桌面平台 native texture 共享路径并不完全一致。必须用 PoC 验证：copy 数量、texture 生命周期、resize/device lost，以及双页持续渲染稳定性。

### R2：超分后端差异

CoreML、Vulkan/ncnn、RealSR、Real-CUGAN、Real-ESRGAN、WebGPU/WASM 不能硬塞进一个 native implementation，但可以共用统一 `Upscaler` API。

### R3：超大图内存

7000×11000 RGBA 原图约 293 MiB。Reader 不能长期持有多张完整 bitmap，应采用 tile、LRU、邻页预取和必要时的 viewport 级处理。

### R4：Web AI SR

Web 端需要独立验证 WebGPU compute、WASM、ONNX Runtime Web 等方案。不要为了 Web 提前牺牲桌面 native 路径。

## 8. PoC 验证标准

第一版至少测试：

- 4K、8K 漫画页
- 单页与双页
- 连续缩放/平移
- 10 页邻页预取
- AI 超分开/关
- CPU / GPU / VRAM / RSS / Dart heap
- Windows + macOS

如果 GPU texture 路径存在明显多余 copy，应调整架构，而不是继续堆 Flutter Image widget 优化。

## 9. 当前结论

**Rossi 继续以 Flutter 为 UI 基座是可行的，但 Reader 图片引擎必须独立于普通 Flutter Image widget。**

优先级：

1. 验证 Flutter + Rust + wgpu GPU surface/texture。
2. 用真实漫画大图压力测试。
3. 接入现有超分实现并测量 copy 与 latency。
4. 再替换现有 Reader 图片显示组件。
5. 最后扩展 WebGPU 与多模型超分。
