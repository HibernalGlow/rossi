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
