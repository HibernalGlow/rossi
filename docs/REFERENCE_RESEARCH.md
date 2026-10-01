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
| **manga-ocr-rs** | `CodeMonkeyNinja/manga-ocr-rs` | **MIT** | Rust；`ort` 约束与本仓相同（`2.0.0-rc.12` caret，本仓 Cargo.lock 锁到 `rc.13`）+ `image`，纯库无 UI；**只有识别**，无检测/擦字/翻译 | 可用。但 `build.rs` 编译期 curl ~441 MB 权重到 `~/.cache`，模型获取方式**不可照抄** |
| **manga-ocr**（上游） | `kha-white/manga-ocr` | **Apache-2.0**（LICENSE 首行，README 不写许可） | Python/PyTorch，ViT + mBERT 编解码 | 识别半边的模型来源；预处理/解码逻辑可作跨语言参考 |
| **comic-text-detector** | `dmMaze/comic-text-detector` | **GPL-3.0**，2023-08 起停更 | Python，DBNet + YOLO | **检测半边的地雷**：Kototoro 与 Mekuru 的检测都自述源自它，故两者都不可取式 |
| **manga-image-translator** | `zyddnys/manga-image-translator` | **GPL-3.0** | Python | Yakuyomi 的检测/擦字/识别**三个权重全部由它转换而来** |
| **Koharu** | `koharu-rs/koharu`（原 `mayocream/koharu`） | **MIT OR Apache-2.0**（commit `f8a25e2a`，2026-08-14 起；此前是 GPL-3.0） | Rust workspace，crate 切得干净（`koharu-ml` / `-pipeline` / `-translator` / `-renderer`，Tauri 只在 `koharu-app`），但视觉跑 **LibTorch**（`Cargo.lock` 里**没有** `ort`），LLM 走 llama.cpp GGUF | **架构与归因参考**。⚠️ crates.io 上的 `manga-ocr 0.5.1` / `lama 0.5.1` / `comic-text-detector 0.5.1` 仍是 **GPL-3 时代**的发布（`license-file`），**不要 `cargo add`**，要就取 relicense 之后的 git |
| **Yakuyomi** | `joyeli/Yakuyomi` + `joyeli/yakuyomi-engine` | **GPL-3.0**（`LICENSE-YAKUYOMI.md` 自述：集成层 + bundled engine + 整体为 GPL-3） | **不是 Rust**：Kotlin 328 KB + C++ 275 KB + C + Python，vendored NCNN，Android arm64 only | **排除**（许可、栈、平台三重不合） |
| **Kototoro** | `Kototoro-app/Kototoro`（作者 `skepsun`，**Kotatsu 后裔，不是 Mihon fork**） | **Apache-2.0** | Kotlin/Android；`onnxruntime-android` + OpenCV + ML Kit + 自写 `ComicTextDetectorOnnx.kt`；`reader/translate/{data,domain}` 分层干净、有单测 | 许可可用，但检测件溯源到 GPL 的 comic-text-detector → **取其结构与分层，不取其检测式** |
| **Yomihon** | `yomihon/yomihon`（真 Mihon fork） | **Apache-2.0** | Kotlin；LiteRT `.tflite`（encoder+decoder，KV-cache 解码）端侧 OCR，`data/src/main/java/mihon/data/ocr/` 自成一体的 `OcrEngine` 接口 | **reader overlay 与 OCR 队列 UI** 的最好参考；**没有整页翻译**，只有取词 |
| **Mekuru** | `mostrowski123/mekuru`（原名 `japan_ebook2`） | **AGPL-3.0**（其 OCR 服务 `mekuru-ocr` 亦 AGPL） | Flutter；两条路都在：远端 FastAPI，以及端侧 `packages/local_manga_ocr`（Android Kotlin/JNI + ONNX + OpenCV；**iOS 改用 Apple Vision**） | 读：`mokuro_models.dart` 的重排 schema。**它 iOS 侧「用 Vision 换掉 GPL 检测器」这条先例本仓已实测否决**（§8.6.5：漫画竖排上 Vision 基本不工作） |
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

- **检测**：`comic-text-detector`（GPL-3、停更）几乎是所有 fork 的共同来源。原本以为有两条许可干净的路：
  XianScan 那条（RF-DETR Seg / PP-OCR det）与 Apple 侧用 Vision（Mekuru 的 iOS 先例）。
  **实测后只剩一条**：Vision 在漫画竖排上基本不工作（§8.6.5），而 RF-DETR 那份权重是 `license: other`
  + Manga109 衍生 → **PP-OCRv4 det（apache-2.0、4.7 MB）是目前唯一既许可干净又当场可用的检测件**，
  代价是漏手写拟声词。
- **权重**：~~无法核实~~ → **2026-09-25 已当场核实**（HF 从本机可达，之前记成「不可达」是调研子代理的
  网络受限，不是事实）。结果见 §8.6.1 —— 识别与擦字这半边的权重是干净的，
  **脏的是检测与另一条 OCR 路线**。

## 8.6 实测：权重许可 + 擦字模型 A/B（2026-09-25，本机）

### 8.6.1 权重许可（HF API `cardData.license` 直读，不是 README 措辞）

| 权重 | 声明许可 | 体积 | 结论 |
|---|---|---|---|
| `kha-white/manga-ocr-base` | **apache-2.0** | ~440 MB | 识别底座干净（之前记成「Manga109 学术条款」是**误判**） |
| `mayocream/manga-ocr-onnx` | **apache-2.0** | enc 343 MB + dec 117 MB | manga-ocr-rs 用的就是这份导出 |
| `ogkalu/lama-manga-onnx-dynamic` | **apache-2.0** | 206 MB | ✅ 单文件、动态尺寸 |
| `mayocream/lama-manga-onnx` | **apache-2.0** | 207 MB | 同上，另一份导出 |
| `mayocream/aot-inpainting` | **mit** | 22.7 MB safetensors | 只有权重，需自己按 Apache 实现导出 ONNX |
| `researchmm/AOT-GAN-for-Inpainting`（实现） | **apache-2.0** | — | 530★，官方实现 → 导出这条路的代码是干净的 |
| `cwxue/aotgan-onnx-float` | **无 license 字段** | 61 MB | ⚠️ 只能用于评测，**不可随包** |
| `mayocream/speech-bubble-segmentation` | **gpl-3.0** | 109 MB | ❌ 气泡检测的常见来源，GPL |
| `mayocream/mit48px-ocr` | **gpl-3.0** | 263 MB | ❌ 另一条 OCR 路线也是 GPL |
| `mayocream/koharu-layout-rfdetr-seg-2xl-1152` | **other** + `datasets: mayocream/manga109-segmentation` | — | ⚠️ Manga109 衍生 + RF-DETR 底座条款未逐项核 → **分发时风险最高的一份** |
| `mayocream/RORem-mixed-GGUF` | **openrail++** | — | ❌ SDXL 衍生，带使用限制，不作为随包选项 |

### 8.6.2 擦字 A/B：合成页 + 有真值，512×512，Apple Silicon

任务形状按真实链路构造：**气泡属于要保留的美术**（画进真值页），只有字是后加的，
掩膜 = 字形笔画外扩 —— 不是整只气泡。两类区域分开看：

| 区域 | LaMa(manga) | AOT-GAN | 谁赢 |
|---|---|---|---|
| 气泡内的字（底是纯白） | 干净白底 | **留下每个字格的淡彩方格残影** | **LaMa** |
| 拟声词压在网点/速度线上 | **留白垩色斑块 + 残点**，网点被抹平成糊 | 网点自然续上，几乎看不出擦过 | **AOT-GAN** |

