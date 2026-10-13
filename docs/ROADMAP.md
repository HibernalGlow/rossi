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
| OCR 翻译 | **已解冻（ADR-0018，2026-09-25）并已实现（逐页，2026-09-26）**：形态是**成品页**（检测→识别→翻译→擦字→回填）。落点 `rust/ocr_core`（rossi_ocr_core）+ `lib/service/ocr/*` + 顶栏每页一颗「译」芯片；产物按页落盘复用，构建在点芯片后异步进行、不进渲染路径，换画面走呈现器增强图轨（与超分互斥）。代码来源走 MIT/Apache 白名单（`xianscan-rust` / `manga-ocr-rs`），**不改仓库许可证**；实测选型见 `docs/REFERENCE_RESEARCH.md` §8.6，真机判据见 `docs/ocr-completed-page-acceptance.md`。一期不做：整本批量、真竖排、拟声词、上色、Android / iOS。<br>**提速**：三段线程数 / 会话跨页复用 / 擦字边长 768 已落地；识别段还剩一条 **ADR-0019（提案）** —— 目标定在 encoder（占 66–69%），攒批的等价性已证（逐位相同），收益待空载复跑，闸门 0.7 倍 |
| 上色 | 不进：GPL 参考实现只能读不能抄，且只在黑白页有意义。与 OCR 共用「页后处理」位，但 ADR-0018 **不代为解冻** |
| Anime4K | 参考实现 GPL；超分统一以 mImageViewer 的 `ort` 核心为准 |
| 视频播放 | **已解冻（ADR-0016）**：形态是「一页可以是视频」，引擎用 media_kit / libmpv，功能并集见 `docs/video-playback-spec.md` |

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
      + `windows/runner/gpu_present_bridge.{h,cpp}` + `lib/gpu/gpu_present_{bridge,page}.dart`
      + **Reader 层** `lib/reader/`（`page_source` / `local_page_source` / `gpu_present_controller` /
      `image_surface`）—— 后四个把「页来源」「就绪状态」「显示节点」从调试页里拆了出来。
      链路 `解码 → wgpu 上传/渲染(letterbox) → GPU→GPU CopyResource → D3D12 共享纹理(BGRA8)
      → Flutter(D3D11/ANGLE) 合成`：**像素全程不过桥**，Dart 侧只拿到一个 `textureId`。
      入口：设置 → 调试 → **GPU 上屏（D3D12 共享纹理）**；判据读数是 `handleOpened > 0`。
      已验证六条：① Rust 侧端到端回读（底色占比／内容包围盒／页内采样／非全黑 四判据全过）；
      ② **真机引擎上 `handleOpened = 1`** —— 引擎确实打开了共享句柄，即"链路真通"。
      ③ **呈现器异步创建**：`create` 只起线程就返回（三态 `loading/ready/failed`），
      启动期不再被那 ~1 s 压住；就绪前 Dart 侧走 CPU 兜底路径，就绪后切到共享纹理。
      顺带量清了那 ~1 s 的构成：**瓶颈在 device 而不是管线**（核显上 2526 / 20 ms）。
      ④ **页来源已收敛成一份**（原待办）：`PageSource` 是唯一抽象，`local_core` 的会话 id
      只由 `LocalPageSource` 持有（顺带修掉了调试页从不 `close` 的会话泄漏），
      显示节点 `ImageSurface` 两条路共用一个来源；两侧页数由控制器交叉校验，
      对不上就回落兜底而不是猜。**仍未统一的只有解码器**，那是"像素不过桥"的必然结果。
      ⑤ **显示节点已从调试页里换出来**：「就绪了就切过去」那套判断原本散在调试页里，
      现在收在一个 `ImageSurface` —— 它自己维持与 native 侧状态一致（注册的纹理、打开的是
      哪一份、呈现的是第几页、目标多大），调用方只给"哪一本、第几页"。两条路共用一个来源：
      就绪前落 `RawImage`、就绪后落 `Texture`，外面不替它排序（真机实测 `通路 = cpu→gpu`）。
      ⑥ **Release 配置下的打包已复验**（2026-09-17，原待办）：`flutter build windows --release`
      通过，`rossi_gpu_present.dll` / `dxcompiler.dll` / `dxil.dll` 均已落位。复验本身**查出过
      一个真问题**——上一份 Release 产物里两个 DXC DLL 是缺的，因为**在 Debug 下改的 CMake
      拷贝步骤不会自动追上已经存在的 Release 目录**。同时确认 `rossi_gpu_present.dll` 在两个
      配置下**是同一份 release 产物**（profile 在 CMake 里写死），故判据 C 的 GPU 侧不受 debug 污染。
      判据 C 的帧时间分布尚未在 Release 下测 —— **产物已就绪，可以开始量**。
      见 `docs/texture-bridge-integration.md` §3.6、§6.2、§7。
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
- 切换提示 Toast（迁移规格 N-17）→ **已采纳（2026-09-20）**：工作台新增「控制面板」，
  首卡为「切换提示」—— neoview `SwitchToastCard` 的 T3 重建（触发开关 + 书/页模板 + 变量表 + 测试提示），
  运行时是 `SwitchToastService` 听 `ReaderSessionCoordinator`，模板引擎与上游
  `renderReaderSwitchToastTemplate` 逐条对照（判据 `test/workspace/switch_toast_test.dart`）。
  **上游不搬部分的口径**：外观摆位由「设置 → 提示样式」（`ToastSettingState` 九宫格）统一负责，
  卡片不再重复一套窗口 X/Y 摆位；`enableAction`（按键操作）在 Rossi 还没有统一挂点，
  留待本阶段输入绑定运行时（ADR-0009）补齐后接入。
  `enableBoundaryToast`（边界翻页）已接入（c41995ff）：判据是「loaded 范围到尽头且没有下一话可续」，
  横翻越界与键位/上下翻页两条入口各自在 `row_mode` 与 `ReaderActionController` 上挂。
