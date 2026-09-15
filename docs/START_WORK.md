# Rossi 开工文档

> 目标：以最小工作量把 Rossi 做成真正可用的跨平台漫画阅读器。
>
> 核心原则：**尽可能拼装现有成熟能力，不重写已经存在的 Reader / Archive / 超分 / GPU 核心。** Rossi 主要负责 Flutter UI、协议适配、生命周期管理和各能力之间的胶水。

---

> **⚠️ 本文档的技术前提已在 2026-09-16 的决策轮次中被部分推翻，正文按「保留原文 + 就地更正」处理。**
> **权威来源是 `CONTEXT.md`（术语）+ `docs/adr/`（决策）+ `docs/ROADMAP.md`（计划）+
> `docs/v0.1_acceptance.md`（验收判据）；与本文档冲突时以上述为准。**
>
> | 位置 | 原文的说法 | 现状 |
> |---|---|---|
> | §3 全节 | mImage 是一个可 vendor 的 Rust 核心 | mImage = `MikageSawatari/mimageviewer`，是 **Windows 11 独占的 egui 单体应用**，架构上不可当库。见 ADR-0001 / 0005 / 0007 |
> | §3.1 | 「Rossi 不重新实现本地漫画 Reader core」 | **已改写**：Rossi 拥有本地核心，mImageViewer 是**源码来源与行为标杆** |
> | §7 | 超分参考 Venera-SSR | 超分以 **mImageViewer 的 `ort` 核心**为准；Venera-SSR 是 GPL，**只能读不能抄** |
> | §2 | 「React UI 迁移为 Flutter」 | 只**提取视觉与交互语言**，在现有 `lib/page/comic_read` 上重建；业务实现不迁移。见 ADR-0003 |
> | §10 | `vendor/mimage/`、`lib/app/`、`lib/features/*`、`rust/mimage_bridge` | 这些路径**全部不存在**；见 §10 就地更正 |
> | §12 | 功能验收清单（含「在线源可以打开」） | v0.1 判据见 `docs/v0.1_acceptance.md`，**在线源不在 v0.1** |
> | §14 | 「mImage 做本地核心并 vendor 成 Rust crate」 | 表述已更正；Gate A 已拆为 A-W（已通过）/ A-M（待验、**不阻塞**） |
>
> 四份「不要据此开工」的约束另见 ADR-0008（v0.1 冻结线：在线源 / OCR 翻译 / 上色 / Anime4K / 视频全不进）。

## 1. 总体方案

Rossi 的最终结构：

```text
┌───────────────────────────────────────────────┐
│                   Rossi                       │
│                                               │
│  Flutter UI                                   │
│  └── 从既有 React UI/交互设计迁移为 Flutter    │
│                                               │
│  Reader Orchestration                         │
│  ├── Online Source Adapter                    │
│  ├── Local Source Adapter                     │
│  ├── Page / Session State                     │
│  ├── Upscaler Adapter                         │
│  └── Render Backend                           │
│                                               │
│  Native / Rust                                │
│  ├── mImage (vendored crate)                  │
│  ├── wgpu renderer                            │
│  └── existing SR backends                     │
│                                               │
│  Existing Breeze ecosystem                    │
│  └── QuickJS / comic source plugins            │
└───────────────────────────────────────────────┘
```

Reader 数据流统一为：

```text
本地：mImage ───────────────┐
                            ├→ PageSource → Reader → RenderBackend
在线：Breeze Plugin ────────┘
                                      ↓
                                   Upscaler?
                                      ↓
                               wgpu GPU surface
                                      ↓
                             Flutter Texture
```

## 2. UI：React 设计迁移到 Flutter

### 2.1 定位

之前确定的 React UI 是**视觉与交互参考实现**，不是 Rossi 的最终运行时。

Rossi 正式前端使用 Flutter，不保留 React DOM/WebView 作为桌面 Reader 的中间层。

迁移目标：

- 保留既有 React UI 的页面层级、布局逻辑、交互方式和视觉语言；
- 用 Flutter Widget 重建；
- Reader 页面、工具栏、设置、图库、本地库等都由 Flutter 原生绘制；
- 不把 React Canvas 当成 GPU Reader；
- 不为了“跨端复用 React”牺牲桌面端 Reader 的 GPU 路线。

