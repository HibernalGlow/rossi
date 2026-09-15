# Rossi 改造路线图

> 目标：以 Breeze 为产品基座，逐步构建高性能跨平台漫画阅读器，并为 Xiranite 集成保留清晰的模块边界。
>
> **平台顺序（ADR-0006）**：**Windows 与 macOS 同期**（本机无 macOS，实际是「代码同期写、验证滞后」），
> **Linux 与移动端随后**。移动端只做最低适配：能编译运行、零新增功能、不参与任何验收。
> 交付目标：**个人自用**——不为对外发行做任何工作，不取代 Breeze 的发行通道。

## v0.1 冻结线（ADR-0008）

**v0.1 = 本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分。** 其余一律不进：

| 不进 v0.1 | 处置 |
|---|---|
| 在线源（QuickJS 插件） | 会把验收面从「本地阅读」扩大到网络 + 插件错误处理 + 源站变化 |
| OCR 翻译 | 最贵的一项（检测+识别+翻译+排版回填）；参考实现是 GPL，**只能读不能抄** |
| 上色 | 同上，且只在黑白页有意义 |
| Anime4K | 参考实现 GPL；超分统一以 mImageViewer 的 `ort` 核心为准 |
| 视频播放 | 推迟，但 `PageSource` **现在就不假设「一页 = 一张静态图」**（占位） |

「推迟」= 留占位，不是删掉。任何一项要进范围，先改本节与 ADR-0008，再动手。

**v0.1 验收判据**（完整定义、测量口径与已知成本见 [`v0.1_acceptance.md`](./v0.1_acceptance.md)）：

1. **覆盖度**：CBZ / CBR / 散图文件夹三种都能读到最后一页
2. **冷启动到第一页 ≤ 2 s**（连续 3 次取中位数，Release）
3. **翻页无卡顿**：`p95 ≤ 16.7 ms`、`p99 ≤ 33 ms`、无任何 `> 100 ms` 单帧
4. **连读三本内存不增长**：RSS 增幅 ≤ 5%，且纹理/handle 计数不单调上升

不采用平均 FPS 作判据——它会掩盖单次长卡，而长卡正是翻页唯一真正被感知的东西。

## Phase 0 — 基线与可回退点

- [x] Fork 上游 Breeze 为 `HibernalGlow/rossi`
- [x] 保留上游同步入口，不直接污染 `main`（`upstream` remote 指向 `deretame/Breeze`，`main` 与上游无漂移）
- [x] 确认平台优先级：桌面优先，移动端最低适配
- [x] 记录环境基线：Flutter `3.47.3` / FRB `2.13.0` / Dart `^3.12.0`（详见 `docs/RESEARCH.md` §3.1）
- [ ] 确认当前 Windows/macOS/Linux 构建基线（三平台各跑通一次 release 构建）
- [ ] 记录现有 Reader 的帧率、内存、翻页延迟
- [ ] 记录现有 RealSR/CoreML/Android 超分链路
- [ ] **vendor spike**（ADR-0005 / ADR-0007，动手前必做）：统计 mImageViewer `src/` 下多少模块
      `use egui`（决定适配层真实厚度）；验证 path 依赖跨 workspace 的 Cargo 归属行为

分支：`research/gpu-reader-foundation`

## Phase 1 — GPU Reader PoC（最高优先级）

目标不是做完整 Reader，而是证明 Flutter 能否承载目标级别的图片显示。

**进展（2026-09-15）**：Gate A 已按「先验 Flutter 侧通道，再验 wgpu 导出」的顺序拆成两个
独立风险。**两个风险在 Windows 上都已跑通**，证据（`handleOpened` 计数、adapter LUID 命中、
像素通道校验、resize/浸泡稳定性）见 `docs/gate-a/README.md`，验证工程为
`poc/texture-bridge/`。

过程中定下两条会影响后续架构的硬结论：

1. **直接共享 wgpu texture 不可行**（`CreateSharedHandle` 返回 `E_INVALIDARG`，因为 wgpu
   的纹理建在默认堆、不带 `D3D12_HEAP_FLAG_SHARED`）；且 wgpu 27 的公开 API 不提供
   「用外部资源反包 texture」的入口，**零拷贝方案在当前 wgpu 上已关闭**。
2. 可行路径是**自建共享纹理 + 每帧一次 GPU→GPU `CopyResource`**。该拷贝不经过 CPU，
   满足「无 GPU→CPU→GPU 往返」，成本已用离屏基准实测量化：视口量级（≤16 MB）占
   60 fps 预算 **0.07%–0.56%**，4K 单页 **2.1%**，8K 双页 **8.3%**。barrier 往返与
   SHARED 堆标志的净成本实测均可忽略（±6% 内）。结论：**不为省掉这次拷贝去改 wgpu-hal**，
   优先落地「copy 按需而非每帧」这一实现约束（见 `docs/gate-a/README.md` §3.5）。
3. **第三条路径（Flutter GPU）已评估，结论是不作为当前替代方案。** 它在 Windows 上
   实测可用（`Texture.asImage()` 零拷贝产出 `ui.Image`，全程无跨设备共享），但**无法导入
   外部纹理** —— 只能替代而不能补充 Rust/wgpu；且引擎导出的符号里**没有任何 compute
   能力**，超分等 GPU 通用计算实现不了。详见 `docs/gate-a/flutter-gpu-path.md`。

**Gate A-W（Windows）：已通过。** 剩余未覆盖项（都不是阻塞条件，而是记账）：

