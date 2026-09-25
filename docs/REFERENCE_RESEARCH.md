# Rossi 参考项目补充调研

> 本文作为 `docs/RESEARCH.md` 的补充，记录当前最值得 Rossi 借鉴的三个方向：Reader、超分、GPU Texture。重点区分“已经在真实阅读器中落地的能力”和“只验证了底层技术路径的项目”。

## 1. Reader：ComicRD

仓库：<https://github.com/andrizan/comicRD>

> **定位更正（ADR-0011，2026-09-16）**：ComicRD 在本项目中**只作参考实现**——不 vendor、不依赖、
> 不进 Cargo；本地核心的来源是 mImageViewer（ADR-0001 恢复有效）。
> 它的 RAR 做法（`rar-sessions`：首次访问 chapter 时把整章图片提取到临时目录）**已被明确否决**，
> Rossi 的 RAR 读取模型以 mImageViewer 的 `src/rar_loader.rs` 为准（逐条目按需读、不落盘）。
> 它仍值得对照的是：tile 布局（`TILE_MAX_HEIGHT = 2048`）、预取窗口、tile 字节缓存。

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

Rossi 不应照搬 ComicRD 的 Flutter Widget，也不把它的 Rust Reader core 当依赖——只按其**接口形状**
（PageSource / bytes-on-demand / 有界预取）自建，并把最后一层抽象成：

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

## 8. OCR 翻译：外部实现的许可与形态核实（2026-09-25）

> 本节每个仓库都经 GitHub API 与 `raw` 的 `LICENSE` / `Cargo.toml` / `Cargo.lock` 核实，
> **不看 README 徽章**。判据是 ADR-0008 的「许可搁置」：**GPL / AGPL 源码不进本仓库**。
> 结论与之前口头传用的一份清单有三处不符，见 §8.2。

### 8.1 许可证与形态对照

