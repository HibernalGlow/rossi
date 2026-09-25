# 从 mImageViewer 搬进来的模块（溯源与同步）

> 这份文档只讲一件事：`rust/local_core` 里有**直接从 `vendor/mimageviewer` 搬来的源码模块**，
> 上游更新时怎么把它们的能力更新吃进来。
>
> 适用前提是你已经知道复用形态是 gitlink + path 依赖（[ADR-0007](adr/0007-mimageviewer-vendor-checkout.md)）。
> 其中的两个策略模块**不能用 path 依赖**，理由见下；文件浏览器使用的源码模块
> 另列在第 2 节。

---

## 1. 为什么是搬源码，而不是 `use`

上游把这两个策略模块藏得比想象中深：

| 上游路径 | 上游可见性 | 结果 |
|---|---|---|
| `src/fs_page_load_scheduler.rs` | `lib.rs:122` 是 `mod fs_page_load_scheduler;`（**私有**），内里一律 `pub(crate)` | 跨 crate 看不见 |
| `src/app/prefetch_policy.rs` | `lib.rs:28` 是 `mod app;`（**私有**），`lib.rs` 只 re-export 了 `LocalAiActivityLease` 和 `draw_video_thumbnail_indicator_snapshot_fixture` | 同上 |

即使 `path` 依赖进来了，`mimageviewer::fs_page_load_scheduler::FsPageLoadScheduler` 也解析不到。
所以只能搬源码 —— 但**搬的方式决定了以后能不能跟**。

**搬的原则：保住上游的名字。** 函数名、类型名、常量名、测试名全部不改（除 `pub(crate)` → `pub`）。
这样上游改了哪个函数、加了哪个分支，都能一一对应上；否则每次升级都是一次重读。

## 2. 清单

| 本地 | 上游 | 搬取时的上游 commit |
|---|---|---|
| `rust/local_core/src/page_load_scheduler.rs` | `src/fs_page_load_scheduler.rs` | `1fd6f863` |
| `rust/local_core/src/prefetch_policy.rs` | `src/app/prefetch_policy.rs` | `1fd6f863` |
| `rust/local_core/src/auto_aspect.rs` | `src/auto_aspect.rs` | `1fd6f863` |
| `rust/local_core/src/page_split.rs` | `src/page_split.rs` | `1fd6f863` |
| `rust/local_core/src/perf_sink.rs` | —— **本地新增**，上游对应物是 `src/perf.rs`（完整 JSONL 性能日志系统） | —— |


文件浏览器还直接使用下面三份 mImageViewer 源码。它们保留上游模块名，
`file_tree::list_directory` 不再自行复制一套扩展名、隐藏项或平台排序规则：

| 本地 | 上游 | 用途 |
|---|---|---|
| `rust/local_core/src/folder_tree.rs` | `src/folder_tree.rs` | 虚拟文件夹、媒体扩展名、归档候选、路径解析、DFS 穿透 |
| `rust/local_core/src/folder_pane.rs` | `src/folder_pane.rs` | 文件树面板状态机、懒展开扫描、RAII 取消、可见行扁平化、游标导航 |
| `rust/local_core/src/fs_entry.rs` | `src/fs_entry.rs` | Windows reparse point、隐藏属性、内部 bundle 过滤 |
| `rust/local_core/src/filename_sort.rs` | `src/filename_sort.rs` | Windows sort key、大小写折叠和自然数字排序 |
| `rust/local_core/src/thumb_loader.rs` | `src/thumb_loader.rs` | 文件夹代表图递归选定、自动缓存键组装与代表图解析 |
| `rust/local_core/src/search_query.rs` | `src/search_query.rs` | 搜索查询语法：空格分词 AND、`-` 否定、`"..."` 短语、`MatchMode`、`decide_partial` |
| `rust/local_core/src/search_norm.rs` | `src/search_norm.rs` | 匹配用文本归一化 `normalize_for_match`（查询期 / 后置过滤同一函数）|

