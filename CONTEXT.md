# Rossi

Rossi 是把既有成熟能力拼装成一个统一 Reader 的跨平台漫画阅读应用，以 Breeze 为基座。
本文件只定义词汇，不含实现决策——实现与取舍记在 `docs/adr/`。

## Language

### 外部参考与上游

**Breeze**:
上游项目 `deretame/Breeze`，本仓库的 fork 来源，也是在线的 QuickJS 插件运行时与插件生态的来源。
_See_: ADR-0002
_Avoid_: zephyr（那是它的 Dart 包名）、upstream（在需要区分两个 remote 时才用）

**neoview**:
`D:\1VSCODE\Projects\Xiranite` 下的 React / TypeScript 阅读前端。在 Rossi 中作**视觉与交互的参考**，
其**操作绑定模型**是 ADR-0009 的目标形态（但技术栈不取）。
_See_: ADR-0003、ADR-0009
_Avoid_: React UI、React 前端、migration target

**mImageViewer**:
`MikageSawatari/mimageviewer`——**Windows 11 独占的图片与漫画查看器应用**，v3.10.0 / MIT，
16 个 crate 的 Cargo workspace。它是 Rossi **本地能力的来源与标杆**。
它的两层身份容易混，必须分开说：`src/lib.rs` 存在，Cargo 会自动生成 lib target（`mimageviewer::run()`），
技术上可作依赖；但它在架构上是**单体应用**——一个 crate root 声明全部模块（含全部 `ui_*`
与 WIC / Shell / DPAPI / WASAPI 平台专属代码），依赖树里带 ffmpeg / pdfium / ort / tantivy，
以及三个被 `[patch.crates-io]` 替换过的 egui。
_See_: ADR-0001
_Avoid_: mImage、mImage core（这两个名字指向错误的粒度）

**ComicRD**:
`andrizan/comicRD`——Flutter + Rust 的桌面本地漫画阅读器，MIT，其 `crates/comicrd_core` 是一个干净的
可复用 crate。在 Rossi 中**只作参考实现**：不 vendor、不依赖、不进 Cargo。
它的 tile 布局、预取窗口、tile 字节缓存可作对照；**它的 RAR 做法（整章落盘提取）明确不采用**。
_See_: ADR-0011
_Avoid_: 用它表示「本地核心的来源」；也不要再说「用 ComicRD 做 Reader」

**上游同步**（upstream sync）:
Rossi 保留从 Breeze 与 mImageViewer 拉取上游改动的能力，但**不对齐**它们：允许破坏性变更，不向上游提 PR。
_See_: ADR-0002

**Venera-SSR**:
`Kiastr/Venera-SSR`——**Flutter + Rust 的多平台改版漫画阅读器**（含 android/ios/linux/macos/windows/debian）。
已实现本地 OCR 翻译、黑白漫画实时上色、Anime4K 超分、JavaScript 漫画源、WebDAV 同步。
Rossi 的 **上色 / Anime4K** 以其为能力参考（不是 neoview——neoview 的对应实现是 Web 侧）。
**OCR 的参考已经换掉**：ADR-0018 之后它的代码来源是 `xianscan-rust`（MIT），
排版回填读 `Koharu`，逐页开关与队列读 `Yomihon` / `Kototoro`；Venera-SSR 在这里只剩「问题定义值得读」。
**注意**：它是 **GPL-3.0**，见「许可边界」。
_Avoid_: venera（那是它上游的 Flutter 漫画阅读器项目名）、SSR（这个词同时指超分与它的项目名）

**ntrn**:
`AmeyKuradeAK/ntrn`——Next.js / React → Flutter 的 **CLI 转换工具**，v0.7.0。
在 Rossi 中的定位是**结构提取器**（出组件图 / 设计令牌 / 路由报告），**不是代码转换器**：
它 v0.7 只支持基础 JSX→Widget，样式（计划 v0.9）、状态（v0.8）、路由与 API（v0.10）均不支持。
**注意**：它是 **GPL-3.0**，作为命令行工具使用与复制其源码是两回事，见「许可边界」。
_Avoid_: 用它指代 React 迁移的产出

### Reader 层

**Reader**:
Rossi 自己的阅读编排层。它拥有会话生命周期、当前页、缩放与平移、翻页、**预取的执行**
（谁来解、解完存哪、淘汰谁）、进度、是否触发超分，以及 RenderBackend 的选择。
它**不**拥有解码与归档，也**不**拥有「该不该预取」这个判决——那在本地核心（见「预取判决」）。
_See_: ADR-0003
_Avoid_: 用它指 neoview 的 Reader 或 `lib/page/comic_read` 那两个东西；提到它们时必须带限定词

