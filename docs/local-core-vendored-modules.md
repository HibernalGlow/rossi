# 从 mImageViewer 搬进来的模块（溯源与同步）

> 这份文档只讲一件事：`rust/local_core` 里有**两个文件是从 `vendor/mimageviewer` 逐字搬来的**，
> 上游更新时怎么把它们的能力更新吃进来。
>
> 适用前提是你已经知道复用形态是 gitlink + path 依赖（[ADR-0007](adr/0007-mimageviewer-vendor-checkout.md)）。
> 那两个模块**不能用 path 依赖**，理由见下。

---

## 1. 为什么是搬源码，而不是 `use`

上游把这两个模块藏得比想象中深：

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
| `rust/local_core/src/perf_sink.rs` | —— **本地新增**，上游对应物是 `src/perf.rs`（完整 JSONL 性能日志系统） | —— |

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

## 4. 刻意偏离（共 7 处）

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

1. `pin..HEAD` 之间上游有没有提交动过这两个文件；
2. **自检**：把 pin 版归一化后与本地比 —— 若仍有代码差异，说明本地有**未登记的偏离**（脚本在替你守规矩）；
3. 打出「上游这段时间对**代码**的改动」—— 这就是要 apply 的东西（注释差异单列，上游的日文注释常写清语义与理由，值得看）；
4. 检查**刻意未搬的那一段**上游有没有长出新的函数名（可能是新能力，该搬）。

### 手工 apply

脚本不会自动改本地文件 —— 这是刻意的：**偏离只有 7 处，但每处都要人判断是否还成立**
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