这两份搜索源码是**零偏离逐字拷贝**：上游本就通体 `pub`、只依赖 `std`、文件内自带单测，
所以 `PORTS` 里两条规则的四个字段全空（M-15，见 [迁移清单](feature-migration-spec.md)）。
`search_norm::zip_entry_key` 在 Rossi 侧暂时无人调用 —— 它属于索引层（M-18），
按「保住上游名字」的原则一并搬入，为将来的索引留接口；`pub` 项不会触发 `dead_code`。

这七份里**有六份**纳入 `sync_vendored_modules.py`：`folder_tree.rs` / `folder_pane.rs` /
`filename_sort.rs` 的 `pinned_at` 已跟到 `1ffce811`（2026-09-25 融合上游的排序改动），
`fs_entry.rs` / `search_query.rs` / `search_norm.rs` 上游自 `1fd6f863` 起零改动，
`pinned_at` 保持原值（内容与 `1ffce811` 一致）。

`thumb_loader.rs` **刻意不登记 PORTS**：本地那 368 行是从上游 4510 行里切出的文件夹代表图
子集，并按 Rossi 需要改过结构（多子项拾取、归档候选、失败回退、有界循环），逐行 diff
只会产出一份毫无意义的报告 —— 与下面 §2.1 的 `file_ops` 同一口径。代价是上游改这个文件时
脚本不会报警，只能人工读（2026-09-25 这次就跟进了它的「列表用排序值不得进入代表图选择」
守卫）。`docs/mimageviewer-gap-audit.md` 把这条切片列为待管缺口。

### 2.1 `file_ops`：**刻意不登记 PORTS** 的一块（ADR-0017）

| 本地 | 上游 | 为什么不在 PORTS 里 |
|---|---|---|
| `rust/local_core/src/file_ops/{selection,execute,clipboard}.rs` | `delete_worker.rs` / `cut_clipboard.rs` / `shell_file_ops.rs`（**一份都没搬**） | `PORTS` 的语义是「本地这份 = 上游那份的改写，逐行可比」。这三份上游文件**一行都不能搬**（函数体内 21 / 11 / 14 处 Windows API），本地三份是 **T4 平台等效重写**：写进 `PORTS` 只会得到一份毫无意义的 diff，并把「上游改这三个文件」误报成需要人处理的偏离 |

`file_ops` 的**形状**参考上游（`FileMutation` / `FileOperationResult` 的字段划分）、
**契约**参考 neoview（`packages/file-operations/src/types.ts`、`DirectorySelection.ts`），
但代码是本地写的。因此：

- 上游改 `delete_worker.rs` 等三份时，`sync_vendored_modules.py` **不会**报警 —— 这是对的，
  因为它没有可以「同步」的东西；
- 反过来，**这三份仍然留在 `vendor/` 里**作为形状参考，别因为「已落地」就把它们删掉。

其中 `filename_sort` 只有公开可见性与来源注释差异；另外三份的平台适配见下文。

这四份源码仍以 mImageViewer 的函数名和测试为准。`activity_gate`、`settings`、
`archive_converter`、`rar_loader`、`zip_loader` 等文件只是给这些纯函数提供 Rossi
已有能力的薄适配，不重新实现列表规则；其中 RAR 头部判定继续委托
`rossi_local_core::rar_source`。

2026-09-19 文件浏览平台适配：`folder_tree::path_eq` 保留 Windows 路径比较，
非 Windows 分支改为区分大小写；`fs_entry::classify_special_dir_entry` 在 Unix
跟随符号链接目标分类，`directory_visit_key` 在 canonicalize 后保留 Unix 路径大小写。
上游 DFS 的 `canonical_ancestor_keys` / `directory_descent_creates_cycle` 也使用同一
平台循环键，避免把 Unix 文件名中的反斜杠或不同大小写路径误认成祖先循环。
`folder_pane::available_drives` 替换为 `file_tree::get_available_roots()` 获取跨平台挂载卷与主目录，
`SortOrder` 对齐上游 `FileName` 变体，perf 事件对接 `perf_sink`，单元测试补充 Unix 等价路径用例。
这些属于平台移植差异，上游升级时须保留；不修改 Catalog 的 `path_key` 数据库键格式。
文件浏览器当前接通能力与尚缺项见 [功能核对](file-manager-parity.md)。