- **掩膜外扩救不了 LaMa**：0 / 4 / 8 / 16 / 24 px 扫下来，原字区墨量 31.4 → 34.4 → 33.3 → 33.6 → 44.0
  （真值 28.6），**越扩越糟**。所以那是模型行为，不是我们的预处理太紧。
- **不碰不该碰的地方**：LaMa 在掩膜外**逐字节不变**（PSNR 99.00、MAE 0.00）；AOT 有轻微全图重绘
  （PSNR 53、MAE 0.33）。这条对「原图永远是真相」的口径是加分项，但两者都只影响产物不影响源。

### 8.6.3 计时：EP 的选择比模型的选择更影响体感

同一 session 连跑、丢掉首次预热后的稳态中位数：

| 模型 | CPU | CoreML EP | 备注 |
|---|---|---|---|
| LaMa 206 MB | **1 656 ms** | 3 825 ms | **CoreML 反而慢 2.3×** —— 别按「Apple 一律走 coreml」推 |
| AOT-GAN 61 MB | 5 916 ms | **295 ms** | CoreML 快 20× |

⚠️ 口径要说清：这是 **Python onnxruntime 1.30** 的数，本仓 Rust 侧是 `ort 2.0.0-rc.13`（Cargo.lock 锁定，
内嵌 **ONNX Runtime 1.28.0**，低于 Python 侧），
EP 行为**不能直接搬**；这张表的作用是「谁明显不该走哪个 EP」，不是可写进验收的数字。
另外 AOT 是**固定 512×512**，真实页 1000–1500 px 要自己分块拼接；LaMa 是动态尺寸，单页一把过。

**这一节把 ADR-0018 的未决 4 从「选哪个模型」改成了「按区域选两个模型，且 AOT 要先补一次导出」。**

**Windows / DirectML 补测（2026-09-26，那台 3090 盒子）**：把 `rust/ocr_core` 单独拷过去
`cargo build --release`（25 s 编过，`ort` / `ort-sys` 都解析到 rc.13），同一张 `mokuro_001a`
（827×1170，28 框 → 15 块，掩膜 87 107 px —— 与 macOS 那次数一模一样）：

| 段 | cpu | directml | 结论 |
|---|---|---|---|
| 检测 infer | **151 ms** | 209 ms | cpu 赢 |
| 识别 28 框合计 | 10 665 ms | **2 632 ms** | DirectML 快 **4.1 倍**（encoder 每框 310 ms → 11 ms） |
| 擦字 LaMa infer | 12 494 ms | **1 438 ms** | DirectML 快 **8.7 倍** |
| 整页三段合计 | ~23.3 s | ~4.3 s | **5.4 倍** |

两条结论：
① DirectML **注册得上也真跑**，且两段的输出与 CPU **逐块一致**（15 块、文本全同，
置信度只差在第 7 位小数）—— 不是「跑通了但结果不对」。
② **「选哪个 EP」这个问题本身就问错了**：同一个人显存上，检测该用 CPU、识别与擦字该用 DirectML。
所以 §决定 3.1 的「EP 按模型指定」升级为**按段指定**，并落成 `Ep::Auto` + `Ep::resolve(stage)`：
Windows 上 det→cpu、recognize/inpaint→directml，其余平台 cpu。显式选的值一定照办（哪怕更慢），
不支持的 EP 仍然**报错**不静默退回。`Ep::ep()` 现在报的是**实际生效**的那个，不是请求值。

⚠️ 还差一步：`--ep auto` 在 Windows 上跑通这条**没验成** —— 传到一半那台盒子掉线了
（scp lost connection 后 22 端口直接超时；后来 `tailscale status` 显示整机 offline）。
策略本身有 Rust 单测钉住（`session.rs` 三条），真机数字是上面这套「分别显式指定 EP」量出来的。

**2026-09-26 补：这条现在是一条命令就能验的事**。原先 `ocr_page --json` 顶层只有一个 `ep`，
装的是**检测那一段**的 EP，识别段（DirectML 收益最大的那段）根本没报 —— 也就是说
「auto 真的落到 det=cpu / 其余=DirectML」这句话在命令行上读不出来。现在三段都从组件身上
读回**实际生效值**并一起输出（人读行 + `ep` 对象）：

```bash
cargo run -q --release -p rossi_ocr_core --bin ocr_page -- \
  --det det.onnx --encoder enc.onnx --decoder dec.onnx --vocab vocab.txt \
  --inpaint lama.onnx --group --ep auto --json page.jpg
# stderr：后端实际生效：检测=cpu 识别=directml 擦字=directml
```

本机（macOS）已用真权重跑过这一条：`--ep auto` 报出 `检测=cpu 识别=cpu 擦字=cpu`，
与 `resolve` 的非 Windows 分支一致（检测 117 ms、识别 210 ms/2 框、擦字 5.3 s，opt 构建）。
**Windows 那一版仍待跑**：预期看到 `cpu / directml / directml` 且整页 ~4 s 才算这条闭合。

### 8.6.4 识别半边：同一探针跑 manga-ocr 的 encoder / decoder

| 件 | CPU 稳态 | CoreML 稳态 | CoreML 建会话+首跑 |
|---|---|---|---|
| `encoder_model.onnx` 328 MB | **38.5 ms** | 131.2 ms | 3 367 ms |
| `decoder_model.onnx` 112 MB | **2.2 ms**/步 | 7.4 ms/步 | 548 ms |

两个 EP 都能跑完（无算子硬失败，日志只有 `attention_fusion` 的 V 级提示），但 **CoreML 在两边都更慢**。
⚠️ 解码器喂的是 `decoder_sequence_length = 1` = **下限**；这份导出**没有 `past_key_values` 输入**
→ 自回归每步重跑整个前缀，单格成本按 O(n²) 长。推论见 ADR-0018 §决定 3.2
（也解释了 Yakuyomi 为什么改用 48 px CTC int8）。

> 复现：`/tmp/inpaint-lab/{run,sweep,zoom,ocr_ep}.py` 与 `/tmp/detect-lab/{det_run.py,vision_probe.swift}`
> （临时目录，未入库）。
> 口径提醒：全部是 **Python onnxruntime 1.30** 的数，本仓 Rust 侧 `ort 2.0.0-rc.13`（内嵌 ORT 1.28.0）更低，
> 这些表回答的是「谁明显不该走哪个 EP / 哪个模型在哪类区域更强」，不是可写进验收的性能数字。

### 8.6.8 擦字落地（LaMa）与它的成本口径

`rust/ocr_core::inpaint`：掩膜由**块框外扩**生成（`mask_from_blocks`，默认 dilate 3 px），
页与掩膜一起降到 `max_side`（默认 1024、对齐 8）推理，输出升采样回原尺寸后**只在掩膜内合成** ——
掩膜外逐像素保持原图（与 LaMa 自身性质一致：它不碰掩膜外的像素）。

实测（mokuro 那页 827×1170，掩膜 87 107 px ≈ 页面的 9%，debug profile）：
降采样到 720×1024 后推理 **36 / 6 725 / 72 ms**（前处理 / 推理 / 合成），整流 ~14.5 s/页
（含检测 192 ms + 识别 3 758 ms + 擦字 6 833 ms）。**原尺寸跑一页要按 6 倍面积算**，
所以「降到 1024」不是省事，是当前唯一可接受的成本口径；release 构建下的数字待测。

质量：文字全部抹掉、**气泡描边保留**、分镜与美术未被改动（人眼比对原图/结果图的放大裁剪）；
网点与速度线上的粗笔画（拟声词区）LaMa 本来就会留糊（§8.6.2），而这类区域检测件也漏，
两处缺口在同一片区域叠加，一期**明确不处理**。

