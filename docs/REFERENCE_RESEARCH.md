# Rossi 参考项目补充调研

> 本文作为 `docs/RESEARCH.md` 的补充，记录当前最值得 Rossi 借鉴的三个方向：Reader、超分、GPU Texture。重点区分“已经在真实阅读器中落地的能力”和“只验证了底层技术路径的项目”。

## 1. Reader：ComicRD

仓库：<https://github.com/andrizan/comicRD>

ComicRD 是一个真实落地的 Flutter + Rust 桌面本地漫画阅读器，重点价值不是 GPU，而是它已经把本地 Reader 最核心的数据生命周期放到了 Rust：文件系统发现、ZIP/CBZ、RAR/CBR、SQLite、进度/书签/历史，以及图片 pipeline。

### 已落地能力

- 文件夹、ZIP/CBZ、RAR/CBR
- JPEG / PNG / WebP / GIF / BMP / AVIF
- metadata-first：先获取页数、尺寸等元数据
- bytes-on-demand：页面 bytes 按需获取
- 有界 prefetch/cache
- 超长页按 <=2048px 切片
- 缩略图 LRU 磁盘缓存
- 阅读进度、书签、历史独立于图片显示实现

### 对 Rossi 的直接借鉴

```text
ArchiveProvider
      ↓
PageMetadata
      ↓
PageSource / bytes-on-demand
      ↓
PrefetchQueue + bounded cache
      ↓
Tile / viewport pipeline
      ↓
RenderBackend
```

Rossi 不应照搬 ComicRD 的 Flutter Widget，而应吸收其 Rust Reader core，并把最后一层抽象成：

```text
RenderBackend
├── FlutterBitmapBackend
└── WgpuTextureBackend
```

### 局限

ComicRD 使用 Flutter 默认渲染器（项目 README 标注 Flutter 3.47+ 默认 Impeller），没有验证 Rust 页面直接进入 Flutter native GPU texture。因此它是 **Reader pipeline 参考**，不是 GPU reader 参考。

## 2. 超分：Venera-SSR

仓库：<https://github.com/Kiastr/Venera-SSR>

Venera-SSR 是一个把漫画源、本地漫画、Reader 与 AI 图像处理放在同一应用内的 Flutter 项目。README 明确列出本地漫画、JavaScript 漫画源、网络漫画源、下载、WebDAV 与 Anime4K 超分，并包含本地实时上色及 OCR/翻译能力。

### 为什么值得参考

它不是一个独立 Anime4K demo，而是把超分真正接入 Reader。仓库中可以看到：

- Anime4K service
- Anime4K upscaler
- Anime4K v4 model manager
- Reader image provider 对 SR service 的调用
- SR 开关与倍率设置

当前代码包含两条主要路线：

1. Anime4K v1：Flutter/Dart 侧实时算法路径，支持倍率设置；
2. Anime4K v4 / ONNX：模型化路线，提供官方 ACNet 2×、Real-ESRGAN 4×、通用 2× 等模型；Android 路线使用 Kotlin + ONNX Runtime + NNAPI GPU。

### Rossi 应抄什么

```text
Reader
  ↓
Upscaler service
  ↓
Model manager
  ↓
Native inference backend
```

最值得迁移的是服务边界和模型生命周期，而不是把当前 Dart/Android 推理实现原样复制进 Rossi。

建议 Rossi 的统一接口：

```text
Upscaler
├── CoreMLBackend
├── NCNNVulkanBackend
├── ONNXRuntimeBackend
├── WgpuComputeBackend（未来）
└── CpuFallbackBackend
```

Reader 只负责输入页、目标倍率、质量档位和输出 surface。

### 局限

Venera-SSR 的 SR 实现并不等于 `Flutter Texture + Rust/wgpu`。所以它证明的是 **“Reader 内置 AI SR 已经可以落地”**，而不是“统一 GPU texture 超分已经解决”。

## 3. GPU：flutter_wgpu_texture

仓库：<https://github.com/flowsai/flutter_wgpu_texture>

这是目前最直接的 Flutter + Rust/wgpu GPU bridge 参考之一。项目明确支持：

| 平台 | 后端 |
|---|---|
| macOS | Metal |
| Windows | D3D12 |
| Linux | Vulkan + dma-buf |
| Web | WebGPU；WebGL2 fallback |

架构核心：

```text
Dart controller
      ↓ flutter_rust_bridge
Rust / wgpu renderer
      ↓
shared Metal / D3D12 / DMA-BUF surface
      ↓
Flutter texture compositor
```

项目还提供 `flutter_wgpu_texture_core` 的 `Scene` trait 与 scene registry，因此应用可以把自己的 Rust renderer 接进来，而不是必须 fork 整个插件。

### 对 Rossi 的意义

它已经足以作为 **GPU Reader PoC 的底层参考**：

```text
Rust image renderer
      ↓
wgpu texture/surface
      ↓
Flutter Texture
```