2026-09-20 文件夹封面适配：`thumb_loader` 保留上游目录优先和排序规则，加入
ZIP/CBZ/RAR/CBR 候选、AppleDouble / 内部元数据过滤、加载失败后继续选图，以及
符号链接循环保护。`thumbnail_pipeline` 从最多四个子项生成封面，每个子目录贡献一张；
仅一张时保留原比例，多张时铺满合成图。默认递归深度为 8，硬上限 32；单次最多访问
256 个目录、尝试 128 个候选文件，归档最多检查前 16 页。解码复用 `decode::decode`
（含已启用的 JXL 后端），缩放与缓存仍走 `fast_resize` / `CatalogDb`。
文件夹缓存键升级为 `auto-v3`，追加合成策略与尺寸，避免复用旧单图或较小的合成图。
这些是 Rossi 的封面策略扩展，上游同步时须保留。

许可：上游 mImageViewer 是 **MIT**，可 vendor，已保留版权与来源声明（每个文件头都写了）。

## 3. 保住的名字 = 能吃到的能力更新

这两个模块提供的「能力」不是数据结构，是**判决与节流**。保住这些名字，才谈得上跟上游：

**`page_load_scheduler.rs`**

- 常量 `FS_PAGE_LOAD_TOTAL_PERMITS` / `FS_PAGE_LOAD_HIGH_RESERVED_PERMITS`
- 类型 `FsPageLoadScheduler` / `FsPageLoadTicket` / `FsPageLoadWaiter` / `FsPageLoadPermit`
  / `FsPageLoadPriority` / `FsPageLoadContract` / `FsPageLoadSchedulerStats`
- 方法 `new` / `request` / `supersede_waiting_for_latest_seek` / `waiter` / `acquire_cancellable`
  / `cancel` / `cancel_token` / `promote_to_high` / `disarm` / `stats`
- 事件 kind `scheduler_enqueue` / `scheduler_acquire` / `scheduler_cancel_waiting`
  / `scheduler_promote` / `scheduler_finish` / `scheduler_abandon_waiter`

**`prefetch_policy.rs`**

- 常量 `PREFETCH_IDLE_THRESHOLD`（100 ms）/ `PREFETCH_BACKSTOP`（3 s）
- 类型 `PrefetchDecision` / `AllowReason` / `BlockReason` / `FinalEffectPrefetchAdmission`
- 函数 `decide_prefetch_allowed` / `interleaved_prefetch_positions`
  / `interleaved_prefetch_targets` / `should_prefetch_final_effect`

> **语义映射**（Rossi 是分页阅读，上游是滚动阅读，但判据同构）：
> 上游的「滚动」= 我们的翻页/跳页；上游的「visible 还在加载」= 我们的「当前页还没出图」。
> 所以 `decide_prefetch_allowed` 是**直接可用**的，不是借用。
> 我们原先手搓的「180 ms 延迟 + 一个布尔」只是它的退化版。

**`auto_aspect.rs`**

- 类型 `AutoAspectState` / `AspectDecision`
- 函数 `fit_score` / `nearest_bucket_to_log_ratio` / `pick_best` / `min_samples_for` / `decide_auto_aspect`
- 方法 `reset_for_new_generation` / `reset_decision_only`
- 关联薄适配类型 `settings::ThumbAspect`

**`page_split.rs`（M-09 横长页左右分割）**

- 类型 `PageSlice` / `SplitDirection` / `PresentationStep` / `StepMove`
- 函数 `presentation_steps` / `landing_step` / `step_forward` / `step_backward`
- 关联薄适配类型 `settings::SpreadMode` / `rotation::Rotation`


## 4. 刻意偏离

每一条都登记在 `script/sync_vendored_modules.py` 的 `PORTS` 里。
**新增偏离必须同时登记**，否则同步脚本会把它误报成「上游改了」。

### `page_load_scheduler.rs`

