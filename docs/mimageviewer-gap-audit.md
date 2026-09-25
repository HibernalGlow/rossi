# Rossi × mImageViewer 差距核对（2026-09-20）

上游：`MikageSawatari/mimageviewer`，MIT，检出在 `vendor/mimageviewer/`，
本文写于 pin = `1fd6f863`（`v3.5.0-403-g1fd6f863`，2026-09-13）。
**2026-09-25 子模块 pin 已跟到 `1ffce811`（上游 `main`，`v3.10.0-115`）**，本文的
「上游这块长什么样」按 `1fd6f863` 核对，涉及排序/收藏/远程窗口/ONNX 的结论要按那 115 个提交重读一遍；
搬入模块的偏离清单以 [`local-core-vendored-modules.md`](local-core-vendored-modules.md) 为准。
neoview 的候选在 [`feature-migration-spec.md`](feature-migration-spec.md) 的 N 系列，不在此重复。

本文回答一个具体问题：**「相比 mImageViewer，Rossi 还差哪些」**。
它不是开工清单——ADR-0008 的 v0.1 冻结线仍然优先，线外能力要先进
[`ROADMAP.md`](ROADMAP.md) 才允许动手。本文的作用是把差距**按能不能搬分好组**，
让「先做哪条」成为一个有依据的决定。

---

## 0. 怎么读 / 判定口径

**三个入口交叉验证「已搬」，缺一不可**：

1. `script/sync_vendored_modules.py` 的 `PORTS` 表（正式登记的逐字移植，当前 **10 条**）；
2. **磁盘体量对照**（同名 ≠ 已搬：本地 `books.rs` 7 行 vs 上游 3741 行）；
3. **文件头溯源声明**（移植文件头写 `Vendored from … at commit 1fd6f863`）。

⚠ **`PORTS` 不是全集** —— 本次实测出 4 份同名移植未登记，见 §7.1。所以判定必须走
「清单 + 体量 + 文件头」三入口，只信清单会漏。

**不算「已具备」的四件事**（沿用 `feature-migration-spec.md` §5.3）：上游模块存在、
FRB 暴露了 API、扩展名被识别、状态在 Dart 侧重算。

---

## 1. 五条硬边界（只涉 mImageViewer 时）

| # | 边界 | 具体内容 | 违反后果 |
|---|---|---|---|
| B1 | 许可 | mImageViewer = MIT ⇒ 可原文拷入，**每个文件头保留版权与来源声明** | 混入 GPL 源码把整仓拖成 GPL |
| B2 | 平台 | 上游大量 Windows 专有：`IFileOperation`、WIC、D3D11/DComp、`SHDoDragDrop`、Susie `.spi`（32bit）、DPAPI、WASAPI、`Known Folder API` | 直接搬 = 编译不过，或把跨平台产品锁死 Windows |
| B3 | 架构 | 上游是单体 egui 应用（`src/app.rs` 76 111 行、`src/ui_fullscreen.rs` 70 457 行）⇒ **只搬纯函数 / 纯策略 / 无 UI 模块**；UI 一律在 Flutter 侧重建 | 把 egui 拖进来等于在 Rossi 里重建一个 App |
| B4 | 依赖树 | `local_core` 刻意克制：`anyhow / image / zune-* / zip / unrar(patched) / rusqlite / sha2 / webp / fast_image_resize / jxl / symphonia`。上游的 `ffmpeg / pdfium / ort / tantivy / eframe` **不进这一层** | 依赖爆炸拖垮编译与交叉编译 |
| B5 | 范围 | v0.1 = 本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分（视频已由 ADR-0016 解冻）。OCR / 上色 / Anime4K / 在线源仍在冻结线外 | 冻结线失守，判据 A–E 收敛没有终点 |

**搬运原则**（既有范式）：T1/T2 搬入的源码**保住上游的名字**——函数名、类型名、常量名、
测试名全不改（除 `pub(crate)` → `pub`）；每处刻意偏离登记进 `PORTS`。

---

## 2. 体量现状（为什么要分档，不是「抄一遍」）

| | 体量 |
|---|---|
| 上游 `src/` | **461 个 `.rs` ≈ 91 万行**（顶层 239 个 536 346 行 + 子目录 373 466 行：`app/` 141 695、`video/` 127 458、`ui_dialogs/` 39 453、`remote_ipc/` 34 977、`ai/` 5 615…），另有 16 个 crate |
| Rossi `rust/local_core/src` | **40 个模块 17 928 行**（其中 10 份逐字移植） |

