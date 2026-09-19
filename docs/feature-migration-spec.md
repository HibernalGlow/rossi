# Rossi 功能迁移候选规格

整理日期：2026-09-19。上游两台「矿」：**mImageViewer**（Windows 11 独占，v3.10.0 / MIT，作为本地
能力的来源与标杆）与 **neoview**（自有项目 Xiranite 的 React / TypeScript 前端，作为视觉、交互
与纯逻辑的参考；许可无碍，但技术栈不取 —— 见 B3）。

本文把**两者中尚未迁移的成体系能力**整理成候选池。每条候选给出：上游出处、体量、Rossi 现状、
迁移形态、依赖增量、准入门槛与价值档。

> **这不是开工清单。** ADR-0008 的 v0.1 冻结线仍然优先，且 CONTEXT.md 要求「线外能力要先进
> `docs/ROADMAP.md` 才允许动手」。本文的作用是**把候选一次盘点清楚**，让「要不要做、先做哪条」
> 成为一个有依据的决定，而不是每次重新翻上游。
>
> 已知事实口径见 [`file-manager-parity.md`](file-manager-parity.md)（文件管理器并集核对）与
> [`local-core-vendored-modules.md`](local-core-vendored-modules.md)（已搬模块的溯源与同步）。
> 本文不重复它们，只写**尚未迁移**的部分。

---

## 0. 怎么读这份文档

三条读法：

1. **先看第 1 节的硬边界**。五条边界里任何一条不满足，候选直接不成立——不看收益。
2. **再看第 2 节的迁移形态**。形态决定成本量级：`T1 原文搬` 与 `T4 平台等效重写` 是两个物种。
3. **候选清单按形态分组，不按功能域分组**。因为「能不能搬」比「重不重要」更早筛掉人。

**「已搬」与「未搬」的判定口径**：以 `rust/local_core/src/` 与 `lib/workspace/` 的**磁盘内容**为准，
不以扩展名识别、FRB 已暴露、上游模块存在为准。这条口径沿用 `file-manager-parity.md` §开头。

---

## 1. 五条硬边界

| # | 边界 | 内容 | 违反的后果 |
|---|---|---|---|
| B1 | **许可** | mImageViewer 是 MIT ⇒ 可原文拷入（保留版权与来源声明，每个文件头都要写）。**neoview 是自有项目**，许可不构成障碍，其代码可读可翻译（翻译形态见 T3 与 B3）。GPL-3.0 的 Venera-SSR / ntrn 只能读不能抄 | 混入 GPL 源码会让整仓分发被拖成 GPL |
| B2 | **平台** | Rossi 跨平台（Windows / macOS / Linux 为桌面主战场，Android / iOS 仅最低适配）。mImageViewer 大量代码是 Windows 专有：`IFileOperation`、WIC、D3D11、`SHDoDragDrop`、Susie `.spi`（32bit）、DPAPI、WASAPI | 直接搬 = 编译不过，或把跨平台产品锁死在 Windows |
| B3 | **架构与技术栈** | 两侧各有各的墙：mImageViewer 是单体 Egui 应用（`src/app.rs` 3.5 MB、`src/ui_fullscreen.rs` 3 MB），**只能搬纯函数 / 纯策略 / 无 UI 模块**，不能整体依赖（ADR-0005 的「适配层」定义）；neoview 是 **React / TypeScript**，而 Rossi 的 UI 是 Flutter / Dart，ADR-0003 明确「**技术栈不取**」⇒ **组件不能搬，纯逻辑可逐行翻译**。UI 一律在 Flutter 侧重建 | 把 egui 或 React 拖进来等于在 Rossi 里重建一个 App |
| B4 | **依赖树** | `local_core` 当前依赖刻意保持克制：`anyhow / image / zune-* / zip / unrar(patched) / rusqlite / sha2 / webp / fast_image_resize / jxl`。上游带的 `ffmpeg / pdfium / ort / tantivy / eframe` **不进这一层** | 依赖爆炸会拖垮编译时间与本机调试路径 |
| B5 | **范围** | v0.1 冻结线 = 本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分。线外能力（在线源 / OCR / 上色 / Anime4K / 视频）不进实现，且「进范围必须先改 ADR-0008 与 ROADMAP」 | 冻结线一旦失守，判据 A–E 的收敛就没有终点 |

**搬运原则（沿用既有范式）**：T1 / T2 搬入的源码**保住上游的名字**——函数名、类型名、常量名、
测试名全不改（除 `pub(crate)` → `pub`）。这样上游改了哪个函数能一一对应上，否则每次升级都是一次重读。
刻意偏离必须登记进 `script/sync_vendored_modules.py` 的 `PORTS` 表。

### 1.1 选源规则（mImageViewer 优先）

**每一块能力先问 mImageViewer 有没有**：有 ⇒ 走 M 系列（T1 / T2 / T4）；**mImageViewer 确实没有
对应模块**才落到 N 系列（T3，neoview 契约重建）。本规则由用户 2026-09-19 明确。

理由是同栈与异栈的差别：mImage 是 Rust ⇒ **可原文搬、可随上游同步**（`sync_vendored_modules.py`
的 PORTS 表 + `--bump` 流程）；neoview 是 React / TypeScript ⇒ 只能翻译，逐行等价性要自己证明。
**能用搬的就不翻译。**

「mImageViewer 有」的判定要跟到**模块注释与公开面**，不能只看文件名。两个已踩过的反例：

- `folder_tree.rs` 名字像「文件树」，实际是 **DFS 导航器**（把 ZIP / PDF 当虚拟文件夹，供
  Ctrl+Up/Down 用）；真正的**文件树面板**是 `folder_pane.rs`（其模块注释明确写了这个分工）。
- `books.rs` / `zip_loader.rs` 本地同名文件只有 7 / 19 行，上游同名文件却是 3741 行。

**「有」还分三档**，直接决定搬的成本：全 `pub` + 零依赖（T1，最便宜）→ 通体 `pub(crate)`
（要按既有范式改 `pub` 并登记 PORTS）→ 绑 Windows API（T4，只能等效重写）。
`search_query.rs` / `search_norm.rs` / `search_walker.rs` 属第一档，`folder_pane.rs` /
`cut_clipboard.rs` 属第二档，`delete_worker.rs` / `shell_file_ops.rs` 属第三档。

---

## 2. 迁移形态分类