- 阅读设置搬进「控制面板」→ **已完成（2026-10-03）**：超分 / 翻译 / 画面调节三节从「阅读设置」面板
  抽成公开 section（`lib/page/comic_read/widgets/settings/sections/`），面板与工作台卡片渲染
  **同一份** widget。存储本来就不在面板里：超分与翻译是 `RealSrSettings` / `OcrSettings`
  （SharedPreferences + 各自的 `ChangeNotifier`），画面调节是 app 级 `GlobalSettingCubit`
  —— 所以两边**零同步代码**，拨哪边另一边当场跟着变。
  完整设置（端点 / API Key / 术语表 / 权重、NCNN 模型下载与导入）走 `OcrSettingsBody` 与
  `RealSrModelManagementSection`：设置页退成壳，卡片就地展开同一份正文（卡片弹不掉路由，
  给它一条「去设置页」等于没有出口）。
  「没开书」时「本书超分」那颗**灰显 + 一行说明**，不是消失；顺带修掉
  `activeLocalBook ?? keyFor(…)` 在「本地书上再 push 一本在线书」时把覆盖写到上一本书上的串书 bug
  （判据改为只信 `ReaderSessionCoordinator`）。平台判不动的卡（翻译在 Android / iOS）
  留壳 + 「仅桌面」tag + 不吃点击，不整张从图标轨消失。
  判据：`test/workspace/control_panel_settings_cards_test.dart`。
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

## 提示个性化（ADR-0020，2026-10-08 已落地）

立项症状是可定位的一条 bug，不是观感：自动同步的成功分支过 `syncNotify` 门禁、
**失败分支裸奔**（改造前 `navigation_bar.dart:478` 过 / `:485` 不过），于是同步配错或断网时每 5 分钟敲一次且关不掉。

交付的三层：

- **判定层** `lib/service/notify/`：`NotifyGateway`（rxdart `PublishSubject` 传输 + 同步门禁与节流）
  → 唯一渲染器（`main()` 里 `attachToastRenderer()` 挂一次）。
  `widgets/toast.dart` 四个 `show*Toast` 签名未动，约 322 处调用点零改动；
  `ToastEvent` 与 eventBus 那一跳、根页面那条 2 秒手写去重，一并删除。