差距不是「少写了几千行」，而是**上游有一整个「图库管理器 + 编辑器」的形状**，
Rossi 要的是「阅读器」。所以下面每条候选的价值由
**「解除的是什么」** 决定，不由行数决定。

---

## 3. 已具备（先说清楚，避免重复提案）

| 能力 | Rossi 落点 | 对应上游 |
|---|---|---|
| 散图文件夹 / ZIP·CBZ / 非固实未加密 RAR·CBR 直读 | `zip_source.rs`、`rar_source.rs`、`folder_source.rs`（逐条目按需读，不落盘） | `zip_loader.rs`（2647）、`rar_loader.rs`（792）——**不是移植**，是重新实现 |
| 解码（jpeg/png/webp/bmp/gif/tiff + JXL 多后端 + AVIF）与降采样解码 | `decode.rs`、`jxl_backend.rs` | `canonical_image_loader.rs`、`wic_decoder.rs` |
| 缩略图目录库 + 文件夹封面合成（四格拼图） | `catalog.rs`（**移植，未登记**）、`thumbnail_pipeline.rs`、`thumb_loader.rs`（切片） | `catalog.rs`、`thumb_loader.rs` |
| 文件浏览：页签 / 面包屑 / 路径编辑 / 列导航 / 搜索 / 类型筛选 / 排序 / 隐藏项 / 穿透 / 视图状态持久化 / 主页 | `file_manager.rs`（2726）、`file_tree.rs`、`settings_db.rs` | 上游这套在 `app.rs`/`ui_main.rs` 的 egui 状态里，**没有可搬模块** |
| 文件树面板（懒展开 + RAII 取消 + 扁平行 + 光标导航） | `folder_pane.rs`（**已搬**，PORTS） | `folder_pane.rs`（1034） |
| 页加载许可（总 6 张 / 2 张留给 High）与预取判决（带理由的纯函数） | `page_load_scheduler.rs`、`prefetch_policy.rs`（**已搬**，PORTS） | `fs_page_load_scheduler.rs`（983）、`app/prefetch_policy.rs` |
| 搜索词法（空格分词 AND、`-` 否定、`"短语"`、部分匹配）+ 匹配归一化 | `search_query.rs`、`search_norm.rs`（**已搬**，零偏离） | 同名的两份 |
| 横长页左右分割 | `page_split.rs`（**已搬**，剥 egui） | `page_split.rs`（484） |
| 缩略图比例自动选择 | `auto_aspect.rs`（**已搬**） | `auto_aspect.rs`（484） |
| 文件浏览的排序 / 隐藏 / 特殊项规则 | `filename_sort.rs`、`fs_entry.rs`、`folder_tree.rs`（**已搬**） | 同名三份 |
| 操作绑定引擎（动作注册表 / 预设 / 冲突 / 轮盘 schema / 绑定表持久化 + 设置页编辑） | `rust/local_core/src/operation_binding/**`、`lib/service/operation_binding/**` | 上游 `keymap.rs`（13 417）——**Rossi 自研，不搬** |
| 视频播放（一页可以是视频） | `lib/video/**`（media_kit / libmpv）+ `wave_peaks.rs` | `src/video/**`（127 458）——**引擎语义映射，不搬解码器**（ADR-0016） |
| 托盘 | `lib/platform/desktop/system_tray.dart` | `tray.rs`（787） |

---

## 4. 还差的（按迁移形态分组）

形态决定成本量级，所以先分组再看收益。「档」见 §5。

### 4.1 T1 — 原文搬（MIT 纯逻辑，零/低依赖）