| 项目 | 仓库 | 许可证 | 栈 / OCR 实际执行处 | 对 Rossi 的可用性 |
|---|---|---|---|---|
| **XianScan** | `ArbenApura/xianscan-rust` | **MIT**（`license = "MIT"`） | Rust；`ort 2.0.0-rc.9` + `ndarray 0.16` + `imageproc`，ML 在 `src/ml/{detect,inpaint,ocr}` 与 `src/pipeline/*`，GUI 是 axum + SvelteKit 且**不在 ML 依赖路径上** | **目前唯一能 vendor 进 `windcore` 的整链路**（检测→识别→擦字）。未上 crates.io，只能 git/path |
| **manga-ocr-rs** | `CodeMonkeyNinja/manga-ocr-rs` | **MIT** | Rust；`ort 2.0.0-rc.12`（与本仓 pin **完全一致**）+ `image`，纯库无 UI；**只有识别**，无检测/擦字/翻译 | 可用。但 `build.rs` 编译期 curl ~441 MB 权重到 `~/.cache`，模型获取方式**不可照抄** |
| **manga-ocr**（上游） | `kha-white/manga-ocr` | **Apache-2.0**（LICENSE 首行，README 不写许可） | Python/PyTorch，ViT + mBERT 编解码 | 识别半边的模型来源；预处理/解码逻辑可作跨语言参考 |
| **comic-text-detector** | `dmMaze/comic-text-detector` | **GPL-3.0**，2023-08 起停更 | Python，DBNet + YOLO | **检测半边的地雷**：Kototoro 与 Mekuru 的检测都自述源自它，故两者都不可取式 |
| **manga-image-translator** | `zyddnys/manga-image-translator` | **GPL-3.0** | Python | Yakuyomi 的检测/擦字/识别**三个权重全部由它转换而来** |
| **Koharu** | `koharu-rs/koharu`（原 `mayocream/koharu`） | **MIT OR Apache-2.0**（commit `f8a25e2a`，2026-08-14 起；此前是 GPL-3.0） | Rust workspace，crate 切得干净（`koharu-ml` / `-pipeline` / `-translator` / `-renderer`，Tauri 只在 `koharu-app`），但视觉跑 **LibTorch**（`Cargo.lock` 里**没有** `ort`），LLM 走 llama.cpp GGUF | **架构与归因参考**。⚠️ crates.io 上的 `manga-ocr 0.5.1` / `lama 0.5.1` / `comic-text-detector 0.5.1` 仍是 **GPL-3 时代**的发布（`license-file`），**不要 `cargo add`**，要就取 relicense 之后的 git |
| **Yakuyomi** | `joyeli/Yakuyomi` + `joyeli/yakuyomi-engine` | **GPL-3.0**（`LICENSE-YAKUYOMI.md` 自述：集成层 + bundled engine + 整体为 GPL-3） | **不是 Rust**：Kotlin 328 KB + C++ 275 KB + C + Python，vendored NCNN，Android arm64 only | **排除**（许可、栈、平台三重不合） |
| **Kototoro** | `Kototoro-app/Kototoro`（作者 `skepsun`，**Kotatsu 后裔，不是 Mihon fork**） | **Apache-2.0** | Kotlin/Android；`onnxruntime-android` + OpenCV + ML Kit + 自写 `ComicTextDetectorOnnx.kt`；`reader/translate/{data,domain}` 分层干净、有单测 | 许可可用，但检测件溯源到 GPL 的 comic-text-detector → **取其结构与分层，不取其检测式** |
| **Yomihon** | `yomihon/yomihon`（真 Mihon fork） | **Apache-2.0** | Kotlin；LiteRT `.tflite`（encoder+decoder，KV-cache 解码）端侧 OCR，`data/src/main/java/mihon/data/ocr/` 自成一体的 `OcrEngine` 接口 | **reader overlay 与 OCR 队列 UI** 的最好参考；**没有整页翻译**，只有取词 |
| **Mekuru** | `mostrowski123/mekuru`（原名 `japan_ebook2`） | **AGPL-3.0**（其 OCR 服务 `mekuru-ocr` 亦 AGPL） | Flutter；两条路都在：远端 FastAPI，以及端侧 `packages/local_manga_ocr`（Android Kotlin/JNI + ONNX + OpenCV；**iOS 改用 Apple Vision**） | 读：`mokuro_models.dart` 的重排 schema，以及它 iOS 侧「换检测器绕开 GPL」的先例 |
| **Frank Yomik** | `akitaonrails/FrankYomik` | **AGPL-3.0**（根）/ **GPL-3.0**（`client/`） | Go + Python server，**OCR 只在自托管 worker 上跑**，端侧只有 WebView 放大镜 | 只读交互设计（§8.5） |
| **Chimahon** | `Chimahon/chimahon` | **GPL-3.0** | Kotlin；`chimahon-local-ocr` 里是**逆向的 Google Lens 私有 on-device SDK**（`OnDeviceApiNative.java` + `lens_asset_init.cpp`） | **排除**（GPL + 不可再分发的私有 blob） |
| **Yomikomi** | `sieugene/yomikomi` | **无 LICENSE 文件** → 默认保留所有权利 | Next.js/TS，PaddleOCR ONNX 跑在浏览器；零 Rust | **排除**（既无授权，也非 Rust） |

### 8.2 三处必须更正的旧结论

1. **Koharu 已经不是 GPL**：2026-08-14 起 `MIT OR Apache-2.0`。但它是 **LibTorch 而不是 ONNX**，
   对 Rossi 的价值从「最完整的可抄 pipeline」降为**架构参考**。
2. **Yakuyomi 的 "Rust engine" 是错的**：它是 Kotlin + C++/NCNN + Python 的 Android 库，且 GPL-3。
3. **Mekuru 是 AGPL 而非 GPL**（更糟：网络条款覆盖它的自托管 OCR 服务）。
   另 `Ranennder/Mihon-AI`（Apache-2.0）**根本没有 OCR/翻译**，只有超分 —— 之前被记成 OCR 候选是误传。

### 8.3 真正的两个卡点，都不在「代码许可证」