- **事项登记表** `NotifyTopic`：`actionFeedback`（谁也都关不掉，否则按钮看起来是坏的）/
  `ambient`（总闸 + 逐事项 + 节流窗口，八条）/ `selfManaged`（阅读器切换提示，真源仍在 `SwitchToastSettingState`）。
  合并键是「事项 + 标题 + 正文」，被窗口压掉的条数挂到下一条尾部；不排总结弹窗。
- **存储** `NotifySettingState`（全局设置块的一个 part）：只存用户的**偏离**，
  稳定字符串键（枚举键会在云同步里 `$enumDecode` 抛），默认值住在登记表。

配套：15 处裸 SnackBar 收编进同一入口（量过——没有一处带 `action:`，不丢按钮能力）；
`syncNotify` 退役（老载荷里多出的键被 `fromJson` 忽略；关过它的人升级后「自动同步完成」会回到开，一次性代价）；
设置 → 提示个性化（八项 + 总闸 + 恢复默认），入口副标题读的是当前真状态。

判据：`test/service/notify_gateway_test.dart` 12 条（含阳性对照，以及一条**源码哨兵**——
钉住 `_autoSync` 的两条腿都过网关、方法体内不得再出现裸的 `show*Toast`，防同类漏法复发）。
`test/workspace/switch_toast_test.dart` 的收信方式改为挂在网关出口上（原来听的是 eventBus 的 `ToastEvent`）。

**本轮明确不做**（理由与后果都写在 ADR-0020）：系统通知栏那一路不动 → 关掉「下载完成/追更」只安静应用内那半条；
不做前台/后台路由；`notifySetting` 不进云同步名单；不换 `toastification` 当渲染层。

## 导航壳换新（ADR-0021，2026-10-09 已落地）

用户点名的诉求：把 Gilberta 里对 FlClash 优化过的**桌面侧栏**与**移动端 Dock** 搬来直接用，
连**自定义导航**一起；追加三条 —— 窄屏自动切移动端、做成可开关、窄屏阈值可自定义。

交付的形态：

- **桌面 / 平板**：左列 `NavigationSidebar`（Arc 化，收起时 48 px、展开 220 px，
  够宽就地撑开、不够宽走浮层）。底部是**底部快捷区**（默认：打开本地漫画 / GPU 上屏 /
  搜索 / 自定义导航）—— 原来挂在 `NavigationRail.trailing` 的那几颗按钮有了新家。
  **2026-10-10 起画成一只竖排分组槽**（`ActionGroup(axis: Axis.vertical)`，图标键 + tooltip）。
- **移动端 / 窄屏**：底部 `NavigationDock` 悬浮胶囊，选中态是一颗在目的地之间弹跳的
  lens（`SpringCurve` + 半隐式欧拉弹簧），可拖拽滑选、惯性投射、两端橡皮筋、
  指针悬停磁吸与视差。底部快捷区 2026-10-10 起直接横排在胶囊尾部
  （`ActionGroup(axis: Axis.horizontal)`；清单为空时整槽不出现 ——
  先前「尾部 FAB 弹底部弹层」的那支已退役）。
- **两支各自两段清单**，用户都能增删排序（`CustomNavigationDialog` 两张页签，
  每张里两段可拖拽列表 + 一个待添加池，每次编辑立即落进全局设置）：
  - **主区**：页面与动作混排，顺序即显示顺序；
  - **底部快捷区**（2026-10-10 追加）：**只放动作**，藏得掉、排得了序 ——
    这一块过去是写死的固定区，用户点名要它可编辑。

  条目有**两种**：**页面**（书架 / 发现 / 更多 / 旧首页 / 旧排行）与**动作**
  （工作台 / 打开本地漫画 / GPU 上屏 / 搜索 / **自定义导航**）—— 动作点一下推路由、
  **不换当前视图**，Dock 那颗 lens 留在原地。「自定义导航」本身也降格成一条普通动作：
  设置里已经有入口，没必要钉在侧栏底部（用户 2026-10-10 提的）。
  两段互斥（主区已有的不在底部再出现一次）；底部那段的出厂值是 `null`（= 没设置过，
  用出厂那四条），所以老用户读到的仍是与改造前一致的那一块。
