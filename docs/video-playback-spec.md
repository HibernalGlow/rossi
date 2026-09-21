# 视频播放功能并集规格（neoview × mImageViewer）

建立于 2026-09-19，随 ADR-0016。本文是**实现与验收的对照表**：两个上游各自的视频能力，
逐条写明在 Rossi 里落在哪个文件、什么形态（沿用 `feature-migration-spec.md` 的 T1–T5 分类）、
以及未纳入项的理由。

模块位置：`lib/video/`（Dart 侧全部视频能力）。Rust 侧只有一处改动，见 §4。

## 0. 引擎选择

`media_kit`（MIT，libmpv 绑定，pub 上跨 Windows / macOS / Linux / Android / iOS 的播放器）。
不搬 mImageViewer 的 FFmpeg 解码器（70k 行、368 处 `cfg(windows)`、D3D11VA + DComp 上屏、
非 Windows 没有显示路径），而是把它的**引擎语义**映射到 mpv 属性上。
逐条映射见下表「mpv 落点」列。

## 1. 来自 neoview（形态 T3：纯逻辑逐行翻译，UI 在 Flutter 侧重建）

| 能力 | 上游出处 | Rossi 落点 | mpv 落点 |
|---|---|---|---|
| 媒体身份表（图片 / 动图 / 视频 / 文档页） | `domain/page/media.ts:17-152` | `lib/video/model/video_media_kind.dart` | — |
| 伪装后缀（`.nov`→mp4、`.wbp`→webp） | `media.ts:35,144-152` | 同上 `disguisedExtensions` | — |
| 用户扩展名别名 + 校验（≤128 条 / ≤16 字符 / 禁与图片重叠） | `media.ts:80-85`、`MediaSettingsCard.tsx:155-283` | `MediaKindOverrides.invalidEntries` + `VideoAliasRegistry`（设置里可编辑，见 `_VideoAliasTile`） | — |
| 「一页可以是视频」的路由 | `features/reader/PageMedia.tsx:41-47` | `read_image_widget.dart` 的 `isVideo` 分支 | — |
| 播放状态机（快照字段、注册栈、动作返回 bool） | `features/video/ReaderVideoController.ts` | `lib/video/controller/reader_video_controller.dart` | — |
| 倍速区间归一化（min≥0.05、step≥0.01） | `ReaderVideoController.ts:339` | `normalizePlaybackRateRuntime` | `speed` |
| 音量⇔静音联动（`muted ⇔ volume==0`） | 同上 | `setVolume` | `volume` / `mute` |
| 循环三态 list→single→none | 同上 | `ReaderVideoLoopMode.next` | `loop-file` |
| 播完接下一页 | `ReaderAppView.tsx:697` | `onListEnded` → `host.onVideoListEnded()` | `loop-file=no` + completed |
| 快进档（翻页输入重映射为跳转） | `ReaderInputActionExecutor.ts:180-190` | `remapPageTurnToSeekWhenSeekMode` | — |
| 点中间播放/暂停、点左右 1/4 ±10 s | `PageVideo.tsx` | `VideoPageSurface._tapZones` | — |
| 控制条自动隐藏 3 s、暂停/钉住/弹层开着时常显 | `PageVideo.tsx:29-71,174-181` | `_armHideTimer` + `panelsOpen` | — |
| 图钉持久化 | `videoControlsPinned` | `VideoSettingsStore` | — |
| 拖动条 + 悬停帧预览（160×90、夹 ±80 px、时间气泡） | `ReaderVideoControlOverlay.tsx:44-359` | `_ScrubBar` / `_FramePreviewBubble` | — |
| 速率弹层（滑杆 + 0.5/1/1.5/2 预设 + 1x⇄上次） | 同上 | `_RatePanel` | `speed` |
| 音量弹层（静音键 + 5% 步长 + 百分比读数） | 同上 | `_VolumePanel` | `volume` |
| 字幕弹层（轨选择 + 字号 0.5–3em + 5 色 + 底色 0–100% + 底部 0–30% + 「大号黄色」+ 重置） | 同上 | `_SubtitlePanel` | `sub-scale` / `sub-color` / `sub-back-color` / `sub-pos` |
| 滤镜三值 0–200% + 重置 | 同上 | `_FilterPanel` | `brightness` / `contrast` / `saturation`（÷2 映射） |
| A–B 循环（打点三次语义） | 同上（overlay 态） | `tapAbLoop` | `ab-loop-a` / `ab-loop-b` |
| 截图 PNG `screenshot_H-M-S.png` | `ReaderVideoPlayerUtils.ts:93-111` | `_screenshot` | `screenshot-to-file` |
| 只听声音 | — | `setAudioOnly` | `video=no` |
| 信息卡（时长/帧率/码率/视频编码/音频编码，缺字段显 `—`） | `ImageInformationCard.tsx:48-83` | `video_info_sheet.dart` | `container-fps` / `bitrate` / `video-codec` / `audio-codec-name` |
| 媒体进度 {position,duration,completed}、5 s 节流、ended/卸载补写 | `PageVideo.tsx:99-141` | `ReaderVideoController` + `VideoProgressStore` | — |
| 完成阈值 `duration - min(5s, 5%)`、恢复门槛 | 同上 | `VideoPlaybackProgress.isCompletedAt` / `restorePosition` | — |
| 归档视频物化（单条目 2 GiB / 总 4 GiB、singleflight、按等待者释放） | `ReaderSeekableMediaCache.ts:6-60` | `VideoMaterializer` | — |
| 抽帧帧缓存键 0.5 s + 100 条 LRU | `ReaderVideoPlayerUtils.ts:23-91` | `VideoFrameCache` | — |
| 单槽位进程调度（只保留最新待办） | `VideoProcessScheduler.ts:9-17` | `_SingleSlotScheduler` | — |
| 外挂字幕同名匹配（`video.zh-CN.srt`）+ 首条自动选 | 字幕管线（`docs/neoview-migration.md:2270-2282`） | `matchSubtitleNames` / `discoverSidecarSubtitles`；外挂轨以 `file:` 前缀**并入同一个字幕弹层**（选中归档内的字幕时先物化再挂） | `sub-add` |
| 只有当前页出声 | 上游无对应（Web 上没有双页同槽） | `VideoPageSurface.active`：双页槽位里非当前页不自动播放，掉出当前页时暂停并补写一次进度 | — |
| SRT/ASS/SSA → WebVTT、MicroDVD `.sub` 转换 | 同上 | `convertSubtitlesToWebVtt` + `convertSubtitleFileForEngine`：**只有 `.sub` 真的过这条转换**（mpv 解不动 MicroDVD），srt/ass/ssa/vtt 原样交给引擎 —— 绕道转换会丢 `sub-scale/sub-color/sub-pos` 这些样式控制 | `sub-add` |
| 视频档过滤（列表里只看视频） | `FolderTypeFilterBar.tsx:31` | 复用既有 FRB `LocalFileTreeNode.is_video` | — |