| 形态 | 含义 | 判据 | 成本量级 |
|---|---|---|---|
| **T1 原文搬** | MIT 源码，依赖已就位或只差许可干净的小 crate，无 UI，无平台绑定 | 文件头加版权声明即可编译；单测一起搬 | 低 |
| **T2 剥离后搬** | MIT 源码，但耦合了上游类型（`GridItem` / `settings` / `egui`） | 先写适配类型或剥掉 UI 部分，再搬 | 中 |
| **T3 契约重建** | neoview 的实现**可读、可翻译**（自有项目，无许可障碍），但组件不能搬（B3 技术栈）。`domain/` 纯规则可**逐行翻译成 Dart**；`application/` 对照重写；`features/` 只取视觉语言 | 翻译后的 Dart 行为能与其源码逐条对照；不引入任何 React / Node 依赖 | 中 |
| **T4 平台等效重写** | 逻辑有价值，但上游实现绑死 Windows API | 用跨平台 crate 或各平台原生 API 重写 | 高 |
| **T5 排除** | 不适配 Rossi 定位，或有硬边界冲突 | —— | —— |

---

## 3. 候选清单

### 3.0 先确认「已搬」——避免重复提案

判定「已搬 / 未搬」的**两个权威入口**：`script/sync_vendored_modules.py` 的 `PORTS` 表（正式登记的
原文搬）+ **本地文件体量与上游对照**（同名 ≠ 已搬）。

| 上游模块 | 本地对应 | 状态 |
|---|---|---|
| `src/folder_tree.rs` | `rust/local_core/src/folder_tree.rs` | **已搬**（PORTS；本地 1622 / 上游 1594 行） |
| `src/fs_entry.rs` | `rust/local_core/src/fs_entry.rs` | **已搬**（PORTS） |
| `src/filename_sort.rs` | `rust/local_core/src/filename_sort.rs` | **已搬**（PORTS） |
| `src/auto_aspect.rs` | `rust/local_core/src/auto_aspect.rs` | **已搬**（PORTS） |
| `src/fs_page_load_scheduler.rs` | `rust/local_core/src/page_load_scheduler.rs` | **已搬**（PORTS） |
| `src/app/prefetch_policy.rs` | `rust/local_core/src/prefetch_policy.rs` | **已搬**（PORTS） |
| `src/catalog.rs` | `rust/local_core/src/catalog.rs` | **已搬**（本地 1871 / 上游 1880 行，日文注释为证） |
| `src/settings.rs` | `rust/local_core/src/settings.rs` | **已搬「切片」**（含 `SortOrder` / `ThumbAspect` / `ReadingDirection` / `SpreadMode` 等，为各纯策略模块提供底座） |
| `src/page_split.rs` | `rust/local_core/src/page_split.rs` | **已搬**（PORTS；B3 几何解耦） |
| `src/folder_pane.rs` | `rust/local_core/src/folder_pane.rs` | **已搬**（PORTS；文件树面板状态机） |

**这份表的直接含义**：`folder_tree.rs` 已搬 ⇒ 它的 `walk_dirs_recursive*` / `sorted_subdirs` /
`navigate_folder_with_skip` 等**递归遍历底座已经在本地**，凡是「递归走目录」的需求先看它，别重复提案。

**编号与形态的对应**（编号按**加入顺序**分配，形态决定它落在哪一节 ⇒ 编号在节之间是跳跃的）：

| 节 | 形态 | 编号 |
|---|---|---|
| 3.1 | T1 原文搬 | M-01～M-06、**M-15** |
| 3.2 | T2 剥离后搬 | M-07～M-09、**M-16～M-20** |
| 3.3 | T3 契约重建 | N-01～N-30 |
| 3.4 | T4 平台等效重写 | M-10～M-14 |

### 3.1 T1 — 原文搬（mImageViewer，MIT）

#### M-01 归档转换器（7z / LZH / 固实 RAR / 嵌套 / 加密 → 无压缩 ZIP）

- **出处**：`vendor/mimageviewer/src/archive_converter.rs`（2224 行）
- **能力**：`ArchiveFormat`（RAR / 7z / LZH / ZIP）、`scan_summary*`、`convert_to_zip*`、
  `ConvertProgress`、`ConvertOptions`、密码路径（`*_with_password`）、嵌套归档递归
  （`MAX_NESTED_ARCHIVE_DEPTH = 8`）、原子替换（`replace_file_atomic`）、上限保护
  （单条目 4 GiB / 总输出 32 GiB）、可取消（`AtomicBool`）
- **Rossi 现状**：`rust/local_core/src/archive_converter.rs` **只有 31 行**，仅做扩展名判定与
  RAR 分卷名识别。`file-manager-parity.md` 已明写「双击返回 7z/LZH/PDF 路径**不代表** Reader 已能读取它们」
- **依赖增量**：`sevenz-rust2`（Apache-2.0，纯 Rust 7z）+ `delharc`（MIT OR Apache-2.0，纯 Rust
  LHA/LZH，3345 行代码）。`unrar` 与 `zip` **已在** `local_core`。三个 crate 都与 MPL-2.0 兼容
- **准入门槛**：超出 v0.1 覆盖度要求（v0.1 只要 CBZ / CBR / 散图文件夹）⇒ 需先落 ROADMAP
- **价值档**：**A** —— 直接解除「识别 ≠ 能打开」这个当前最刺眼的结构性缺陷

#### M-02 归档转换缓存

- **出处**：`vendor/mimageviewer/src/archive_cache.rs`（824 行）
- **能力**：转换产物的 SQLite 索引（`rusqlite` + `Sha256` key），命中即免转换
- **Rossi 现状**：无
- **依赖增量**：无（`rusqlite` / `sha2` 已在依赖里）
- **准入门槛**：M-01 的配套，单独存在无意义
- **价值档**：**A**（随 M-01）

#### M-03 内容身份（文件移动 / 复制后仍能找回编辑与元数据）

- **出处**：`vendor/mimageviewer/src/content_identity.rs`（3753 行）
- **能力**：`size → 64 KB → 全量` 三段哈希的渐进身份判定；`rename_key_migration` 配套
- **Rossi 现状**：无。当前的 `path_key` 是**路径**键，文件一移动就断
- **依赖增量**：无（`rusqlite` / `sha2` 已在依赖里）
- **准入门槛**：它服务于「编辑与元数据」——而那块整体在 v0.1 线外。**先有 M-01/M-10 再谈它**
- **价值档**：**C** —— 本身很干净，但当前没有消费方

#### M-04 缩略图比例自动选择

- **出处**：`vendor/mimageviewer/src/auto_aspect.rs`（484 行）
- **能力**：log 比率中位数 + 6 段门控，为一批缩略图选统一长宽比
- **Rossi 现状**：已接通。源码搬入 `rust/local_core/src/auto_aspect.rs`，`settings.rs` 补充 `ThumbAspect` 薄适配，`thumbnail_pipeline.rs` 接入 `pick_aspect_from_dimensions` 与 `pick_aspect_for_cached_book`
- **依赖增量**：仅需 `settings::ThumbAspect`（本地 `settings.rs` 已是同款薄适配）
- **价值档**：**C**


#### M-05 目录代表图手动固定（父子级联 pin）

