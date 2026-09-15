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

## 2. 平台优先级

2026-09-15 决定：**重心在桌面端，移动端只做最低程度适配。**

| 平台 | 投入级别 | 说明 |
|------|----------|------|
| Windows | 主战场 | Gate A 验收平台，D3D12 路径必须达标 |
| macOS | 主战场 | Gate A 验收平台，Metal 路径必须达标 |
| Linux | 次要 | 跟随桌面路径，不单独设 Gate，尽力而为 |
| Web | 延后 | Phase 7 才开，不提前为 Web 牺牲桌面 native 路径 |
| Android | 最低适配 | 不投入 GPU texture 桥，维持现有 Flutter Image + ncnn/waifu2x 链路 |
| iOS | 最低适配 | 不投入 GPU texture 桥，保留现有 CoreML 超分 |

### 2.1 移动端边界

- 不为 Android / iOS 实现 `ImageSurface` 的 native texture 后端；
- 移动端 Reader 继续使用当前 `photo_view` + Flutter Image 显示链；
- 移动端不阻塞桌面端的 Gate A / Gate B，也不参与 Gate 判定；
- 移动端只保证编译通过、既有功能不回归；
- 若日后移动端确实需要 GPU 路径，作为独立立项重新评估（`wgpu` 本身支持 Android Vulkan，缺的是 Flutter 侧的 surface 桥）。

## 3. 上游现状

Breeze 是 Flutter 跨平台漫画阅读器，插件提供漫画源。当前工程包含 Flutter、Rust、QuickJS、`flutter_rust_bridge`；Rust 主 crate 为 `windcore`。当前图片阅读显示链包含 `photo_view`。

上游已经存在多套超分实现：

- Apple：`packages/coreml_upscale`，基于 CoreML，使用 Neural Engine / GPU / CPU；
- 桌面 RealSR：`lib/page/setting/real_sr/service/real_sr_super_resolution.dart` + Rust API；
- Android：ncnn/Vulkan/waifu2x CLI 路线；
- `aidoku-upscale-cli`：从 Aidoku 拆出的 CoreML 超分测试工具。

因此 Rossi 不应该重新发明“模型下载/超分配置”，而应该先统一上层 `Upscaler` 接口，再逐步统一后端。

### 3.1 环境基线（2026-09-15 实测）

| 项 | 实际值 | 来源 |
|----|--------|------|
| Flutter | `3.47.3` | `.fvmrc` / `.puro.json` |
| Dart SDK | `^3.12.0` | `pubspec.yaml` |
| flutter_rust_bridge | `2.13.0` | `rust/Cargo.toml` 精确锁定 `=2.13.0`，`pubspec.lock` 同为 2.13.0 |
| Rust 主 crate | `windcore`，edition 2024 | `rust/Cargo.toml` |
| QuickJS 子 crate | `rquickjs_playground` | `rust/Cargo.toml` |
| 桥接构建方式 | `native_toolchain_rust ^1.0.4` + `hooks ^2.1.0` + `hook/build.dart` | `pubspec.yaml` |
| 平台目录 | `android/ ios/ linux/ macos/ windows/`（**无 `web/`**） | 仓库根 |
| 已生成的 FRB Web 绑定 | `lib/src/rust/frb_generated.web.dart` | `lib/src/rust/` |
| 现有 wgpu / dma-buf / external texture 代码 | **无** | 全仓库检索 |

三点需要注意：

- `pubspec.yaml` 声明 `flutter_rust_bridge: ^2.10.0`，实际锁定 2.13.0；Rust 侧为精确 `=2.13.0`。接入第三方 GPU 桥接代码前必须核对对方的 FRB 版本，2.12 → 2.13 存在生成代码层面的 breaking 变化。
- 仓库中**没有** `rust_builder/` 目录，桥接构建走 `hook/build.dart`。
- `AGENTS.md` 的版本信息已过时（写 Flutter `3.44.2`、FRB `2.12.0`、Dart `^3.9.2`、`rust_builder`），以本表为准。

## 4. Flutter 性能判断

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

## 5. GPU Texture 参考实现