1. 全部结论来自 Debug 构建，Release 行为未验证（含「引擎每帧重新打开 handle」是否同样存在）；
2. 跨设备同步（keyed mutex / fence）与真实渲染负载均未纳入。

**Gate A-M（macOS）：尚未进行**，不阻塞 Phase 1–2，见 ADR-0004。

另有一个前置缺口：Gate A 需要一个**对照物**才能判定「达标」，即 Phase 0 尚未采集的
现有 Reader 帧率 / 内存 / 翻页延迟基线。

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

验收平台范围：

- **Gate A 只以 Windows + macOS 为准**（A-W 已通过，A-M 待验）；
- Linux 跟随桌面路径，尽力而为，不阻塞 Gate A；
- Android / iOS **不纳入** Gate A，见「移动端最低适配」。

验收：

- 单张 4K/8K 漫画图稳定显示
- 平移/缩放不依赖 Dart bitmap rebuild
- 不发生不必要的 GPU→CPU→GPU 往返
- 能正确处理 resize、texture 销毁与重建
- Windows 通过（A-W）；macOS 待验（A-M，不阻塞）

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
- **CBR/RAR 读取**（v0.1 验收判据要求；`windcore` 当前**无任何 RAR 依赖**，需新引入。
  两个必须记账的点：RAR 解码以**文件路径**为前提、读不了流，本地核心要预留
  「归档项 → 临时文件 → 解码器」这条路径；UnRAR 许可证非 copyleft，但分发须附其条款文本。
  见 `docs/v0.1_acceptance.md` §4）
- 7z 仍属后续评估
- 大图 tile 化
- LRU GPU/CPU cache
- 当前页 + 邻页预取
- 双页共享/复用策略

## Phase 3 — Unified Upscaler

统一现有超分入口：**实现与模型集以 mImageViewer 的 Rust 核心为准**（`ort` + ONNX）。

```text
Upscaler
 ├── mImageViewer 的 ort 核心（Real-ESRGAN / Real-CUGAN / NMKD-Siax）  ← Windows 先行
 └── 各平台原生核心（macOS 后续转原生；Android 保留现有 ncnn，不新增模型）
```

设计原则：模型、执行后端与 Reader UI 解耦。

超分策略：

- 原图先显示，增强完成后平滑替换
- 当前页优先
- 邻页低优先级预取
- 可选择 1x / 2x / 4x
- 允许模型级别配置
- 允许 Original / Enhanced 即时切换

**验收只以 Windows 为准**：两套后端意味着模型集不同（它是 Real-ESRGAN / CUGAN / NMKD-Siax，
Breeze 是 RealSR / waifu2x），跨平台画质必然不一致，不做画质对齐。

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
- 输入设备适配 → **已提前到 v0.1**，见 ADR-0009 与判据 E（v0.1 只做键盘 / 鼠标 / 滚轮 / 触屏 / 区域；
  手柄 / 轨迹手势 / 轮盘留 schema 占位，运行时推迟到本阶段）

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

## 移动端最低适配（横切约束）

Android 与 iOS 不是当前投入方向，只做最低程度适配：

- 不实现 `ImageSurface` 的 native texture 后端；
- Reader 继续使用现有 `photo_view` + Flutter Image 显示链；
- 保留既有超分能力（iOS：CoreML；Android：ncnn/Vulkan/waifu2x CLI），不新增模型；
- 只保证编译通过、既有功能不回归；
- 移动端问题不阻塞桌面端 Gate，也不参与 Gate A/B 判定；
- 若日后确实需要 GPU 路径，独立立项重新评估（`wgpu` 原生支持 Android Vulkan，缺的是 Flutter 侧 surface 桥）。

代价与对策：桌面与移动端会长期并存两条显示实现，页面尺寸计算、缩放语义、超分注入时序可能在两端产生差异行为。需把显示层抽象成同一套上层语义（见 `docs/RESEARCH.md` R5）。

## 明确不做

- 不做 v0.1 冻结线之外的任何能力（在线源 / OCR 翻译 / 上色 / Anime4K / 视频，见 ADR-0008）
- 不引入 GPL-3.0 源码（Venera-SSR / ntrn），也不为此把仓库改为 GPL
- 不为省掉一次上屏拷贝去 fork `wgpu-hal`（Gate A-W 实测：4K 单页 0.348 ms，占帧预算 2.1%）
- 不把 mImageViewer 的显示管线照抄进来（decode → CPU RGBA → `load_texture`）
- 不先重写整个 Breeze UI
- 不先迁移到 Mangayomi
- 不先兼容所有插件协议
- 不先做 Web 版本
- 不为 Android / iOS 实现 GPU texture / external surface 后端
- 不把所有图片转成 Dart `Uint8List` 后再交给 Flutter
- 不在没有 PoC 数据的情况下宣称「追平 mImageViewer」

## 决策门

### Gate A（已按 ADR-0004 拆分）

- **Gate A-W（Windows）：已通过。** Rust/wgpu → GPU texture → Flutter 合成链跑通，证据见 `docs/gate-a/README.md`。
- **Gate A-M（macOS）：尚未进行。** 等价验收待做，**不阻塞 Phase 1–2**，是一笔显式技术债（本机无 macOS 机器）。
- 旧表述「Gate A 在 Windows 与 macOS 均达标才进入 Phase 2」**已废弃**。
- Linux 不参与 Gate A；Android / iOS 不在范围内。

### Gate B

超分能够以可接受的 latency 进入显示链路，才进入大规模 Reader 重构。

### Gate C

桌面端稳定后再做 WebGPU backend。

### Gate D

Reader engine API 稳定后再接 Xiranite。