| # | 偏离 | 理由 |
|---|---|---|
| 1 | `pub(crate)` → `pub` | 跨 crate 必须公开。机械替换 |
| 2 | `crate::perf::*` → `crate::perf_sink::*`，`serde_json::Value` → `PerfValue` | `local_core` 目前只依赖 anyhow / image / zip / unrar；为了埋点引 serde_json 会让这一层凭空背一棵依赖树。**埋点的调用位置、事件 kind、字段名一个没动** |
| 3 | `stats()` 由 `#[cfg(test)]` 提升为 `pub` | FRB 层要在调试页显示「此刻在跑几个解码」。上游只在自己测试里看这个数 |
| 4 | 补 `impl Default` | clippy `new_without_default` |
| 5 | 多一行 `use crate::perf_sink::PerfValue;` | 上游没有 `perf_sink` 模块 |

### `prefetch_policy.rs`

| # | 偏离 | 理由 |
|---|---|---|
| 6 | `pub(crate)` → `pub` | 同上 |
| 7 | 文件末尾新增 `mod tests` | 上游这个文件自己没有测试（纯函数测试散在 `src/app/tests.rs` 里、与 `App` 混放）。搬来其中只用纯函数的那些，作为「搬运等价」的证据 |

### `page_split.rs`

| # | 偏离 | 理由 |
|---|---|---|
| 8 | 剥离 `eframe::egui`，本地提供纯 Rust `Pos2` / `Rect`（别名 `NormalizedRect`） | 遵循 **B3** 规范，几何与切分算法为纯逻辑，不引入 UI 框架依赖 |
| 9 | `crate::rotation_db::Rotation` → `crate::rotation::Rotation` | 上游 rotation 位于独立模块，本地收敛至 `local_core::rotation` |
| 10 | `crate::displayed_image_transform::inverse_uv` → `crate::rotation::inverse_uv` | 同上 |

### 文件浏览器模块

| 本地差异 | 理由 |
|---|---|
| 三份模块的 `pub(crate)` → `pub` | 核心适配层跨模块调用 |
| `folder_tree::path_eq` 按平台比较，两个 DFS 循环判定调用平台循环键 | 保留 Unix 路径大小写和反斜杠语义 |
| Unix 符号链接分类与 `directory_visit_key` 分平台 | 可浏览链接，且不会把合法目录误判为循环 |
| Windows 路径用例加平台门，新增 Unix 用例 | 保留原测试并补上移植回归 |
| 上游 RAR 样本路径指向 vendor，未 checkout 样本时显式跳过 | 测试数据仍由原仓库管理 |

### 2026-09-25 融合上游排序改动（`1fd6f863` → `1ffce811`）新增的偏离

上游这三个提交与本仓有关：`38092874 Add descending name and numeric sort options`、
`61471572 Separate folder tree sorting from list order`、`6f720e42`（只动了
`last_descendant_dir` 的可见性）。跟进来之后本仓多出的偏离：

| 本地差异 | 理由 |
|---|---|
| 树排序继续共用 `settings::SortOrder`，不拆上游的 `FolderTreeSortOrder`，也不加 `Settings.folder_tree_sort_order` | 拆枚举要连带设置存储与 Dart 侧开关，属**新功能**；本仓只跟上它的形状（`uses_mtime()` 等）与用例 |
| `FolderPaneListingOptions::new(sort, show_hidden)` 取代上游的 `from_settings(&Settings)` | 上游那两项归 `Settings`，本仓归文件管理器会话（`FileManagerSettings`） |
| 上游用例里的 `SortOrder::NumericDesc` 在本仓用 `Numeric` 顶替 | 本仓 `SortOrder` 没有数字降序；该断言只需要一个与前次**不同**的选项值 |
| `folder_tree::last_descendant_dir` 保持私有 | 上游提它是给 `smart_folder` 用，本仓没有那个消费者。`pub(crate)` → `pub` 的机械规则因此对它不适用 |
| 上游 `folder_tree.rs` 两个依赖独立树排序的用例未搬（`upstream_strip`） | 与本仓刻意不拆的设置有耦合 |
| `page_load_scheduler.rs` 的 `mod tests` 体搬到 `page_load_scheduler/tests/cases.rs`，本文件只留 3 行声明 | 单文件 ≤1000 行（AGENTS §6.5）。**代价**：脚本不再比较那部分测试内容，跟版时要人工读那个文件 |
| `auto_aspect.rs` / `page_split.rs` 若干行尾注释与断言文案翻成中文 | 带行尾注释的行按代码行比较，所以翻译也要登记成规则 |
| `folder_tree.rs` 的扩展名表加 `wbp` / `apng`，图像与视频判定改走 `media_formats`，视频表指向 `page_order::VIDEO_EXTENSIONS` | 文件浏览器可见性判定的单一正本在本地（这些是早于本次融合、此前**未登记**的偏离） |