**本地核心**（Local Core）:
负责本地文件与压缩包的打开、页列举、解码、页元数据的组件。**所有权在 Rossi**；
Windows 上的实现以 mImageViewer 的源码为来源，macOS / Linux 上参照它重建可移植子集。
_See_: ADR-0005、ADR-0011（来源曾在 2026-09-16 当天一度改为 ComicRD，同日回退）
_Avoid_: mImage、ComicRD（它已降为参考实现，不再指代来源）

**适配层**（adapter crate）:
Rossi Rust 侧新增的薄 crate，把外部的 mImageViewer 源码包成 Rossi 需要的接口。
它**不**包含 mImageViewer 的 UI 与平台专属代码。
**「薄」是设计目标而不是已成立的事实**——取决于对方 `src/` 里多少模块引用了 egui。
_See_: ADR-0005

**逐条目按需读**（per-entry on-demand read）:
RAR/CBR 的读取模型：打开归档 → `read_header` 顺序推进 → 命中条目读出字节、未命中跳过；
字节直接进内存交给解码器。**不落盘、不建 session、不跨调用持有归档句柄**；
缓存只允许缓存**判定结果**（key = `path + len + mtime`），不允许缓存归档内容或句柄。
_See_: ADR-0011
_Avoid_: 归档会话（session）、归档句柄池

**降采样解码**（decode-time downscale）:
在解码出口就按目标宽度把位图缩小（`target_width` / `decode_rgba_scaled`），
而不是把原尺寸位图交给上层再缩。
**在「Rust 解码 → 过桥 → `decodeImageFromPixels`」这条路径上它不是画质选项，
是可用性前提**：一页 44.8 MPix 的原尺寸位图 170.8 MB，实测端到端 1526 ms 里
有 1260 ms 花在搬运而不是解码，砍像素量就是砍那 1260 ms。
_See_: `docs/v0.1-local-core.md` §5.3、`rust/local_core/src/bin/scale_probe.rs`
_Avoid_: 与外壳路径的 `cacheWidth` / `ResizeImage` 混为一谈 —— 那是「先全尺寸解、
再重采样」，解码成本砍不掉；降采样解码砍的是**解码之后**的搬运

**整章落盘**（chapter materialization):
曾被考虑、**已被否决**的 RAR 实现：首次访问 chapter 时把整章图片一次性提取到
`<app-data>/rar-sessions/chapter-<id>`，之后 probe / read 走磁盘。
唯一允许临时文件的场景是**嵌套归档**（内层必须先落地成路径才能被打开），v0.1 不实现嵌套。
_See_: ADR-0011
_Avoid_: 用「RAR 读不了流」概括这条约束——需要路径的是**归档本身**，不是条目字节

**预取判决**（prefetch admission decision）:
「现在该不该发预取、发哪几页」的判决，由本地核心的 `prefetch_policy` 出，
**带理由而不是一个 bool**（没翻过页 / 翻页静默且当前页已出图 / 3 秒兜底 vs 还没静默 / 当前页还在加载）。
它是**纯函数**：输入是时刻与计数，输出是判决 —— 不持有任何一页的字节或像素，
所以它的位置在本地核心而不违反「Reader 拥有预取」那条线。
**「让路」不是这个判决的一部分**：判决说的是「该不该**发**」，而「已经在跑的这一轮
要不要**停**」由宿主观测许可（有没有 High 在跑 / 有人在排队）后决定 ——
因为停不停取决于「解码器能不能并行」这种本机事实，不是本层的语义。
_See_: `docs/local-core-vendored-modules.md`、`docs/v0.1-local-core.md` §12.5、§12.6
_Avoid_: 在宿主侧再写一套「该不该预取」的判决 —— 那会让 `prefetch_policy` 的测试管不到真实行为