**泳道首击归属**：neoview `docs/neoview-swimlane-ui.md:56` 规定「点一个尚未激活的
Reader lane，那一次点击归工作台所有」。Rossi 用 `VideoPageSurface` 里的一层 `Focus`
实现同一语义：**没拿到焦点之前的那一次点击只激活、不执行**，否则用户在泳道里点一下视频
第一次永远是「暂停」，而他要的只是「把这页切过来」。

**画中画**：上游是浏览器的原生 PiP。桌面 App 没有等价的系统 PiP（mpv 也不提供），
Rossi 实现为**应用内置顶浮窗**（`_pip` 分支）——同一 `VideoController` 渲染到角落小窗，
可关可缩。这是等效替代，登记在此以免被当成漏做。

## 2. 来自 mImageViewer（形态 T1/T2 的纯逻辑 + T4 平台等效）

| 能力 | 上游出处 | Rossi 落点 |
|---|---|---|
| 视频扩展名白名单 | `folder_tree.rs:81` | `page_order.rs:VIDEO_EXTENSIONS`（与 Dart 表同源，并集含 `webm/m4v/ogv/3gp/flv`） |
| 传输命令面（open/play/pause/seek/seek_relative/seek_paused/step_frame） | `video/engine/actor.rs:37-265` | `VideoTransport` 接口 |
| 就绪闩（preroll 前不许操作进度条） | `video/engine/state.rs:23-118` | `VideoEnginePhase` + `_awaitFirstFrame` |
| 主时钟 / A-V 锚 | `video/engine/clock.rs:56-199` | mpv 内部时钟；暴露 `avDriftMs()`（`avsync`） |
| `is_seeking` 状态 | `mod.rs` | seek 置位 + 位置恢复前进后清位 + 2 s 兜底 |
| SAR 归一化 | `decoder.rs:1185 normalize_sar` | `VideoMetadata.normalizeSar`（单测覆盖） |
| 章节边界 | `decoder.rs:1594 boundary_starts_from_chapters` | `mpv chapter-list` → `VideoChapter` 画在进度条刻度上 + `jumpChapter`（`add chapter ±1`）配 `video.next-chapter` / `video.previous-chapter` 两条动作；无章节时动作判为「不适用」而不是跳到第 0 章 |
| 硬解开关 | `settings.rs video_hw_decode` | `MpvKeys.hwdec` = `auto-copy` / `no`，走 `VideoSettingsStore` |
| 去隔行 | `VideoPlayer::open(deinterlace)` | `MpvKeys.deinterlace` |
| 倍速不失真 | `audio_stretch.rs`（signalsmith-stretch） | mpv `speed` 默认 `audio-pitch-correction=yes` |
| 拖动条缩略帧的**容差最近帧**设计 | `video/thumbnail.rs` | `VideoFrameCache.nearest`（整数微秒键 + 有序表 + 每次请求独立容差）；**预览自带一路 headless 解码器**（同 `thumbnail.rs` 的独立 worker：自己的输入、自己的解码器），悬停先定位到鼠标所指的时刻再截图（`screenshot` 截的是当前解码位置，不先 seek 就是「划到哪儿都同一张图」）。**悬停只解帧，绝不碰主播放器的位置** —— 借主播放器 `seekPaused` 定位等于「鼠标划过进度条就把视频拖到那儿去」，落点归 Slider 的点击与拖动。seek 没落到目标附近就不给帧（宁可不显示，也不显示上一帧）。代价是预览期间多一台 mpv 实例，空闲 60 s 释放 |
| 视频→纯音频模式 | `video->audio` | `setVideoEnabled(false)` |
| `KeyAction::Video*` 键位面 | `keymap.rs:1752-1780` | `vocabulary.rs` 的 22 条 `video.*` 动作 + `ACTION_CATALOG`，执行体在 `video_action_dispatch.dart` |

## 3. 明确不做（T5）