| 编号 | 能力 | 上游出处（体量） | Rossi 现状 | 依赖增量 | 档 |
|---|---|---|---|---|---|
| **G-01** | **归档转换器**：7z / LZH / 固实 RAR / 嵌套（深度 8）/ 加密 → 无压缩 ZIP，含 `scan_summary*`、`ConvertProgress`、原子替换、上限保护（单条目 4 GiB / 总 32 GiB）、可取消 | `src/archive_converter.rs`（2224） | `archive_converter.rs` **只有 31 行**，只做扩展名与分卷名判定 | `sevenz-rust2`（Apache-2.0 纯 Rust）+ `delharc`（MIT OR Apache-2.0 纯 Rust）；`unrar`/`zip` 已在 | **A** |
| **G-02** | 归档转换缓存：转换产物的 SQLite 索引（SHA-256 key），命中即免转换 | `src/archive_cache.rs`（824） | 无 | 无（`rusqlite`/`sha2` 已在） | **A**（随 G-01） |
| **G-03** | **crash-safe 文件操作事务层**：把移动/复制拆成幂等的 forward/rollback 步骤，每步从路径（复制场景再加 SHA-256）**自证状态** | `src/book_fs_journal.rs`（1253） | 无 | 无（纯 `std` + `serde` + `sha2`，**实测零 Windows API**） | **A** |
| G-04 | IO 信号量与索引优先级（保索引不抢前台 IO） | `src/io_semaphore.rs`（488） | 无 | 无（`std`） | C |
| G-05 | 图片后处理滤镜链（`post_filter.rs`） | `src/post_filter.rs`（2100） | 无 | 待核 | C |

> **G-01 是当前最刺眼的一条**：`file-manager-parity.md` 已明写「双击返回 7z/LZH/PDF 路径
> **不代表** Reader 已能读取它们」；`lib/reader/page_source.dart:152` 更是把 7z / PDF
> 直接归到「不支持的来源格式」。即**识别面比打开面宽**——这是结构性断层，不是缺功能。

### 4.2 T2 — 剥离后搬（MIT，但耦合了上游类型 / UI）

| 编号 | 能力 | 上游出处（体量） | 耦合与剥离方式 | 档 |
|---|---|---|---|---|
| G-10 | 嵌套 ZIP 树（归档内目录可展开 + 分层 materialize） | `zip_tree.rs`（1269） | `crate::grid_item::GridItem`（Rossi 无）→ 写最小适配或抽成纯索引；`settings::SortOrder` 已有 | B |
| G-11 | 递归扫描 + 3-way diff 索引维护 | `search_walker.rs`（846）+ `indexer_progress.rs`（318） | 硬依赖 `fts_meta::FtsMetaDb`（1131，`rusqlite`）。**实测这三份 + fts_meta 里 `tantivy` 引用为 0** ⇒ 换不换搜索引擎都不挡它 | C |
| G-12 | 全文索引搜索体系（三模式 + Tantivy 索引 + 启动对账 + watcher 防抖） | `fts_index.rs`（1951）+ `search_index_db.rs`（1860）+ `fts_meta.rs`（1131）+ `global_search.rs`（788）+ `search_watcher.rs`（387） | 见下「引擎选择」 | C |
| G-13 | 文件名堆叠（一堆图按前缀聚成「一本书」） | `filename_stack.rs`（932）+ `_ui.rs`（796）+ `_script.rs`（625，Rhai） | 同上 `GridItem` + `SortOrder` | C |
| G-14 | 目录代表图**手动固定**（父子级联 pin） | `folder_thumb_pins.rs`（1966） | Rossi 已有自动选代表图（`thumb_loader.rs`），缺「手动 pin」这一层 | C |
| G-15 | 制本（页面收集与安全重排，零填充四位页码） | `books.rs`（3741）+ `book_fs_journal.rs`（见 G-03） | 本地 `books.rs` **只有 7 行**，是 `path_is_under_any` 路径适配，与「制本」无关 | C |
| G-16 | 设置世代备份与手动恢复（`settings.db.bak1`～`.bak10`） | `settings_restore.rs`（1260）+ `db_backup.rs`（374） | 无（`rusqlite` 已在）。配套 `cache_maintenance.rs`（371） | C |
| G-17 | per-位置视图状态整组记忆 | `favorite_view_state.rs`（345） | **部分已有**：`file_manager_view_states`（按目录记忆视图与排序）已落 `settings.db`，但**未覆盖** `thumb_aspect` / `grid_display_order` / 默认阅读方向这些字段 | C |
| G-18 | 内容身份（文件移动/改名后仍能找回编辑与元数据） | `content_identity.rs`（3753）+ `rename_key_migration.rs`（2984） | 无（`rusqlite`/`sha2` 已在）。当前 `path_key` 是**路径**键，文件一移动就断 | C |
| G-19 | 标签 / 评分体系 | `tags_db.rs`（1475）+ `tag_ops.rs`（915）+ `tag_view.rs`（825）+ `tag_write_worker.rs`（550）+ `rating_db.rs`（634）+ `rating_view.rs`（670）+ `folder_rating_counter.rs`（346） | 无。**注**：搜索词法里 `#标签` 能解析，但 Rossi 没有标签库可判，当前退化成普通子串 | C |
| G-20 | 阅读侧书签 / 历史库 | `book_bookmarks.rs`（2655）+ `bookmark_browser.rs`（1428）+ `reading_history_db.rs`（739）+ `spread_db.rs`（916）+ `rotation_db.rs`（374）+ `comic_db.rs`（409）+ `comic_presets.rs`（519） | 部分（Breeze 有历史；书签无） | C |
| G-21 | 显示后处理（边距适配 / 裁边 / 形状适配 / 最终合成 / 3×3 显示矩阵） | `margin_fit.rs`（653）+ `view_trim.rs`（709）+ `shape_fit.rs`（1502）+ `final_composite.rs`（396）+ `displayed_image_transform.rs`（3035） | 部分：`rotation.rs` 已取 `inverse_uv`/`forward_uv`；其余无 | C |
| G-22 | GPU 侧：Lanczos 重采样 / VRAM 预算 / GPU 信息 | `gpu_lanczos.rs`（3270）+ `vram_budget.rs`（342）+ `gpu_info.rs`（654） | 无（Rossi 用 `fast_image_resize` 走 CPU 侧） | C |
| G-23 | 元数据读写（XMP / PNG prompt / EXIF / sidecar） | `xmp_writer.rs`（2069）+ `xmp_reader.rs`（1761）+ `png_metadata.rs`(3443) + `exif_reader.rs`（1538）+ `sidecar.rs`（3551）+ `sidecar_import.rs`(2711) + `save_with_metadata.rs`(1622) + `metadata_transfer.rs`（9942） | 无 | C（图库/编辑语境，见 §6） |
| G-24 | 编辑与标注（补正 / 遮罩 / 擦除 / 矢量编辑 / 裁切导出 / LUT / 上色） | `adjustment*.rs`、`mask_db.rs`（3252）、`conceal*.rs`、`vector_edit.rs`（1597）、`export_crop.rs`（1791）、`creative_lut.rs`（1139）、`colorize.rs`（1842）… | 无 | **排除**（见 §6），此处只登记体量 |