### 8.6.7 聚块（翻译/擦字的单位）与它的硬限制

检测框会被长竖排列切段，逐框翻译只得到半句，所以翻译与擦字以**块**为单位
（`rust/ocr_core::group`）。合并条件两条，缺一不可：**邻接**（间隙 ≤ `clamp(0.9 × 最短边, 6, 20)` px）
且**邻接轴上投影重叠 ≥ 0.6**。第二条是实测补的 —— 只用距离会把「きたんだよお前!」与
「初めて見たよ!」并成一簇（两者 y 差 3 px、距离 0，但横向重叠仅 0.18）。

块内读序是**列优先**（右→左、列内上→下，`TextBlock::order_reading`）。
原先用的「y 分桶 + x 降序」会把同列两段拆开：实测「あ」「田舎とかに」「いる!?」「の」被拼成
「あ田舎とかにいる!?の」，改列优先后正确为「あの田舎とかにいる!?」。

实测（同一页 28 框 → 15 块，块文本逐条可读）：
「なんだこれ!?」「トカゲじゃやない!?」「これって...ヤモリ!?」「あの田舎とかにいる!?」
「どっから捕まえてきたんだよお前!」「初めて見たよ!こんな住宅地にもいるんだ!」。

**硬限制（登记，不假装修好）**：几何规则分不开「相邻且间隙极小的两个气泡」——
本页「これって…」与「ヤモリ!?」是两只气泡，间隙 6 px，**比气泡内的列距（7.5–15 px）还小**，
被并成一簇（译文会连读、回填会跨两只气泡）。要真正分开需要**气泡轮廓分割**，
而那份权重（`speech-bubble-segmentation`）是 GPL-3 → 只能自己标数据训（见 ADR-0018 未决 6）。
另：检测件的碎框（把「じゃ」的一部分识别成独立小框）会被并入同块，出现「トカゲじゃ**や**ない!?」
这类多字 —— 属检测件缺口，不是聚块逻辑错。

### 8.6.9 成品页端到端（真权重，2026-09-26）与它暴露的排版缺陷

`test/ocr/completed_page_e2e_test.dart`：五个权重**符号链接**进 `getFilePath()/manga_ocr/`，
跑**不带注入的** `TranslatedPageBuilder`（只有翻译那一跳是假的 —— 端点要网络与 key，
而「条数对不对」已由 `parseTranslatedLines` 钉住），对 `mokuro_001a.jpg` 出一张成品页。

实测：**15 块 / 10.2 s / 827×1170**（同一条在满载机器上重跑是 126 s ——
`xcodebuild` + `mds_stores` + SiYuan 一起把 load 顶到 37，所以这个数**只能在空机上引用**），缓存落在
`manga_translated/zh-Hans_fake-for-e2e_<hash>/p0.png`，第二次构建命中缓存；
断言「每一块内都有墨」逐块通过（漏一块 = 一个空气泡，是最难发现的一类错）。

**看图看出的缺陷（断言抓不到）**：一期只做水平排版，而漫画气泡**多是窄高框**。
窄框里 3–4 字一行，视觉上变成「假竖排」，读起来是竖着断句的一串；
右上那只竖气泡（`〔译〕すごい♪ケンタ…`）整列贴着页边，几乎不像回填过的成品页。
**已修（同日）**：回填改按**框的长短边**选排法 —— 高 ≥ 宽 × 1.6 且超过 3 字时走
「一字一行」的竖堆（把可用宽度收到约一个字，引擎每行只放得下一个字；CJK 不旋转就能读），
宽扁框仍走横排换行。同一页重跑，左侧竖气泡与中间窄气泡从「3–4 字一行的假竖排」
变成单字一列，右侧两只宽气泡照旧横排。判据是**墨的包围盒宽度**（竖堆只有一个字宽，
横排会铺满框宽），钉在 `translated_page_renderer_test.dart`。
真正的竖排（标点旋转、列与列之间的读序）仍按 ADR-0018 的砍单顺序排在后面。

**第二版又被用户的真页推翻了（2026-09-27）**：上面那个「一字一行」把竖排的可用宽度锁死成
**一个字号**，于是**永远只有一列** —— 长句只能靠缩字号塞进那一列。用户那一页里
60×240 的旁白框有 15 字，被压到 12.5 px，评价是「一行纵向塞了太多字根本没办法阅读」。
**现在的规则是按框宽开列**：字号从大到小取第一个「列数 × 每列字数 ≥ 总字数」的，
列与列按**右→左**落位，整块居中；短句仍只开一列（装得下就别拆，空列比小字更难读）。
判据从「墨的包围盒宽度」换成了**直接断言决策**（`TranslatedPageRenderer.plan()` 返回
排法/字号/列数）+ 复核墨铺开了框宽 + 越框那把尺子照旧 —— 因为像素断言看得见「有没有越框」，
看不见「字号小到读不了」，这个缺陷两轮都是靠肉眼看图才发现的。
证伪做过：把列数强行改回 1，那条测试立刻红在 `columns >= 2`。

另两类已知残留，与排版无关：**拟声词原样保留**（「だんだんだん」「かえして」「ゆジベ」——
检测件不覆盖，见 §8.6.5 与 ADR-0018 未决 6）；**相邻极窄气泡并成一块**（§8.6.7 的硬限制）。

### 8.6.10 擦字段 A/B：裁剪推理 × 掩膜外扩，同一批真页对表（2026-09-30）

台架 `rust/ocr_core/src/bin/inpaint_ab.rs`：**8 张真页**，每页只跑一次检测与聚块，然后把
`外扩 {0,3,6,8} × 模式 {整页, 掩膜外接框, 分簇}` 全跑一遍（96 组，同一会话、同一批块 → 页内可比），
每档跑两遍取较小值。产物 `/tmp/ocr-lab/inpaint-ab/{runs.jsonl, *_d*_*.png, *_map.png}`，
汇总 `.local/inpaint_ab_report.py`。

**两个参数必须一起量的理由**：外扩把掩膜变大（更慢、残留更少），裁剪把推理面积变小（更快、可能改变填充）。
只调一个就宣称好了，等于把另一个的代价藏进对方的噪声里。

**⚠️ 第一轮（09-30）的绝对秒数全部作废，并已换成干净复跑（10-01）**：那轮跑的时候用户的
`Rossi` 正在吃 311% CPU，同一配置（827×1170 整页 threads=1）两次测出 **4.7 s 与 15 s**。
但根因不只是「有人在抢核」，而是**测量设计本身错了**：串行分块（先跑完 1 线程再跑 2 线程）
把「这段时间谁在吃 CPU」直接算进了结论里，偏差与待测效应同量级。
所以补了 `inpaint_threads`：**同进程多会话、逐轮轮换起点、每臂取中位** ——
负载漂移对每个臂的影响相同，剩下的差才是被测量本身的差。下面凡是秒数，都出自这套交替设计
（`/tmp/ocr-lab/inpaint-t1`、`inpaint-th*`），并且**同时报比值与极差**：
极差 >40% 的格子说明那一刻机器不干净，只能看比值。

**判据（先数，再看眼）**：
- `环带漏墨` = 块框外扩 12 px 的环带里、亮度 < 阈值却**没被掩膜盖住**的像素 —— 纯覆盖问题，与模型无关。
  阳性对照：每页 d=0 都必须 > d=3，**8 页 × 3 模式全部合格**。
- `掩膜内残` = 擦完之后掩膜内仍发暗的像素 —— 填充质量。
- `裁剪差` = 同页同档下，裁剪结果与整页结果在掩膜内的逐通道差 —— 裁剪有没有改变填充。
- `*_map.png` = 红=掩膜、蓝=还在页面上的暗像素。**这张图是本轮真正的产出**（见 8.6.11）。