| 项 | 理由 |
|---|---|
| 360° / 球面视频（`spherical_metadata.rs`） | 需要 v360 重投影，与「一页 = 一个矩形画面」的泳道模型冲突 |
| Anime4K / RealESRGAN 视频离线放大（`video/upscale/`） | Anime4K 在 ADR-0008 冻结线外，且那是离线批处理作业不是播放功能 |
| DComp 原生 presenter / 子 HWND 交换链 | media_kit 已经把帧注册成 Flutter texture，Rossi 的纹理桥是给静态图的单 `Owner` 路 |
| ~~波形进度条~~ | **已移出本表**：见 §2 末尾。解码走纯 Rust 的 symphonia（MPL-2.0），确实不需要也不引入 ffmpeg |
| 视频内字幕的自绘层 | mpv 的 `sub-*` 原生渲染在字序、时序、多轨上比自绘更稳，样式能力（字号/颜色/底色/位置/延迟）已覆盖 neo 的自绘项 |

## 4. Rust 侧改动面

`rust/local_core/src/page_order.rs`：新增 `VIDEO_EXTENSIONS` / `is_video_name` / `is_page_name`；
`zip_source.rs`、`zip_loader.rs`、`rar_source.rs`、`folder_source.rs` 的页判定从 `is_image_name`
换成 `is_page_name`。**没有新增 `#[frb]` 函数、没有改任何已暴露类型的形状** ⇒ 不需要 FRB 代码生成。
「这一页是视频」的判定在 Dart 侧按扩展名做，与既有「页身份 / 页内容分离」口径一致。

## 5. 验收状态

