# Rossi 改造路线图

> 目标：以 Breeze 为产品基座，逐步构建高性能跨平台漫画阅读器，并为 Xiranite 集成保留清晰的模块边界。

## Phase 0 — 基线与可回退点

- [x] Fork 上游 Breeze 为 `HibernalGlow/rossi`
- [ ] 保留上游同步入口，不直接污染 `main`
- [ ] 确认当前 Windows/macOS/Linux 构建基线
- [ ] 记录现有 Reader 的帧率、内存、翻页延迟
- [ ] 记录现有 RealSR/CoreML/Android 超分链路

分支：`research/gpu-reader-foundation`

## Phase 1 — GPU Reader PoC（最高优先级）

目标不是做完整 Reader，而是证明 Flutter 能否承载目标级别的图片显示。

```text
Flutter Widget
      ↓
ImageSurface API
      ↓
Rust / FRB
      ↓
wgpu renderer
      ↓
Metal / D3D12 / Vulkan
      ↓
Flutter-composited texture/surface
```

验收：

- 单张 4K/8K 漫画图稳定显示
- 平移/缩放不依赖 Dart bitmap rebuild
- 不发生不必要的 GPU→CPU→GPU 往返
- 能正确处理 resize、texture 销毁与重建
- Windows + macOS 均通过

## Phase 2 — Manga Image Pipeline

建立独立于 Flutter Image widget 的图片引擎抽象：

```text
ImageSource
  ├── HTTP page
  ├── local file
  └── archive entry

        ↓
Decoder
        ↓
ImageBuffer / Tile
        ↓
Cache
        ↓
GPU Surface
```

重点：

- ZIP/CBZ 原位读取
- 后续评估 CBR/RAR/7z
- 大图 tile 化
- LRU GPU/CPU cache
- 当前页 + 邻页预取
- 双页共享/复用策略

## Phase 3 — Unified Upscaler

统一现有超分入口：

```text
Upscaler
 ├── CoreML
 ├── RealSR
 ├── Real-CUGAN
 ├── Real-ESRGAN
 └── WebGPU/WASM backend
```

设计原则：模型、执行后端与 Reader UI 解耦。

超分策略：

- 原图先显示，增强完成后平滑替换
- 当前页优先
- 邻页低优先级预取
- 可选择 1x / 2x / 4x
- 允许模型级别配置
- 允许 Original / Enhanced 即时切换

## Phase 4 — Reader 体验

- 单页 / 双页
- RTL / LTR
- Webtoon / vertical
- Fit width / height / original
- 平滑缩放
- 连续滚动
- 页面预览
- 章节切换
- 阅读历史
- 输入设备适配

这一阶段尽量不改变在线源层。

## Phase 5 — Source / Plugin 统一层

第一阶段继续使用 Breeze 插件生态。

随后抽象：

```text
ComicSource
 ├── Breeze adapter
 ├── Mangayomi adapter（可选）
 └── Native source
```

只有在统一 source API 稳定后才考虑兼容 Mangayomi extension。

## Phase 6 — Xiranite Integration

目标：Reader 作为 Xiranite 的一个可嵌入工具，而不是另一个独立 App。

共享：

- Comic metadata
- Source API
- Reader state
- Download/cache
- Upscaler configuration
- Rust image engine

宿主：

- Rossi standalone
- Xiranite desktop
- Xiranite web

## Phase 7 — Web Backend

在不改变 Reader 上层 API 的前提下加入 Web backend：

```text
Shared Reader
      ↓
ImageSurface
 ┌────┴────┐
Native    Web
  ↓         ↓
wgpu     WebGPU
```

Web 端独立评估：

- WebGPU texture
- WGSL compute
- WASM decoder
- ONNX Runtime Web / WebGPU
- 浏览器内存上限

Web 端不要求与 native GPU backend 使用完全相同的实现，只要求保持统一上层语义。

## Phase 8 — 性能目标

最终性能目标不是“Flutter benchmark 很快”，而是以真实漫画工作负载衡量：

- 4K/8K/10K 大图
- 连续滚动
- 快速 page flip
- 双页
- AI SR 开启
- 10~20 页预取
- 长时间阅读

需要记录：

- Frame time / dropped frames
- CPU usage
- GPU usage
- VRAM / RSS
- Dart heap
- decode latency
- SR latency
- texture upload latency
- page-ready latency

## 明确不做

- 不先重写整个 Breeze UI
- 不先迁移到 Mangayomi
- 不先兼容所有插件协议
- 不先做 Web 版本
- 不把所有图片转成 Dart `Uint8List` 后再交给 Flutter
- 不在没有 PoC 数据的情况下宣称“追平 mImageViewer”

## 决策门

### Gate A

GPU texture PoC 在 Windows/macOS 的性能与稳定性达标后，才进入 Phase 2。

### Gate B

超分能够以可接受的 latency 进入显示链路，才进入大规模 Reader 重构。

### Gate C

桌面端稳定后再做 WebGPU backend。

### Gate D

Reader engine API 稳定后再接 Xiranite。
