# Phase 0 vendor spike 结果（mImageViewer 适配层）

> 2026-09-16 跑完，对应 ADR-0005 / ADR-0007 里「动手前必做」的两项。
> 证据与可复现脚本在 `poc/`，本文只写结论。
>
> **一句话**：「薄适配层」**成立**，但成立的方式是「**剪 9 条反向依赖边**」，
> 不是「排除 `ui_*` 目录」——后者在这个仓库里根本切不出来。

## 0. 先记两件 vendor 检出的事实

| 事实 | 值 |
|---|---|
| 源头 | **原版上游 `MikageSawatari/mimageviewer`**（同日第二次更正：最初指向个人 fork `HibernalGlow/neoxide`，但该 fork 不会被维护，且与上游 diverged 领先 2 / 落后 34，见 §0.1） |
| 检出位置 | `vendor/mimageviewer/`，`.gitmodules` 记录上游 URL，gitlink = **`1fd6f863`**（上游 `main`） |
| 与上游的关系 | **零漂移**（`git rev-list --left-right --count main...origin/main` = `0 0`） |
| 上游同步 | `git -C vendor/mimageviewer fetch origin main && git -C vendor/mimageviewer reset --hard origin/main`，父仓库只改一个 gitlink |
| LFS | 仓库用 **git-lfs** 存根目录 `models/` 下 9 个模型，合计 **335 MB**。当前检出**保留指针文件**（v0.1 用不到模型） |
| 恢复 LFS | `git -C vendor/mimageviewer lfs pull`（约 335 MB 带宽） |

### 0.1 为什么把源头从 fork 换成上游

最初检出的是 `HibernalGlow/neoxide`（2026-09-13 建），它只比上游多 2 个提交：
`feat(i18n): add Chinese (zh-hans) translation layer` 与
`tools(i18n): add wrap/verify script and i18n design docs`。

丢掉它不会损失任何 v0.1 需要的东西——那 2 个提交是 **UI 字符串层**，
而 ADR-0005 已经把 UI 层明确排除在复用范围外（只复用归档 / 解码 / 缓存 / 超分）。

反过来说，留着它有真实代价：一个不会被维护的 fork 停在「落后上游 N 个提交」的位置，
会让 `vendor/` 看起来在跟上游、实际却锚在一个私人分支上。这类漂移是**静默**的，
和 ADR-0007 实测到的 `[patch.crates-io]` 不传播属于同一类问题——没人会提醒你。

仓库内部还有一个 `vendor/`，两类东西要分清：

- `vendor/egui`、`vendor/eframe`、`vendor/egui-wgpu` —— **仓库内 git 跟踪**的本地副本，
  正是 `[patch.crates-io]` 的目标（见 §2）。
- `vendor/{models,ort,pdfium,ffmpeg,susie-worker,vst3sdk}` —— 被 `.gitignore` 排除，
  **构建期由 `build.rs` 生成**。

`src/ai/model_manager.rs` 用 `include_bytes!("../../vendor/models/*.onnx")` 指向的是**后一类**，
所以「干净检出上直接编译它的主 crate」本来就不成立（得先跑构建脚本把 `vendor/models/` 造出来）。

## 1. spike 1：适配层到底有多厚

脚本 `poc/mimageviewer-adapter-thickness/measure.py`，原始输出同目录 `results.txt`。

| 指标 | 数 |
|---|---|
| `src/` 下的 `.rs` | **467** |
| 真正引用 egui（非注释行）的模块 | **183** |
| 只在注释里提到 egui 的模块 | 16 |
| 这 183 个里**名字不像 UI** 的 | **92** |
| Rossi 要复用的 11 个种子模块 → `crate::` 传递闭包 | **301 个模块，其中 120 个碰 egui** |

### 1.1 「核心 vs UI」的边界**不能用名字划出来**

183 个脏模块里，92 个的名字完全不像 UI：`books`(84 行)、`keymap`(384)、`ime_focus`(264)、
`displayed_image_transform`(292)、`gpu_lanczos`(141)、`os_theme`(90)、`settings`(3)、`thumb_loader`(6)……

→ ADR-0005 担心的「底层模块也引用 egui 类型」**确有其事**，而且比预期更靠底层：
连 `settings.rs`、`grid_item.rs` 都碰。**按目录切「核心」的做法直接判死。**

### 1.2 但「薄」仍然成立 —— 只要剪反向边

301 个模块 / 120 个脏，是「**不剪边**」的量级，不是「必须全改」的量级。真正的切集很小：

- **11 个种子里 8 个完全干净**：`archive_cache`、`rar_loader`、`zip_loader`、`zip_tree`、
  `wic_decoder`、`page_dims`、`fast_resize`、`path_key`。