**G-12 的引擎选择（2026-09-19 实测，两条路并列，不替用户拍板）**

搜索栈 14 模块合计 **12 855 行 = 生产 6 094 + 测试 6 761**，但**真正 `use tantivy` 的只有
`fts_index.rs` 一个文件**（生产 880 行）；其余全是 `tantivy::Result` 类型签名或历史迁移命名。

| | A. 原文搬 tantivy | B. 换 SQLite FTS5 |
|---|---|---|
| 新增依赖 | `tantivy`（体积大） | **无** |
| 新增 crate | 闭包 142 个，35 个全新，67 个需版本对齐（顶动全仓 `Cargo.lock`） | **0** |
| 平台 | 五平台重验（mmap / rayon） | 走既有 `rusqlite` 路径，五平台已在编 |
| 改写的代码 | 880 行照搬 + plumbing 适配 | 880 行改写成 FTS5 版 |

FTS5 语义可用已实测（真实中文名 + bigram 切分：`MATCH '星空'` 从 0 命中变 1 命中；
1 字查询与 tantivy 的「最小 2 字」一致）。**前置条件已核实**：`rusqlite` 的 bundled
`libsqlite3-sys 0.28` 带 `-DSQLITE_ENABLE_FTS5`，**FTS5 是现成的**。
> 风险（必须写进判据）：FTS5 不支持自定义 tokenizer ⇒ bigram 只能在 Rust 侧切；
> **查询侧忘了同样切分就静默返回 0 命中**，所以判据里必须配一条「真的搜到过」的正向断言。

**只在「搜索对象变成几十万条带丰富 EXIF/XMP 的图库」时才该选 A。** 上游自己的选型对比
（`docs/search-architecture.md` §6.1）是在**图库管理器**语境下写的，不是漫画阅读器的结论。

### 4.3 T4 — 平台等效重写（撞 B2）