> 更正（2026-09-16，ADR-0003）：上列「保留交互方式和视觉语言」**不包括业务实现**。
> neoview 是约 20 万行的完整应用（前端 96,384 行 + 后端 103,216 行），其中约 80% 是业务
> （OPDS 客户端、zip/7z/epub loader、5 个超分 service、AI 翻译、语音与手势输入），**一律不迁移**。
> Reader 的**骨骼用现有 `lib/page/comic_read`**，neoview 只提供视觉与交互语言。
> → **「迁移」在本项目里只指视觉与交互语言的重建，不指代码移植。**
> → `ntrn` 只当**结构提取器**用（出组件图 / 设计令牌 / 路由报告）：它的转换能力只支持基础
>   JSX→Widget，样式转换排在 v0.9，状态在 v0.8，且它是 GPL（代码不可抄）。

### 2.2 UI 迁移顺序

先做 Reader 最小闭环，不需要一次迁移所有页面：

1. Reader shell
2. 页面/缩放/平移
3. 顶部/底部阅读控制
4. 本地文件选择与打开
5. 阅读进度
6. Library
7. Settings
8. 在线源页面

UI 迁移阶段禁止引入新的状态管理复杂度；优先让页面结构稳定，再统一 state architecture。

## 3. 本地核心：mImageViewer（源码来源 + 行为标杆，不是依赖库）

### 3.1 原则

**Rossi 拥有本地核心；mImageViewer 提供源码来源与行为标杆。**

> 更正（2026-09-16）：原文写「Rossi 不重新实现本地漫画 Reader core」，前提是 mImage 可以作为一个
> Rust 核心库被 vendor。该前提不成立 —— `MikageSawatari/mimageviewer` 虽有 lib target，
> 但架构上是 **Windows 11 独占的 egui 单体应用**，依赖树带 ffmpeg / pdfium / ort / tantivy
> 与三个被 `[patch.crates-io]` 替换的 egui；且它的显示管线（decode → CPU RGBA → `load_texture`，
> 20MP 26–58 ms/张）与 Rossi「禁止 GPU→CPU→GPU 往返」的目标方向相反。
> 见 ADR-0001 / ADR-0005。

**可复用范围限定在归档 / 解码 / 缓存 / 超分，不含上屏路径。**

建议目录（已按 ADR-0007 更正）：

```text
vendor/
└── mimageviewer/          ← 独立 git 检出（clone 自自己的 fork），父仓库以 gitlink 记录 commit
                             适配层用 Cargo `path` 指向它；同步上游 = 在此目录 `git merge upstream/main`

rust/                      ← 由单 crate `windcore` 改为 workspace
├── windcore/（现有 FRB crate，保持不动）
└── mimageviewer_adapter/  ← 薄适配 crate（不含 UI 与平台专属代码）
```

**注意**：`vendor/mimageviewer/` **不得**成为 Rossi workspace 的 member（否则 ffmpeg / ort /
tantivy / egui 会一起进构建）；新机 clone 需要 `--recursive`，忘了会报「找不到
`vendor/mimageviewer/.../Cargo.toml`」，那个报错看起来像路径写错。

改动上游代码是允许的（要跟得住 merge，见 ADR-0002），但不为适配 Rossi 而大改其架构。

### 3.2 Rossi 只包一层 Adapter

目标接口保持很薄：

```rust
open(source) -> ReaderHandle
list_pages(handle) -> Vec<PageInfo>
get_page(handle, index) -> PageHandle / bytes / native surface
close(handle)
```

Rossi 自己拥有：

- Reader session 生命周期
- 当前页/当前 offset
- UI 状态
- 是否触发超分
- RenderBackend 选择

mImage 自己拥有：

- 本地文件与 archive
- 解码
- page metadata
- 其已有 cache / image pipeline
- 其已有高性能本地图像能力

**不要把 mImage 的内部实现复制到 Rossi。**

### 3.3 Vendor 策略

第一阶段优先使用固定 revision / commit，确保 Rossi 可复现构建。

后续再决定：