**页加载许可**（page load permit）:
本地核心的 `page_load_scheduler` 持有的**在跑 / 在等的请求数与许可**（总 6 张、其中 2 张
只给高优先级）。请求分两种**优先级**（用户正在等的 `High` / 可以等的 `Normal`）与两种**契约**
（相邻翻页 `Sequential` 永不互相作废 / 跳页 `LatestSeek` 作废同会话中还在排队的旧请求）。
它管的是**并发度**，不是页内容 —— 「预取占满许可、用户那一页排在后面」因此在结构上不可能。
**许可 ≠ 核**：预留席位只保证高优先级**拿得到名额**，不保证它**不与预取同时解码**。
对内部能并行的解码器，并发几张没问题；对 dav1d 这种一条流几乎不吃并行的（1→8 核 2.59×、8→16 核只再快 7%），
并发不是分核而是两边都慢（实测：公平分 8+8 各 340 ms vs 串行 252 ms；App 里两个 auto=16 线程的解码并发时，
翻页被饿到只剩 ~1 核，550–648 ms）—— 所以「别让预取与翻页同时解码」是**宿主侧**的责任，
不能指望许可模型替你解决（实测见 `docs/v0.1-local-core.md` §12.6）。
_See_: `docs/local-core-vendored-modules.md`、`docs/v0.1-local-core.md` §12.5、§12.6
_Avoid_: 与「预取判决」混用（一个是该不该发，一个是能同时跑几个）；也别把它当成缓存淘汰；
也别以为「有预留席位」就等于「不抢核」—— 上游在这个判断上翻过车（`app.rs:55196`）

**PageSource**:
Reader 唯一的页面来源抽象，把本地页与在线页统一到同一个接口。
_Avoid_: 图片源、图源（那是插件语境下的词）

**UI 迁移**:
从 neoview 提取**视觉语言与交互方式**，在 Flutter 里重建。**不含**任何业务实现或代码移植。
_Avoid_: 用它表示移植 neoview 的业务实现或代码

### 渲染与超分

**上屏拷贝**（presentation copy）:
Rust/wgpu 渲染出的纹理被复制到 Flutter 可合成的 native texture 的那**一次** GPU→GPU 拷贝。
实测成本：4K 单页 0.348 ms、4K 双页 0.70 ms、8K 双页 1.38 ms。
_Avoid_: zero-copy、upload（后者专指 CPU→GPU）

**ImageSurface**:
一页的**显示节点**：拿一个页面来源与页下标，按当前可用的后端把这一页画出来
（GPU 共享纹理 / CPU 兜底位图）。它拥有与后端一致的**呈现状态** —— 纹理句柄、目标尺寸、
那边打开的哪一份来源 —— 所以「拖窗口之后画面还在不在」「页码和画面对不对得上」
这类问题只在这一处有答案。它**不**拥有页面来源的生命周期，也**不**决定页码。
_See_: `docs/texture-bridge-integration.md` §2.3、§3.6
_Avoid_: 上屏组件、渲染器（那是 Rust 侧的 wgpu 呈现器）、Renderer（会与 SR backend 混）

**SR backend**:
真正执行超分的实现，例如 CoreML、ncnn、ONNX。
平台矩阵：**Windows 用 mImageViewer 的 ONNX（`ort`）核心**；其余平台**暂时**沿用 Breeze 现有后端
（macOS / iOS 走 CoreML，Android 走 ncnn）；**macOS 后续也转为原生核心**。
「是否需要按内容分工」（Real-ESRGAN 类做彩页 vs Anime4K 类做线条）尚未定。

**UpscalerController**:
Reader 内决定「哪一页、什么时候、用哪个 backend」触发超分的组件。

### 能力（v0.1 冻结线之外）

本节列的是**曾经**在冻结线外的能力。要进范围必须先改 ADR-0008 与 `docs/ROADMAP.md` ——
**视频页（ADR-0016）与 OCR 翻译（ADR-0018）就是走这条流程进来的**，上色与 Anime4K 仍在线外。

**OCR 翻译**:
在漫画页内检测文字区域、识别、翻译、**擦除原文并回填译文**的链路。
**已解冻（ADR-0018，2026-09-25）**，交付形态是**成品页**。
能力参考分三处，不再单指一个项目：代码来源 `xianscan-rust`（**MIT**，同 `ort` 栈）；
排版回填与竖排 `Koharu`（**MIT OR Apache-2.0**，但跑 LibTorch → 只读不依赖）；
逐页开关与任务队列 `Yomihon` / `Kototoro`（**Apache-2.0**，Kotlin → Dart 仍是重写）。
`Venera-SSR` 仍是**问题定义**的参考，但它 GPL → 只能读。
_Avoid_: 实时翻译（歧义：可指「边翻页边翻」，也可指「流式增量翻译」）