| 编号 | 能力 | 上游出处（体量） | 上游为何搬不动 | 跨平台等效 | 档 |
|---|---|---|---|---|---|
| **G-30** | **文件操作：删除（回收站/永久）、复制、移动、重命名、新建** | `delete_worker.rs`（1100）+ `cut_clipboard.rs`（2191）+ `shell_file_ops.rs`（166） | 顶部 `use` 只有 `std`，**函数体内分别有 11 / 21 / 14 处 Windows API**（`IFileOperation`、`hwnd: Option<isize>`） | `trash` crate（macOS `NSFileManager` / Linux `gio trash` / Windows `IFileOperation`）+ 纯 `std::fs` 逐项结果报告，**外面套 G-03 的事务壳** —— **前半已落地（ADR-0017，§4.3.1）；「套 G-03」那一半仍未做** | **A** |
| **G-31** | **目录监听（外部变化自动刷新）** | 上游用 `notify` crate | Walter 用法散在 `app.rs` 里 | `notify`（MIT/Apache-2.0，跨平台 inotify / FSEvents / ReadDirectoryChangesW） | **A** |
| G-32 | 用其他程序打开 / 在文件管理器中显示 | `open_with.rs`（1267）+ `explorer_integration.rs`（260） | Windows Shell API | `opener` crate 或各平台 API（`open` / `xdg-open` / `explorer /select`） | B |
| G-33 | 文件拖入 / 拖出 | `file_drag.rs`（504） | `IDataObject` + `SHDoDragDrop` | 只在 Flutter 内做应用内拖拽（卡片之间 / 面板之间），**不做平台原生拖出** | C |
| G-34 | 单实例（第二次启动唤起已有窗口） | `single_instance.rs`（922） | Windows 命名互斥 + 消息泵 | 锁文件 / 本地 socket（Dart 侧已有 `window_manager` 基建） | C |
| G-35 | 截图 | `capture.rs`（1212） | Windows 抓窗口/DComp | Flutter `RepaintBoundary` + 平台文件选择 | C |
| G-36 | Android SAF / iOS 安全作用域访问 | —— 上游**不解决**（它是 Windows 独占） | —— | 必须自己设计；`file_tree::get_available_roots()` 目前只有 windows/macos/兜底三分支 | D |
| G-37 | 触屏 / 手柄 / 鼠标轨迹手势的**运行时** | `touch_input.rs`（1024）、`gamepad.rs`（785）、`gesture` 族 | Windows 指针 API | Rossi 已自研绑定引擎且 **schema 一次做全**（`InputDescriptor` 含 `Gamepad` / `MouseGesture` / `Radial`），缺的是运行时与手势采集 | C |

**多选是 G-30 的前置**：上游 `delete_worker::spawn(paths: Vec<PathBuf>, …)` 原生收多路径，
而 Rossi 的 FM 此前**没有任何选中集合**。文件操作与多选必须一起设计，否则会做出
「只能删当前光标那一项」的形态。**这一条已经按它说的方式做了**（ADR-0017）：
`local_core::file_ops::selection` 先落地，`execute` 才拿得到「一串路径」这个输入。

### 4.3.1 G-30 的落地状态（2026-09-20）

已做：`local_core::file_ops`（选中 / 执行 / 剪贴板三块）+ FRB 桥 + MD3 右键菜单 + 多选操作条。
**未做：G-30 那一行原方案里的「外面套 G-03 的事务壳」。** 这不是遗漏而是显式的分期 ——
G-03（`book_fs_journal.rs`，crash-safe 的 forward/rollback 自证）是**另一条**候选，
它要的是「崩溃后重放」，而本轮交付的是「跑完逐条报结果 + 会话内可撤销」：

| 场景 | 本轮的行为 | 要 G-03 才有的行为 |
|---|---|---|
| 批量中途**某一条失败** | 后续标 `cancelled`，已成功的逐条列出，可整批撤销 | 同左 |
| 进程在批量中途**被杀死 / 崩溃** | **停在半路**：已落地的留下，未做的不做；撤销日志随进程一起没了 | 重启后按 journal 自证并回滚 |

所以 G-03 仍然是独立的 A 档候选，**不能因为 G-30 落地就把它划掉**。

---

## 5. 价值档

分档依据是**「这条解除的是什么」**，不是工时：