| 掩膜外扩 | 掩膜像素（中位） | 环带漏墨 t=140（中位） | 相对 d=3 新增暗像素 | 整页模式推理面积 |
|---|---|---|---|---|
| 0 px | 74 492 | 7 104 | −1 900（对照） | 恒定 |
| 3 px（现产） | 86 434 | 5 204 | — | 恒定 |
| 6 px | 99 500 | 3 558（−32%） | +3 546 | 恒定 |
| 8 px | 108 694 | 2 369（−55%） | +4 969（最大一页 25 796） | 恒定 |

**结论 1：外扩的时间代价近乎为零，代价全在「附带损伤」那一列**。整页模式的推理面积与掩膜无关
（恒为 737 280），干净复跑实测 d=3 → d=8 的时间比是 **0.97–1.05×**（8 页里 7 页），
只有一页（`mokuro_000a`，4 个大 AABB）报 1.39× —— 那一页的掩膜像素增幅最大，但也与极差同量级，
不当成结论。看图确认过附带损伤不是纸上的：`mokuro_002b` 那只黑底假名「にゃん」在 d=8 下
被啃掉一圈边，变成**半擦除的残缺** —— 比完全不擦更难看。
所以「外扩越大越干净」不成立，6 px 与 8 px 之间是取舍，不是单调变好。

| 页 | 整页面积 | 外接框面积 | 分簇面积 | 簇数 |
|---|---|---|---|---|
| ctd_Aisazu | 745 472 | **0.56×** | 0.70× | 8 |
| mangaocr_random | 524 288 | 1.00× | **2.96×** | 6 |
| mokuro_000a | 737 280 | 0.99× | 0.37× | 2 |
| mokuro_000b | 737 280 | 1.07× | 0.92× | 6 |
| mokuro_001a | 737 280 | 0.90× | 0.75× | 6 |
| mokuro_001b | 737 280 | 0.93× | 0.72× | 6 |
| mokuro_002a | 737 280 | 0.89× | 0.52× | 4 |
| mokuro_002b | 737 280 | 1.00× | 0.88× | 5 |

**结论 2：「按掩膜包围盒裁剪」这条被自己的面积表否掉了** —— 漫画页的文字本来就铺满整页，
外接框中位数是整页的 0.93×，省不下来；只有封面（Aisazu，标题挤在上半页）才到 0.56×。

**结论 3：分簇裁剪是「多数页省、密集页反噬」，而且时间几乎严格按面积走**：
干净复跑（threads=1、repeat=3）的时间比与面积比逐页对齐 ——

| 页 | 面积比 | 时间比 | 页 | 面积比 | 时间比 |
|---|---|---|---|---|---|
| mokuro_000a | 0.37× | **0.45×** | mokuro_001b | 0.72× | 0.64× |
| mokuro_002a | 0.52× | 0.46× | mokuro_002b | 0.88× | 0.81× |
| ctd_Aisazu | 0.70× | 0.63× | mangaocr_random | **2.96×** | **2.92×** |
| mokuro_001a | 0.75× | 0.65× | mokuro_000b | 0.92× | 0.85× |

中位 **0.65×**（d=8 时 0.68×），但密集页 2.92×。机制写清楚，免得后人以为是簇数的问题：
**整页模式被 `max_side = 1024` 封顶降采样，而裁剪块小于 1024 时按原生分辨率跑** ——
同一件事既让裁剪更省（稀疏页）又让它更贵（密集页），还顺手抬高了有效分辨率。
所以裁剪要上，**必须带面积闸门**（Σ裁剪块面积 < 整页面积才裁，且这个判断要用 `max_side`
换算后的面积），不能按簇数或页型猜。

**结论 4：裁剪确实改变了填充**，不是等价替换。掩膜内逐通道平均差 5–19（最大 223–240），
且残留方向按页不一（`mokuro_000a` 分簇更少、`mokuro_001a` 分簇更多）。
也就是说「裁剪只快不坏」这个直觉是错的 —— 它换掉的是模型看到的上下文。

**结论 5（已落到生产）：线程数是这一段最干净的那个旋钮**。`intra_threads` 一期定 1，
而那条注释是**策略**不是实测 —— 偏偏 Apple 上没有可用的加速器 EP（§8.6.3：CoreML 反而慢 3–5 倍），
所以线程是擦字剩下的唯一旋钮。交替测（`inpaint_threads`，3 页 × 5 轮 × 轮换起点）：

| 臂 | 相对 t=1 的中位时间比 | 跨页范围 | 绝对值（`mokuro_001a` 整页 d=3） |
|---|---|---|---|
| t=1 | 1.00 | — | 4 927 ms |
| t=2 | 0.71 | 0.57–0.85 | — |
| t=4 | **0.55** | **0.54–0.56** | 2 732 ms |
| t=8 | 0.67 | 0.51–0.78 | 不再更好 |

4 = 本机性能核数（`hw.perflevel0.physicalcpu`），把能效核留给阅读器渲染；t=8 与 t=4 同量级，
所以取 4。**并且用一条叫 `prod` 的臂验了「改的确实是生产那条码路」**：`prod` 走
`Inpainter::from_file`，比值 0.54（0.53–0.54），与 t=4 那一臂重合 ——
只看代码里换了参数、不看跑出来的数，是「注入了」当成「画面上换了」的同一种错。
检测与识别两段没跟着改：它们单次推理短，那条「= 1 省得抢核」的策略对它们仍然成立，
而且没量过。

**还没做**：面积闸版本的裁剪（结论 3 的前提是结论 5 已经把整段压到 2.7 s，收益变小、
质量风险还在，先不动）；以及 §8.6.11 那笔检测账。

### 8.6.11 「擦不干净」的主因不在擦字段：检测覆盖，以及我们移植漏了 box_thresh（2026-09-30）

`*_map.png`（红=掩膜、蓝=还在页上的暗像素）把残留分成了三类，**只有第一类是外扩能治的**：

1. **框到了但外扩不够**：笔画的抗锯齿边贴着框边留在掩膜外 → d=3→8 把环带漏墨砍掉 55%。
2. **只框到半截**：`mokuro_001a` 左下角那条竖排旁白「でもリーリィ!?」，检测在 960 输入下
   **只框住中间两个字**（绿框叠加图：`/tmp/ocr-lab/det_960.png`），上面「でも」和下面「ィ!?」
   在框外 20–40 px —— 外扩 8 px 治不到，而它是用户截图里最显眼的那处残留。
3. **完全没框到**：同一页上 8 个人工标注的位置（`だだだだ`、`かえして`、`2ひきめ!?` 的其余部分、
   `ゆジベ`、`あっ`、`お水…`）在 `--cover` 尺子上是 **0/8**。

**这条要更正 ADR §决定 3.3.2 的口径**：那里写的是「手写拟声词三家全漏 → 一期保持原样」，
对 `だだだだ` 这类仍然成立；但「でもリーリィ!?」**不是拟声词，是印刷体竖排旁白**，
它漏下来是**我们自己的端口参数把框做小了**，不是模型能力边界。

**为什么这两个旋钮一直没动**：移植 PaddleOCR 的 `DBPostProcess` 时**漏了 `box_thresh`**
（框内概率均值闸，PaddleOCR 默认 0.6）。`score` 我们算了（`postprocess.rs:119`）却从没拿来筛。
后果不是「多几个框」，而是**上面两个召回旋钮不敢动**：把 `prob_thresh` 从 0.30 降到 0.20，
`ctd_Aisazu` 一页从 **33 框涨到 104 框**。已补上 `Params::box_thresh`（默认 `0.0` = 旧口径不变，
带证伪对：弱块在 0.6 下被拦、强块留下），这才谈得动分辨率这一档。