- 脏的 3 个都是**个位数行数**：`thumb_loader` 6、`canonical_image_loader` 7、`page_split` 9。
- 把每个种子的**直接**脏依赖去重，得到 **9 个模块**：

| 要处理的模块 | egui 行数 | 被谁需要 |
|---|---|---|
| `ui_helpers` | 252 | archive_cache / rar_loader / zip_loader / thumb_loader |
| `displayed_image_transform` | 292 | page_split |
| `edit_preview_cache` | 52 | thumb_loader |
| `adjustment` | 44 | thumb_loader |
| `fs_animation` | 18 | canonical_image_loader |
| `settings` | 3 | zip_tree / thumb_loader / page_split |
| `catalog` | 2 | thumb_loader |
| `grid_item` | 1 | zip_tree / thumb_loader |
| `thumb_loader`（自身） | 6 | canonical_image_loader |

其中 4 个是「≤3 行」的（大概率只是 `egui::Color32` / `Rect` 这类类型或一个开关），
真正的活是前四个：`ui_helpers`、`displayed_image_transform`、`edit_preview_cache`、`adjustment`。

> 注意 `ui_helpers` 被 4 个种子共用 —— 它像是一个「人人都 import 的杂物间」。
> 剪它之前要先看那 252 行里有多少是**真的被用到的工具函数**（要拆，不是删）。
>
> **再往下一层量过之后（见 `docs/adapter-cut-plan.md`）**：这 9 个模块的**生产代码**里 egui 相关行
> 合计只有 **67 行**，其中**真 UI 只有 4 行**（`settings::apply_ui_scale_factor` 的 `&egui::Context`、
> `grid_item` 与 `fs_animation` 的 `TextureHandle`）；其余都是 `ColorImage` / `Color32` / `Rect`
> 这三个**与 UI 无关的纯数据类型**的替换。
> 尤其注意 **`canonical_image_loader` 的生产代码是 0 行** —— 它的 7 处引用全在 `#[cfg(test)]` 里。
> → 所以上面那个「301 模块 / 120 脏」是**「不剪边」的假象**，真实代价是可控的。

### 1.3 `crates/` 的干净程度（意外的好消息）

| crate | `.rs` | 碰 egui |
|---|---|---|
| **`unrar-patched`** | 7 | **0** |
| `music-core` | 6 | 0 |
| `susie-worker` / `remote-ipc` / `remote-web` / `launcher` | 5 / 4 / 13 / 3 | 0 |
| `local-adjust-core` | 2 | 2 |
| `comic-core` | 7 | 3 |
| `vst3-host-tester` | 5 | 1 |

→ **`unrar-patched` 完全干净**，这就是「CBR 能力直接复用它的实现、而不是重写」的依据（ADR-0011 第 6 条）。

## 2. spike 2：`[patch.crates-io]` 不跨 workspace 传递，而且**不报错**

脚本 `poc/cargo-patch-scope/run.sh`，原始输出同目录 `results.txt`（4 个案例，都用 `cfg-if` 当假想的 egui）。

| 案例 | 场景 | 实际拿到哪个 cfg-if | 结果 |
|---|---|---|---|
| 基线 | patch 就在自己 workspace 根 | **1.0.0 本地副本** | 编译通过 |
| 1 | 外部有 patch，父 workspace 没有 | **1.0.4 ← crates.io** | 拿到未打补丁的注册表版本 |
| 2 | 父 workspace 自己补一份同样的 patch | 1.0.0 本地副本 | 编译通过 |
| 3 | 外部直接 path 依赖本地副本，父又依赖 crates.io 同名（版本不同） | 1.0.0(路径) **与** 1.0.4(注册表) 共存 | 不报错 |
| 4 | 同上，但父锁到**完全相同的版本** `=1.0.0` | 1.0.0(路径) **与** 1.0.0(注册表) 共存 | **仍然不报错** |

三条结论：

1. `[patch]` **只在它所在的 workspace 根生效**，用作 path 依赖时**不传递**。
2. 症状是**静默**的：父 workspace 会解析到 crates.io 上最新的满足版本
   （实测 `cfg-if = "1"` 拿到 1.0.4，比外部那份本地副本的 1.0.0 还新）。不警告、不报错。
3. **ADR-0007 里「若不薄，会撞上『同名 crate 有两个来源』的构建错误」已被证伪**（案例 3 / 4）：
   同名同版本来自两个来源时 Cargo 允许共存。也就是说**编译器不会告诉你 patch 没生效**。

修法两条，**第二条才是我们该走的**：

- **(a)** rossi 自己的 workspace 根（`rust/Cargo.toml`）写一份同样的 `[patch.crates-io]`
  指向 `vendor/mimageviewer/vendor/egui` —— 实测生效，代价是这张 patch 表要跟上游同步维护。