| 档 | 定义 | 本档候选 |
|---|---|---|
| **A** | 解除**当前已存在**的结构性断层——能力被声明为已有，但用户实际做不到 | **G-01、G-02**（识别 ≠ 能打开：7z/LZH/固实 RAR）、**G-03 + G-30**（文件管理器这个词的下限）、**G-31**（外部变化不刷新） |
| **B** | 已有现成 ADR / ROADMAP 依据 | G-10、G-32 |
| **C** | 框架补齐或体验增强，收益明确但无现成依据 | G-04、G-11～G-29、G-33～G-35、G-37 |
| **D** | 受「移动端最低适配」约束，不参与验收 | G-36 |

**档 ≠ 排期。** A 档只是说「做完能立刻消掉一个已知的不一致」，是否现在做仍由 ADR-0008 与 ROADMAP 裁决。

---

## 6. 明确排除（每条写明撞哪条边界）

| 排除项 | 上游出处 | 理由 |
|---|---|---|
| Susie `.spi` 插件（PC-98 / X68000 格式） | `susie_loader.rs`（1804）+ `crates/susie-worker` | 32bit 子进程 + 二进制协议，**Windows 专有**（B2）。本地 `susie_loader.rs` 只有 5 行，是占位 |
| PDF | `pdf_loader.rs`（6722） | 需要 `pdfium`（B4）。Rossi 现状是「`folder_tree::is_pdf_extension` 认识它、Reader 打不开它」——**要做得先过依赖边界这一关**，不是纯移植 |
| 360° 全景 | `panorama.rs`（1859）+ `panorama_wgpu.rs`（1033） | 与漫画阅读无关；WGSL 渲染在 Flutter 侧无落脚点 |
| 重复检测 / 相似图 / 颜色搜索 | `dupe/`（2945）+ `similar_*.rs` + `color_search.rs`（699） | 需要索引层（B4） |
| 编辑与标注全家桶 | `mask_db.rs`、`conceal*.rs`、`vector_edit.rs`、`export_crop.rs`、`creative_lut.rs`、`ui_erase.rs`… | Rossi 是**阅读器**不是编辑器；且会拖进 `ort`（B4） |
| AI 上色 | `colorize.rs`（1842） | ADR-0008 冻结线外 |
| 音乐视图 / 音频分析 / VST3 宿主 | `crates/music-core`、`crates/vst3-host`、`ui_music_*.rs` | 超出定位（B5） |
| Web Remote（三进程 + HLS 转码） | `crates/remote-web`、`src/remote_ipc/`（34 977） | 需 `ffmpeg`（B4） |
| 视频再编码 / 切片推流 | `src/video/stream/` | 是输出侧子系统，不是播放能力；Rossi 无接收端 |
| TensorRT / DirectML worker pool | `src/ai/`（5615） | NVIDIA 专有；Rossi 的 SR 走既有 CoreML / ncnn / ONNX 矩阵 |
| AI 生成元数据（PNG/EXIF prompt） | `png_metadata.rs`、`exif_reader.rs` | 「AI 绘画图库」场景 |

**「排除」≠「永不做」**：要重启先按 CONTEXT.md 改 ADR-0008 与 ROADMAP。

---

## 7. 本次核对查出的三件事

### 7.1 `PORTS` 漏登记 4 份同名移植（同步盲区）

`script/sync_vendored_modules.py` 只守 10 份文件。但磁盘上还有：

| 本地 | 上游 | 证据 | 风险 |
|---|---|---|---|
| `catalog.rs`（1871 行） | `catalog.rs`（1880 行） | 10 个同名顶层 `pub fn` + 日文注释原样 | 上游改它**不会报警** |
| `fast_resize.rs`（178 行） | `fast_resize.rs`（326 行） | 5 个同名 `pub fn`（`resize_rgba8_exact` 等） | 同上 |
| `thumb_loader.rs`（368 行） | `thumb_loader.rs`（4510 行） | 文件头写明 `Vendored from … at commit 1fd6f863` | 只搬了切片，上游那 4142 行里的纯逻辑长出来了没人管 |
| `rotation.rs`（137 行） | `displayed_image_transform.rs`（3035 行） | `inverse_uv` / `forward_uv` 同名 | 同上 |

**后果**：`file-manager-parity.md` 里「五份源码与固定版本的差异均已登记」这句话
只对 `PORTS` 里的那几份成立。**建议**：把这 4 份并进 `PORTS`（或写进文档的显式例外表），
否则「上游更新时一条命令跑完就知道要不要跟」这个承诺是打折的。