- **出处**：`vendor/mimageviewer/src/folder_thumb_pins.rs`（1966 行）
- **能力**：把某个子条目的图 pin 成父容器（文件夹 / 归档）的代表图，级联到最终 leaf
- **Rossi 现状**：无
- **依赖增量**：待核（需先确认它对 `catalog` 之外还引用了什么）
- **价值档**：**C**

#### M-06 制本（页面收集与安全重排）

- **出处**：`vendor/mimageviewer/src/books.rs`（3741 行）+ `book_fs_journal.rs`
- **能力**：零填充四位数页码、crash-safe 的重排日志
- **Rossi 现状**：`rust/local_core/src/books.rs` **只有 7 行**——只是一个
  `path_is_under_any` 的路径适配，与「制本」无关
- **依赖增量**：待核（3741 行里估计有 UI 与设置耦合，需按 B3 剥离）
- **准入门槛**：属于「写文件」类能力，跨平台风险高于 M-01
- **价值档**：**C**

#### M-15 搜索查询语法与文本归一化（递归搜索的第 0 层）

- **出处**：`vendor/mimageviewer/src/search_query.rs`（610 行）+ `src/search_norm.rs`（96 行）
- **能力**：
  - `search_query`：`parse(&str) -> Vec<Token>`、`matches` / `matches_with_mode` /
    `matches_lowercased_with_mode`、**`decide_partial`（边打边搜的增量部分匹配判定）**、
    `MatchMode`、`PartialResult`
  - `search_norm`：`normalize_for_match`（索引期 / 查询期 / 后置过滤**三处必须同一函数**，否则出假阴性）、
    `zip_entry_key`（`<zip_path>\x1F<entry>`，用 ASCII Unit Separator 结构性排除
    `book.zip!cover.jpg` 这类歧义）
- **可搬性（最好的一档）**：**两者通体 `pub`、`pub(crate)` 零处、外部依赖零个**（只有 `std`），
  且文件内自带 `#[cfg(test)]` 单测 ⇒ 纯 T1，连适配类型都不用写
- **Rossi 现状**：**已搬**（`rust/local_core/src/search_query.rs` + `search_norm.rs`，
  零偏离逐字拷贝，已登记 PORTS）。`file_manager.rs` 的 `matches_entry` 与新的
  `search_entries` 都走 `parse` + `matches_lowercased_with_mode`，hay 侧走
  `normalize_for_match`。`decide_partial` 暂无消费者（它是为「避免读 XMP」设计的，
  Rossi 的遍历没有那种分段成本模型），按「保住上游名字」的原则随文件一起搬入
- **依赖增量**：**无**
- **准入门槛**：无。这条是「递归搜索」里最便宜、最早能用上的一块
- **落地补充（2026-09-20）**：M-15 只给词法，递归与页签是同一批做的 ——
  `search_entries` 广度优先 + 层数/条数上限 + `AtomicBool` 取消，命中写进
  `FileManagerTab.search`。见 [功能核对](file-manager-parity.md)
- **价值档**：**A** —— 单一函数就能把「搜索」从子串匹配升级成带语法（否定 / 引号 / 多词 / 部分匹配）
  的查询，且**对当前目录搜索也立即生效**，不必等索引体系

### 3.2 T2 — 剥离后搬（mImageViewer，MIT）

#### M-07 嵌套 ZIP 树

- **出处**：`vendor/mimageviewer/src/zip_tree.rs`（1269 行）
- **能力**：`ZipTree` / `ZipDir` 树状导航 + 分层 materialize，归档内目录树可展开
- **Rossi 现状**：无嵌套归档支持（ADR-0011 明确「v0.1 不实现嵌套」）
- **耦合**：`crate::grid_item::GridItem`（Rossi 无此类型）、`crate::settings::SortOrder`（已有）
- **剥离方式**：为 `GridItem` 写最小适配，或把树结构抽成不依赖 item 的纯索引
- **价值档**：**B** —— 与 M-01 的自然延伸（转换器已能递归展开嵌套归档）

#### M-08 文件名堆叠

- **出处**：`vendor/mimageviewer/src/filename_stack.rs`（932 行）+ `filename_stack_ui.rs`
  + `filename_stack_script.rs`（Rhai 脚本分类）
- **能力**：按文件名前缀把一堆图聚合成「一本书」，可在聚合⇔扁平之间切换
- **Rossi 现状**：无（`file-manager-parity.md` 未接通项里列的是紧邻的「视图模式」，
  堆叠是更远的一层）
- **耦合**：同上 `GridItem` + `settings::SortOrder`
- **价值档**：**C**

#### M-09 横长页左右分割

- **出处**：`vendor/mimageviewer/src/page_split.rs`（484 行）
- **能力**：`SpreadMode::SplitLtr / SplitRtl`，横长跨页的切割顺序与坐标映射
- **Rossi 现状**：**已搬**至 `rust/local_core/src/page_split.rs`（登记入 PORTS）
- **耦合与剥离**：按 B3 剥离 `eframe::egui`，提供纯 Rust 几何类型 `Pos2` / `Rect`（`NormalizedRect`）；`Rotation` 与 `inverse_uv` 收敛至 `rust/local_core/src/rotation.rs`；`SpreadMode` 收敛至 `rust/local_core/src/settings.rs`
- **价值档**：**B** —— Phase 4「双页」的必备件，且预期剥离成本低

#### M-16 文件树面板（懒展开树状态机）

- **出处**：`vendor/mimageviewer/src/folder_pane.rs`（1034 行）；对应 UI 在 `src/ui_folder_pane.rs`
  （473 行、46 处 egui，**不搬**，在 Flutter 重建）
- **能力**：
  - 类型：`FolderPaneState` / `FolderPaneNode` / `FolderPaneRow` / `FolderPaneTreeKey` /
    `FolderPaneCommand` / `FolderPaneScanPending`
  - **懒展开**：`ensure_scans_for_expanded` / `ensure_scan` / `poll_pending`（只扫描展开的节点）
  - **异步扫描 + RAII 取消**：`FolderPaneScanPending` 的 `Drop` 即取消（同 ADR-0014 那类「撤旗子」手法）
  - **可见行扁平化**：`visible_rows`（树 → 扁平行，直接喂虚拟列表）
  - **游标导航**：`move_cursor` / `collapse_cursor` / `expand_cursor` / `handle_tree_key` / `set_cursor`
  - **深度保护**：`MAX_TREE_DEPTH = 64`
  - **与激活路径同步**：`sync_to_active` / `reload_for_active` / `set_focus_tree` / `set_focus_grid` /
    `cursor_nav_target_if_moved`；`scan_real_subfolders`