- **检测**：`comic-text-detector`（GPL-3、停更）几乎是所有 fork 的共同来源。许可干净的替代只有两条：
  XianScan 那条（RF-DETR Seg / PP-OCR det，上游 Apache-2.0），以及 Apple 侧用 Vision/CoreML（Mekuru 的 iOS 先例）。
- **权重**：`huggingface.co` 与 `hf-mirror.com` 在本机**网络不可达**，以下均未核实 ——
  `konojonatatan/manga-ocr-base`、`mayocream/lama-manga`、`ogkalu/lama-manga-onnx-dynamic`、
  RF-DETR 的 Manga109 衍生条款。已知风险：manga-ocr 的 README 自述训练集含 **Manga109-s（学术条款、限制再分发）**。
  → 这条与 ADR-0018 的「模型不随包分发」决定绑定，代码许可证干净**不等于**产物可以分发。

### 8.4 修正后的来源分工

```text
检测 + 识别 + 擦字的代码  → xianscan-rust 的 src/ml/{detect,ocr,inpaint}（MIT + ort，唯一 vendor 候选）
                          → manga-ocr-rs（MIT，ort rc.12 同 pin）作识别半边对照
pipeline 分层 / 排版回填   → Koharu（MIT OR Apache-2.0，读分层与 vert+vrt2 竖排，不取 LibTorch）
reader overlay 与 OCR 队列 → Yomihon、Kototoro（Apache-2.0，但 Kotlin → Dart 仍是重写）
按住窥视译文的交互         → Frank Yomik（AGPL，只读设计）
```

> 与 §5 的结论同构：**代码来源与交互来源必然是两个不同的项目**。
> 没有任何一个项目同时具备「Flutter + 端侧 OCR + 擦字回填 + 可 vendor 许可」。

### 8.5 只读也要读的部分：reader 侧交互

> 前三条（Frank Yomik / Mekuru / Chimahon）是 GPL/AGPL → **读设计，禁止粘贴**；
> 第四条 Kototoro 是 Apache-2.0，可搬但它是 Kotlin → Dart 仍是重写。

- **Frank Yomik — 按住窥视（最高价值）**：页面保持原样，长按 200 ms 开一个跟随指针的圆形放大镜，
  镜内是**译文渲染**，镜外仍是原图；松手即消失，快速点击仍然翻页。页角一个点表示该页 pipeline 状态
  （琥珀=进行中 / 绿=就绪 / 红=失败），译文未到时就按住会看到**空环** —— 于是「还在算」与「坏了」可分。
  文件：`client/lib/webview/lens_controller.dart`、`overlay_controller.dart`、`extension/src/content/lens.js`、
  手势测试 `client/test/lens_test.dart`。Rossi 等价物是 `GestureDetector` 长按 + `CustomClipper<Circle>` 叠第二层图，
  **不需要 WebView**。
- **Mekuru** — 逐页 OCR 触发与词级命中：`ocr_action_sheet.dart`（长按识别按钮 → 选端侧/远端、本页/整本、是否替换既有）、
  `manga_word_tap_hittest_test.dart`（词级 hit-test 的测试形状）、`local_ocr_page_overlay.dart`。
- **Chimahon** — 大幅面页的 overlay 对齐：`OcrSubsamplingImageView.kt`（分块解码以免缩放时叠加层跑位）、
  `OcrCoordinateMapper.kt`（图像坐标→视图坐标）、`ChapterOcrIndicator.kt`（章节列表上的「已 OCR」徽标）、
  `OcrSmokeTestScreen.kt`（应用内 OCR 冒烟页 —— 在本仓几乎没有测试基础设施的情况下特别值得抄这个模式）。
- **Kototoro** — `ReaderPageEnhancementController.kt` / `State.kt`（**逐页**开/关的状态机，
  即「按格切换译文」所需的那一层），`ReaderTapGridConfigScreen.kt`（用户可编辑的点击分区，
  决定「按住窥视」能否与翻页手势共存）。