| 判据 | 状态 |
|---|---|
| `dart analyze lib/`（整个应用） | **No issues found** |
| 视频测试 `flutter test test/video/` | **61 条全部通过、0 skip**（其中 3 条「波形数据结构的降采样与区间换算」随那两个没人调用的接口一起删了 —— 整条列一次算完之后，那些分支没人走，留着只是假覆盖 **）**：媒体身份 / 别名登记表 / 状态机 / 循环与翻页 / A–B / 进度阈值 / 章节 / 字幕匹配与 SRT·ASS·MicroDVD 转换 / 抽帧缓存 / 波形数据结构 / 设置持久化往返 / 注册表跨语言一致性 / 中英文案覆盖，**再加七条 mpv 引擎探针，以及一条把 24 个视频动作逐条派发到执行器的覆盖测试** |
| mpv 探针 ①：出厂引擎的名字表 | **通过**。`Mpv.framework` 在 bundle 外 dlopen 不了（依赖全是 `@rpath/…` 且自身无 `LC_RPATH`），所以这条不加载它 —— 直接把产物里那份 mpv（实测 **0.36.0**）的 C 字符串读出来，逐个核对我写给 mpv 的属性名/命令名。**名单是从 `mpv_video_transport.dart` 现读的**（`MpvKeys` 常量 + `_get('…')` + `_cmd` 首位），不是在测试里抄第二份：抄的那份会失真成一个"通过"的假测试。名字写错在 mpv 侧是静默失败，静态检查和出包都问不出来 |
| mpv 探针 ②：属性活体回读 | **通过**。合成一个 2 s WAV，用真 `MpvVideoTransport` 打开，再逐条 `getProperty` 回读：倍率 1.75 / 音量 40 / `mute=yes` / `loop-file=inf` / `ab-loop-a=1.000`+`ab-loop-b=2.000` / 清除后 `=no` / `brightness=75`+`saturation=30`（neo 的 0–200% ÷2）/ `sub-scale=1.6`+`sub-pos=12` / `video=no` / `avsync` 可解析 / 暂停态 seek 不顺手开播。加载的是**系统 libmpv**（`MediaKit.ensureInitialized(libmpv:)` 显式传绝对路径；`LIBMPV_LIBRARY_PATH` 在测试 VM 里读不到），版本比出厂的 0.36 新 —— 所以这条证的是"语义与取值形状"，名字存在性由探针 ① 对出厂那份负责 |
| mpv 探针 ③：视频侧（元数据 / 逐帧 / 截图） | **通过**。片源是自己手写出来的 **231 KB 未压缩 RGB24 AVI**（`hdrl`/`movi`/`idx1` 三段，`mpv -v` 认它：`rawvideo 64x48 25 fps`）—— 不依赖任何外来素材。断言：`metadata` 报出 64×48 / 25 fps / 编码名含 `raw`、时长正好 1 s；**暂停态 `frame-step` 走 40 ms**（= 1/25 s）且不擅自开播；`screenshot-to-file` 落盘的是真图像（PNG/JPEG 魔数）。`lavfi://` 这条路试过，这份 libmpv 的 `protocol-list` 里没有 lavfi，放弃 |
| mpv 探针 ④：打不开的文件 | **通过**。指向一个不存在的 mp4，相位必须落到 `failed` 且 `failureReason` 非空 —— 兑现「视频是装饰，不该让一页读不下去」那句。这条是**修出来的**：原先 mpv 的错误在 `Player.open()` 的 await 期间就发完了，而 media_kit 的 error 是普通广播流，晚一帧订阅永远收不到 ⇒ 相位停在 `prerolling`，页面（`video_page_surface.dart:646`）于是给一个转个不停的圈 |
| mpv 探针 ⑤：海报那条路 | **通过**。`VideoPosterService` 用的是裸 `Player()`（页面树里没有 `Video` 组件），而 media_kit 给裸 Player 的默认是 **`--vid=no`**（`real.dart:2325`，只有 `NativeVideoController.create` 附着时才改回 `auto`，见 `media_kit_video/native_video_controller/real.dart:160`）⇒ 视频轨根本不选、`videoParams` 永远不来、`screenshot()` 永远 null，表现是「视频卡片从来没有封面」。这条断言「显式 `vid=auto` 就足够」，因此它同时也是那个修复的守门人。（断言里刻意把 `NativePlayer.test` 关回 false，否则前提就不成立了） |
| mpv 探针 ⑥：外挂字幕 | **通过**。同一份合成 AVI + 现场写的一段 SRT：`sub-add` 之后 mpv 的 `track-list` 里出现 `"type":"sub","external":true` 且 `decoder=srt`；`selectSubtitleTrack(null)` 后 `sid=no`，再按数字轨号选回去后 `sid=1`。**选择状态只能问 mpv（`getProperty('sid')`）—— media_kit 的 `state.track` 只记它自己最后一次设的值**，刚 `sub-add` 完时它仍显示 `auto`。这条顺手抓出两个真缺陷（下面 ⑫⑬） |
| mpv 探针 ⑥b：MicroDVD 转出来 mpv 认不认 | **通过**。现场写一个 `{0}{100}第一句|换行` 的 `.sub` → `convertSubtitleFileForEngine` → 断言产物以 `WEBVTT` 开头、`sub-add` 之后它成为第二条字幕轨、按号 `sid` 选得中。**这条值得验**：转换的动机就是「mpv 对 MicroDVD 不可靠」，而转换错了的症状 （挂上了但什么都不显示）比不认这个后缀更难查 |
| mpv 探针 ⑦：音轨与音画同步 | **通过**。合成源加了一条**交错**的 PCM s16le（8 kHz 单声道，每 40 ms 一块跟着视频帧走，`mpv -v` 报 `Audio --aid=1 (pcm_s16le 1ch 8000 Hz 128 kbps)`），于是「要有两条轨才看得见」的那半也活体了：`audio-codec-name` 进得了信息卡、音轨列表里只有真轨（`auto`/`no` 伪轨已被滤掉）、`aid` 关得掉选得回、`avsync` 有值、**「只听声音」开→关之后画面回得来**。写这条探针的过程本身抓出一个缺陷（下面 ⑰）：只验「关」方向的断言是**假绿** |
| 波形过桥（Dart→FRB→Rust） | **通过**（`test/video/waveform_bridge_probe_test.dart`，3 条）。之前这段只能靠真机看进度条底下有没有柱子：现在自己写一个「前半响后半轻」的方波 WAV，过桥取整条列，断言 2 s/0.1 s ≈ 20 格、归一化后峰值正好 1.0、前后段均值差 4 倍以上、同文件第二次命中缓存（**同一实例**）、`clearCache()` 之后确实重解，以及坏文件退化成 `VideoWaveformStrip.empty` 而不抛。**顺带这条还是「仓库根那份 `rust/target/release/libwindcore.dylib` 与 `frb_generated` 的 content hash 对得上」的守门人** —— `RustLib.init()` 的不一致已经咬过两次，症状是启动后一片黑且零线索（见 `lib/main.dart` 的注释）；本轮它就红了一次，修法是 `cd rust && cargo build -p windcore --release` |
| 真实编码探针（mkv/mp4） | **通过**（`test/video/mpv_real_sample_probe_test.dart`，3 条）。前面那些探针的片源都是合成的，有几件事问不到；这里用**系统 ffmpeg 现场生成**一个 h264 + aac + 两章 + 字幕的 mkv（外加 mp4 变体；**没有 ffmpeg 就整条 skip**，样本是工具链产物、不进仓库），于是补齐了三块：① **章节** —— `chapter-list` 解出两条且 `at` 是 1500 ms 而不是 1 s（缺陷 ⑨ 的回归判据），`jumpChapter(±1)` 真的跳到 1.5 s 再跳回开头；② **真解码器路径** —— `video-codec` 含 264、`container-fps` 25、`audio-codec-name` 含 aac、关键帧结构下**定位到 3.0 s 落在 ±150 ms**、`screenshot-to-file` 出的是真图、音轨一条且无伪轨、`deinterlace=yes` 与 `hwdec=auto-copy` 都落到引擎上；③ **波形过真实容器** —— symphonia 解 mkv/mp4 里的 aac 各拿满 40 格。`current-hwdec` 这里测不了（libmpv 无渲染面时 `vo=null`），所以「到底走没走 VideoToolbox」留在验收 D8 |
| 页序判定层（Rust 侧，3 条新测） | **通过**。`is_video_name` / `is_page_name` 之前**一条测试都没有** —— 而「一页可以是视频」的判定就落在这两个函数上，两种失败形状都很难查（页序里没有它 → 用户以为书少了页；把它当图片 → 翻到那页报解码失败）。现在：① 视频后缀算页但**不算图片页**（含大小写、子目录、`.nov` 伪装、不认识的格式两档都不算）；② **跨语言表漂移守卫** —— 从 `lib/video/model/video_media_kind.dart` 现读 `videoExtensions` 与 Rust 的 `VIDEO_EXTENSIONS` 比集合（表头注释早写了「两边必须一致」，这条把它变成断言）；③ `folder_source::enumerate` 真实混排目录 → 3 页、自然序、中间那页是视频 |
| 动作派发覆盖（24/24） | **通过**。逐条对 `kVideoActionIds` 派发并验「接到执行器」：±10 s 走 `seekRelative`、逐帧走 `stepFrame(±1)`、倍速三键走 `setRate`/`toggleSpeed`、音量/静音、循环轮换、A–B 打点、字幕轮切与延迟、纯音频、章节跳转、UI 两条走 `uiActions` 广播。**判据表少一条 id 就失败** —— 注册表里加动作而派发器走进 `default` 静默吃掉键，是这类系统最难查的形状。同一轮还断言「没有活动视频时一条都不吃」 |
| `cargo test -p rossi_local_core` | **360 passed / 0 failed**（含页序改名、24 条视频动作注册表、视频档键位优先级断言，以及 `wave_peaks` 的 5 条：格数、绝对刻度可比较、窗口不越界、坏文件报 Err 不 panic、前后响度落差） |
| 死接口清理 | 删了 6 个「定义了但没人调」的东西：`VideoWaveformStrip.fromPcm`/`binsFor`（PCM 源换成 Rust 侧峰值后不再存在）、`VideoMaterializer.cachedBytes`/`cachedItems`、快照里永远为 null 的 `buffered`、`VideoLabels.subPresets`、自绘字幕时代的 `buildVttCueStyleCss`；`VideoPosterService.shutdown` 与 `VideoWaveformService.clearCache` **不删而是接上** —— 挂进 `LocalReadSession.dispose()`，因为海报服务里挂着一个 mpv 实例、波形缓存的键是物化后的临时路径，退出阅读后必然失效 |
| 死接口清理（第二遍） | 动作派发覆盖做完之后再扫一遍「公开却没人调」的东西，删掉 5 个 + 2 个只写不读的字段：`ReaderVideoController.resetFilter`（滤镜重置走的是 `onChanged(VideoFilterState.neutral)`）、`setSeekMode`（派发只用 `toggleSeekMode`）、`MpvVideoTransport.mpvUri` / `.openOptions` 与它们的 backing `_openUri` / `_options`、`VideoMaterializer.rootForTest`（连带 `_rootOverride`，测试从来没用过它）。**保留**：`clampPlaybackRate`（`setPlaybackRate` 内部在用）、`isSeeking`（测试在用）、`markedPointA`（控制条读它画「已标 A」中间态） |
| 海报队列 | `_serialize` 原本是 `while (_busy) await delay(40ms)` 的空转轮询（mimage 的贡献规范明确禁这一型等待），换成串行尾指针队列，并保证**一次失败不会把后面排队的所有任务永久卡住** |
| FRB 生成 | **已跑** `flutter_rust_bridge_codegen generate`（2.12.0，与运行时同版）：新增 `localVideoWavePeaks` 过桥，`cargo check -p windcore` 与 `dart analyze lib/` 均干净 |
| macOS 出包 | **通过**：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug` 产出 `build/macos/Build/Products/Debug/Breeze.app`，包内含 `Mpv.framework` + `media_kit_video.framework` + `media_kit_libs_macos_video.framework` ⇒ libmpv 真的链进了产物。（先前记的「本机没有 Xcode、出不了包」是错的：Xcode 在装着，只是 `xcode-select` 指向 CLT）。加 A–B 单位修复后**再出一次包仍然 `✓ Built`，退出码 0** |
| `cargo check -p rossi_local_core` | **通过**（含本次的 `page_order.rs` / `vocabulary.rs` 改动） |
| 运行时行为（真机点一遍） | **引擎语义已验（上面两条探针），画面与声音这一层未验** —— 也就是「有没有画面、声音走哪个设备、拖动手感、字幕渲染观感、进出泳道时音频有没有漏关」还得开一次 App 才算数 |
| 过程中真查出来的缺陷 | ① ASS 字段数判成 11（正常字幕行整行被丢）；② 快照未从 transport 打底 ⇒ 拖不动进度、进度永不上报；③ `completed=false` 不复位结束闩 ⇒ 第二次播完不翻页；④ 抽帧缓存不优先精确键；⑤ 帧键桶宽 250 ms 与注释的 0.5 s 不符；⑥ **设置反序列化里 `map[k] == 'true'` 把「键不存在」读成「用户关了」** ⇒ 少写一个字段的设置文件会静默关掉硬解/自动播放/去隔行；⑦ 全视频的一章会把 mp4 字节写进按路径哈希的封面缓存；⑧ **`ab-loop-a/b` 写成毫秒**（`Duration.inMilliseconds`）—— mpv 要的是秒，于是 1 s 的 A 点变 1000 s，循环段永远撞不到，而 mpv 一声不响；⑨ `chapter-list` 的 `time` 是 double 秒，代码按 `toInt()` 取整 ⇒ 每个章节起点往前最多挪 0.9 s；⑩ **错误订阅挂得太晚** —— mpv 的 error 在 `open()` 的 await 期间就发完了，于是坏文件把相位永远留在 `prerolling`（页面表现为转不停的风扇）；⑪ **media_kit 给裸 `Player()` 默认 `--vid=no`**，而海报服务正是用一个没有渲染面的裸 Player 取首帧 ⇒ 视频轨压根没选上、`screenshot()` 恒 null，即「视频卡片的封面从来不出来」；⑫ **media_kit 的轨表里混着它自己造的伪轨 `auto` / `no`**（mpv 的真 track-list 没有这两条），原样映射进 `subtitleTracks`/`audioTracks` 就是字幕/音轨弹层里两条点不动的假轨；⑬ `selectSubtitleTrack` 用 `external` 当「该不该走 URI」的判别，而 `sub-add` 进来的轨**也是** external、它的 id 是轨号 '1' ⇒ 会拿 '1' 当路径 叫 mpv 去开一个叫 "1" 的字幕文件。现在按「id 是不是数字轨号」判别；⑭ **暂停态标记 A 点界面不刷新** —— `tapAbLoop` 第一跳只改私有 `_pointA`，快照没变 ⇒ `_update` 的等值短路把通知吞了，而 `video_control_overlay.dart:327` 读的就是 `controller.markedPointA`：播放中有位置流搭车还能亮，暂停时（正是会去打点的时刻）那颗 A 按钮永远不亮。改成动 `_pointA` 一律无条件通知；⑮ **`dispose()` 里 `detach()` 没等** —— `detach` 尾部的 `_update` 会落在已释放的 notifier 上，debug 下每次离开视频页都响一次 `A ReaderVideoController was used after being disposed`。加了 `_disposed` 闸并 `unawaited(detach())`；⑯ **字幕延迟与字幕轮切下标挂在模块全局** ⇒ 上一本调到 -0.5 s，换一本接着算。现在 `resetVideoSubtitleActionState()` 由 `VideoPageSurface._start()` 在每次起播前调一次，测试里有一条专门盯它；⑰ **「只听声音」关回去时画面回不来** —— `setVideoEnabled` 写的是 mpv 的 `video=yes`，而轨已经被关掉了，`yes` 并不会把轨重新选上（实测暂停与播放中 `vid` 都还是 `no`） ⇒ 黑屏到永久。现在两遍都写：先 `vid=auto`/`no` 管轨，再 `video` 管画不画。探针 ② 以前只钉了 `no` 那一半，所以一直是绿的；⑱ **暂停态按 ±10 s / 逐帧，时间标签不动** —— 暂停态里 media_kit 的位置流是不发的（探针量到：定位之后 `state.position` 仍是 0），而 `seekRelative`/`stepFrame` 只等事件不回填，用户按了键数字却不变。改成与 `seek()` 一样乐观回填（按 outcome 贴端点、按 1/fps 算一帧），纯逻辑测试里有一条专门用「从不发位置事件」的假实现钉它；⑲ **首次 load 偶发什么都不上报** —— 同进程已经起过别的 mpv 实例时实测 5 次撞 2 次，而紧接着重开一次总是立刻成功。preroll 闩现在允许一次原地重开（`allowRetry`），第二次仍无结论才判 failed；探针因此从 3/5 失败变成 5/5 稳定；⑳ **symphonia 的音轨判别看 `channels.is_some()` 是错的** —— 它在**打开解码器之前**常常还没解析出声道数，于是真实的 mkv/mp4 + AAC 被整条判成「这个视频里没有音轨」，症状是**进度条对最常见的视频永远不画波形**（WAV 测试全绿也发现不了）。改成拿「能不能造出解码器」当判据 —— 视频 codec 不在 symphonia 注册表里，自然只会挑到音频轨，并且优先采用解码器打开后补全的 `sample_rate`/`time_base`；㉑ **设置页的硬解开关会被 media_kit 覆盖** —— `NativeVideoController.create` 附着时写自己那套默认值（`hwdec ?? 'auto'`），时间上晚于 `open()` 里那次 `_set(hwdec)` ⇒ 用户关了硬解仍然开着。现在 `VideoController` 构造时把我们的 `hwdec` 传进去 |
| 探针自己也被抓了一次 | ⑧ 之所以能漏过第一版探针，是因为那条断言写成了 `abA.contains('1')` —— `'1000.000000'` 里有 `1`，**通过**。跨单位边界的断言必须把值解析成数值再比，不能对字符串化后的数字做子串匹配；同理 `sub-pos` 断 `'12'` 会假失败（mpv 对 double 属性一律按 `%f` 回读 `12.000000`），这两处都已改成数值比较 |
| 仓库测试 `flutter test test/video/` | 见上面「视频测试」那行。曾经跑不动的这段时间里，卡点是别的会话的 native assets / `frb_generated.rs` 失同步，与本功能无关 |
| `cargo check -p rossi_local_core` | **通过**（含本次的 `page_order.rs` / `vocabulary.rs` 改动） |
| 全量回归 `flutter test`（最新一次：**+543 ~1 -56**） | **视频域零失败** —— `test/video/` 的 61 条在全量跑里同样全绿。56 处红的文件固定是这几个：`comic_sync_core`、`swimlane_runtime`、`library_entry_list`、`lane_more_menu`、`top_chrome`、`layout_persistence`、`file_manager_card`、`mimage_model_settings`、`page_split`、`comic_folder_link_service` —— 都是并行会话正在改的 sync / workspace / bookshelf / reader 域；`rg` 过失败文本，**没有一条提到 video / mpv / wave**，而且这十个文件我一个都没改过（我在这几个域里只碰过 `_activeContextsFor`，无活动视频时是恒等分支，以及文件管理器卡片的缩略图分支）。判据始终是「失败点是否走我改的代码路径」，不是「看起来不像我」 |
| 真机播放、控制条手感 | **未验证**（由用户验收，清单见 `docs/video-playback-acceptance.md`）。「mpv 属性是否全部生效」这一项已从待验清单里**划掉** —— 由 §5 两条探针代验；剩下的是只能靠眼睛和耳朵判的：有没有画面、声音设备、拖动/悬停手感、字幕观感、进出泳道的音频生命周期、`hwdec` 在 Windows/Linux 上的实际表现 |

## 6. 缺口与已替代项

先说**已落地**的三件（它们曾在这里列为缺口）：首帧海报（`video_poster_service.dart`，
接文件管理器卡片 / 阅读页列表条 / 本地漫画封面三处）、视频设置区
（`_VideoSection`，含去隔行与自定义后缀编辑器）、图钉与字幕样式的播放时持久化。

| 项 | 上游出处 | 现状 |
|---|---|---|
| 视频动作的**出厂键位** | neoview `READER_FACTORY_INPUT_BINDINGS` 的 video 段 + mimage `keymap.rs` | **已做**：`preset.rs` 的 `DEFAULT_VIDEO_KEY_BINDINGS` 照上游抄（← / → 是 ±10 s，媒体键同义，C / X / Z 是加速 / 减速 / 切换倍速），`context = video` 与 `reader` 同键并存，靠优先级 150 > 100 决胜，`cargo test` 里有 `video_context_wins_over_reader_on_the_same_key` 钉住。**与上游的偏差**：上游把 C/X/Z 挂在 `global`，Rossi 先留在 `video` 档（全局吃掉按键而没有活动视频时，用户看到的是「按了没反应」）；三条 area 点击由 `VideoPageSurface._tapZones` 直接实现，不再进绑定表以免双触发 |
| 波形进度条 | mimage `seek_strip_wave.rs` + `audio_decode.rs` | **已做**：`local_core/src/wave_peaks.rs`（RMS 分格 + 100 ms 粗列 + 0.75 s 预滚 + `(path,mtime,size)` 身份）→ `localVideoWavePeaks` 过桥 → `VideoWaveformService`（整条列一次取、缓存 24 条、归一化在拿完整列之后做）→ `_ScrubBar` 底下垫一层柱子。**与上游的差别**：上游解码用 FFmpeg（B4 禁），这里用纯 Rust 的 symphonia；上游还要做「放大到 10 分钟窗口」的分块解码，Rossi 的进度条一次要的就是整条 180 格，窗口路径留待真做缩放时再补 |
| 视频文案的 i18n | — | **已做**：新增顶层 `video` 段（zh_CN / en_US 各 69 条）。控制条 tooltip 经 `videoLabels()` 构造，弹层 / 信息表 / 设置区直接走 `t.video.*`；`test/video` 里有一条断言钉住「英文不是把中文复制过去」。`MediaKindOverrides` 的校验提示仍是中文字面量（诊断串，出现在 SnackBar），要翻时连带改那条断言 |
| 容器转置（mimage `display_metadata.rs`） | **已做（引擎等效）**：mimage 自己读 3x3 显示矩阵并摆像素，Rossi 这边 mpv 的 autorotate 已经把转置**折进几何** —— 真实转置样本上 `video-params` 直接给 120x160（原编码是 160x120），所以信息卡的「尺寸」与画面一致。`rotate` 字段仍从 `video-params/rotate` 透到信息卡（那是额外旋转 `--video-rotate` 那一层，autorotate 折完之后这里是 0）。判据在真实样本探针第 4 条 |
| 变速不变调（mimage `audio_stretch.rs`） | **已做（引擎等效）**：上游用 signalsmith-stretch 自己做时间拉伸，mpv 侧对应 `audio-pitch-correction`（默认开）。真实样本探针第 4 条断言它确实是 `yes` —— 这条不算「新能力」，但它是上游的一项语义，漏了就变成「2x 播放像花栗鼠」 |
| A/V 漂移诊断（mimage `audio_diagnostics.rs`） | **已做（引擎等效）**：上游是一堆共享 atomic，mpv 直接给 `avsync`；信息卡有「音画漂移」一行，探针断言它可解析 |
| 真机播放验证 | 判据本身 | **构建、打包与属性层已过**（`flutter build macos --debug` 成功，产物内含 `Mpv.framework` + media_kit 两个 framework，即 libmpv 真的链进了 App；§5 两条探针覆盖属性名与取值）。**运行时仍未点过**：不宜由 agent 启动 GUI。剩下只有只能靠人判的：画面出不出来、声音设备、进出泳道时音频有没有漏关、字幕观感，以及 `hwdec=auto-copy` 在 Windows/Linux 上的表现 |
| 动图当视频播的精简控制条 | neo `ReaderAnimatedImageControlOverlay.tsx:52-101` | 未分叉，运动页复用完整控制条：上游精简是因为浏览器里给 GIF 做倍速/音量语义不成立，而 mpv 这些是真能力，精简反而少给可用项 |
| 折叠进 `PageContent` sealed 联合 | ADR-0008 占位条款 | 视频页在 `ReadImageWidget` 处按 `extern['isVideo']` 提前分叉，**没有**新增 `VideoPageContent`：理由是视频页永远不该走 `PageSource.load()`（那是像素路）。与占位条款的字面写法有偏离，已在 ADR-0016 说明 |
| 真 PiP（系统级） | neo `PiP` 按钮 | 桌面 mpv 不提供系统级 PiP，已用应用内置顶浮窗替代 |
| mimage `stream/`（`encoder.rs`/`video_tap.rs`/`segmenter.rs`/`playlist.rs`/`quality.rs`/`session.rs`/`timeline.rs`） | **不做**：那是把视频**再编码推流/切片**（HLS 那套）的输出侧子系统，不是播放能力；需要编码器接入，B4 明确禁 `local_core` 引 ffmpeg，且 Rossi 没有任何接收端。属于「上游有、与本产品的读漫画场景无交集」，不是并集缺项 |
| mimage `frame_selection.rs` | **不做**：它解决的是自建 present 循环里「下一 tick 摆哪一帧」的累积偏差（每帧 ~0.16 ms 系统偏差 ⇒ 约 7 s 掉一帧）。Rossi 的帧调度在 libmpv/mpv 内部（`--video-sync`/`--display-fps-...`），没有那圈 tick 算术可搬 —— 属 B3 栈差 |
| mimage `avio_progress.rs` | **不做**：网络/大文件读取进度 HUD（「准备中… N MB」）。Rossi 的视频只有本地文件与归档物化两条路，物化进度已有 `VideoMaterializer` 的 singleflight 与失败退化；且网络播放不在范围内 |
| 360° 球面视频、视频离线放大、DComp 原生 presenter | mimage `spherical_metadata.rs` / `video/upscale/` / `native_presenter/` | 见 §3 排除表，属决定不做 |

## 7. 现在到哪一步了（交接用）

**已经证到的**（每一条都有可重跑的命令，不靠叙述）：

| 层次 | 命令 | 结果 |
|---|---|---|
| 纯逻辑 + 动作接线 | `flutter test test/video/video_playback_logic_test.dart` | 47 条全绿；含 24 条视频动作逐条派发到执行器 |
| 引擎语义（合成源） | `flutter test test/video/mpv_property_probe_test.dart` | 7 条全绿：出厂 mpv 名字表、属性回读、逐帧/截图/元数据、坏文件落 failed、裸 Player 出画面、字幕与伪轨 |
| 引擎语义（真实编码源） | `flutter test test/video/mpv_real_sample_probe_test.dart` | 4 条全绿：章节毫秒精度与跳转、h264/aac 元数据与精确定位、变速不变调、容器转置 |
| 波形全链路 | `flutter test test/video/waveform_bridge_probe_test.dart` | 3 条全绿：Dart→FRB→symphonia→归一化→缓存→坏文件退化 |
| 页序判定（Rust） | `cd rust && cargo test -p rossi_local_core` | 360 全绿；含视频算页不算图片页、跨语言后缀表漂移守卫、混排目录枚举 |
| 静态与出包 | `dart analyze lib/video test/video`；`DEVELOPER_DIR=... flutter build macos --debug` | 无告警；退出码 0，产物内含 `Mpv.framework` |

**只有真机能判的**（`docs/video-playback-acceptance.md`，样本 `script/make_video_samples.sh` 一条命令生成）：
画面/声音的实际观感、拖动手感、字幕渲染、进出泳道与反复进出视频页的音频与资源生命周期（A1–E5）、
`hwdec` 在 Windows/Linux 与 macOS VideoToolbox 上的**生效**（探针只能验到「请求值落到引擎」，
因为无渲染面时 `vo=null`）、以及章节刻度线画在不在位置上。

**过程中改掉的真缺陷**：见 §5 的 ①–㉑ —— 其中 ⑧(A–B 单位)、⑪(海报永远不出封面)、
⑰(只听声音关不回去)、⑳(symphonia 判不出现实音轨)、㉑(硬解开关被 media_kit 覆盖)
都是「静态检查、出包、甚至单元测试全绿」也发现不了的形状。

## 2026-09-20：实际播放与性能修复

本节更新前文「真机未验证」及 `auto-copy` 的历史记录。当前桌面/iOS 使用
`media_kit` 的 `hwdec=auto`，Android 使用 `auto-safe`；关闭硬解仍为 `no`。
解码选项在视频输出初始化后、加载媒体前设置，避免起播后再切换解码器。

- macOS 原生测试已显示真实首帧，并用 1920×1048、60 fps H.264 本地视频持续播放。
  `hwdec-current=videotoolbox`，输入和输出像素格式均为 `videotoolbox`。
  稳定播放 10 秒期间，解码丢帧与显示丢帧计数均未增加（不含起播/定位阶段）。
- 同一调试进程中的解码选项对比：`videotoolbox-copy` 播放 10 秒消耗 5.23 秒 CPU，
  `videotoolbox` 消耗 3.98 秒，减少约 24%。这是单机、单片源的解码路径对比，
  不是完整工作区或 Release 的性能保证；各平台实际硬解由驱动与片源决定。
- 进度最多每 100 ms 刷新进度条，时间文字每秒更新；按钮和菜单只响应操作状态或轨道变化。
  控制条隐藏时停止进度组件订阅，视频与手势子树通过 `ListenableBuilder.child` 保持稳定。
  退出或换源会释放自有 Player、原生视频纹理、流订阅、预览目录与**预览解码器**（预览自己的那台
  mpv，空闲 60 s 也会自行释放）；异步旧目标不会重新起播。
- 截图失败不再遮住正在播放的画面；悬停取帧走预览自己的解码器 —— 播放中与暂停时都不碰
  主播放器的位置（旧做法借它 `seekPaused` 定位，鼠标划过进度条就会把视频拖走）。
- `integration_test/video_page_surface_test.dart` 覆盖首帧、暂停恢复、真实截图、截图失败后
  连续悬停 15 秒、子树稳定、切换硬解/目标、延迟路径解析，以及退出后的资源释放。
  默认使用仓库内自生成 H.264 样本，可通过
  `--dart-define=VIDEO_PAGE_TEST_FILE=/absolute/path/video.mp4` 指定本地片源。
- 控制条和弹层使用 MD3 的主题表面、文字、图标按钮与 Slider，深浅色跟随应用。
  播放时取消固定会重新计时隐藏；暂停、固定或打开弹层时保持可见，关闭弹层或恢复播放后重新计时。
  Widget 测试覆盖深浅色、菜单内切换主题、窄泳道、滤镜/倍速/音量操作与菜单关闭；
  原生测试覆盖取消固定后无鼠标移动仍会隐藏，以及播放进度不重建菜单。