### 7.2 既有文档里已过时的现状描述

| 文档 | 过时的话 | 现在 |
|---|---|---|
| `feature-migration-spec.md` §3.1 | M-15「`decide_partial` 暂无消费者」 | 已接通（`search_entries`） |
| 同上 §3.2 | M-16 列在「未搬」 | **已搬并接通到卡片**（`file_manager_tree_snapshot`） |
| 同上 §3.2 | M-19 列在「未搬」 | **部分已做**（`file_manager_view_states` per-目录视图与排序） |
| 同 §2 / ROADMAP | 「视频播放不进 v0.1」 | **已解冻**（ADR-0016），`lib/video/` 已落地 |
| `file-manager-parity.md` §「尚未接通」 | 「视频/音频仍缺阅读器适配」 | 视频已有（media_kit）；音频仍缺 |
| `file-manager-parity.md` | 「工作台的绑定表持久化 + 设置页编辑 UI」待做 | 已有 `operation_binding_setting_page.dart` / `radial_binding_editor.dart` |

### 7.3 差距的**形状**归纳（一句话版）

Rossi 与 mImageViewer 的差距集中在四块，其余是长尾：

1. **写不出去**——文件操作、目录监听、归档转换、制本，全属「对用户数据做修改」的动作；
   `local_core` 生产代码里目前**一处用户路径写操作都没有**（实测：`fs::remove_file|rename|copy|create_dir`
   只在测试夹具里出现），所以这四块是同一类缺口。
2. **索引不起来**——标签 / 评分 / 全文索引 / 内容身份 / 阅读元数据库。
3. **认得出打不开**——7z / LZH / 固实·加密 RAR / PDF / 音频。
4. **编辑器那一半**——明确不做（§6）。

---

## 8. 判据与验收

搬源码类沿用既有机制，不发明新流程：

```bash
cd rust && cargo test -p rossi_local_core      # local_core 不在 default-members，裸 cargo test 跑不到
python script/sync_vendored_modules.py         # 自检：有没有未登记的偏离
dart analyze lib/                              # 连目录跑
```

**逐条补充（每条都要负例，不能只断言「没出错」）**：

| 候选 | 必须有的判据 |
|---|---|
| G-01 | `verify_output_zip` 不能省；损坏包要返回 `ConvertError` 而不是产出半截 ZIP；分卷后续卷 `looks_like_non_first_rar_part` 必须为真 |
| G-02 | 缓存命中与失效各一条（改 mtime 后必须重转，不能只断言「第二次更快」） |
| G-03 | 每个步骤都要有「崩溃在中间态之后能接着做完 / 能回滚」的用例；幂等性要真跑两遍 |
| G-12 | **FTS5 路线必须配「真的搜到过」的正向断言**（查询侧漏切 bigram 是静默 0 命中的形状） |
| G-30 | 删除要覆盖「回收站 vs 永久」「目标已存在」「中途被打断」；不能只断言「文件没了」 |
| G-31 | 要断言「外部新建文件后列表**真的变了**」，只断言「没有报错」是空转 |

---

## 9. 挂钩与变更规则

| 本文候选 | 关联文档 |
|---|---|
| G-01 / G-02 / G-30 / G-31 / G-10 | `docs/file-manager-parity.md`（「尚未接通」表是原始口径）、`docs/file-manager-acceptance.md` |
| G-03 | ADR-0011（文件操作与归档读取的所有权划分） |
| 全部 T1 / T2 | `docs/local-core-vendored-modules.md`、ADR-0001 / 0005 / 0007 / 0011 |
| G-12 / G-11 | `feature-migration-spec.md` 的 M-17 / M-18 |
| 全部 | ADR-0008、`docs/v0.1_acceptance.md`（**准入门槛**：线外候选需先改 ADR-0008） |

**变更规则**：

1. 候选被采纳 ⇒ 移出本文、进 ROADMAP（本文只留「尚未进入路线」的）。
2. 新增候选必须给**可定位的上游出处与体量**（本文所有路径已实测存在，脚本见 §7.1 建议）。
3. 排除项变更要写明**哪条边界变了**，不能只删行。
4. **「已搬」判定以磁盘为准，且负向结论必须换工具复核**（shell `grep` 的交替会被吞成静默零匹配，
   见 `~/.workbuddy/MEMORY.md`）。