**实测（`detect_image --limit-side … --prob-thresh … --cover x,y;…`）**：

| 检测输入 | prob_thresh | mokuro_001a 框数 | 8 个漏字点找回 | 8 个阳性对照 | 检测总耗时 |
|---|---|---|---|---|---|
| 672×960（现产） | 0.30 | 28 | 0/8 | 8/8 | 394 ms |
| 832×1184（≈原尺寸） | 0.20 | 29 | **2/8** | 7/8 | 453 ms |

找回的是 `かえして` 那两处，代价是掉一个对照点（`2ひきめ` 那条弧线被拆得更碎）+ ~60 ms。
**但同一次改动把「でもリーリィ!?」从 2 字碎片变成了整行框**（`/tmp/ocr-lab/det_1280.png`）——
这正好是三类残留里的第 2 类，也就是用户那一页上最扎眼的一处。
所以这一档的真实收益**不在框数，在框的完整度**，而框数这把尺子看不见它 —— 得看叠加图。

#### 8.6.11 的续：10-01 用「固定参照带」重量，上面两个说法各收回一半

补了 `det_cover_ab`：尺子换成**参照带漏墨%** —— 参照带 = **所有配置的块框并集**再外扩 12 px，
对所有配置都一样，于是「框得少」不会再因为「环带也跟着变小」而显得干净。
8 张真页 × 8 个配置（`/tmp/ocr-lab/det-cover.jsonl`）：

| 配置（limit_side/ prob / box） | 参照带漏墨% 均值 | 中位 | 最差一页 | 检测中位 ms |
|---|---|---|---|---|
| **1280 / 0.30 / 0** | **26.3** | 25.0 | 35.8 | 172 |
| 1280 / 0.20 / 0.5 | 28.7 | 28.6 | 45.5 | 174 |
| 1600 / 0.20 / 0.6 | 30.4 | 31.7 | 38.9 | 175 |
| 1280 / 0.20 / 0.6 | 32.2 | 30.2 | 56.4 | 173 |
| 1280 / 0.30 / 0.6 | 32.6 | 31.2 | 54.6 | 173 |
| 960 / 0.30 / 0（现产） | 35.1 | 28.5 | 75.4 | 114 |
| 960 / 0.30 / 0.6 | 37.4 | 29.3 | 83.6 | 113 |
| 1280 / 0.20 / 0.7 | 40.4 | 35.7 | 73.7 | 172 |

**收回之一：`box_thresh` 不是那把钥匙。** 我 09-30 的推断是「移植漏了这道闸，所以召回旋钮不敢动」——
闸确实漏了（已补，默认 `0.0` 不改行为），但**装上它并没有让事情变好**：
同一 limit_side 下把闸打开 0.6，均值从 35.1% 涨到 **37.4%**（960）与从 26.3% 涨到 **32.6%**（1280），
最差那一页（`ctd_Aisazu`）从 75.4% 恶化到 83.6%。原因是彩页与低对比页的框内概率均值本来就低，
这道闸在漫画上砍掉的是**真字**。它留在代码里当一个可选旋钮，**默认不开**，
而不是像 PaddleOCR 那样当默认 0.6。

**收回之二：`limit_side` 960 → 1280 的收益是真的，但它是把双刃，不能当参数默默改掉。**
尺子上它最好（35.1 → 26.3%，+58 ms）；可同一批页的**成品图**显示它做了另一件事：
`ctd_Aisazu` 右下那一整版**手写笔记**在 960 下完整保留，在 1280 下被**整片擦成灰白涂抹**
（`/tmp/ocr-lab/det-ls960/ctd_Aisazu_d3_full.png` vs `det-ls1280/…`，框数 12 → 19 块 / 33 → 102 框）。
也就是说：调大输入 = 承认「这些也是字」= 连带承诺能翻好它们。
而 manga-ocr 对手写笔记的识别质量并没有量过 —— **擦掉又翻不出，就是净损失**，
比留着原文更糟。所以这一档不是「取 1280」，而是要先回答：**手写体/拟声词到底进不进翻译范围**。

**并且这把尺子本身是单边的**：参照带漏墨只罚「没盖住」，不罚「多盖」，
所以它天然奖励大掩膜 —— 上面那张表必须和 `mask_px`（同一份 jsonl 里有）与**人眼**一起读，
单独引用任何一列都会得出反向结论。09-30 那版 `环带漏墨` 与这版 `参照带漏墨` 在 3 张页上
**方向相反**（`ctd_Aisazu`：own-ring 说 1280 更差、fixed-band 说 1280 更好），
差别正是来自分母跟着配置变。这条写死在这里，免得下次再拿一把会自己变形的尺子下结论。

### 8.6.12 最后那块固定开销：会话每页重建（2026-10-01，M4）

把 §8.6.9 那张端到端日志加进测试之后，一条对不上的差浮出来：`分析` 三段自报合计
（检测 129 + 识别 2057 + 擦字 4808 = 6994 ms），而**分析段墙钟是 9.0 s**。
那 2 s 不在任何一段里 —— 是每页都把三个会话重新 `from_file` 一遍
（检测 4.7 MB + encoder 343.5 MB + decoder 117.5 MB + 擦字 206.3 MB）。

改法是 `rust/src/api/ocr_sessions.rs` 的一个进程内缓存。**键不是模型名**，
而是 `EP|路径:字节数:mtime` 四件套：重下权重时路径不变而内容变，
只按路径缓存等于让新权重永远不生效 —— 那正是本 ADR 一路在防的「静默用旧的」。
锁的粒度是**整个一次建页**（同时两页各建一套会把内存顶到 1.3 GB×2，
而阅读器本来就一页一页建，串行没有损失）；重建时**先丢旧的再建新的**，反序会瞬时驻留两套。

同机两轮对表（`test/ocr/completed_page_multi_page_probe_test.dart`，8 页真页，
每页打印「建会话 = 分析段墙钟 − 三段自报合计」）。这把尺是**同一页内取差**，
所以不受两轮之间的负载漂移影响 —— 这也是为什么不用「上一轮会话记录的 8146 ms 均值」当结论：

| 页 | 每页重建：总 / 三段 / **建会话** | 复用：总 / 三段 / **建会话** |
|---|---|---|
| ctd_Aisazu | 8518 / 5930 / **2381** | 8867 / 6035 / **2518**（第一页，该付） |
| mangaocr_random | 9674 / 7587 / **1954** | 9534 / 9310 / **46** |
| mokuro_000a | 5358 / 3421 / **1826** | 4096 / 3860 / **103** |
| mokuro_000b | 6246 / 4337 / **1794** | 5618 / 5443 / **19** |
| mokuro_001a | 7061 / 5145 / **1793** | 5912 / 5766 / **20** |
| mokuro_001b | 8056 / 5694 / **2226** | 5250 / 5114 / **15** |
| mokuro_002a | 6403 / 4426 / **1866** | 4493 / 4364 / **17** |
| mokuro_002b | 6505 / 4478 / **1877** | 4691 / 4558 / **15** |
| **8 页均值** | **7227** | **6058**（省 1170 ms/页） |

证伪照做：在测试里每页调一次 `releaseSessions()` 强制重建，**八页全部**回到 1793–2381 ms；
去掉那一行后只有第一页付这笔。这条也顺手说明复用不是「运气好碰上机器空」。

**收回一条我写在 `ocr_sessions.rs` 里的猜测**：我原本断言
「每页新建还会让擦字多吃一次动态 shape 冷启动，所以实际差距比 2 s 更大」。
上表否掉了它 —— 擦字所在的三段合计在复用一侧**没有**更快（`mokuro_000a` 3421 → 3860，
八页里只有两页略降，量级是负载噪声）。差距**全部**落在建会话那一段。