- **开关与阈值**在「设置 → 外观 → 导航栏」：侧栏开 / 侧栏展开 / Dock 开 /
  窄屏自动切 / 窄屏阈值（滑块 320–1600，可恢复默认）。

判据：`test/widgets/navigation_pure_test.dart` 22 条（阈值的开闭区间、越界夹取、
平台能力先于宽度、两段清单的容错、主区「两条页面」的下限、底部那段的 `null` / `[]`
之分、动作与页面混排、排序），`test/widgets/navigation_shell_test.dart` 5 条
（侧栏 / Dock 能挂起来能点、点动作不换页、`extendBody` 那条「内容铺到屏幕底部 +
拿到底栏高度」的框架契约、弹窗两段都在且能搬能藏），以及 2026-10-10 起的
`test/widgets/action_group_test.dart` 5 条（横竖两档分组槽的几何：槽厚 / 槽壁 /
组内间距 / 竖排不锁高不溢出 / 槽真的画了底色）。
组件动效不在这里 —— 那要真帧，`dart analyze lib/` 是这一轮的编译口径（0 error）。

## 工作台与书架的 UI 统一（2026-10-10，ADR-0021 延伸）

用户拿 FlClash 截图点名的四件事，全部围绕同一只组件收口 —— `ActionGroup`
（`widgets/action_group.dart`，FlClash 药丸槽的移植，GPL 边界同 ADR-0021）：

1. **书架页右上角**：筛选（桌面）与「放大镜 + 滑块」（移动）装进分组槽，
   槽底色与左侧胶囊 tab 同为 `surfaceContainerHighest @ 50%`；左侧 tab 不动。
2. **侧栏底部 / Dock 尾部**：同一份清单、同一只槽，只换 `axis`（见上节）。
3. **工作台「书签」「阅读历史」两面板内部**：共用的 `ShelfListToolbar`
   从「只靠间距分级」改成**两只下沉槽**（「怎么看」一组 + 导入导出一组）；
   书签面板的列表轨两颗键换 `ActionIconButton` 并装进槽。顺手修了
   没有时间线档时「排序 ↔ 搜索」叠出两个组内间距的旧账。
4. **文件管理器操作栏**：主工具组（视图 / 排序 / 搜索 / 文件树 / 穿透 / 多选）
   与「更多」组各装一只槽；`FileManagerToolbarMetrics` 改为转发
   `ActionGroupMetrics`（常数只此一份），三个旧类名降为 `typedef` 别名，
   调用点零改动。

**弹出菜单动画统一（2026-10-10 晚间修订）**：第一轮曾把手搓的 `FluentPopupMenu`
（淡入 + 从锚点缩放）铺到全部弹层 —— 用户指出那不是 FlClash 的动画。
**原文搬入 `lib/widgets/common_popup.dart`**（FlClash `popup.dart`，GPL 同源）：
`CommonPopupRoute` 的托盘从锚点胶囊沿弧线飞出、长成卡片，内容在里面缩放 /
淡入 / 由糊变清，关闭先收缩再飞回（iOS 26 菜单手感）；`CommonPopupBox` 负责把
触发键拍成快照随托盘一起飞；`CommonPopupMenu` 支持多级原地展开。已接入
**泳道栏头 ⋮（左键 + 右键两条路）与文件管理器工具栏的视图 / 排序 / 更多 /
主页 / 路径操作五个菜单**。面板级菜单（`panel_tab_strip` / `lane_panel_host`）、
书架文件夹页与漫画详情的弹层还在 `FluentPopupMenu` 上，是后续独立一步。