重点参考 `flowsai/flutter_wgpu_texture`：该项目已经实现 Rust/wgpu → Flutter 的 GPU 渲染路径，覆盖 macOS/Metal、Windows/D3D12、Linux/Vulkan + dma-buf、Web/WebGPU，并使用 `flutter_rust_bridge`。

它最有价值的地方是证明：Flutter 可以作为 UI/compositor，Rust/wgpu 可以作为实际 GPU renderer。Rossi 不要求直接复制其 3D 场景代码，而是借用其 surface/texture bridge 思路。

### 5.1 平台覆盖与差距

- 支持：macOS（Metal）、Windows（D3D12）、Linux（Vulkan，经 dma-buf）、Web（WebGPU，Chrome 120+；WebGL2 fallback）
- **不支持：Android、iOS**，官方表格均标注 “Soon”

因为 Rossi 已决定桌面优先，这**不构成 Gate A 的阻塞**；但意味着移动端无法复用该插件的 texture bridge，移动端继续使用 Flutter 现有显示链。

技术栈同源：该插件基于 `flutter_rust_bridge` + `native_toolchain_rust`，与 Breeze 现有构建方式一致，桌面侧移植成本低。

## 6. Web 端结论

Flutter Web 与桌面不能共享同一张 native GPU texture。合理的抽象应是共享 `ImageSurface` / `RenderSurface`，然后按平台使用：

- Native：Metal / D3D12 / Vulkan
- Web：WebGPU（必要时 WebGL2 fallback）

Reader、页面布局、手势状态、缓存策略、源协议等尽可能共享。

## 7. 插件体系

Rossi 第一阶段继续使用 Breeze 插件运行时与现有插件生态。Mangayomi 与 Breeze 的插件协议不是直接兼容的；后续可以建立：

```text
Universal ComicSource API
    ├── Breeze Adapter
    └── Mangayomi Adapter
```

插件兼容层不是第一阶段任务。

## 8. 主要风险

### R1：External texture / GPU interop

Flutter 各桌面平台 native texture 共享路径并不完全一致。必须用 PoC 验证：copy 数量、texture 生命周期、resize/device lost，以及双页持续渲染稳定性。

### R2：超分后端差异

CoreML、Vulkan/ncnn、RealSR、Real-CUGAN、Real-ESRGAN、WebGPU/WASM 不能硬塞进一个 native implementation，但可以共用统一 `Upscaler` API。

### R3：超大图内存

7000×11000 RGBA 原图约 293 MiB。Reader 不能长期持有多张完整 bitmap，应采用 tile、LRU、邻页预取和必要时的 viewport 级处理。

### R4：Web AI SR

Web 端需要独立验证 WebGPU compute、WASM、ONNX Runtime Web 等方案。不要为了 Web 提前牺牲桌面 native 路径。

### R5：双显示链路维护成本

桌面走 GPU texture、移动端走 Flutter Image，意味着 Reader 显示层会长期并存两条实现。页面尺寸计算、缩放语义、超分结果注入时序都可能在两端产生差异行为。必须把显示层抽象成同一套上层语义，避免两端各自演化。

## 9. PoC 验证标准

第一版至少测试：

- 4K、8K 漫画页
- 单页与双页
- 连续缩放/平移
- 10 页邻页预取
- AI 超分开/关
- CPU / GPU / VRAM / RSS / Dart heap
- Windows + macOS

平台范围：Gate A 只在 **Windows + macOS** 上验收；Linux 跟随桌面路径、尽力而为，不单独设 Gate；Android / iOS 不纳入 Gate A。

如果 GPU texture 路径存在明显多余 copy，应调整架构，而不是继续堆 Flutter Image widget 优化。

## 10. 当前结论

**Rossi 继续以 Flutter 为 UI 基座是可行的，但 Reader 图片引擎必须独立于普通 Flutter Image widget。**

优先级：

1. 验证 Flutter + Rust + wgpu GPU surface/texture（桌面）。
2. 用真实漫画大图压力测试。
3. 接入现有超分实现并测量 copy 与 latency。
4. 再替换现有 Reader 图片显示组件。
5. 最后扩展 WebGPU 与多模型超分。

移动端（Android / iOS）在以上过程中不投入 GPU 路径，仅保持现有链路可构建、功能不回归。