- **与已搬的 `folder_tree.rs` 的分工（关键，别搞混）**：上游模块注释写得很明确——
  > `folder_tree` 是 Ctrl+Up/Down 的 **DFS 导航器**，且**把 ZIP / PDF 当虚拟文件夹**；
  > `folder_pane` 是**左侧文件系统树面板**，**只显示真实文件系统目录**。

  本地已搬的是**前者**，**后者未搬** ⇒ 这正是 `file-manager-parity.md` 里的「文件树」缺口
- **耦合与剥离**：
  - 依赖只有 `std` + `crate::settings::SortOrder`（**本地 `settings.rs` 已提供**）⇒ 剥离面很小
  - 通体 `pub(crate)`（25 处）⇒ 按既有范式改 `pub` 并登记 PORTS
  - `refresh_drives` 是 Windows 盘符枚举（`DRIVE_REFRESH_THROTTLE = 1500 ms`）⇒ 替换为既有的
    `file_tree::get_available_roots()`
- **Rossi 现状**：**已搬**（`rust/local_core/src/folder_pane.rs`，已登记 PORTS 表，通过 10 项全平台测试）
- **依赖增量**：**无**
- **价值档**：**A** —— 与 M-15 同属「不必等索引体系就能落地」的一档

#### M-17 递归扫描与索引差分（`search_walker`）

- **出处**：`vendor/mimageviewer/src/search_walker.rs`（846 行）+ `src/indexer_progress.rs`（318 行）+
  `src/io_semaphore.rs`（488 行）
- **能力**：`scan(fav_id, root, db, ...)` 递归遍历并与 `fts_meta.db` 做 **3-way diff**（FS 现状 vs 索引），
  产出 `CandidateFile` / `CandidateKind` / `ScanResult` / `ScanDiag` / `WalkerEvent`；
  `indexer_progress` 负责进度上报，`io_semaphore`（`GlobalIoSemaphore` + `IoPriority`）保证索引不抢前台 IO
- **可搬性**：`search_walker` 通体 `pub`（`pub(crate)` 零处），但**硬依赖 `fts_meta::FtsMetaDb`**
  ⇒ 要动就得连带搬 `fts_meta.rs`（rusqlite，1131 行）
- **引擎无关（好消息）**：这三个模块 + `fts_meta.rs`（生产 679 行）里 **`tantivy` 引用为 0 处**，
  全走 `rusqlite` ⇒ **换不换全文引擎都不影响这一层**，可独立推进
- **⚠ 这一条做的是「索引维护」**（增量差分），不是「用户当场搜一次」。若只想要**递归文件名搜索**，
  本地已有的 `folder_tree::walk_dirs_recursive*` **直接可用**，不必引入 `fts_meta`
- **实测修正（2026-09-20）**：`walk_dirs_recursive` 收集的是**目录**（`Vec<PathBuf>`），
  拿不到「这一条是不是已识别媒体 / 是否被隐藏策略滤掉」。所以递归搜索没有复用它，
  而是在 `file_manager::search_entries` 里按层展开、逐条目走
  `file_tree::node_for_dir_entry`（与整目录列举同一策略出口），环保护复用
  `fs_entry::mark_directory_visited`。若将来做 M-17，这一层的遍历可以直接换成它
- **价值档**：**C**（除非确定要做索引式搜索，否则 M-15 + 已有的 `walk_dirs_recursive` 就够）

#### M-18 全文索引搜索体系（本池最重的一条）

- **出处**：`fts_index.rs`（1951）+ `search_index_db.rs`（1860）+ `fts_meta.rs`（1131）+
  `global_search.rs`（788）+ `search_watcher.rs`（387）
- **能力**：三模式搜索（容器名 / 当前地过滤 / 全局元搜索，架构见
  `vendor/mimageviewer/docs/search-architecture.md`）、Tantivy 全文索引（`INDEX_VERSION` 协议、
  Tantivy First 写入协议）、启动时 reconciliation、FsWatcher + debounce 增量索引、
  ZIP / PDF / 视频 / 音频各格式 scope、标签与 facet
- **依赖增量（重）**：
  - `tantivy`（全文引擎）← **新增，体积大**；B4 已明确写「`tantivy` 不进 `local_core` 这一层」
  - `notify`（文件监听）+ `crossbeam_channel`
  - `rusqlite` / `sha2` / `uuid` 已在
- **准入门槛**：**高**。它不只是「加个搜索框」，而是一整套索引生命周期（建库 / 迁移 / 崩溃修复 /
  watcher 防抖 / 启动对账）
- **价值档**：**C** —— 收益真实，但与「本地漫画阅读器」的体量不匹配。**默认不选**

**引擎选择（2026-09-19 实测，两条路二选一）**

先把体量拆开，否则「12k 行」会误导：搜索栈 14 模块合计 **12 855 行 = 生产 6 094 + 测试 6 761**。
其中**真正引用 `tantivy` 的只有 `fts_index.rs` 一个文件**（生产 880 + 测试 1070）；
其余模块的 tantivy 出现处**全是 `tantivy::Result` 类型签名或旧标签迁移的命名**
（`global_search.rs` 只在错误重试处、`fts_writer_dispatcher.rs` / `ingest_worker.rs` 只在签名、
`indexer_manager.rs` / `tags_db.rs` 只在 `import_legacy_tantivy_tags` 这条历史迁移路径）。
⇒ **换引擎 = 重写 `fts_index.rs` 的生产 880 行，plumbing 不动。**

| | **A. 原文搬 tantivy** | **B. 换 SQLite FTS5** |
| --- | --- | --- |
| 新增依赖 | `tantivy = "0.26"`（`default-features=false` + `mmap`/`lz4-compression`） | **无** |
| 新增 crate | 闭包 **142** 个，其中 **35 个全新**，**67 个需版本对齐**（会顶动全仓 `Cargo.lock`） | **0** |
| 平台 | 五平台重验（mmap / rayon 线程） | 走既有 `rusqlite` 路径，**五个平台已经都在编** |
| 改写的代码 | 880 行照搬 + plumbing 适配 | 880 行改写成 FTS5 版 |
| 用到 tantivy 的比例 | —— | 实测只用到 TermQuery / BooleanQuery / TopDocs / 自定义分词器；`QueryParser`、facet、range、fuzzy、regex、highlight、聚合、fast field **全部零使用** |

FTS5 这条路**语义可等价**，已用 `sqlite3` 实测（不是推断）：

```text
真实中文名「漫画星空全集第01话.cbz」
  unicode61 直查 MATCH '星空'      => 0 命中   ← 整段 CJK 被当成一个 token
  预切成 bigram 后 MATCH '星空'     => 1 命中
  预切成 bigram 后 MATCH '星空 全集' => 1 命中（多 bigram 隐式 AND）
  1 字查询 MATCH '星'              => 0 命中   ← 与 tantivy bigram「最小 2 字」语义一致
ASCII 同理：索引切了 bigram，查询也必须切（未切查 'diff' => 0，切 'di if ff' => 1）
trigram tokenizer 直查 2 字        => 0 命中   ← 印证 mImage 文档 §6.1 的「3 字下限」
```