**图标语汇统一（2026-10-10，晚间补齐）**：动作面上的 Material 图标换成自绘 glyph
（`AppGlyphs` / `GlyphIcon`，与侧栏同一套形状语言）：书签·历史面板工具栏、
书架页右上角、书签列表轨、文件管理器工具栏（含导航五颗键与掌形控件）、
泳道栏头三颗键与紧凑轨、泳道「更多」菜单、卡片位置菜单与书架条目右键菜单。
**第一轮对词表缺的语义留过 Material 兜底，用户否决（不许新旧混用）** ⇒
按词表画风新增 10 个符号（`arrowForward` / `home` / `folder` / `book` / `tree` /
`passThrough` / `fold` / `unfold` / `rowsTwo` / `resize`，见 `app_glyphs.dart`
尾部「本仓新增」），动作面上的 Material 兜底清零；时间线用词表既有的
`clock`、停靠左右用 `columnsTwo`、展开用新 `unfold`。**约束写进词表注释：
词表已有同语义符号时复用旧符号，不许同一语义长两颗图标**。视图模式图标
词表 `LibraryViewModeX.icon` 保持 `Glyph` 型，文件管理器与书架共用。

判据：`test/workspace/shelf_list_toolbar_test.dart` 14 条、
`test/widgets/action_group_test.dart` 5 条、
`test/workspace/lane_more_menu_test.dart` 11 条（弹出器换 `CommonPopupMenu` 后
重写 finder，项集与分派断言逐条保留）、`lane_header_fit_test.dart` 5 条、
`top_chrome_test.dart` / `layout_persistence_test.dart` / `swimlane_runtime_test.dart`
随栏头图标 glyph 化同步换 finder。`dart analyze lib/` 0 error（17 条基线 info）。
顺带修复（10-03 滚动跟随判据踩出来的框架断言）：
`page_list_card.dart` 详细列表行给 `ListTile` 套透明 `Material` ——
带 active 底色的 `Container` 包着 `ListTile` 会报
「ListTile background color or ink splashes may be invisible」。

**这一轮把状态记账从「下标」改成「身份（id）」**：两支布局的清单能被用户改，
同一页在两边下标不同，记下标会在切布局或改清单时指到别的页上。动作进来之后这条
更要紧 —— 「当前页」的下标必须永远落在页面上。

**许可待决**：这批代码是 FlClash 的 **GPL-3.0** 正文，`LICENSE` 暂不改 ⇒
仓库当前处于**已知的许可不一致状态**。退出条件（转 GPL-3.0 / 撤出重写）与
「在决出之前不新增 GPL 源码」的栅栏写在 ADR-0021。

## 非破坏式显示处理层（ADR-0024，2026-10-14 立项）

用户对 mImageViewer 功能清单的逐条裁决放行了六项、明确否掉三项。
**裁决表、边界与理由一律以 [`adr/0024`](adr/0024-non-destructive-display-image-processing-tier.md) 为准**，
本节只登记阶段与验收，不复述决策。

核心变化是把 ADR-0008 那个「页后处理位」从**一次一档**改成**一条有序阶段链**：
`解码 → 非破坏式处理链 → 上屏`，链末端才是那份替代位图，
派生指纹覆盖「每档模型标识 + 参数指纹 + **档序**」。

**阶段 A — 链的形状 + 滤镜预设**（清单 4）

- [ ] 处理链建模：有序阶段列表 + 参数指纹 + 档序进缓存/内存索引键
- [ ] 11 项滤镜（亮度/对比度/伽马/色温/饱和度 + 灰度/反色/暖色/护眼 + 可调强度锐化 + 黑白对比增强），
      算法对照上游 `src/post_filter.rs`，**不移植 38 种全量枚举**
- [ ] 全局默认 + 单本覆盖，复用「本书超分」那套解析入口，作用域判定只有一个落点且在渲染路径上

**阶段 B — 画质增强**（清单 1、2）

- [ ] AI JPEG 降噪作为独立 **1×** 阶段：原图 / 仅降噪 / 仅超分 / 降噪→超分 四档
      （`ModelKind::DenoiseRealplksr` 已在 `rust/local_core/src/final_pipeline.rs`，
      先核它到底接没接后端，再决定是接线还是补阶段）