内存的收口：`OcrService.releaseSessions()`（过一次桥调 `ocr_release_sessions`），
挂在 `LocalReadSession.dispose()` 上 —— **退出阅读器**交还 670 MB，**换章不交**
（人还在读，下一张多半还要译，那 1.8 s 省得下来）。
`releaseSessions()` 里那句 `if (!_sessionsHeld) return;` 不是给测试打洞：
没建过会话就没有可交的东西，退出时白过一次桥是错的；
同时它让 `test/reader/local_read_session_translation_gate_test.dart`
（不带原生库跑 dispose 那条路）能跑 —— 摘掉那行该测试立刻变红，已实测。

### 8.6.6 识别件落地与实测（manga-ocr ONNX，2026-09-25）


模型与配置（`mayocream/manga-ocr-onnx`，**apache-2.0**）：encoder `pixel_values [1,3,224,224]` → `[1,197,768]`；
decoder 输入 `input_ids` + `encoder_hidden_states`、输出 `logits [1,len,`**`6144`**`]`；
`decoder_start_token_id = 2 = [CLS]`、`eos_token_id = 3 = [SEP]`、pad = 0。
预处理是 **224×224 压扁**（不保宽高比）+ 均值方差 **0.5 / 0.5** ——
**不是 ImageNet 那组**（那组是检测件的，两处容易抄串）。
`vocab.txt` 是**字符级**词表、**CRLF** 行尾、无 `##` 续词 → 解码就是「拼接 + 丢特殊 token」。

Rust 侧（`rust/ocr_core::recognize`）：贪心 + `no_repeat_ngram_size = 3`（参考实现是 `num_beams = 4`，
一期不要 beam 的代价）；`truncated` 标志区分「遇到 EOS 停」与「被 `max_new_tokens` 截断」，
截断的文本必须当可疑结果看。

实测（mokuro 的 4 格页，**28 个框全部识别、无截断、无乱码**；debug profile，opt-level 1）：
检测 36 + 176 + 5 ms，识别合计 2 742 ms（≈98 ms/框；encoder 64–106 ms，decoder 9–48 ms）。
样本与页面气泡逐条对得上：「トカゲじゃ」「ない!?」「ヤモリ!?」「どっから捕まえて」「きたんだよお前!」
「初めて見たよ!」「こんな住宅地にも」「いるんだ!」。

两个可复现的调参结论：
1. **裁剪外扩默认 6 px**：pad=2 时「出てきなさ」被裁半截，pad=6 补全为「出てきなさい」；
   再大就会带进相邻列的墨。
2. **检测框会切断长竖排列**（「すごいのハッ」+ 另一框的「ケン」；「トカゲじゃ」/「ない!?」）→
   翻译前必须**把同一块的框按列邻接聚成块**，否则译文只有半句。这是下一段（翻译）的前置条件。

### 8.6.5 检测件实测：8 张真实页，三家对比（未决 3）

真实页来源：`kha-white/mokuro` 的测试数据 6 页、`kha-white/manga-ocr` 示例 1 页、
`dmMaze/comic-text-detector` 文档页 1 页（Manga109 的 `AisazuNihaIrarenai-003`）。
本机没有漫画库，所以用的是这些公开测试图。

| 检测件 | 许可 / 体积 | 单页耗时 | 结果 |
|---|---|---|---|
| **PP-OCRv4 mobile det**（`breezedeus/cnstd-ppocr-ch_PP-OCRv4_det`） | **apache-2.0** / **4.7 MB** | **~70 ms** | 框**紧贴在竖排文字列上**，误报极少；**漏手写拟声词**（`だだだた`、`かえして`、`ピピピピ`） |
| comic-text-detector（`mayocream/comic-text-detector-onnx`） | 声明 apache-2.0，但**权重源自 GPL-3 项目** → 灰色 | ~450 ms | 召回更高（含部分拟声词），但**大量假框压在美术上**（壁虎、猫身、手臂、脸都有巨型斜框） |
| **Apple Vision** `VNRecognizeTextRequest`（revision 3, `.accurate`, `ja`） | 系统 API，零模型 | ~200 ms | **在漫画竖排上基本不工作**：Manga109 那页 **0 框**，4 格页只出 1 框。同一 API 在别页能出 35 框 → 是真召回失败，不是接口坏了 |

- **这直接推翻了 §8.1 里那条「Mekuru 的 iOS 先例（用 Apple Vision 做检测）可以照搬」**：
  Vision 认的是文档式横排文字，漫画的竖排列它看不见。Apple 侧想免模型这条路**不成立**。
- ⚠️ **对 comic-text-detector 要公平**：我取的是它的 `det` 分割通道 + 通用 DB 后处理
  （pyclipper unclip + minAreaRect），**没有用它自己的 `blk` 头与官方后处理** →
  那批巨型斜框里有一部分是我这边解码方式造成的，不是模型上限。要真选它，得按官方解码重测。
**Rust 侧移植（`rust/ocr_core`，2026-09-25 首落）**：同一批 8 张页跑通。框数对照 Python 参考为
`33 vs 39 / 4=4 / 18=18 / 28 vs 30 / 25=25 / 18=18 / 18 vs 21 / 84 vs 93` —— 4 张完全一致，
其余低 0–15%。差异来自 Rust 侧把 `min_area` 判据换成 `cv2.contourArea` 的等价量
（`像素数 − 边界长度/2`，对 w×h 实心块恰好等于 `(w−1)(h−1)`）并补了「最小边 < 4 丢弃」；
换之前普遍**偏多 2–6 个**（小斑点漏过）。耗时（debug profile，opt-level 1）：
前处理 22–59 ms、推理 80–160 ms/页，后处理 2–14 ms。
复跑：`cargo run -p rossi_ocr_core --bin detect_image -- <model.onnx> <page.jpg> [--ep cpu|coreml] [--limit-side N] [--json]`。

- **三家共同的缺口是手写拟声词**（PP-OCR 全漏、CTD 只捞回一部分）——
  这是「漫画检测」区别于「文档检测」的核心难点，也是 §8.1 里那些 fork 都要自己训一个检测器的原因。

### 8.7 本地翻译模型选型：1.8B / 7B / 漫画微调 / Sakura / Apple 同台（2026-10-01，M4）

台架与原始数据都在 `docs/mt-bench/`（`corpus.json` 33 条、`mt_bench.py`、`apple_bench.swift`、
`results.jsonl` 267 行）。模型放 `.local/mt-bench/models/`（15 GB，不入库）。

**语料不是编的**：30 条取自本仓 8 张真页的**识别输出**（含 3 条真实 OCR 残缺/乱码行）+ 3 条自造专名句。
三条**客观对照**先钉死，免得排名变成口味之争：

- **壁虎/蜥蜴**：ヤモリ(壁虎) 与 トカゲ(蜥蜴) 出现在同一页（那格的笑点就建立在这个区别上），
  译成同一个词 = 笑点消失。可机器判。
- **专名一致性**：危機契約 在 #3 与 #29 各出现一次，两次必须同一个词。可机器判。
- **残缺输入不许编**：模型卡自己承认「残缺的输入会被补全，而不是照译」，
  而我们送进去的就是残缺的 —— 补出一句没发生过的话比译得难看严重得多。

**为什么这份排名可信 / 不可信，先说清楚**：第一轮里基座是 `temp 0`（贪心、可复现），
而漫画微调版按它模型卡推荐用了 `temp 0.15`，**且每条只跑一次** —— 这个对比不公平，
任何一条错译都可能只是采样噪声。补跑一轮：**同一批关键句在 `temp 0` 下各跑一次、`temp 0.15` 下跑三次**，
结果全部稳定复现（唯一抖动的是 `だだだだ` 在带术语块时「颤颤颤/疼疼疼疼」二选一，以及 `かえして` 的
「拜拜/拜托啦」）。所以下面这些是模型行为，不是骰子。