前置条件已核实：`rust/local_core/Cargo.toml` 的 `rusqlite = { version = "0.31", features = ["bundled"] }`
—— `libsqlite3-sys 0.28.0` 的 `build.rs` 里带着 `-DSQLITE_ENABLE_FTS5`，**FTS5 是现成的**。

> **风险与反例（必须写进判据）**：FTS5 **不支持自定义 tokenizer**，所以 bigram 只能在 Rust 侧切、
> 显式入库，索引体积比原文字符数大一档；**查询侧若忘记同样切分，会静默返回 0 命中**（上面场景 A 就是）。
> 这条与「手势被静默拒绝」同类，判据里必须配一条「真的搜到过」的正向断言。
> tantivy 的优势（BM25 排序 / facet / 高亮 / 几十万条元数据索引）在**图库管理器**场景才划算——
> mImage 的 §6.1 选型对比正是在那个语境下写的，别把它当成漫画阅读器的结论。

- **建议**：先做 **M-15**（查询语法 + 归一化，零依赖，最干净的一档）；真要做索引式全文搜索时
  走 **B（FTS5）**——它的外骨骼 **M-17**（`search_walker`）**一行 tantivy 都没有**，先搬它不吃亏。
  留着 tantivy 不引入，除非将来搜索对象变成「几十万条带丰富 EXIF/XMP 的图库」。
- **备选（形态更轻）**：neoview 的 `searchReaderFileTree`
  （`packages/nodes/neoview/src/application/browser/ReaderFileTreeSearch.ts`，196 行）是
  **即时异步流式**——返回 `AsyncDisposable` handle，不建索引、每次遍历，慢但零存储。
  与之配套的 `ReaderFileTreeIndex.ts`（190 行）提供分页懒加载节点（`ReaderFileTreeNodePage`）

#### M-19 per-位置视图状态持久化（「持久化」这块里 mImage 的答案）

- **出处**：`vendor/mimageviewer/src/settings.rs` 的 `FavoriteViewState`（约 3595–3640 行）
  + `src/settings_db.rs`（7231 行，SQLite 后端）
- **能力**：`FavoriteViewState` 把**每个位置**的视图状态整组记忆：
  `grid_view_mode`（视图模式）、`grid_cols`（列数 ⇒ 用户感知的缩略图大小）、
  `thumb_aspect` / `thumb_aspect_auto`（缩略图比例）、`grid_display_order`、
  `sort_order`（排序）、`default_spread_mode` / `default_reading_flow`（阅读方向）。
  配套 `from_settings` / `apply_to_settings` 双向同步，以及「`common` 是正本，viewer context
  切换时先回公共值再套 overlay」的规则
- **配套**：`settings_db.rs` = SQLite（`settings.db`）+ `serde_json` 的键值存储后端
- **Rossi 现状**：
  - 视图模式只有 列表 / 网格
  - 排序本身有（`compare_entries`），但**没有「按目录记忆」**
  - FM 的页签 / 布局**未纳入** `WorkspaceLayoutSnapshot`（已核：该文件里无任何 FM 字段）
- **依赖增量**：**无**（`rusqlite` / `serde_json` 已在）
- **重要边界**：**mImageViewer 没有「页签」概念**（egui 单窗口 + 文件夹导航）⇒
  **页签布局与启动恢复仍走 neoview（N-23 / N-24），不要在这里找**
- **价值档**：**A**

#### M-20 设置世代备份与手动恢复

- **出处**：`vendor/mimageviewer/src/settings_restore.rs`（1260 行）
- **能力**：列出「当前设置 + 世代备份 `settings.db.bak1`～`.bak10` + 升级前快照」，让用户选用哪一代
  替换回去。起因是**真实事故**——`cargo test` 用 defaults 踩烂了生产 `settings.db`
- **Rossi 现状**：无
- **依赖增量**：**无**（`rusqlite` 已在）
- **准入门槛**：M-19 的配套（先有 `settings.db` 才谈世代）
- **价值档**：**C**

### 3.3 T3 — 契约重建（neoview；纯逻辑可逐行翻译，组件不搬）

> **选源复核（2026-09-19，按 §1.1 规则）**：以下 N 条目逐条回查了 mImageViewer 侧。结论——
> **能搬的已上提到 M 系列**，留在 N 系列的都是 mImage 确实没有对应模块的：
>
> | N 条目 | mImage 侧复核结论 | 去向 |
> |---|---|---|
> | N-01 文件树 | **有**（`folder_pane.rs`，1034 行，零 egui，通体 `pub(crate)`） | → **M-16** |
> | N-02 面包屑 | 逻辑在 egui 地址栏（`ui_main::AddressBarNav`），无独立可搬模块 | 留 N |
> | N-03 多选 / 焦点 / 范围选择 | **Rust 侧无选中集合**（在 egui UI 状态里；`delete_worker` 只收 `Vec<PathBuf>`） | 留 N |
> | N-04 视图模式 | 部分（`GridMode` 在 `settings.rs`）；封面 / 横幅 / 详情的展示契约在 UI 层 | 留 N，视图状态见 **M-19** |
> | N-06 目录排序偏好 | **有**（`FavoriteViewState` 含 `sort_order` + per-位置整组记忆） | → **M-19** |
> | N-23 页签布局持久化 | **无**（mImage 无页签概念，是单窗口 + 文件夹导航） | 留 N |
> | N-24 启动恢复 | 部分（`known_folders.rs` + `StartupFolderMode`，但**是 Windows 专有 Known Folder API**） | 留 N |
> | **递归搜索**（原缺条目） | **有**，且分三层 | → **M-15 / M-17 / M-18** |
>
> 未列出的 N 条目（N-05 / N-07～N-22 / N-25～N-30）多为 Reader 展示层、输入绑定、预加载与缓存——
> 那部分 mImageViewer 同样有实现，但深度绑 egui，按 B3 只能走契约重建，留在 N 系列正确。

neoview 的分层很规整，四层正好对应四种处理方式（下层越纯，能搬得越彻底）：

```text
packages/nodes/neoview/src/domain/      纯领域规则     ← 可逐行翻译成 Dart（最值得搬）
packages/nodes/neoview/src/application/ 应用服务编排   ← 对照重写（流程与状态机可循）
packages/nodes/neoview/src/platform/    平台适配       ← 读它如何隔离平台差异，映射到 Rossi 平台层
src/nodes/neoview/features/             React UI       ← 只取视觉语言与交互方式（组件不搬）
```

**注意目录位置**：`application/` / `platform/` / `domain/` 在 `packages/nodes/neoview/src/` 下，
**不在** `src/nodes/neoview/`（后者只有 `features/`、`app/`、`adapters/`）。按 GUI 路径去找会全部落空。

