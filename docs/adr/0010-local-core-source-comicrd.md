# 本地核心来源改为 ComicRD，mImageViewer 收窄为超分来源

> **⚠️ 已被 ADR-0011 取代（同日，2026-09-16）。** 本 ADR 的对比表只核对了许可证、依赖数量、
> UI 耦合三件事，**没有核对「读一页的代价」**——它把 `comicrd_core` 的 `rar-sessions`
> （首次访问 chapter 时把整章提取到临时目录）当成了优点。该做法已被明确否决，
> 本地核心来源回退 mImageViewer，ComicRD 降为参考实现。
>
> **仍然成立**的部分：RAR 与解压的代价必须实测、「阅读视图归 Rossi 自己」（来自 ADR-0003）、
> 「几何布局的真源在 Rust」。
> **不再成立**的部分：ComicRD 作为本地核心来源、`vendor/` 的检出对象、
> Phase 0 spike 的问法（`ROADMAP.md` 里本来就仍写着 mImageViewer 版）。

## Context

用户给出线索 `andrizan/comicRD`。核实后，事实与 ADR-0001 的选型前提冲突：

| | `andrizan/comicRD` → `crates/comicrd_core` | `MikageSawatari/mimageviewer` |
|---|---|---|
| 许可证 | MIT | MIT |
| 栈 | **Flutter 3.47+ / Dart ^3.12.1 / Rust 1.98 / FRB 2.13.0**，与 Rossi 完全同代 | Rust + egui |
| 直接依赖 | **9 个**：`rusqlite 0.40.2(bundled)`、`serde`、`serde_json`、`walkdir`、`zip 8.6.0`、`unrar 0.5.8`、`image 0.25.10`、`fast_image_resize 6.1.0` | 含 `ffmpeg`、`pdfium`、`ort`、`tantivy`、`cpal`、VST3 |
| UI 耦合 | **AGENTS.md 明文要求「必须保持可复用，不得依赖 Flutter、Tauri 或生成的桥代码」** | 单体应用，全部模块挂在一个 crate root，含全部 `ui_*` |
| `zip` 版本 | **8.6.0 —— 与 Rossi 现有 `zip 8.2.0` 同大版本，不会双份编译** | `zip 2` —— 会双份编译 |
| 归档覆盖 | 文件夹 · ZIP/CBZ · RAR/CBR —— **恰好等于 v0.1 判据 A 的三种来源** | 追加 7z 与 PDF |
| 大图分块 | **已实现**：`TILE_MAX_HEIGHT = 2048`，适配宽 `min(original, 2048)`，**Rust 是 tile 布局的唯一真源** | 无分块（缩放靠 TurboJPEG DCT scale） |
| 缓存 / 预取 | 已实现且有明文策略：预取窗口 `current ± 2` tile、2 个 page source、16 条 raw tile 字节、`Arc<Vec<u8>>` | 有缓存，但上屏走 CPU RGBA |
| 超分 | **无** | `ort` + Real-ESRGAN / Real-CUGAN / NMKD-Siax |
| 阅读视图 | **只有垂直滚动**（README 的 reader 一节仅列 vertical） | 单页 / 双页 / 跨页 |
| 平台 | Windows 与 Linux 已 smoke test；macOS target 存在、待验 | Windows 11 独占 |

`comicrd_core` 的规模是 8 个 `.rs` / 约 183 KB / `tests/` 下 11 个按关注点拆分的集成测试。

它已经解决了两件 Rossi 还没解决的事：

1. **RAR/CBR 读不了流**（`v0.1_acceptance.md` §4.3 记下的约束）。它的方案有完整生命周期：
   首次访问 chapter 时一次性提取图片条目到 `<app-data>/rar-sessions/chapter-<id>`，
   之后 probe/read 走磁盘；session 跟随已有 page-source LRU（**上限 2**），
   在 `evictChapterPages(chapter_id, [])`、LRU 淘汰、启动时全量清扫三处清理。
   其 backlog 记录了改前的病态成本：`rar_image_bytes` 每请求从头扫 header、
   `get_chapter_pages` 每页全量解压（unrar API 没有 partial read），**CBR 200 页 ≈ 打开时 200 次全量解压**。
2. **大图分块**（`ROADMAP.md` Phase 2 里还是待办的「大图 tile 化」）。

## Decision

1. **本地核心的来源 = `comicrd_core`**：文件系统发现与扫描、归档直读（文件夹 / ZIP·CBZ / RAR·CBR）、
   章节目录、图片解码与缩放、缓存与预取、分块布局、SQLite、进度 / 书签 / 历史、缩略图、备份导入。