但是它目前不是成熟漫画阅读器；官方示例主要是 spinning cube、particles、WGSL shader playground、custom scene。故定位为：

> **GPU bridge / rendering infrastructure，而不是现成 Reader。**

### Web 注意事项

Web 路径和 native texture 路径不同，不能设计成“把 Metal/D3D12 texture ID 跨平台直接传给 Web”。Rossi 应抽象：

```text
RenderSurface
├── NativeSurface
└── WebSurface
```

Native 用 Metal/D3D12/Vulkan；Web 用 WebGPU，并保留 WebGL2 fallback。

## 4. GPU：flutter_rust_3d / Flutter 3D Engine

仓库：<https://github.com/IILLUMINATION/flutter_3d_engine>

该项目展示另一种已经工作的 Flutter native texture bridge：Rust + wgpu 直接渲染到 **irondash native texture**，Flutter 侧通过 `Texture(textureId: id)` 显示，并明确强调 **zero pixel copies into Dart**。

技术链：

```text
Rust
 ↓
wgpu
 ├── Vulkan
 ├── Metal
 └── DX12
 ↓
irondash native texture
 ↓
Flutter Texture
```

同时使用 `flutter_rust_bridge` 暴露控制 API。README 给出了 native texture 初始化、frame render 等完整接口，因此它对研究 texture 生命周期、帧提交以及 Rust-side rendering ownership 很有价值。

### 与 flutter_wgpu_texture 的定位差异

| 项目 | 更值得研究的部分 |
|---|---|
| `flutter_wgpu_texture` | 跨平台 GPU surface、Flutter plugin 结构、Web 路线、custom scene |
| `flutter_rust_3d` | irondash native texture、zero-copy into Dart、Rust renderer ownership、frame submission |

Rossi 不需要 3D scene 本身，重点是把这类 texture bridge 变成 2D 漫画 page renderer。

## 5. 综合结论

目前没有找到一个已经成熟落地、同时具备：

```text
Flutter
+ 本地漫画 Reader
+ GPU Texture
+ 内置 AI 超分
```

的单一项目。因此 Rossi 最合理的参考组合是：

```text
Reader：ComicRD
    ↓
archive / metadata / bytes-on-demand / cache / prefetch / tile

超分：Venera-SSR
    ↓
Reader 内 SR service / model manager / multi-backend

GPU：flutter_wgpu_texture / flutter_rust_3d
    ↓
Rust/wgpu → native texture/surface → Flutter
```

### 建议的 Rossi 架构

```text
                  ┌──────────────────────┐
                  │      Flutter UI      │
                  │ reader / gesture     │
                  │ layout / controls    │
                  └──────────┬───────────┘
                             │
                       RenderSurface
                             │
              ┌──────────────┴──────────────┐
              │                             │
       Flutter Bitmap                 Wgpu Texture
              │                             │
              └──────────────┬──────────────┘
                             │
                    ComicReaderCore
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ArchiveProvider       PageCache          Upscaler
   ZIP/CBZ/CBR           prefetch/tile       CoreML/ONNX/
                                             NCNN/wgpu
```

核心原则：**先把 Reader 数据管线、超分服务、渲染 backend 三者解耦，再做 GPU texture 替换。** 不要先把 Rossi 整个 Reader 改成 Texture，再反过来解决 archive/cache/SR 生命周期。

## 6. 落地顺序

### Phase 1 — Reader core

借鉴 ComicRD：Rust archive abstraction、page metadata、bytes-on-demand、bounded cache、prefetch、long-page tiling。

### Phase 2 — SR service

借鉴 Venera-SSR：Reader 内 SR service、model manager、多模型和多 backend。先统一 Rossi 现有 CoreML / ncnn / RealSR。

### Phase 3 — GPU PoC

用 `flutter_wgpu_texture` / `flutter_rust_3d` 建最小实验：只显示一张静态漫画页，不先接 archive，不先接 SR。

### Phase 4 — Reader + GPU

```text
CBZ/CBR/Folder
      ↓
Rust decode/cache
      ↓
RenderSurface
      ↓
Flutter Texture
```

与普通 Flutter Image 做 A/B benchmark。

### Phase 5 — SR + GPU

保留平台原生 SR backend，随后再验证 wgpu compute / WebGPU compute 是否值得统一。

### Phase 6 — WebGPU

最后实现 Web `RenderSurface`。不要因为 Web backend 限制而牺牲 Windows/macOS native GPU pipeline。

## 7. 验证指标

必须做真实 A/B 测试：

- 4K / 8K 漫画页
- 单页 / 双页
- 连续 zoom / pan
- 邻页预取
- SR 开 / 关
- Dart heap
- CPU / GPU 利用率
- 显存
- first-frame latency
- frame time / FPS
- native texture 是否出现额外 CPU↔GPU copy

最终判断标准不是“Texture 能显示图片”，而是：**在大图、双页、连续缩放和 SR 场景下，GPU Texture pipeline 是否真的比普通 Flutter Image 降低 CPU/Dart 压力并改善帧时间。**
