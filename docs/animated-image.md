# 本地与在线的动图支持（GIF / APNG / 动图 WebP）

参考实现是 mImageViewer（本仓 `vendor/mimageviewer`，下称 mimage）。
口径来自 2026-09-21 的四条决定：两条管线都要、**动图 AVIF 不做**、本地动图不做自研帧循环、
`.wbp` 按 neoview 的口径处理（见下）。

> **`.wbp` 的口径后来改过一次**：一开始按「动图 webp 的别名」实现（后缀即动图），
> 后来核对 neoview 源码发现它是 `image/webp`（`media.ts:13`）—— 一颗**改名的 WebP**，
> 会不会动仍然要查容器。上游的动图信号是文件名里的 `[#dyna]` 关键字与 MIME，不是后缀。
> 于是 `animatedNameSuffixes` 收回到 `{gif, apng}`，`.wbp` 与 `.webp` 走同一条容器嗅探。
> 顺带纠正一处旧注释：`video_media_kind.dart` 里写的「neoview 的 `formatAlias` 设置」
> 在上游并不存在，真名是 `supportedImageFormats` / `videoFormats` / `mediaMimeTypes`。

## 1. 改了什么

| 档 | 改动 | 落点 |
|---|---|---|
| 动图判定 | 新增容器嗅探（APNG 看 `acTL` 帧数、动图 WebP 看 VP8X animation 位 / `ANIM`/`ANMF` 块），移植自 mimage 的 `canonical_image_loader.rs::probe_static_animation` | Rust `rust/local_core/src/animation.rs`、Dart `lib/reader/page_animation.dart` |
| 本地渲染 | 新增 `AnimatedLocalPage` 装饰器：判定为动图就把这一页交给引擎的解码器（`Image` + `FileImage`/`MemoryImage`），否则原样交回 `ImageSurface` | `lib/reader/animated_local_page.dart`、`read_image_widget.dart` |
| 页序 | `.apng` 与 `.wbp` 进核心档：以前它们**连一页都不算**，用户看到的就是「书里凭空少几页」 | `page_order::CORE_DECODABLE_EXTENSIONS` |
| 在线不被拍平 | 禁漫反混淆原先只放过 GIF；现在动图容器一律原样返回 | `rust/src/decode/segmentation.rs` |
| 超分不被拍平 | RealSR 的动图守卫换掉，并覆盖 APNG | `real_sr_super_resolution.dart` 的两处守卫 |

## 2. 为什么不照抄 mimage 的「全帧展开」

mimage 用 `image` crate 的 `AnimationDecoder::into_frames()` 把**所有帧一次解完**
（`vendor/mimageviewer/src/fs_animation.rs`），代价是它必须自己补三件引擎已经做好的事：
帧长下限钳到 20 ms、每帧 clamp 到纹理上限、以及**根本不读循环次数**（永远无限循环）。

这里改成让引擎出帧：`ui.instantiateImageCodec` 对多帧容器返回 `MultiFrameCodec`，
`Image` 配 `FileImage` / `MemoryImage` 会起 `MultiFrameImageStreamCompleter` 自己播，
帧时长、循环次数、GIF/WebP 的 disposal 合成全在 Skia 侧，Dart 侧零帧管理。
实测（`flutter_tester`，样本现造）：

| 样本 | `frameCount` | `repetitionCount` | 帧时长 | `targetWidth=30` |
|---|---|---|---|---|
| 动图 GIF | 3 | -1 | 见下注 | **不生效**，仍是原尺寸 |
| 动图 APNG | 2 | -1 | 40 ms | 不生效 |
| 动图 WebP | 3 | -1 | 100 ms | 不生效 |
| 静图 WebP / PNG / AVIF | 1 | 0 | 0 | 生效 |

> 注：那次 GIF 帧长读出 0 ms 是**夹具**没有写 per-frame delay（`identify -format %T`
> 同样报 0），不是引擎读错。APNG / WebP 的帧长与源文件一致。

