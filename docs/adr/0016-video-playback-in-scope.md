# 视频播放进范围：解冻 ADR-0008 的「视频」一条

ADR-0008 把 v0.1 冻结线定为「本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分」，并把**视频播放**
与在线源 / OCR / 上色 / Anime4K 一起列为「不进 v0.1」。本 ADR 只解冻其中**视频播放**一条。

## 决定

1. **视频播放进入实现范围**，形态是「**一页可以是视频**」而不是「新增一个视频 App 页面」：
   章节（文件夹 / ZIP / RAR）里的一个条目可以是 mp4 / mkv / webm…，它与图片页共用页序、
   滑杆、泳道与进度体系。理由：这是两个上游共同的形态 —— neoview 的
   `PageMedia.tsx` 按 `mediaKind` 把页路由到 `PageVideo`，mImageViewer 的视频也挂在
   文件页序上（`folder_tree.rs` 的 `SUPPORTED_VIDEO_EXTENSIONS`）。
2. **两个上游的功能并集都要**（清单见 `docs/video-playback-spec.md`），来源分工沿用 §1.1 选源规则：
   - **交互与状态机以 neoview 为准**（它是可读可翻译的自有项目，形态 T3）：
     控制条布局、自动隐藏 3 s 与图钉、循环三态、速率档、seek-mode、字幕样式、A-B 循环、
     截图、滤镜、播放结束→翻页、媒体进度 {position,duration,completed} 与阈值。
   - **引擎语义以 mImageViewer 为准**（形态 T1/T2 的纯逻辑 + T4 的平台等效）：
     主时钟 / A-V 漂移、preroll 就绪闩、帧步进、章节边界、SAR 与显示矩阵、
     拖动条缩略图的**容差最近帧**缓存、波形条、硬解开关、去隔行、视频→纯音频模式、
     音画同步的可观测性（`av_drift_ms`）。
3. **播放引擎用 `media_kit`（MIT，libmpv）**，不在 Rossi 里重建 FFmpeg 解码器。
   这是本 ADR 的核心代价交换：mImageViewer 的解码器 70k 行、368 处 `cfg(windows)`、
   D3D11VA + DComp 上屏 + cpal，**非 Windows 没有显示路径**，逐块等效重写的长期成本
   远高于换一个已经跨五平台的引擎。mpv 的原生能力恰好覆盖两个上游的功能面
   （`speed` / `ab-loop-a|b` / `frame-step` / `chapter` / `sub-*` / `video-properties`
   的 brightness/contrast/saturation / `screenshot-to-file` / `hwdec` / `deinterlace` /
   `video=no`），因此「不重建解码器」不等于「少做功能」。
4. **归档里的视频要可播放** ⇒ 物化（materialize）。沿用 neoview 的
   `ReaderSeekableMediaCache` 额度与释放规则（单条目 2 GiB / 总量 4 GiB、singleflight、
   按等待者计数释放），落盘目录在临时区。文件夹来源直接用原路径，不物化。

## 边界怎么改

- **B4 依赖树不变**：`ffmpeg` / `mpv` **不进 `local_core`**。引擎在 Dart 侧（media_kit 自带
  native 产物），`local_core` 多做两件事：
  1. **承认视频条目是一页**（`page_order.rs` 的 `is_page_name`），并按需提供该条目的字节（既有 `page_bytes`）；
  2. **波形取峰值**（`wave_peaks.rs`）—— 这条是后补的：mimage 的波形走 FFmpeg，B4 不许，
     所以用**纯 Rust 的 symphonia（MPL-2.0，非 GPL）**解 PCM。它不引入外部二进制、不解析 C 头，
     因此不触 B4 想防的那件事（编译时间与交叉编译链路）。它确实让 `local_core` 多了一个
     解码器族，这是明知代价接受的结果 —— 备选是「并集里少一条功能」。
  两处都**不改变已暴露类型的形状**地过桥：`localVideoWavePeaks` 是本次唯一新增的 `#[frb]` 函数。
- **许可不变**：`local_core` 仍不引入 GPL 源码。media_kit 是 MIT；它链入的 mpv 是 LGPL/GPL
  可选构建，由 media_kit 的预编译产物提供，不进入本仓库源码树。
- **FRB 生成物不动**：本 ADR 的所有 Rust 改动都**不改变已暴露类型的形状**（不加字段、
  不加 `#[frb]` 函数），因此不需要 `flutter_rust_bridge_codegen`。视频身份判定在 Dart 侧
  按扩展名做，理由与 ADR-0008 里「页身份 / 页内容分离」的既有口径一致。

## Considered Options

- **搬 mImageViewer 的 `src/video/`**：T1 搬不动 —— 它绑 D3D11 / DComp / Win32 消息泵，
  且帧从不进 egui 纹理（直接进子 HWND 交换链）。要在 Rossi 里用，等于再写一个 wgpu presenter，
  而后Rossi 的 GPU 路是给静态图的单 `Owner` 纹理桥。
- **官方 `video_player`**：桌面三平台支持零散（Linux 无官方实现），控制条要另写（chewie），
  且没有 A-B 循环 / 帧步进 / 字幕样式 / 滤镜这些 mpv 白送的能力。
- **只做「视频页能放」不做控制条**：与「两个的功能都要」直接冲突，不采纳。

## Consequences

- v0.1 的**可数判据 A–E 不受影响**：它们全部关于静态图链路。视频页**不进入**判据 C 的
  连续翻页帧时间采样（翻页判据测的是「翻页 + 渲染」，视频页在那里是另一条渲染路）。
- 新增一类**跨页生命周期**：静态图页是「取一次像素」，视频页是「有一个活的播放器 + 一条音频」。
  泳道切 lane、退出阅读、切章时必须显式 dispose，否则音频会继续响。这是新的一致性要求，
  不是实现细节。
- 冻结线其余三条（在线源 / OCR / 上色 / Anime4K）**仍然在冻结线外**，本 ADR 不代为解冻。
  > **后续更正（2026-09-25）**：这一句写于 ADR-0018 之前 —— **OCR 翻译其后已单独解冻**（成品页形态）。
  > 现在仍在冻结线外的是：在线源 / 上色 / Anime4K。本 ADR 的其余内容不受影响。
- 360° / 球面视频（mimage 的 `spherical_metadata.rs`）**明确不做**：它需要 v360 重投影，
  与「一页 = 一个矩形画面」的泳道模型冲突，登记在 spec 的排除表里。