- **(b)** 让适配层**不依赖任何被 patch 的 crate**。那 patch 传不传递就与我们无关，
  连 (a) 都不需要。**这正是「薄」的意义**：它不只是省代码，它是把这类隐式耦合整条消掉。

## 3. 对既定决策的影响

- **ADR-0005**：「薄」的方向不变，但**工作量的口径要改** —— 不是「统计一次 `use egui` 就完事」，
  而是「逐个种子模块剪反向依赖」的实施工作。风险从「未知」变成「已知、且最小切集是 9 个模块」。
- **ADR-0007**：patch 语义那句已就地更正；spike 两项打勾。
- **ADR-0001**：「抽瘦 lib 时的最大未知是 egui 耦合深度」→ **现在已知**。
- **没有推翻任何 ADR。** 本地核心仍是 mImageViewer（ADR-0011），本次只是把它的代价量化了。

## 4. 下一步

1. **（待用户定）** 是否在检出里 `git merge upstream/main`（落后 34 个提交）。
2. **（待用户定）** 是否 `git lfs pull` 拿那 335 MB 模型（v0.1 不需要，Gate B 才需要）。
3. 把 §1.2 的 9 个模块写成具体工单 —— **已完成**，见 **`docs/adapter-cut-plan.md`**：
   9 个模块生产代码里的 egui 行合计 **67 行**，其中**真 UI 只有 4 行**，
   其余是 `ColorImage` / `Color32` / `Rect` 三个与 UI 无关的纯数据类型的替换。
4. Phase 0 剩余项（`ROADMAP.md`）：三平台 release 构建基线、现有 Reader 的帧率 / 内存 / 翻页延迟基线、
   现有超分链路记录。

## 5. 补测：它的**阅读器也是全尺寸解码**（2026-09-16，只为回答一个具体问题）

问题来源：Rossi 的 Dart 兜底路径上，单页 44.8 MPix 的全尺寸解码 332 ms、而缩到 1600 px 只要 140 ms。
那么「mImageViewer 的阅读器是不是按显示尺寸解码」——如果是，它就有值得我们抄的招。

**答案：不是。它同样全尺寸解码。** 核对如下（`vendor/mimageviewer`，gitlink `1fd6f863`）：

| 环节 | 位置 | 事实 |
|---|---|---|
| 全屏加载主路径 | `src/app.rs:54021` `start_fs_load` | → `start_fs_load_with_purpose`，worker 线程 |
| 解码调用 | `src/app.rs:54639` | `decode_canonical_image(canonical_source, CanonicalDecodeOptions::fullscreen_cancellable(..))` —— **没有任何目标尺寸参数** |
| 上传前唯一的缩小 | `src/app.rs:75236` `clamp_dynamic_for_gpu` | **仅当某条边 > 8192 才触发**，且它是防 `wgpu` 默认 `Limits` **panic** 的安全网，不是性能路径 |
| 那条 8192 的来历 | `src/app.rs:75164-75168` | 注释明说：eframe 用默认 `Limits` 初始化，超 8192 会 panic；RTX 4090 实际能到 16384 |
| TurboJPEG DCT 缩放 | `src/app/cache_ops.rs:481-499` | **只用在缩略图缓存生成**（`thumb_px`），全屏路径不经过它 |
| `compute_display_px` | `src/thumb_loader.rs:966`，被调于 `app.rs:27071 / 34785 / 35911` | 全是**网格 / 缩略图**场景（`cell_w` / `cell_h` / `dpi`），不是阅读器 |

它对同一个代价的处理方式，是**承认它并绕过 UI 线程**，不是消除它：
`app.rs:75174` 的注释写着「UI 线程上跑 `resize_exact(Triangle)`，7K–9K 级图片会**秒级同步卡死**」，
于是它做了两件事 —— ① 换成 SIMD 的 `fast_image_resize`（自称比 `image` 的标量 Triangle 快 **7–10×**）；
② 把 clamp 挪到 worker 线程（`clamp_color_image_for_gpu`）。

### 5.1 三个对 Rossi 直接的结论

1. **这不是「mImage 更快」，也不是「它不做全尺寸」** —— 我们量到的 60 ms 读页 vs 500 ms 解码
   是这条 CPU 路径的固有成本，不是 Rossi 的实现缺陷。它的阅读器同样是全尺寸解码。
2. **GPU 缩放这条线是真的，但它替代不了解码**（见 §5.3）。它把「缩放」放到了 GPU，
   CPU 一次缩放都不用做；但 CPU 的全尺寸解码照付。
3. **真正让它手感好的，是「付在翻页之前」**（见 §5.4 的前后预取），不是任何一次绘制的优化。
   这与 `ROADMAP.md` Phase 1 那条「解码必须移出翻页关键路径」是同一件事 —— 现在有上游代码作旁证。