**文件浏览层**

| 编号 | 能力 | 上游出处 | Rossi 现状 |
|---|---|---|---|
| N-01 | 文件树（独立于页签的懒展开树索引 + 搜索 + watcher） | `packages/.../application/browser/ReaderFileTreeService.ts`、`ReaderFileTreeIndex.ts`、`ReaderFileTreeSearch.ts`；UI 为 `src/nodes/neoview/features/panels/cards/folder/FolderTreePanel.tsx` | 缺（`file-manager-parity.md` 列此项） |
| N-02 | 面包屑（可编辑 + 逐级列导航） | 同上 `folder/` 卡片族；`neoview-card-functional-checklist.md` 的 `folder-ui` 组 | 缺 |
| N-03 | 多选、焦点、范围选择与批量操作入口 | `application/browser/ReaderDirectorySelection.ts`、`application/files/ReaderDirectorySelectionOperationService.ts` | 缺 |
| N-04 | 视图模式（封面 / 横幅 / 详情 / 缩略图）与共享展示契约 | `src/nodes/neoview/features/panels/readerFilePresentation.ts`；文档 `neoview-explorer-ui-guidelines.md` | 只有列表 / 网格 |
| N-05 | 底部缩略图条与缩略图 surface | `src/nodes/neoview/features/thumbnails/ThumbnailStrip.tsx`、`ReaderThumbnailSurface.tsx` | 缺 |
| N-06 | 目录排序偏好（每目录持久化 + 锁定） | `application/browser/ReaderDirectorySort.ts`、`ReaderDirectorySortPreferences.ts`、`domain/sorting/natural-sort.ts` | 已有排序本身，**缺按目录记忆** |
| N-07 | 搜索历史（独立存储 + 旧格式导入） | `application/browser/ReaderSearchHistoryService.ts`、`migration/LegacySearchHistoryCodec.ts` | 缺 |
| N-08 | 目录元数据懒加载与水合（滚动按需补，失败可重试） | `application/browser/LazyReaderDirectoryMetadataProvider.ts`、`ReaderMetadataHydratingScanner.ts` | 缺 |
| N-09 | 受保护标签导航（`search` / `efu` 不可被外部浏览覆盖） | 文档 `neoview-folder-tab-navigation.md` | 缺（这条是非显然契约，容易漏） |

**Reader 展示层**

| 编号 | 能力 | 上游出处 | Rossi 现状 |
|---|---|---|---|
| N-10 | 页面布局模式（单页 / 双页 / 全景 / 宽页拆分 / 连续虚拟窗口 / 旋转重排） | `domain/frame/frame-builder.ts`、`features/reader/ReaderPanoramaFrame.tsx` | 无（ROADMAP Phase 4 已列） |
| N-11 | 缩放 / 适应 / 旋转 / 放大镜 / 光标自动隐藏 | `features/reader/ReaderMagnifierLayer.tsx`、`domain/view/ReaderMouseCursor.ts`、`useReaderMouseCursorAutoHide.ts` | 无 |
| N-12 | 阅读方向与页面顺序（LTR/RTL、首尾跳转、随机页、运行时重排） | `domain/navigation/navigation.ts`、`application/reader/ReaderPageOrder.ts` | 部分（`page_order.rs` 有顺序判定，无 UI 语义） |
| N-13 | 图片效果（颜色滤镜 / 自动裁边 / 页面过渡 / 长图悬停滚动） | `features/color-filter/`、`features/image-trim/`、`features/page-transition/`、`useReaderHoverScroll.ts` | 无 |
| N-14 | 阅读背景（solid / ambient / aurora / spotlight） | `features/reader/ReaderBackgroundLayer.tsx`、`features/panels/cards/AmbientBackgroundCard.tsx` | 无 |
| N-15 | 信息悬浮窗（图上叠加书籍 / 图片信息） | `features/info-overlay/ReaderInfoOverlayStore.ts` | 无 |
| N-16 | 幻灯片自动翻页 | `application/slideshow/ReaderSlideshow.ts`、`features/reader/ReaderSlideshowToolbar.tsx` | 无 |
| N-18 | 阅读进度层可视化 | `features/reader/ReaderProgressLayer.tsx` | 部分（`reader_history_service.dart` 有进度保存） |

**状态与配置层**

| 编号 | 能力 | 上游出处 | Rossi 现状 |
|---|---|---|---|
| N-19 | 每本书设置（布局 / 方向覆盖 + revision CAS 回滚） | `application/reader/ReaderBookSettingsService.ts` | 无 |
| N-20 | 历史 / 书签 / 进度（去重、排序、flush 时机） | `application/library/ReaderLibraryService.ts`、`features/library/reader-library-mutations.ts` | 部分（历史有，书签无；且是 Breeze 在线语境） |
| N-21 | 历史自动清理（`on-show` / `interval`，只删 missing 不删 unknown） | `application/library/ReaderLibraryCleanupService.ts` | 无 |
| N-22 | 设置导入 / 导出 / 备份 / Gist（模块选择、merge/overwrite） | `application/migration/ReaderSettingsPortableService.ts`、`platform/backup/ReaderBackupBundleService.ts` | 无 |
| N-23 | 面板 / 卡片布局持久化（补齐页签布局与默认值注册表） | `application/config/ReaderShellDefaults.ts`、`ReaderLayoutManifest.ts` | 部分（ADR-0014 已做面板栏，**FM 页签布局未持久化**） |
| N-24 | 启动恢复（最近书 / 文件夹 / 窗口状态 / 工作区快照） | `app/ReaderStartupRestore.ts`、`ReaderWorkspaceRestoreStore.ts` | 部分 |

**框架与性能层**

| 编号 | 能力 | 上游出处 | Rossi 现状 |
|---|---|---|---|
| N-25 | 输入绑定系统（上下文键绑定、单击/双击/按住、九宫格区域、冲突阻止保存） | `domain/input/ReaderInputBindings.ts`、`features/input/ReaderInputRouter.tsx` | v0.1 已有键盘/鼠标/滚轮/触屏/区域；**自定义与冲突检测待做**（ADR-0009 已定形态） |
| N-26 | 径向菜单 | `features/input/ReaderRadialMenuOverlay.tsx`、`vendor/ray-menu/` | 无（ADR-0009 留了 schema 占位） |
| N-27 | 预加载协调器（View / Ahead / Background 优先级、方向感知、背压、快速翻页取消） | `application/preloading/PreloadCoordinator.ts` | 部分（`prefetch_policy.rs` 是**判决**，无协调器） |
| N-28 | 统一缓存生命周期（LRU / 磁盘 L3 / singleflight / lease / pin / 字节预算） | `application/cache/ReaderCacheService.ts`、`platform/cache/*` | 部分 |
| N-29 | 全局优先级资源调度器（多工具共存的 lease 队列、interactive slot） | `platform/scheduler/PriorityResourceScheduler.ts` | 部分（`page_load_scheduler.rs` 只覆盖页加载） |
| N-30 | 诊断 / 基准 / 系统监控卡片 | `application/diagnostics/ReaderDiagnosticsService.ts`、`features/panels/cards/SystemMonitorCard.tsx` | 部分（`perf_sink.rs` 是上游 `perf.rs` 的极简替代） |