**成品页**（translated page）:
OCR 翻译链路的**产物**：擦掉原文、填入译文后的一张**替代位图**。
它是**可失效的派生物**，不是渲染路径的一部分 —— 原始解码图永远是真相，Reader 只读缓存、缺失时静默回落。
其缓存 key **必须把每一项影响产物的输入都编进去**（译文语言、翻译端点/模型、术语表版本、
检测/识别/擦字模型版本、字体版本、排版参数版本），少一项就是「换了模型页面还是旧的」那种静默错误。
_Avoid_: 翻译层、译文叠加层（一期不做叠加层）、烧图（口语，不精确）

**上色**（colorization）:
把黑白漫画页实时转成彩色的链路。能力参考 Venera-SSR（int8 轻量模型），同样是 GPL。
**它只在黑白页上有意义**，且必须能逐页开关。**不在 v0.1**；
与成品页共用「页后处理」位，但 **ADR-0018 不代为解冻**。

**视频页**:
Reader 中「一页不是一张图而是一段视频」的情形。**已解冻（ADR-0016，2026-09-19）**，
形态是「一页可以是视频」，引擎用 media_kit / libmpv，功能并集见 `docs/video-playback-spec.md`；
**不进入 v0.1 的可数判据**。
**PageSource 与 Reader 不得假设「一页 = 一张静态图」**——这个前提现在定型几乎免费，以后改很贵。

### 操作绑定（ADR-0009）

**动作**（action）:
Reader / 书架 / 全屏等**可被用户触发的最小行为单元**，以**稳定字符串 id** 命名（如 `reader.next-page`）。
它是操作绑定、右键菜单、工具栏共用的契约层。
**动作必须由注册表统一声明**（id + 显示名 + 分类 + 所属上下文 + 触发方式），
不允许以 controller 私有方法的形式存在——否则它无法被绑定、也无法被测试驱动。
_Avoid_: 命令（command，在绑定语境下指另一种输入来源）、快捷键（那是绑定不是动作）

**绑定**（binding）:
「一组输入 → 一个动作」的映射，是用户可编辑的最小单位。
一条绑定包含：动作 id、输入描述、所属上下文、是否启用、是否忽略重复。
_Avoid_: 快捷键、hotkey（这两个词会漏掉鼠标 / 滚轮 / 触屏那部分）

**输入描述**（input descriptor）:
绑定的**输入侧**，是一个联合类型，覆盖键盘组合键 / 鼠标按键 / 滚轮 / 触屏手势 / 画面区域点击，
并预留游戏手柄 / 鼠标轨迹手势 / 轮盘。
**schema 一次做全、运行时按子集实现**：因为用户一旦存了配置，改 schema 就要写迁移，
而运行时处理器可以逐个补且不动已存数据。
_Avoid_: key（太窄，会暗示只有键盘）

**上下文**（context）:
绑定生效的作用域，带**明确优先级**，且低优先级上下文可在高优先级上下文下被**隔离**。
没有优先级与隔离，绑定越多越互相打架——它是「高自定义」能成立的前提，不是可选项。

**冲突**（conflict）:
同一上下文内、两条绑定占用同一个输入。**冲突阻止保存，不是警告。**
只警告等于把问题推给用户，而用户没有能力判断哪条该让路。

**绑定包**（binding bundle）:
绑定表的可导出形态：JSON，带 `format` 标识与 `format_version`，用于换机 / 备份 / 分享。
**高自定义如果没有导出导入就不可迁移、不可恢复**，所以它与编辑 UI 同等重要，不是附加功能。

### 范围

**v0.1 冻结线**（scope freeze）:
v0.1 的边界 = **本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分**。线外的能力一律不实现。
它是目前唯一在真正裁剪范围的机制（「个人自用」不是）。
_See_: ADR-0008

**占位**（placeholder）:
对被推迟能力**现在只做、以后不做就会很贵**的那部分准备。当前两处**都已结束留白**：
① `PageSource` / Reader 不假设「一页 = 一张静态图」（视频）—— 由 ADR-0016 兑现；
② 页面渲染层的「页后处理」位 —— 由 ADR-0018 定型为「**一页 = 一张图，但这张图的来源可被替换**」，
后处理产出「替代位图 + 派生指纹」，不改 `PageSource` 形状、不引入「一页 = 图层集合」。
占位**不等于**预留公开 API——它只是不让架构把未来的可能性堵死；一旦某个能力真的要接进来，
那个位才从「不固化」变成「定型」，这两处就是两次这样的时刻。
_See_: ADR-0008、ADR-0016、ADR-0018