## 5. 刻意**没**搬的部分

`src/app/prefetch_policy.rs` 后约 140 行是 **UI 指示器数据模型**：

`FsPrefetchPageState` / `FsPrefetchStateCount` / `FsPrefetchSideDisplay` / `FsPrefetchIndicator`
/ `build_fs_prefetch_indicator` / `summarize_fs_prefetch_states` / `fs_prefetch_page_state`
/ `behind_display` / `ahead_display` / `tooltip_text` / `MAX_DOTS_PER_SIDE`

**理由**：那是给 egui **画点**用的显示模型（近处画点、远处折成计数、带日文 tooltip 文案）。
Rossi 的 UI 在 Flutter 侧、由 Dart 自己画，搬过来只会得到「一个没人渲染的数据结构 + 一段日文」。

将来若要照抄它的显示规则（`MAX_DOTS_PER_SIDE = 4` 那条取舍注释写得很清楚），
直接照上游文件取即可。同步脚本会盯着这一段 —— 如果上游在这里长出**新的纯策略函数**，会报出来。

## 6. 上游更新时怎么同步

### 一条命令

```bash
python script/sync_vendored_modules.py           # 出报告
python script/sync_vendored_modules.py --diff    # 附上游原始 diff
```

脚本做四件事，退出码 0 = 无需处理、1 = 需要人看：

1. `pin..HEAD` 之间上游有没有提交动过这五个文件；
2. **自检**：把 pin 版归一化后与本地比 —— 若仍有代码差异，说明本地有**未登记的偏离**（脚本在替你守规矩）；
3. 打出「上游这段时间对**代码**的改动」—— 这就是要 apply 的东西（注释差异单列，上游的日文注释常写清语义与理由，值得看）；
4. 检查**刻意未搬的那一段**上游有没有长出新的函数名（可能是新能力，该搬）。

### 手工 apply

脚本不会自动改本地文件 —— **每处偏离都要判断是否还成立**
（例如上游若自己把 `pub(crate)` 改成了 `pub`，偏离 1 就该删掉）。

所以流程是：读报告 → 手工编辑本地文件（保持上游的函数名）→ 跑测试：

```bash
cd rust && cargo test -p rossi_local_core
python ../script/sync_vendored_modules.py        # 应回到「已知偏离清单是完整的」
```

→ 两条都干净后，更新 pin：

```bash
python script/sync_vendored_modules.py --bump <新的上游 commit>
```

并把本文档第 2 节的 commit 一并改掉。

### 为什么不做自动 apply

自动 patch 在「本地已有偏离 + 上游也改了同一处」时必然冲突，而冲突的解法就是要人想的那一步。
把归一化规则和偏离清单**写下来**（`PORTS` 表），比写一个有 30% 概率猜错的 patcher 划算。

## 7. 对 v0.1 判据的影响

`rust/local_core/src/lib.rs` 原本声明「不做预取」。这两个模块进来后那条声明**没有松动**，
理由写在 `lib.rs` 头部，摘要如下：

- `prefetch_policy` 是**纯函数**：输入时刻与计数，输出「该不该预取」+ 理由。不持有任何一页的字节或像素；
- `page_load_scheduler` 持有的是**在跑/在等的请求数与许可**，不是页内容。它的作用恰恰是**限制**并发度
  （总 6 张、2 张留给高优先级），让「一页 179 MB 同时解好几张」这种内存爆炸在结构上不可能发生。

预取的**执行**（谁来解、解完存哪、淘汰谁）仍在 Reader 层 —— 那是「谁拥有 `pixels`」的问题，
不是判决问题。所以判据 D（连读三本 RSS 增幅 ≤ 5%）的依据不变。