### 3.4 T4 — 平台等效重写

#### M-10 文件操作（复制 / 移动 / 重命名 / 新建 / 删除）

- **上游出处**：`vendor/mimageviewer/src/shell_file_ops.rs`（166 行）、`delete_worker.rs`（1100 行）、
  `cut_clipboard.rs`（2191 行）、**`book_fs_journal.rs`（1253 行）**
- **上游能力**：
  - 删除（回收站 vs 永久）、copy / cut、进度与冲突处理；
    `delete_worker::spawn(paths: Vec<PathBuf>, hwnd: Option<isize>)` 原生收多路径
  - **`book_fs_journal` 是这一条里最值钱的部分**——它是 **crash-safe 的文件系统操作计划**：
    > The bookmark DB owns persistence and phase transitions. This module owns the deterministic
    > filesystem steps and their idempotent forward/rollback rules. A persisted `next_step` is only a
    > hint: every step also proves its state from the source/destination paths and, for copied files,
    > a SHA-256 identity.

    即把移动 / 复制拆成**幂等的 forward / rollback 步骤**，每步都能从路径（复制场景再加 SHA-256）
    **自证状态**，崩溃后可以接着做完或回滚
- **可搬性实测（逐个数过）**：
  - `book_fs_journal.rs`：**零 Windows API**，纯 `std` + `serde` + `sha2` ⇒ **可 T1 先搬**
  - `shell_file_ops.rs`：顶部 `use` 只有 `std`，但函数体内 **11 处 Windows API** ⇒ T4
  - `delete_worker.rs`：`std` + **21 处 Windows API**（`hwnd: Option<isize>`）⇒ T4
  - `cut_clipboard.rs`：`std` + **14 处 Windows API**，且**通体 `pub(crate)`（30 处）** ⇒ T4
- **⚠ 依赖核实教训（与 M-01 同一个坑）**：这四个文件的**顶部 `use` 全是 `std`**，看起来零平台依赖——
  真正的 Windows 调用在**函数体内全路径引用**。只看文件头会得出完全相反的结论
- **平台问题**：`IFileOperation` 是 Windows COM API（B2）。跨平台等效：
  - 删除走系统回收站 ⇒ `trash` crate（macOS `NSFileManager` / Linux `gio trash` / Windows `IFileOperation`）
  - 复制 / 移动 ⇒ 纯 `std::fs` + 逐项结果报告，**外面套 `book_fs_journal` 的事务壳**
- **Rossi 现状**：**`local_core` 生产代码内无任何对用户路径的写操作**（只有 `catalog.rs` 的缓存清理）；
  FM 侧也还没有多选（选中集合未建立，见 N-03）
- **建议拆分**：**M-10a** = `book_fs_journal` 事务层（T1，先搬，零平台依赖）；
  **M-10b** = 跨平台操作实现 + 多选（T4，绑 Windows 的部分全部重写）
- **价值档**：**A** —— `file-manager-parity.md` 把它列为核心缺口，且它是「文件管理器」这个词的下限

#### M-11 目录监听（外部变化自动刷新）

- **上游出处**：`vendor/mimageviewer/src/` 的 watcher 用法（`notify` crate）
- **Rossi 现状**：无 `notify` 依赖
- **依赖增量**：`notify`（MIT/Apache-2.0，跨平台 inotify / FSEvents / ReadDirectoryChangesW）
- **价值档**：**A**

#### M-12 文件拖出 / 拖入

- **上游出处**：`vendor/mimageviewer/src/file_drag.rs`（`IDataObject` + `SHDoDragDrop`）
- **平台问题**：桌面三平台的 D&D 机制各不相同，Flutter 侧已有 `Draggable` / `DragTarget`
- **建议**：**不做平台原生拖出**，只在 Flutter 内做应用内拖拽（卡片之间、面板之间）
- **价值档**：**C**（降级形态）

#### M-13 系统集成（用其他程序打开 / 在文件管理器中显示）

- **上游出处**：`open_with.rs`、`explorer_integration.rs`
- **跨平台等效**：`opener` crate 或各平台 API（`open` / `xdg-open` / `explorer /select`）
- **Rossi 现状**：无
- **价值档**：**B**

#### M-14 移动端存储访问（Android SAF / iOS 安全作用域）

- **上游**：不适用——**mImageViewer 与 neoview 都不解决这个问题**，两者都是桌面
- **Rossi 现状**：`file_tree::get_available_roots()` 只有 windows / macos / 兜底三分支
- **注**：这一条不是「迁移」，而是**必须自己设计**。放在 T4 只因为它与 M-10/M-11 同属文件层的平台差异问题
- **价值档**：**D**（受「移动端最低适配」约束，不参与验收）

---

## 4. 价值档定义

分档依据是**「这条候选解除的是什么」**，不是工时估计：

| 档 | 定义 | 本档候选 |
|---|---|---|
| **A** | 解除**当前已存在**的结构性断层——能力被声明为已有，但用户实际做不到 | M-01、M-02、M-10、M-11 |
| **B** | 已有**现成的 ADR / ROADMAP 依据**，做它是执行既定路线 | M-07、M-09、M-13、N-10、N-11、N-12、N-25、N-27 |
| **C** | 框架补齐或体验增强，收益明确但无现成依据 | M-03～M-06、M-08、M-12、N-01～N-09、N-13～N-24、N-26、N-28～N-30 |
| **D** | 受横切约束（移动端最低适配）限制，当前不参与验收 | M-14 |

档位**不等于排期**。A 档只是说「做完能立刻消掉一个已知的不一致」，
是否现在做仍取决于 ADR-0008 与 ROADMAP 的裁决。

---

## 5. 判据与验收

### 5.1 T1 / T2（搬源码）

沿用 `local-core-vendored-modules.md` 的既有机制，不发明新流程：

```bash
# 1. 单测（上游的单测一起搬，函数名不改）
cd rust && cargo test -p rossi_local_core
# 注意：local_core 不在 default-members，裸 cargo test 只跑 windcore，跑不到这些判据

# 2. 同步脚本自检：确认没有未登记的偏离
python script/sync_vendored_modules.py     # 退出码 0 = 无需处理

# 3. 静态分析（连目录跑）
dart analyze lib/
```