`targetWidth` 对动图不生效这条是硬结论：动图按**原始尺寸逐帧**解，
所以超大动图比静图那条路（按显示宽度降采样）吃内存。mimage 全帧展开在同样的素材上更糟。

两套嗅探对**真编码器产物**（ImageMagick 出的 11 个文件）逐行对拍，Dart 与 Rust 结论完全一致：
动图 apng/webp 全 true、静图 png/webp/带 ICC 的 png/avif 全 false、GIF 一律靠后缀。

## 3. 明确不做

- **动图 AVIF**：mimage 自己也不支持（AVIF 只走 Windows WIC 且 `GetFrame(0)` 硬取首帧）。
  要做必须自己啃 ISOBMFF 的 `meta`/`iref`/`infe` 轨道解析。静帧 AVIF 维持现状（dav1d）。
- **归档（CBZ/CBR）内 webp / png 的容器嗅探**：查头部要整条 inflate 再过桥，而这条判定
  服务的是翻页关键路径。所以归档内只认后缀说得出的档（`.gif` / `.apng`）；
  归档里的动图 webp、改名成 `.wbp` 的动图 webp、以及改名成 `.png` 的 APNG 都停在第一帧。
  散图文件夹与单文件不受此限。
  要补这一格，代价是给 `LocalPageInfo` 加一个 Rust 侧算好的字段（需要重跑 FRB 代码生成）。
- **动图页不进 GPU 呈现器、不进超分、不做横长页分割**：三者都建立在「一页 = 一张位图」上。
  与 mimage 同口径（它把动画标成 playback-only，绕过 edit / final / 校正缓存）。
- **单帧 GIF 会被认成动图**：`animatedNameSuffixes` 按档处理，不看内容 ——
  GIF 的第二帧在第一帧的 LZW 数据之后，4 KiB 头部判不出来，整串扫不划算。
  后果只是这一页不走 GPU/超分，画面无差别。
- **e-Ink 遮罩延时**不参与动图页（首帧遮罩与「这一页会动」互相矛盾）。

## 4. 实机验收清单

设备验证由使用者做；下表编号用于回报（报「3 通过 / 5 不通过」这种形式即可）。
Windows 侧注意：引擎没链 AV1，静帧 AVIF 仍走 Rust 解码那条路，与本次改动无关。

1. **本地散图 · GIF**：打开一个含 `.gif` 的文件夹 → 该页会动；邻页照常预取，翻页不卡。
2. **本地散图 · 动图 WebP**：含真动图 `.webp` 的文件夹 → 会动；同目录里的静图 webp
   仍然走原来的 GPU 上屏（放大/旋转/超分行为不变）。
3. **本地散图 · APNG**：`.apng` 文件**算一页**（改动前会凭空少这一页）且会动。
4. **`.wbp`**：改名为 `.wbp` 的动图 webp 在**散图文件夹**里算一页并且会动；
   在 CBZ 里算一页但停在第一帧（见 §3）。同名的静图 webp 改名成 `.wbp` 应当**不会动**。
5. **本地 CBZ · gif/apng**：归档内的 `.gif` / `.apng` 会动（走整条字节过桥那条分支）。
6. **不误伤**：一本全是静图 jpg/png/webp 的 CBZ，页数、翻页速度、超分提示与改动前一致。
7. **改名成 `.png` 的 APNG（散图）**：在文件夹里会动；在 CBZ 里停在第一帧（见 §3）。
8. **顶栏尺寸链路**：停在动图页时，「原始大小」与缩放/旋转面板给的比例按该页画布算，
   不跳成 0 也不沿用上一页。
9. **在线 · 禁漫反混淆**：正常章节不受影响；若遇到图源给的是动图 webp/apng 的页，
   这一页会动而不是被重编码成静帧。
10. **超分守卫**：开着超分时，动图页被跳过（只记一条日志，界面上不弹提示）而不是被
    拍平成一张静帧；同书的静图页照常超分。