**一处归因更正（我自己先写错的）**：下面排名表里「ヤモリ→母狗」那条**只在带术语块的变体里出现**，
默认提示下它给的是「鳄鱼」。两者都错（正解壁虎），但「加术语表把它带崩」和「模型本来就译成母狗」
是两个结论，前者才是实测到的。术语块确实有副作用：`トカゲ` 从「蜥蜴」变成「蝰鱼」。

**为什么 1.8B 这一档会这样 —— 不是微调把它弄坏的，是它本来就不认识这些词**：

| 条目 | 基座 1.8B | 漫画微调 1.8B | 7B | Apple |
|---|---|---|---|---|
| `ヤモリ`（壁虎） | 龙鱼 ✗ | 鳄鱼 ✗ | 壁虎 ✓ | 壁虎 ✓ |
| `危機契約` | 危机协议 ✗ | **危机契约 ✓** | 危机契约 ✓ | 危机合同 ✗ |
| `怪我してない` | 没有受伤 ✓ | 有没有受伤 ✓ | 没受伤 ✓ | 没有受伤吗 ✓ |
| `敵わない`（比不过你） | **我根本比不过你 ✓** | 你根本配不上我 ✗（**语义反向**） | 根本比不上你 ✓ | 敌不过你 ✓ |

读出来是两件事同时成立：**微调确实修好了它训练过的那几类**（同形专名、`怪我`→受伤、日文残留、标点，
它比基座稳），**但 1.8B 的参数装不下词条级世界知识** —— ヤモリ/トカゲ 之分基座也不懂，
这不是微调造成的。而它在**语气句上比基座倒退**（`敵わない` 译反），这是窄域 SFT 的代价，
实测到了，不是猜的。它自己的模型卡也写着「**没有任何中文母语者检查过输出**」，
全部结论来自 chrF/COMET/LLM 评审 —— 这次人工评审做了，就是上面这张表。

**「7B 太大」这个约束下的出路：Apple + 输出端术语替换**（实测）。Apple 没有术语表接口，
但专名这一类错**可以在译文落笔前做字符串替换**：4 条术语（危机合同→危机契约、换一下→还给我、
也完全→真是的、诺拉博斯→野良波）跑完 33 条，**命中 5 条、术语类残留 0 条**，
代价是零下载、零显存、134 ms/条。它救不了语义反向和语气，但那类 Apple 本来就没做错。
所以本机的取舍不是「1.8B 还是 7B」，而是
**「Apple + 术语替换（快、小，专名靠表兜）」vs「7B（准，但 4.6 GB / 8 s 一页）」**。

**先修两个台架 bug，否则数字全是错的**：

1. **llama.cpp 在这台机器上默认不走 GPU。** 它同时列出 `BLAS: Accelerate` 与 `MTL0: Apple M4`，
   不点名就吃 CPU —— 1.8B 实测 **8.9 tok/s**；加 `--device MTL0` 之后 **43 tok/s，差 4.8 倍**。
   ⚠️ 设备名必须是 `MTL0`，写 `metal` 会 `invalid device` 直接退出。
2. **Sakura 的 GGUF 里没带 `tokenizer.chat_template`**（只有 `eos_token_id=151645`），
   而它的提示词格式在它两个 HF 仓库的 README 里都**没有**（GGUF 仓库的 README 是 33 字节空文件，
   非 GGUF 仓库要登录）。所以按 OpenAI chat 方式发过去 = 让它**续写轻小说**：
   每条平均 **232 字**、27 s，输出是「……」循环。
   **这一条不许记成「Sakura 质量差」** —— 是我的调用方式接不上它，它得先手抄提示词。
   对照组：manga 微调版**带了**模板且 `eos=120020`（与它 README 的警告一致），
   所以它那些错译是模型自己的行为，不是台架 bug。

| 系统 | 壁虎/蜥蜴对照 | 危機契約（两次） | 日文残留 | GPU 中位延迟/条 | 体积 |
|---|---|---|---|---|---|
| **Apple 系统翻译** | **过** | 危机合同／危机合同（一致地**错**） | 0/33 | **134 ms**（整批摊）/ 187 ms（单条） | 0（系统已装） |
| Hy-MT2-1.8B 基座 | ✗ 译成「龙鱼」 | 危机协议／危机协议（一致地错） | 1/33 | 193 ms | 1.13 GB |
| Hy-MT2-1.8B 漫画微调(zh) | ✗ ヤモリ→「鳄鱼」 | **危机契约／危机契约（对）** | 0/33 | 192 ms | 1.13 GB |
| 同上 + 术语块 | ✗ ヤモリ→「**母狗**」、トカゲ→「蝰鱼」（**被术语块带崩**） | 危机契约／危机契约 | 0/33 | ~192 ms | 同上 |
| **Hy-MT2-7B** | **过** | **危机契约／危机契约（对）** | 1/33 | **555 ms** | 4.62 GB |
| Sakura-7B-LNovel | 不可判（续写循环） | 不可判 | 0/33 | 26 987 ms | 4.90 GB |

**逐条里最扎眼的几条**（原文 → 各系统）：

- `かえして〜`（这页是「还给我！」）：Apple「换一下~」✗ ／ 基座「还回来吧」✓ ／
  **漫画微调「回头见」✗** ／ 7B「反而」✗
- `まったくもう…あなたには敵わないわ` → 漫画微调给出「你根本配不上我」—— **语义反向**（原文是"我比不过你"）
- `こーなったらご主人さまと根くらべよ` → 基座「和丈夫相比就公平了」、漫画微调「划清界限」，只有 7B「一决胜负」对
- 残缺行 `間どもはそう手ぶ`：Apple 直译成「中间是那样的手」（难看但**没编**），
  1.8B 系全部补成一句完整的话（「你们几个，别这样打我」）—— 这正是模型卡警告的行为，
  而我们的输入**经常就是这样的**

**结论（与那份外部推荐的排序相反，逐条给依据）**：

1. **不采纳「Hy-MT2-1.8B 漫画微调版」作为默认。** 它在两条客观对照上都输：ヤモリ 在贪心解码下
   稳定译成「鳄鱼」，加上术语块之后更崩成「母狗」/「蝰鱼」；并把「我比不过你」译反。
   它的模型卡自己写着**「没有任何中文母语者检查过这个模型的输出」**，
   上面那些结论全部来自自动指标与 LLM 评审 —— 本节就是那份它缺的人工评审，结果是负的。
   而且加术语块**没有帮忙反而更糟**（危机契约本来就对，加了之后 トカゲ 变成「蝰鱼」）。
2. **本地要质量就 7B，别在 1.8B 上找。** 7B 是全场唯一同时过两条客观对照的本地模型，
   语气与惯用语也最稳；代价是 555 ms/条 → 一页 15 块约 **8 s**，比擦字整段（2.7 s）还贵。
3. **Apple 系统翻译是这台机器上「不想花钱」的正确答案**：最快（一页约 2 s）、零下载、零显存，
   而且**在两条客观对照上都不输 1.8B 本地模型**。它的短板很具体：专名（危机合同）与口语语气（也完全），
   以及**没有术语表接口**。
4. **7B 这一档不需要新代码**：`llama-server --device MTL0` 本身就是 OpenAI-compatible 端点，
   把 `baseUrl` 指过去就是 `endpoint` 档 —— 所以「加本地大模型」在这套架构里是**一条配置**，
   不是第四个引擎。Hy-MT2 还有文档化的 **Terminology 提示模式**，术语表能真用（Apple 不行）。