2. **mImageViewer 收窄为超分来源**（`ort` 核心 + 模型），服务 Gate B / v0.1 冻结线里的第 5 环。
   **v0.1 不引入它的任何其他部分**——FFmpeg / pdfium / tantivy / 三个被 patch 过的 egui 都不进构建。
   它的另一项不可替代之处是 **7z / PDF 归档**，但这两项在判据之外，暂不处理。

3. **挂载方式沿用 ADR-0007 的形态但换对象**：`vendor/comicRD/` 独立 git 检出 + 父仓库 gitlink +
   rossi 内一个薄封装 crate，把 `comicrd_core` 的 API 映射到 Rossi 的 `PageSource` 契约。
   **与 mImageViewer 不同的是：这里的封装是「映射」而不是「抽瘦」**——`comicrd_core` 本来就是干净的
   可复用 crate，不需要剥离 UI，ADR-0005 里那条「egui 耦合深度未知」的风险在这里不存在。

4. **阅读视图不取 ComicRD，归 Rossi 自己。** ComicRD 的 Reader 是**纯垂直滚动**的
   （契约围绕 `CustomScrollView` + 拍平的 tile 列表 + `_ExactTotalSliverList`），
   **没有单页 / 双页 / 跨页 / RTL / fit 模式**。这些恰好是 Breeze 的 `lib/page/comic_read` 已经做好的部分，
   ADR-0003 已把它定为 UI 基线。
   → **采用原则，不采用契约**：Rossi 从 ComicRD 取「按需页字节 + 尺寸探测 + 分块布局 + 缓存」，
   在它之上自建单页 / 双页 / 垂直三种视图。其中「**几何布局的真源在 Rust**」
   （Rust `f32` 舍入可能与 Dart `double` 差一行）这一条原则要保留。

5. **不采用 ComicRD 的 `app_flutter`**：Riverpod 状态层、路由、主题、Widget 一律不进。
   Rossi 用 BLoC + auto_route（既有约定），只取 `crates/comicrd_core`。

6. **v0.1 的两项取舍**：不补 7z / PDF（判据之外）；
   **暂不启用 AVIF** —— 它走 `image` 的 `avif-native` feature，需要本机 dav1d
   （Windows 要 vcpkg 或 meson 自建并设 `PKG_CONFIG_PATH`），是为一个判据之外的功能付构建复杂度。

## Considered Options

- **维持 ADR-0001，只用 mImageViewer**：归档格式最全（含 7z / PDF）、超分现成。
  但要把一个 16 crate 的单体应用抽成可复用 crate，而它依赖树里带 ffmpeg / pdfium / tantivy，
  还自己 `[patch.crates-io]` 了三个 egui —— 这是 ADR-0005 承认过的最高风险项。
- **只用 ComicRD，完全弃用 mImageViewer**：只维护一份外部源码。
  但超分没有现成实现（`comicrd_core` 完全没有 SR），要自己接 `ort` 与模型。
- **连 ComicRD 的 UI 一起取**：能少写阅读器代码，但会同时放弃 ADR-0003（UI 基线）与
  Breeze 已有的单页 / 双页 / RTL —— 而用户已明确指出这块 Breeze 做得更好。

## Consequences

- **ADR-0001 的「唯一来源」不再成立**，它的其余部分（显示管线不照抄、`include_bytes!` 内嵌模型需要另行搬运）
  对超分那一路仍然有效。ADR-0005 的「薄适配层」形态对两路都成立，但**只有超分那一路有抽瘦风险**。
- **ADR-0007 的落地对象从 mImageViewer 换成 ComicRD**；mImageViewer 的检出推迟到 Gate B 再做，
  v0.1 阶段 `vendor/` 下只有一个检出。
- **Phase 0 的 vendor spike 换目标且换了要问的问题**：不再是「统计 `use egui` 的模块数」，
  而是「把 `comicrd_core` 的公开 API 映射到 `PageSource` 需要补哪些东西」——预期要补的是
  **RAR session 生命周期与「旧版归档项字节流」的差异**（Rossi 侧的归档项必须能给出字节，
  而 `unrar` 路径下它是「先落地再读」）。
- **v0.1 判据 A 的实现成本大幅下降**：三种来源全覆盖，且 `zip` 同大版本不必处理双份。
- **多出一个必须自己写的部件：阅读视图层**（单页 / 双页 / RTL / fit）。它本来就该由 Rossi 拥有
  （ADR-0003），但现在它从「改造 `comic_read`」变成「在 ComicRD 的页字节接口上重建」，
  工作量比原计划大——这是本次换源的主要代价。
- **ComicRD 自己的 Phase C 手工 QA 尚未完成**（tiling 真机、Impeller 内存、桌面 smoke、CI）。
  Rossi 的判据 B / C / D 实际上会顺带验证其中一部分，但不能假设它已被验证过。
- 许可：**MIT**，与 mImageViewer 同级，可原文拷入并保留版权声明；不改变 ADR-0008 的 GPL 约束。