11. **不崩**：反复进出含动图的页、双页模式含一页动图、以及动图页上下滑（列模式）。

## 5. 媒体格式表可以自定义（第二轮）

上面第 3、4 条暴露了一个更大的问题：**「什么算一张图」这件事在本仓有两张互不相干的表**。

| 表 | 住哪 | 管什么 |
|---|---|---|
| `folder_tree::SUPPORTED_EXTENSIONS` | Rust | 条目**是否出现在文件管理器 / 列表 / 搜索**里 |
| `page_order::CORE_DECODABLE_EXTENSIONS` + `SHELL_…` | Rust | 打开书之后**算不算一页**、谁来解 |
| `RossiMediaKind` / `disguisedExtensions` | Dart | 已经列出来的那一页**是谁** |

第一轮只补了中间那张，所以出现了不对称的症状：**翻开书能看见这一页，列表里根本没有它**。
这就是「`.wbp` 在文件管理器里被隐藏」的根因。现在两张 Rust 表都收口到
`media_formats::Tables`，判定路径统一成一条。

### 设置项

「阅读设置 → 媒体格式」两档（`t.video.mediaSection`），照 neoview 的
`supportedImageFormats` / `videoFormats`：

- **填了就整体替换内置表**（上游 `media.ts:64-65` 的语义，有测试钉着：自定义之后
  `resolve("clip.mp4")` 反而变 `undefined`）。**留空才是「没设置过」**，继续用内置默认。
  所以填错不是「多加一条」而是「其余全不见了」—— 界面提示把这个写在前面。
- 校验在上游规则之上加两条：一颗后缀不许同时进两档（否则页序里它被随机路由，
  症状是「同一本书每次打开页数不一样」）。条数 ≤128、每条 ≤16 字符、
  字符集 `^[a-z0-9][a-z0-9+_-]{0,15}$` —— 与 Rust 侧 `media_formats.rs` 同值。
- 原有的「自定义视频后缀」保持**追加**语义，与替换档并存：替换档定基线，追加档永远叠上去。
  两张表要**同进同出**推给 Rust（`VideoSettingsStore._apply` 是唯一同时看到两档的地方）。
- 启动时 `main.dart` 会 `load()` 一次把表推进 native；否则用户自定义的格式在第一屏是隐身的。

### 为什么这张表必须在 Rust

浏览层的判定在 Rust（`folder_tree::is_recognized_image_ext`、`file_tree.rs` 的 `is_video`）。
只改 Dart 那张 `RossiMediaKind` 的话，用户新加的后缀仍然看不见 —— 正是这次的原始症状。
所以新增了一条 `#[frb(sync)] media_formats_set(image, video, extraVideo)`，
同步是因为它只是一次内存写，而它必须在第一次列目录之前生效。

`Tables` 的判定刻意做成**纯函数**（表当参数传），只有一份进程级 `static` 给生产路径用：
测试直接写那份 `static` 会洗掉别人的断言（第一轮就撞过，25 条无关测试一起红）。

### 这一轮的验收（接上表编号）

12. **文件管理器看得见**：把一颗动图 webp 改名成 `.wbp` 放进散图目录 → 列表里**就有它**
    （本轮之前它是隐身的），点开能读；`.apng` 同理。
13. **加一条自己的格式**：设置里图片格式填 `cbz-dbg`（举例），把一张 jpg 改名成该后缀
    → 列表里出现、能翻开；改完之后**不用重开**。
14. **替换语义的后果**：图片格式只填 `png` 之后，同目录里的 `.jpg` 应当**从列表消失**
    （这就是「替换」的意思，不是 bug）；清空这一档 → 全部回来。
15. **两档不许重叠**：同一个后缀同时填进图片与视频两档时，保存要弹一条中文错误、
    并且**不写入**。
16. **重启保持**：填好两张表 → 杀掉应用重开 → 第一屏的列表就已经按新表来（不需要进设置页）。
