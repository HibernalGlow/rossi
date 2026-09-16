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
- [x] **vendor 检出**（ADR-0007，2026-09-16 完成）：`vendor/mimageviewer/` 直连**原版上游**
      `MikageSawatari/mimageviewer`（`.gitmodules` 记录上游 URL），gitlink = `1fd6f863`，
      子模块与上游零漂移。初版检出曾指向个人 fork `HibernalGlow/neoxide`，
      因该 fork 不会被维护而改回上游（丢掉的只是 UI i18n 层，不在复用范围内）
- [x] **vendor spike**（ADR-0005 / ADR-0007）—— **2026-09-16 完成**，结论见 `docs/phase0-vendor-spike.md`：
      `src/` 467 个 `.rs` 里 **183 个碰 egui**，其中 **92 个名字不像 UI**（按目录切不出「核心」）；
      但 11 个复用种子里 8 个干净，**剪掉 9 个直接脏依赖**即可自洽；
      path 依赖的 `[patch.crates-io]` **不传递、且静默**（实测解析到 crates.io 最新版，不报错）

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

4. **判据 C 的量级问题已用真实漫画量化**（`docs/v0.1-local-core.md` §12）：单页
   44.8 MPix 的 JPEG，全尺寸解码 193–332 ms、RGBA 位图 179 MB；即使只解码到 800 px
   也要 72 ms —— 而判据 C 的预算是 **p95 ≤ 16.7 ms**。即「CPU 解码 → Flutter 上屏」
   这条路在数量级上就不成立，**Phase 1 不是优化而是必需**；且解码必须落在翻页关键
   路径之外（预取 / 提前一页），否则单帧预算仍会被它吃掉。

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

- [x] **ZIP/CBZ 原位读取** —— 已实现于 `rust/local_core/src/zip_source.rs`
      （按中央目录下标寻址、每次重开归档不常驻句柄；见 `docs/v0.1-local-core.md`）
- [x] **CBR/RAR 读取** —— 已实现于 `rust/local_core/src/rar_source.rs`（v0.1 判据要求）。
      依赖落在新增的 `local_core` crate 上（`windcore` 本身**无任何 RAR 依赖**），
      用的是 vendor 检出里的 `crates/unrar-patched`。读取模型是**逐条目按需读**：
      打开归档顺序 `read_header`，命中条目读出字节、未命中 `skip()`，
      **不落盘、不建 session、不跨调用持有句柄**（ADR-0011）。四个必须记账的点：
  ① **读取模型是「逐条目按需读」**——打开归档顺序 `read_header`，命中条目读出字节、未命中 `skip()`，
  **不落盘、不建 session、不跨调用持有句柄**（ADR-0011）；
  ② 原表述「RAR 解码以文件路径为前提、读不了流」的正确边界是**归档本身**需要路径，
  不是条目字节——临时文件只在**嵌套归档**时才允许，v0.1 不实现嵌套；
  ③ UnRAR 许可证非 copyleft，但分发须附其条款文本。
  **solid / 加密 CBR 不在 v0.1 判据内**（报明确错误即可）。见 `docs/v0.1_acceptance.md` §4）
- [x] **Dart 侧接线（判据 A 的观察窗口）** —— `lib/debug/local_source_debug_page.dart`，
      入口为 设置 → 调试 → **本地来源读取（判据 A）**：打开文件夹 / CBZ / CBR、
      页列表 + 预览、会话数探针、逐页计时（判据「按需 seek vs 整段解压」的尺子）。
      它走的是 **Dart 兜底显示路径**（`Image.memory`，即编码字节过桥），
      **不是目标上屏形态、不能当判据 B/C 的依据** —— 判据 B/C 要等下面那条 GPU 上屏接线
      （**链路已接通，但帧时间尚未在 Release 下量**）。手测夹具由 `poc/local-samples/make_samples.py` 生成
      （真实截图 + 含两条拒绝路径的固实/加密 CBR）。见 `docs/v0.1-local-core.md` §11。
- [x] **GPU 上屏接线（Phase 1 收口）** —— `rust/gpu_present/`（cdylib `rossi_gpu_present.dll`）
      + `windows/runner/gpu_present_bridge.{h,cpp}` + `lib/gpu/gpu_present_{bridge,page}.dart`。
      链路 `解码 → wgpu 上传/渲染(letterbox) → GPU→GPU CopyResource → D3D12 共享纹理(BGRA8)
      → Flutter(D3D11/ANGLE) 合成`：**像素全程不过桥**，Dart 侧只拿到一个 `textureId`。
      入口：设置 → 调试 → **GPU 上屏（D3D12 共享纹理）**；判据读数是 `handleOpened > 0`。
      已验证两条：① Rust 侧端到端回读（底色占比／内容包围盒／页内采样／非全黑 四判据全过）；
      ② **真机引擎上 `handleOpened = 1`** —— 引擎确实打开了共享句柄，即"链路真通"。
      已知待办：启动期 `initMs ≈ 982 ms`（wgpu device + 管线）压在第一帧之前，**威胁判据 B**；
      判据 C 的帧时间分布尚未在 Release 下测。见 `docs/texture-bridge-integration.md`。
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
