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
| SRT/ASS/SSA → WebVTT | 同上 | `convertSubtitlesToWebVtt` | （mpv 原生也吃 srt/ass，转换供自绘与测试） |
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
| 拖动条缩略帧的**容差最近帧**设计 | `video/thumbnail.rs` | `VideoFrameCache.nearest`（整数纳秒键 + 有序表 + 每次请求独立容差）；**预览会先定位到鼠标所指的时刻**（`screenshot` 截的是当前解码位置，不先 seek 就是「划到哪儿都同一张图」）：已暂停时借用当前播放器定位，播放中不抢用户位置、只给已缓存帧 —— 上游为此单开 worker，这里没有第二台解码器 |
| 视频→纯音频模式 | `video->audio` | `setVideoEnabled(false)` |
| `KeyAction::Video*` 键位面 | `keymap.rs:1752-1780` | `vocabulary.rs` 的 22 条 `video.*` 动作 + `ACTION_CATALOG`，执行体在 `video_action_dispatch.dart` |

## 3. 明确不做（T5）

| 项 | 理由 |
|---|---|
| 360° / 球面视频（`spherical_metadata.rs`） | 需要 v360 重投影，与「一页 = 一个矩形画面」的泳道模型冲突 |
| Anime4K / RealESRGAN 视频离线放大（`video/upscale/`） | Anime4K 在 ADR-0008 冻结线外，且那是离线批处理作业不是播放功能 |
| DComp 原生 presenter / 子 HWND 交换链 | media_kit 已经把帧注册成 Flutter texture，Rossi 的纹理桥是给静态图的单 `Owner` 路 |
| 波形进度条（`seek_strip_wave.rs`） | 需要整文件 PCM 解码；`VideoWaveformStrip` 已备好数据结构与降采样，缺数据源（`local_core` 的音频解码），刻意不接 ffmpeg 进 B4 层 |
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
| 视频纯逻辑测试 `flutter test test/video/` | **全部通过（37 条）**：媒体身份 / 别名登记表 / 状态机 / 循环与翻页 / A–B / 进度阈值 / 章节 / 字幕匹配与 SRT·ASS 转换 / 抽帧缓存 / 设置持久化往返 |
| `cargo test -p rossi_local_core` | **351 passed / 0 failed**（含页序改名与 45 条动作的注册表） |
| 过程中真查出来的缺陷 | ① ASS 字段数判成 11（正常字幕行整行被丢）；② 快照未从 transport 打底 ⇒ 拖不动进度、进度永不上报；③ `completed=false` 不复位结束闩 ⇒ 第二次播完不翻页；④ 抽帧缓存不优先精确键；⑤ 帧键桶宽 250 ms 与注释的 0.5 s 不符；⑥ **设置反序列化里 `map[k] == 'true'` 把「键不存在」读成「用户关了」** ⇒ 少写一个字段的设置文件会静默关掉硬解/自动播放/去隔行；⑦ 全视频的一章会把 mp4 字节写进按路径哈希的封面缓存 |
| 仓库测试 `flutter test test/video/` | 见上一行：已通过。曾经跑不动的这段时间里，卡点是别的会话的 native assets / `frb_generated.rs` 失同步，与本功能无关 |
| `cargo check -p rossi_local_core` | **通过**（含本次的 `page_order.rs` / `vocabulary.rs` 改动） |
| 全量回归 `flutter test`（639 条） | **我碰过的域零失败**。按文件归口只有 3 处在红：`comic_folder_link_service_test`（setUpAll 失败级联）、`comic_sync_core_test`、以及 `widget_tester.dart` 里的加载失败 —— 都在并行会话正在改的 bookshelf / sync 域。此前一度失败的 `page_split_test`、`mimage_model_settings_test` 在他们推进后已自行转绿，可反证不是我引入的 |
| 真机播放、控制条手感、mpv 属性是否全部生效 | **未验证**。本机跑不了 `flutter build macos` / `flutter run`（无 Xcode），需要真机验收，清单见 §6 |

## 6. 缺口与已替代项

先说**已落地**的三件（它们曾在这里列为缺口）：首帧海报（`video_poster_service.dart`，
接文件管理器卡片 / 阅读页列表条 / 本地漫画封面三处）、视频设置区
（`_VideoSection`，含去隔行与自定义后缀编辑器）、图钉与字幕样式的播放时持久化。

| 项 | 上游出处 | 现状 |
|---|---|---|
| 视频动作的**出厂键位** | mimage `keymap.rs` 的 `KeyAction::Video*` 默认和弦 | 动作已可达（解析现在带 `video` context），但 `preset.rs` 的默认表里**还没有视频那一组**：该文件正被另一路会话改（未提交的重构），我不在他们手上抢着加。今天用户可以在绑定设置页自行绑定这 24 条（注册表里都标着 `implemented: true`）；等那边稳定后补一张 `DEFAULT_VIDEO_KEY_BINDINGS`（空格→播放/暂停、左右→±10 s、`,`/`.`→逐帧、`[`/`]`→倍速、`L`→循环档、`M`→静音、`T`→快进档、`A`/`B`→A-B、`V`→切字幕、`F`→全屏） |
| 波形进度条 | mimage `seek_strip_wave.rs` | 数据结构与降采样已就位（`VideoWaveformStrip.fromPcm`），**缺 PCM 数据源**：要接它得在 `local_core` 加音频解码并跑一次 FRB 生成，而 B4 明确不许 ffmpeg 进那一层。这是并集里唯一一条「上游有、这里没有实现体」的功能 |
| 视频文案的 i18n | — | 视频文案目前是 `defaultVideoLabels` 常量表与设置区的中文常量，**没进 slang `reader.*`**（与 `_SuperResolutionSection` 同一先例）。要接时改的是「构造 `VideoLabels` 的那一处」，控件本身不感知 |
| 真机播放验证 | 判据本身 | **未做，且本机做不了**（没有 Xcode，跑不了 `flutter build macos` / `flutter run`）。需要真机逐项确认：`ab-loop-a/b`、`loop-file=inf`、`frame-step`、`brightness/contrast/saturation`、`sub-*`、`screenshot-to-file`、`hwdec=auto-copy` 三平台表现，以及视频页进出泳道时音频有没有漏关 |
| 动图当视频播的精简控制条 | neo `ReaderAnimatedImageControlOverlay.tsx:52-101` | 未分叉，运动页复用完整控制条：上游精简是因为浏览器里给 GIF 做倍速/音量语义不成立，而 mpv 这些是真能力，精简反而少给可用项 |
| 折叠进 `PageContent` sealed 联合 | ADR-0008 占位条款 | 视频页在 `ReadImageWidget` 处按 `extern['isVideo']` 提前分叉，**没有**新增 `VideoPageContent`：理由是视频页永远不该走 `PageSource.load()`（那是像素路）。与占位条款的字面写法有偏离，已在 ADR-0016 说明 |
| 真 PiP（系统级） | neo `PiP` 按钮 | 桌面 mpv 不提供系统级 PiP，已用应用内置顶浮窗替代 |
| 360° 球面视频、视频离线放大、DComp 原生 presenter | mimage `spherical_metadata.rs` / `video/upscale/` / `native_presenter/` | 见 §3 排除表，属决定不做 |