```text
vendor/mimage
  ├── 固定版本
  └── periodic sync upstream
```

若后续 upstream 足够稳定，可以从完整 vendor 切换到 git dependency；在第一阶段不为了“干净”增加依赖管理复杂度。

## 4. 在线漫画源：继续沿用 Breeze

Breeze 已经有成熟的插件/QuickJS 路径，因此在线源不重新设计。

维持：

```text
QuickJS plugin
      ↓
Breeze Source API
      ↓
ComicSource Adapter
      ↓
Reader PageSource
```

在线页和本地页最终都映射到统一的 `PageSource`。

```text
PageSource
├── LocalPageSource (mImage)
└── RemotePageSource (Breeze plugin)
```

这样 Reader 不需要知道页面来自文件、HTTP、WebDAV 还是插件。

## 5. Reader 层

Reader 是 Rossi 自己真正需要写的主要业务层，但保持“编排器”性质，不重新实现图像核心。

建议拆分：

```text
ReaderController
├── ReaderSession
├── PageSource
├── PageCache
├── PrefetchController
├── UpscalerController
└── RenderController
```

### 5.1 第一阶段必须支持

- 单页
- 长页
- 连续滚动
- 双页布局
- 缩放
- 平移
- 翻页
- 阅读进度
- 邻页预取
- 页面错误恢复

### 5.2 Copy 策略

当前 Windows/D3D12 已验证的正式路径是：

```text
Rust / wgpu texture
        ↓
GPU → GPU copy
        ↓
Flutter native texture
```

**允许这一份 GPU→GPU copy。**

硬性禁止：

```text
GPU → CPU → Dart → CPU → GPU
```

现阶段不为了理论 zero-copy 修改 wgpu-hal。

## 6. GPU Renderer

### 6.1 当前正式方案

以已经验证的 `flutter_wgpu_texture` / 自有 probe 思路作为实现参考，但 Rossi 最终控制 renderer 生命周期，不依赖 3D 示例场景。

职责：

```text
RenderController
       ↓
Rust/wgpu
       ↓
D3D12 / Metal / Vulkan
       ↓
Flutter Texture
```

### 6.2 Windows

当前采用：

```text
wgpu texture
    ↓
D3D12 GPU copy
    ↓
Flutter surface
```

现阶段已确认：

- copy 不经过 CPU；
- barrier 没有系统性额外成本；
- 大 surface copy 吞吐约 169–198 GB/s；
- 4K 单页约 0.348 ms；
- 8K 双页约 1.384 ms；
- 小于约 16 MB 的数据受 L2 影响，不能作为显存带宽指标。

### 6.3 Zero-copy

zero-copy 仍作为后续优化：

```text
wgpu texture
    ↓
D3D12 shared resource
    ↓
Flutter
```

只有真实 Reader profile 证明 GPU copy 已经成为明显 frame-budget 大头时才进入实现阶段。

不要因为 `CreateSharedHandle` 探针得到 `E_INVALIDARG` 就视为故障；对于普通 wgpu 默认堆资源，这是当前路径的预期边界。

## 7. 超分：以 mImageViewer 的 ort 核心为准

> 更正（2026-09-16）：原文是「参考 Venera-SSR，优先复用 Rossi 已有后端」。现在改为：
> **实现与模型集统一以 mImageViewer 的 Rust 核心为准**（`ort` + Real-ESRGAN / Real-CUGAN /
> NMKD-Siax），Windows 先行、macOS 后续转原生，其余平台暂沿用 Breeze 现有后端（CoreML / ncnn）。
> **取消「按内容分工」**（Anime4K 类做线条）：参考实现是 GPL，且不在 v0.1。
> **超分验收只以 Windows 为准**（两套后端意味着模型集不同，跨平台画质必然不一致，不做对齐）。

Venera-SSR 仍值得借鉴的是**Reader 内超分的业务组织方式**（`UpscalerController` 放在哪、
什么时候触发），而不是它的实现代码。

推荐边界：

```text
Reader page
   ↓
UpscalerController
   ↓
Upscaler backend
```

统一接口：

```text
Upscaler
├── CoreML
├── RealSR
├── NCNN / Vulkan
├── ONNX / platform backend
└── CPU fallback
```