**v0.1 验收判据**:
v0.1 达标的四条硬条件：覆盖度（CBZ / CBR / 散图文件夹）、冷启动 ≤ 2 s、
翻页 `p95 ≤ 16.7 ms` 且 `p99 ≤ 33 ms` 且无 `> 100 ms` 单帧、连读三本 RSS 增幅 ≤ 5%
且纹理计数不单调上升。**判据用帧时间而非平均 FPS**，因为平均帧率会掩盖单次长卡。
完整定义与测量口径见 `docs/v0.1_acceptance.md`。

### 许可边界

**MPL-2.0（本仓库）**:
Rossi 与 Breeze 的许可证。它决定**哪些外部源码可以直接搬进来**，不只是法律形式问题。

**可直接抄**:
`mImageViewer`（**MIT**）——可原文拷入，只需保留其版权声明。
`xianscan-rust`（**MIT**）、`manga-ocr-rs`（**MIT**）、`manga-ocr` 与 `PP-OCRv4 det`（**Apache-2.0**）——
ADR-0018 §决定 1 的**代码来源白名单**，OCR 链路只从这几处取码。
`LXGW WenKai Lite`（**OFL-1.1**）——可随包嵌入，但**再分发必须附 `OFL.txt` 全文**，
且**不许自行子集化**（它的保留名书面特例只覆盖「未改源码的重编译」与「仅为 Web Font 交付」的子集）。

**只能读不能抄**:
`Venera-SSR` 与 `ntrn`（均 **GPL-3.0**）。GPL 源码进入 MPL-2.0 仓库会把整体分发拖成 GPL。
→ 「抄 Venera-SSR 的 OCR / 上色 / Anime4K」与「把 Rossi 整体改为 GPL-3.0」是**同一个决定**。
→ 但**算法与思路不受版权保护**：读它的实现、理解它的问题定义、自己重写，不触发 GPL。
→ `ntrn` 作为**命令行工具**运行（输出是自有源码的变换）通常不感染输出；复制它的源码不行。
同一类还有：`comic-text-detector`（GPL-3，2023 停更，**几乎所有 fork 的检测件都源自它**）、
`manga-image-translator`（GPL-3，Yakuyomi 的三个权重由它转换）、Yakuyomi（app 与 engine 均 GPL-3）、
Mekuru 与 `mekuru-ocr`（**AGPL-3**，网络条款连它的自托管 OCR 服务一起覆盖）、
Frank Yomik（根 AGPL / `client/` GPL）、Chimahon（GPL-3 + **逆向 Google Lens 私有 blob**）、
mokuro、yomitan（GPL-3）。
**权重与代码是两件事**：HF 上标 `apache-2.0` 不代表可随包 ——
`mayocream/comic-text-detector-onnx` 声明 Apache 但权重源自 GPL 项目，按脏处理；
`speech-bubble-segmentation` 与 `mit48px-ocr` 是 GPL-3；RF-DETR 那份是 `license: other` + Manga109 衍生。
`sieugene/yomikomi` **没有 LICENSE 文件** = 默认保留所有权利，连读都别引其数据。
_See_: ADR-0018 §决定 1 / §决定 5、`docs/REFERENCE_RESEARCH.md` §8.1 与 §8.6.1

### 平台与验收

**最低适配**（minimum adaptation）:
移动端（Android / iOS）在第一阶段的状态：保留现有 Flutter Image + CoreML / ncnn 链路，能编译运行，
**不新增功能、不参与任何验收**。任何移动端专属工作必须先写进 `docs/ROADMAP.md` 才允许动手。

**能力标杆**（behavior baseline）:
一个真实存在的成熟实现，用于定义「做对了是什么样」。Rossi 的本地能力以 mImageViewer 为标杆，
但**标杆的显示管线不照抄**：它走 decode → CPU RGBA → `ctx.load_texture`（20MP 26–58 ms/张、每帧限 1 张），
与 Rossi「禁止 GPU→CPU→GPU 往返」的目标方向相反。可对标的是归档 / 解码 / 缓存 / 超分，**不含上屏路径**。

**Gate A-W**:
Windows 侧的 PoC 验收：Rust/wgpu → GPU texture → Flutter 的合成链，性能与稳定性达标。**已通过**。
_See_: ADR-0004

**Gate A-M**:
macOS 侧与 Gate A-W 等价的验收。**尚未进行**，不阻塞 Phase 1–2，且是显式技术债。
_See_: ADR-0004