- [ ] 局部调整层复用上游 `crates/local-adjust-core`（实测无 UI 耦合），
      **不另写一份图层合成核心**；Dart 侧只做刷选遮罩与图层列表的编辑界面
- [ ] 后端不许静默回退：选了加速后端就要么用要么喊出来，实际用了哪条 EP 要看得见

**阶段 C — 专业工具**（清单 6、7、9）

- [ ] 图像分析模式（取色器 / 直方图 / 灰度查看 / 局部色差）落**开发者工具或高级设置**，
      读数必须来自链上那份真实像素，而不是另开一次解码
- [ ] 放大镜扩成「原图 vs 处理后」对比：分割线拖动 + 按住临时切回原图；
      那个「按住」要进操作绑定引擎，与轮盘/键位/触屏同一注册路径
- [ ] 页面信息面板：尺寸 / 格式 / 压缩类型 / 文件大小 / **当前页实际经过哪几档**，
      只披露回读得到的事实

**判据（每条都要证伪用例，这条链的失效模式是静默的）**：改一个滤镜参数 ⇒ 该页产物档名变；
降噪挪到超分前后各一次 ⇒ 两档不同名；参数改回原值 ⇒ 命中回旧档（不留孤儿档）；
「开了开关画面没变」必须能被一条测试抓住，而不是只断言「没报错」。

---

## 明确不做

- 不做 v0.1 冻结线之外的能力（在线源 / 上色 / Anime4K，见 ADR-0008）。
  已按同一流程解冻的三条不在此列：**视频页**（ADR-0016）、**OCR 翻译成品页**（ADR-0018）、
  **非破坏式显示处理层**（ADR-0024）
- **图像处理清单里被用户明确否掉的三条**（ADR-0024 §明确不做）：
  手动选区擦除与 AI 修复（清单 3）、非破坏式旋转 / 手动裁切 / 结果导出（清单 5）、
  图像处理的撤销 / 重做（清单 8）。局部调整层因此**没有 undo/redo**，
  误刷的恢复手段只有「删那一层」与「整页重置」两档 —— 这是被接受的代价，不是遗漏
- 不引入 GPL-3.0 源码（Venera-SSR / ntrn / comic-text-detector / manga-image-translator / Mekuru / Frank Yomik /
  Chimahon / mokuro / yomitan），也不为此把仓库改为 GPL。
  **权重按 ADR-0018 §决定 5 一律首下、不随包**；字体是 OFL 可随包，与权重是两回事
  > **例外（ADR-0021，2026-10-09）**：FlClash（GPL-3.0）的桌面侧栏与悬浮 Dock 已原文搬入
  > （`lib/icons/` + `lib/widgets/navigation/` 里那批有来源声明的文件），`LICENSE` 暂不改 ⇒
  > 仓库当前是**已知的许可不一致状态**。退出条件见 ADR-0021；
  > **在 A/B 决出之前不新增任何 GPL 源码**。上面这份名单其余部分照旧。
- 不为省掉一次上屏拷贝去 fork `wgpu-hal`（Gate A-W 实测：4K 单页 0.348 ms，占帧预算 2.1%）
- 不把 mImageViewer 的显示管线照抄进来（decode → CPU RGBA → `load_texture`）
- 不先重写整个 Breeze UI
- 不先迁移到 Mangayomi
- 不先兼容所有插件协议
- 不先做 Web 版本
- 不为 Android / iOS 实现 GPU texture / external surface 后端
- 不把所有图片转成 Dart `Uint8List` 后再交给 Flutter
- 不在没有 PoC 数据的情况下宣称「追平 mImageViewer」
- 不在「提示个性化」里管系统通知栏那一路（`flutter_local_notifications` / Android 通知渠道不动，ADR-0020 §明确不做 1）
- 不为省掉自研提示条而换 `toastification` 当渲染层，除非点名要做（ADR-0020 §明确不做 4：换了并不减少弹窗骚扰，代价是五端视觉无法本机回读）

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