Venera-SSR 中值得参考的内容：

- Reader image provider 与 SR service 的连接；
- Anime4K service；
- model manager；
- 本地/网络页面统一走 SR；
- 模型倍率与输入输出尺寸管理。

Venera-SSR 当前的 Dart/Android 实现不直接成为 Rossi 的最终 GPU pipeline。它是业务层参考。

## 8. 参考项目的最终定位

| 项目 | 在 Rossi 中的角色 | 是否直接嵌入 |
|---|---|---|
| React UI | Flutter UI 的视觉/交互参考"D:\1VSCODE\Projects\Xiranite\src\nodes\neoview" | 否 |
| mImage | **本地 Reader / image core** | **是，vendor crate** |
| Breeze | 在线漫画源 / QuickJS plugin runtime | **是，保留现有代码** |
| Venera-SSR | SR service / model management 参考 | 部分复用思想/实现 |
| flutter_wgpu_texture | GPU bridge / surface 参考 | 可作为基础实现参考 |
| flutter_rust_3d | native texture / irondash 参考 | 不引入 3D 场景 |
| ComicRD | cache/prefetch/Reader 生命周期参考 | 否 |

## 9. 首个可运行版本（MVP）

### MVP-0：Renderer

目标：Flutter 页面能显示 Rust/wgpu 输出。

```text
Flutter
 ↓
Rust bridge
 ↓
wgpu
 ↓
D3D12
 ↓
Flutter Texture
```

只需要一张静态纹理。

### MVP-1：本地漫画

```text
打开 CBZ / Folder
 ↓
mImage
 ↓
page metadata
 ↓
page decode
 ↓
GPU
 ↓
Reader UI
```

先不做超分。

### MVP-2：完整 Reader

加入：

- 连续滚动
- 双页
- zoom/pan
- progress
- prefetch
- cache

### MVP-3：在线源

把 Breeze plugin 的远程图片接到同一 `PageSource`。

```text
LocalPageSource ──┐
                  ├→ Reader
RemotePageSource ─┘
```

### MVP-4：超分

第一阶段只需要：

```text
Reader
 ↓
UpscalerController
 ↓
existing SR backend
```

确认 SR 不破坏 Reader 生命周期之后再优化 GPU residency。

## 10. 推荐工程目录

> 更正（2026-09-16）：下面是**更正后**的结构。原文提议的 `vendor/mimage/`、`lib/app/`、
> `lib/features/{library,reader,source,settings}/`、`lib/rendering/`、`lib/upscale/`、`lib/bridge/`、
> `rust/mimage_bridge/`、`rust/gpu_renderer/`、`rust/source_bridge/` **全部不存在**。
> 仓库现状：`lib/page/`（已有 `comic_read` / `bookshelf` / `setting` / `plugin_store` / `comic_follow`）、
> `rust/` 是单 crate `windcore`（无 workspace）。

```text
rossi/
├── docs/
│   ├── RESEARCH.md
│   ├── REFERENCE_RESEARCH.md
│   ├── ROADMAP.md
│   ├── START_WORK.md
│   ├── v0.1_acceptance.md
│   ├── adr/                     ← 决策的权威来源（0001–0008）
│   └── gate-a/  windows-build/
│
├── CONTEXT.md                   ← 术语表（仓库根）
│
├── vendor/
│   └── mimageviewer/            ← 独立 git 检出（gitlink），**不是** rossi 自己的文件
│
├── lib/
│   └── page/
│       ├── comic_read/          ← Reader 骨骼（ADR-0003：在这上面重建，不从零画）
│       ├── bookshelf/  setting/  plugin_store/  comic_follow/
│       └── ...
│
├── rust/                        ← 由单 crate 改为 workspace
│   ├── windcore/                ← 现有 FRB crate，保持
│   ├── mimageviewer_adapter/    ← 薄适配 crate（待建）
│   └── wgpu-probe/ …            ← PoC（在 poc/ 下，不进发布路径）
│
└── poc/                         ← Gate A 验证工程，独立于主代码
```

`lib/` 不做大规模重排——现有 Breeze 结构是基准，**新增目录只在真正需要时加**。

## 11. 第一阶段不要做什么