**额外要求（M-01 专属）**：`convert_to_zip` 的验收必须包含**负例**——
`looks_like_non_first_rar_part` 对分卷后续卷要返回真，`convert_to_zip` 对损坏包要返回
`ConvertError` 而不是产出一个半截 ZIP。上游的 `verify_output_zip` 已经做了这件事，**搬的时候不能省**。

### 5.2 T3（契约重建）

neoview 可以「读着翻」而不是「猜着做」，按层用不同的验收方式：

1. **`domain/` 层 —— 翻译等价性**。逐行翻译的代码，验收方式是**输入输出逐一对照**：
   把 `packages/nodes/neoview/test/` 下对应的用例改写成 Dart 测试。这是最强的验收，
   也是 T3 里性价比最高的部分（N-27 预加载协调 / N-28 缓存生命周期 / N-29 资源调度属于这一类）。
2. **`application/` 层 —— 流程对照**。状态机与编排逻辑按它的流程重写，逐条对照分支与边界。
3. **UI 层 —— 行为对照**。先用它现成的验收清单：`neoview-card-functional-checklist.md`
   按 Card 逐项写好了判据（如 `folder-ui.tree`、`file-tree.*`）。
   **把它当测试用例来源，不要自己重新想。**
4. **交互契约必须写进 Dart 测试**：结构事件 / 点击次序 / 驻留时长这类「容易静默失效」的行为，
   配上「真的发生过」的断言（ADR-0014 的教训：手势被静默拒绝时「次序不变」照样通过）。
5. **变异验证**：`python3 test/workspace/mutation_check.py`。每个变异体**从干净基线出发**
   （前一个残留会让后一个假红），并区分「判据失败」与「编译错」。

### 5.3 不算判据的东西

- 上游模块存在 ≠ Rossi 已具备该能力
- FRB 暴露了 API ≠ 用户能完成对应操作
- 扩展名被识别 ≠ Reader 能打开
- 状态在 Dart 侧重算 ≠ 通过（状态应归属 Rust）

---

## 6. 明确排除

| 排除项 | 上游 | 理由 |
|---|---|---|
| Susie `.spi` 插件（PC-98 / X68000 格式） | mImageViewer `susie_loader.rs` / `susie-worker` | 32bit 子进程 + 二进制协议，**Windows 专有**（B2）；`local_core` 里的 `susie_loader.rs` 只有 5 行，是占位而非实现 |
| VST3 宿主 | `crates/vst3-host` | 音乐创作领域，与漫画阅读器无关（B5） |
| TensorRT / DirectML worker pool | `src/ai/trt_worker_pool.rs` | NVIDIA 专有；Rossi 的 SR 走既有 CoreML / ncnn / ONNX 矩阵 |
| Web Remote（三进程 + HLS 转码） | `crates/remote-web`、`remote_ipc` | ROADMAP Phase 7 才谈 Web；且它需要 `ffmpeg`（B4） |
| 音乐视图 / 音频分析（波形 / 频谱 / BPM） | `crates/music-core` | 超出定位（B5） |
| 编辑与标注（补正 / 遮罩 / inpaint / 裁切 / SNS 导出 / 注解图形） | 上游半个 `src/` | Rossi 是**阅读器**不是编辑器；且这块会拖进 `ort`（B4） |
| 360° 全景 | `panorama.rs` / `panorama_wgpu.rs` | 与漫画阅读无关；WGSL 渲染在 Flutter 侧无落脚点 |
| 重复检测 / 相似图搜索 / 颜色搜索 | `dupe/pdq.rs`、`similar_index.rs`、`color_search.rs` | 需要 `tantivy` 索引层（B4）。**若将来要做，优先看 neoview 的 `platform/thumbnails` 而非这一套** |
| 触控（Windows 指针 / tap zone / pinch） | `touch_input.rs` 等 | 上游是 Windows 触屏；Rossi 的手势语义应由 Flutter 侧统一（B3） |
| AI 生成元数据读取（PNG/EXIF prompt） | `png_metadata.rs`、`exif_reader.rs` | 与漫画阅读无关；且是「AI 绘画图库」的场景 |

**「排除」不等于「永不做」**：它们只是**当前不适配**。若要重启，先按 CONTEXT.md 的要求改 ADR-0008 与 ROADMAP。

---

## 7. 与既有文档的挂钩

| 本文候选 | 关联文档 | 关系 |
|---|---|---|
| 全部 T1 / T2 | `docs/local-core-vendored-modules.md`、ADR-0001 / 0005 / 0007 / 0011 | 搬入流程与溯源机制照它走 |
| M-01 / M-02 / M-10 / M-11 / N-01～N-09 | `docs/file-manager-parity.md` | 该文档的「尚未接通」表是本文这些候选的**原始口径** |
| M-10 / M-15 / M-16 / M-17 / M-19 | `docs/file-manager-parity.md`、`docs/file-manager-acceptance.md` | 用户 2026-09-19 点名的三块未完成缺口（**持久化 / 文件树与文件操作 / 递归搜索**）的落点 |
| N-10～N-18 / N-27 | `docs/ROADMAP.md` Phase 4「Reader 体验」 | 本文的候选是它的细化 |
| N-25 / N-26 | ADR-0009、CONTEXT.md「操作绑定」 | **schema 已定**（输入描述、上下文、冲突、绑定包），本文只补运行时子集 |
| N-23 | ADR-0014、`docs/adr/0014-workspace-interaction-behaviors.md` | 面板栏持久化已完成，**FM 页签布局是缺口** |
| 全部 | ADR-0008、`docs/v0.1_acceptance.md` | **准入门槛**：v0.1 冻结线优先，线外候选需先改 ADR-0008 |
| 本文候选的判据 | `docs/file-manager-acceptance.md` | 两者互补：那份是「文件管理器并集」的判据，本文是「候选池」的索引 |

---

## 8. 变更规则

1. **候选被采纳 → 从本文移到 ROADMAP**。本文只保留「尚未进入路线」的候选。
2. **新增候选必须给出上游出处与体量**。找不到可定位文件的能力不写进来。
3. **排除项变更需写明理由**（哪条边界变了），不能只删行。
4. 本文的「已/未迁移」判定**以磁盘为准**，且必须**用 ripgrep 复核负向结论**——
   本机 `grep` 的 BRE 交替 `\|` 会被吞掉，产生静默零匹配（详见 `~/.workbuddy/MEMORY.md`）。
5. **选源规则（§1.1）优先于形态分组**：新增候选必须先查 mImageViewer **有没有**，没有才写进 N 系列。
   判定「有没有」要跟到**模块注释 + 公开面 + 平台痕迹**三处，不能只看文件名或文件头的 `use`。
   2026-09-19 按此规则做的修订：N-01 → **M-16**、N-06 → **M-19**；新增 **M-15 / M-17 / M-18 / M-20**；
   **M-10** 拆为 M-10a（`book_fs_journal` 事务层，T1）+ M-10b（跨平台实现，T4）。