### 5.2 一处必须读准的数字

ADR-0001 / ADR-0005 / `START_WORK.md` 里的「20MP 26–58 ms/张」注的是**紧随其后的 `load_texture`（上传）**，
**不是解码**。按 Rossi 自己量的吞吐（Skia 全尺寸 ≈ 135 MPix/s），20 MPix 解码应在 **150 ms 量级**；
26–58 ms 对应的是 80 MB RGBA 以 **1.4–3 GB/s** 上卡 —— 只有上传对得上。
两者相差约 3× 且方向不同，读错会把「上传贵」当成「解码便宜」。

### 5.3 它**有** GPU 重采样，但位置在解码**之后**

`src/gpu_lanczos.rs`（**3270 行**）是生产级的全屏重采样，着色器有五个：
`gpu_lanczos_spike.wgsl`（Lanczos3）、`gpu_lanczos_visible_upscale.wgsl`（可见区）、
`gpu_nis.wgsl`（NIS）、`gpu_pixel_aa.wgsl`，以及 `gpu_anime4k{,_s,_m,_l,_ul}.wgsl`（Anime4K）。

关键是它挂在链路的哪一段 —— 模块头第一段就写明了：

> The original `egui::TextureHandle` remains the logical-size owner.
> A native resampled texture only replaces the `egui::TextureId` supplied to paint.

即：**CPU 解码出的全尺寸纹理仍是所有者**，GPU 重采样产物只是替换「绘制时引用的 texture id」。
分支由 `fullscreen_paint_scale_branch(logical_scale, pixels_per_point, post_filter)` 决定
（`src/gpu_lanczos.rs:80-101`）：

| 条件 | 分支 | 含义 |
|---|---|---|
| 近整数且 `physical_scale ≤ 1.0` | `OriginalOneToOne` | 不重采样，直接用原纹理 |
| `physical_scale < 1.0` | **`DownscaleLanczos`** | **缩小由 GPU 做**（CPU 不缩） |
| `≥ 1.0` + `PostFilter::None` | `UpscaleLanczos` | 放大默认走 GPU Lanczos3 |
| `≥ 1.0` + NIS / Anime / PixelArt | `UpscaleNis` / `UpscaleAnime` / `UpscalePixelArt` | 按后处理滤镜选上采样器 |

→ 它的 CPU **从不做缩放**，但 CPU **照做全尺寸解码**。GPU 重采样省掉的是「CPU 重采样那一趟」。
输出另有上限：`MAX_UPSCALE_TARGET_PIXELS = 4096×4096`（16.7 MPix），持久输出每个 ≤ 64 MiB。

### 5.4 手感好的真正来源：**前后预取**

- `src/app.rs:5765`：`enum FsLoadPurpose { Display, Prefetch, AnimationPromotion }`，
  由 `for_page(is_current)` 决定 —— 当前页走 `Display`，邻页走 `Prefetch`。
- `src/app/prefetch_policy.rs:219-222`：**预取张数的设置上限前后都是 10 张**，
  默认 **后方 2／前方 3**；UI 上还有「预取: 已取得／取得中／未取得」的状态指示器。
- 另有一条防饥饿规则（同文件 `PREFETCH_IDLE_THRESHOLD = 100 ms` / `PREFETCH_BACKSTOP = 3 s`），
  不过那是**网格缩略图**的入队抑制，与阅读器邻页预取是两套。

→ **全尺寸解码那笔钱它照付，只是付在翻页之前。** 我们量到的 500 ms 是「裸付」的数字。

### 5.5 给 Rossi 的可用杠杆（按性价比排序，均未实施）

| 杠杆 | 预计收益 | 前提 / 代价 |
|---|---|---|
| **邻页预取**（解码移出关键路径） | 翻页**命中**时解码成本 ≈ 0 | 需要内存/VRAM 预算与淘汰策略；`ROADMAP.md` Phase 1 已列 |
| **JPEG DCT scale**（`turbojpeg`，1/1·1/2·1/4·1/8） | 8192 宽单页 → 1/2 档 ≈ **4× 便宜** | **仅 JPEG**；档位离散，1/2（4096）用于 4K 屏不是无损 |
| GPU 重采样（Lanczos/NIS） | 省掉 **CPU 重采样**那一趟，质量更好 | **不减解码**；多一趟 GPU pass + 一块常驻纹理 |
| 更快的 inflate 后端 | 读页那 60 ms 中的一部分 | 与解码那 500 ms 无关 |

**不要指望 `cacheWidth` / `ResizeImage`**：实测像素量降 45× 只换来解码 4.6×（Skia 仍是先解后缩）——
这条已在 `docs/v0.1-local-core.md` §12 用数据否掉。