5. **Metal 与 CPU 的译文 0/36 条不同** —— 换后端只换速度，不换质量。这条是上面所有质量结论
   可以跨后端引用的前提。

**还没测的**：Marian/NLLB 那一档真 NMT（要装 torch，且 NLLB 卡是 `cc-by-nc`）；
以及云端 LLM 端点 —— 那要花用户的 API 余额，不该由我替他决定花不花。

**再一步：术语表能把 1.8B 缺的那块知识逐条补回来（10-01 补测，这条改了上面的排名）**

上面那张表里 1.8B 的两个错（ヤモリ→龙鱼/母狗、危機契約→危机协议）都不是「模型坏了」，
是**它不知道该词**。把它们放进 Hy-MT2 原生的 Terminology 块（`X 翻译成 Y`）重测，
贪心解码、同一台机器、同一份 llama-server：

| 条目 | 不带术语表 | 带术语表 |
|---|---|---|
| 基座 #11 `ヤモリ` | 龙鱼 ✗ | **壁虎 ✓** |
| 基座 #30 | 蜥蜴和龙鱼 ✗ | **蜥蜴和壁虎 ✓** |
| 基座 #3 / #29 `危機契約` | 危机协议 ✗ | **危机契约 ✓** |
| 漫画版 #11 | 母狗 ✗ | **壁虎 ✓** |
| 漫画版 #30 | 老虎 ✗ | **壁虎 ✓** |
| 漫画版 #9 `かえして` | 回头见 ✗ | **还给我 ✓** |
| 漫画版 #6 `敵わない` | 配不上我 ✗（反向） | **比不过你 ✓** |
| 漫画版 #10 `だだだだ` | 颤颤颤 | 不、不行、不行、不行 ✗ |

**所以「本地要质量就上 7B」这句要收回一半**：10 条里 7 条被术语表直接修对，
修完的 1.8B 在**这批句子上不输无术语表的 7B**（7B 自己 `かえして` 还翻成「反而」，是错的）。
代价从 4.6 GB / 555 ms 降到 **1.1 GB / 158 ms**。
最后一行是反面：**术语块也会带坏拟声词**（`だだだだ` → 「不行不行」），
所以「加了术语表就一律更好」不成立，那类要单独看。
另外这条本质是**查表不是长知识** —— 表里没有的词照样错，所以它能不能用，
取决于用户愿不愿意维护术语表；这也是为什么 Apple 那一档（自带这些词知识）仍然值得当默认。

**并发这条：顺手写的优化被实测否掉了。** `HyMt2Translator` 我一开始设了 4 路并发，
实测（16 条真实术语提示、llama-server `-np 4`）：串行 **158 ms/条**、2 路 **184 ms（0.86×，更慢）**、
4 路 **141 ms（1.12×）**。这类模型解码吃的是**显存带宽**不是请求数，并发换不到吞吐，
却要多背一个「服务端 `-np` 得够」的依赖和一类回填错序的风险 —— 已经改回 **1**，
并把「并发度必须等于配置值」钉成测试，防止下次有人不测就改回去。

### 8.4 修正后的来源分工

```text
检测 + 识别 + 擦字的代码  → xianscan-rust 的 src/ml/{detect,ocr,inpaint}（MIT + ort，唯一 vendor 候选）
                          → manga-ocr-rs（MIT，同 ort 约束）作识别半边对照
pipeline 分层 / 排版回填   → Koharu（MIT OR Apache-2.0，读分层与 vert+vrt2 竖排，不取 LibTorch）
reader overlay 与 OCR 队列 → Yomihon、Kototoro（Apache-2.0，但 Kotlin → Dart 仍是重写）
按住窥视译文的交互         → Frank Yomik（AGPL，只读设计）
回填字体                  → 霞鹜文楷**轻便版** `lxgw/LxgwWenKai-Lite`（**OFL-1.1**，v1.522，Regular 13.2 MB；
                          完整版 24–27 MB）。随包分发合法，但**不得自行子集化**（见 ADR-0018 §决定 5）
```

> 与 §5 的结论同构：**代码来源与交互来源必然是两个不同的项目**。
> 没有任何一个项目同时具备「Flutter + 端侧 OCR + 擦字回填 + 可 vendor 许可」。
>
> **形态已定（ADR-0018）**：交付物是**成品页**（擦字 + 回填），叠加层不是交付物 ——
> 因此 §8.5 里 Yomihon / Kototoro 的 overlay 价值降为「逐页开关与队列的形状参考」，
> 而 Koharu 的排版回填与竖排成为**必须读**的那一项。

### 8.5 reader 侧交互：哪些在成品页形态下仍然要读

> 前三条（Frank Yomik / Mekuru / Chimahon）是 GPL/AGPL → **读设计，禁止粘贴**；
> 第四条 Kototoro 是 Apache-2.0，可搬但它是 Kotlin → Dart 仍是重写。
>
> **注意形态差异**：ADR-0018 定的是一期交付**成品页**，不是叠加层 —— 所以「放大镜本身」与
> 「overlay 跟随缩放」这两类解法**不采用**；下面每条只标出仍然成立的那一件。

- **Frank Yomik — 要读的是状态可见性，不是放大镜**：页面保持原样，长按 200 ms 开一个跟随指针的圆形放大镜，
  镜内是**译文渲染**，镜外仍是原图；松手即消失，快速点击仍然翻页。
  ⚠️ 本仓不做这个交互（成品页不需要「窥视另一份渲染」）。
  **仍然照搬的是它的页角状态点**：一个点表示该页 pipeline 状态（琥珀=进行中 / 绿=就绪 / 红=失败），
  且**结果未到时给出可分辨的「空」状态** —— 于是「还在算」与「坏了」在 UI 上是两件事。
  成品页形态下这个点挂在「本页有没有缓存产物」上。文件：`client/lib/screens/reader_screen.dart`、
  `extension/src/content/overlay.js`、手势测试 `client/test/lens_test.dart`。
- **Mekuru** — 逐页 OCR 触发与词级命中：`ocr_action_sheet.dart`（长按识别按钮 → 选端侧/远端、本页/整本、是否替换既有）、
  `manga_word_tap_hittest_test.dart`（词级 hit-test 的测试形状）、`local_ocr_page_overlay.dart`。
  其中**「本页 / 整本」+「是否替换既有」这两维是成品页任务队列的正解**，直接对应 ADR-0018 §决定 3 的缓存语义。
- **Chimahon** — 大幅面页的对齐问题：`OcrSubsamplingImageView.kt`（分块解码以免缩放时叠加层跑位）与
  `OcrCoordinateMapper.kt`（图像坐标→视图坐标）**是 overlay 形态的解法，本仓不采用**；
  成品页要防的是**预处理逆变换**（识别框/掩膜/基线必须回到同一套像素坐标，见 ADR-0018 Consequences）。
  **仍然照搬的是** `ChapterOcrIndicator.kt`（章节列表上的「已 OCR」徽标 = 「已有缓存产物」）
  与 `OcrSmokeTestScreen.kt`（应用内冒烟页 —— 本仓几乎没有测试基础设施，这个模式特别值得抄）。
- **Kototoro** — `ReaderPageEnhancementController.kt` / `ReaderPageEnhancementState.kt`：
  **逐页**开/关的状态机。成品页形态下它就是「本页显示成品页 / 回退原图」那一层，
  与 ADR-0018 §决定 3 的「原图永远是真相」直接对齐。
  `ReaderTapGridConfigScreen.kt`（用户可编辑的点击分区）在放弃放大镜后**优先级下降**。