为了保持最小工作量，以下全部后置：

- 不重写 mImage archive/decode/cache；
- 不重写 Breeze plugin runtime；
- 不迁移所有 React 页面后再开始 Reader；
- 不首先做 Web；
- 不首先改 wgpu-hal；
- 不首先实现 WebGPU SR；
- 不为了统一 API 提前兼容 Mangayomi extension；
- 不设计复杂插件 marketplace；
- 不做 GPU zero-copy 的通用 external texture framework。

## 12. 验收标准

> **v0.1 的验收判据以 [`v0.1_acceptance.md`](./v0.1_acceptance.md) 为准**（四条：覆盖度 /
> 冷启动 ≤ 2 s / 翻页 p95≤16.7ms·p99≤33ms·无 >100ms 单帧 / 连读三本 RSS 增幅 ≤5%）。
> 下面这份清单是**更长期的目标**，其中多项不在 v0.1：**「在线源可以打开」不在 v0.1**（ADR-0008）。
> `CBR` 在 v0.1 判据里是**硬要求**，但它不是本清单里的任何一项 —— 见 `v0.1_acceptance.md` §4。

### 功能

- [ ] 本地文件夹可以打开
- [ ] CBZ/ZIP 可以打开
- [ ] CBR/RAR 可以打开（v0.1 硬要求）
- [ ] 在线源可以打开（**不在 v0.1**）
- [ ] 单页/双页可切换
- [ ] 连续滚动稳定
- [ ] zoom/pan 稳定
- [ ] 阅读进度可保存
- [ ] SR 可开关

### GPU

- [ ] Windows 使用 Rust/wgpu renderer
- [ ] 不发生 GPU→CPU→GPU 往返
- [ ] 单页内容更新时才进行 presentation copy
- [ ] 连续平移/缩放不重复搬运不变的页面内容
- [ ] 4K / 8K 页面可稳定显示

### 性能

重点 profile：

```text
decode
upload
SR
GPU copy
composite
Dart heap
GPU memory
```

不要再使用受刷新率限制的 FPS 直接推断 GPU copy 吞吐；copy 性能使用离屏批量 + GPU timestamp。

## 13. 开工顺序

### Step 1

把现有 React UI 的 Reader 页面迁成 Flutter 第一版，只做静态页面和交互骨架。

### Step 2

把 mImage 放进 `vendor/`，建立 Rust crate/workspace dependency，完成最薄 bridge。

### Step 3

接通：

```text
mImage → Reader → wgpu → Flutter Texture
```

先只显示真实本地漫画。

### Step 4

加入 cache/prefetch、单页/双页、长页处理。

### Step 5

把 Breeze 在线源接入统一 PageSource。

### Step 6

加入 Venera-SSR 风格的 UpscalerController，挂现有超分后端。

### Step 7

真实 4K/8K + 双页 + 高刷 benchmark。

### Step 8

只有 profile 证明值得，才研究 D3D12 shared heap / wgpu-hal zero-copy。

## 14. 开工判定

**现在正式进入开发，不再以“寻找一个已经全部完成的项目”为前置条件。**
**Gate A 也不再是开工门槛**（已按 ADR-0004 拆分：A-W 已通过，A-M 待验但不阻塞）。

最终方案（已更正）：

> **Flutter 做 UI；neoview 只提供视觉与交互语言，在现有 `lib/page/comic_read` 上重建；
> mImageViewer 提供本地能力的源码与标杆（vendor 到 `vendor/mimageviewer/`，Rossi 侧加薄适配 crate）；
> Breeze 保留在线源插件生态（但不在 v0.1）；超分统一以 mImageViewer 的 `ort` 核心为准；
> Rust/wgpu 做 GPU renderer；Flutter Texture 做 presentation。**

v0.1 = **本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分**，判据见 `docs/v0.1_acceptance.md`。
动手前的第一件事是 Phase 0 那两项未勾选任务与 **vendor spike**（统计 mImageViewer `src/` 下多少模块
`use egui`，决定「薄适配层」能否成立）。

重点不是重新造一个漫画阅读器，而是把这些已经存在的能力用最薄的 adapter 拼成一个统一 Reader。