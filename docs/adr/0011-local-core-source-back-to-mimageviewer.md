# 本地核心来源回退 mImageViewer，ComicRD 降为参考

**本 ADR 取代 ADR-0010（同日，2026-09-16）。** ADR-0001 恢复有效，
ADR-0005 / ADR-0007 的对象回到 mImageViewer。

## Context

ADR-0010 用一张对比表把本地核心的来源换成了 ComicRD。那张表核对了三件事：
许可证、直接依赖数量、UI 耦合。**它没有核对「读一页的代价」。**

用户指出 `comicrd_core` 的 RAR 路径不可接受：**首次访问 chapter 时一次性把整章图片提取到
`<app-data>/rar-sessions/chapter-<id>`**，再配 LRU（上限 2）与三处清理。
这把「打开一本 CBR」变成一次全量解压加一份等量磁盘副本——漫画一本动辄 200 页。
更关键的是：ADR-0010 把这件事写成了 ComicRD 的**优点**（"已经解决了两件 Rossi 还没解决的事"之一）。

回查 mImageViewer 源码取证，`src/rar_loader.rs`（模块自述 *"Flat, non-solid RAR/CBR access
used by the virtual-folder read boundary"*）：

| 事实 | 证据 |
|---|---|
| 不落盘 | 全文件没有临时目录写入路径；`tempdir()` 只出现在 `#[cfg(test)]` |
| 无常驻句柄 | `read_entry_bytes()` 每次重新 `open_for_processing()`，函数返回即释放 |
| 只读命中条目 | 循环 `read_header()`；命中 `header.read()`（字节进内存），未命中 `header.skip()` |
| 只缓存判定 | `DECISION_CACHE`(32) / `VOLUME_RESOLUTION_CACHE`(128)，key 是 `(path, len, mtime)`；<br>注释原话 *"without retaining archive contents or handles"* |
| 分类 | `Direct` / `Solid` / `NestedArchive` / `Encrypted`，只有 `Direct` 走直读 |
| 分卷 | 以 header 的 `volume_info()` 为准解析到第一分卷（`Single` / `First` / `Subsequent`）；<br>inspection、条目读取、DFS 检查共用一次卷头 probe |
| 取消 | `AtomicBool` + `Relaxed`，**每个条目边界**都检查 |
| 条目的字节上限 | `MAX_DIRECT_ENTRY_BYTES` = 4 GiB |

即：**mImageViewer 的 RAR 是「按需读一个条目」，ComicRD 的 RAR 是「一次读整章」。**
这一列是 ADR-0010 的对比表里缺的那一行，而它恰好决定磁盘与延迟的量级。

## Decision

1. **撤回 ADR-0010 的全部 Decision 项。** 本地核心的来源 = mImageViewer，
   ADR-0001 恢复有效；`vendor/` 的检出对象回到 mImageViewer，且**需要先建 fork**（ADR-0007 原样生效）。

2. **RAR 读取模型写死为「逐条目按需读」**（本 ADR 唯一的新增实现约束）：
   打开归档 → `read_header` 顺序推进 → 命中条目读出字节、未命中跳过；
   **字节在内存里交给解码器**；不落盘、不建 session、不跨调用持有归档句柄。
   缓存**只允许缓存判定结果**（key = `path + len + mtime`），不允许缓存归档内容或句柄。

3. **明确禁止 `rar-sessions` 式的整章提取。** 「首次访问 chapter 时把整章解压到临时目录」
   不再是一个可选实现，而是**被否决的实现**。

4. **临时文件只在一个场景允许：嵌套归档**（内层必须先落地成路径才能被打开）。
   v0.1 不实现嵌套。这与「读不了流」的原约束并不冲突——那条约束对**归档本身**成立，不对条目字节成立。

5. **solid / 加密 CBR 不在 v0.1 判据内。** 实现按 mImageViewer 的 `classify_direct_read`
   给出判定，遇到 `Solid` / `Encrypted` 报明确错误即可。
   → 判据 A / D 里的「CBR」应读作**非固实、未加密的 CBR**。

6. **`unrar` 沿用 mImageViewer 的 patched `0.5.8`。** 上游 `UCM_CHANGEVOLUMEW` 用定长 2048 切片
   读变长分卷名（`RAR_VOL_NOTIFY` 的 `P1` 可能指向按当前名字长度分配的 `std::wstring`），
   **分卷 RAR 上会越界访问违例**；选这个 crate 就要跟这条补丁（`crates/unrar-patched/PATCHES.md`）。

7. **ComicRD 降为参考实现**：不 vendor、不依赖、不进 Cargo。保留它作为对照的三条设计
   ——tile 布局（`TILE_MAX_HEIGHT = 2048`）、预取窗口（`current ± 2` tile）、tile 字节缓存——
   以及「几何布局的真源在 Rust」这条原则；它的 RAR 做法明确不采用。

## Considered Options

- **维持 ADR-0010（ComicRD 做本地核心）**：依赖树干净（9 个直接依赖）、`zip` 与 Rossi 同大版本、
  tile 与预取已实现。但要换成「按需读」就得重写它的 RAR 后端——
  那等于「ComicRD 的壳 + 自己写的 RAR」，它相对 mImageViewer 的最大优势（干净可复用）也随之失效。
- **按需读 + 超阈值落盘兜底**：正常 CBR 零落盘，solid / 分卷才回落到临时文件。
  比纯按需读多一条代码路径和一套生命周期（清理、并发、失败恢复），
  而 solid / 加密已定不在判据内——**这条兜底在 v0.1 里没有服务对象**。
- **回退 mImageViewer（本 ADR）**：代价是 ADR-0005 的 egui 抽瘦风险重新成为最高风险项，
  并回到 Windows 独占的源码（macOS / Linux 子集要逐模块判定）。

## Consequences

- **ADR-0010 作废**，它引入的「按关注点拆分来源」不再成立。它的对比表作为**调研记录**仍有价值
  （ComicRD 的栈 / 依赖 / tile / 预取数据在 `docs/REFERENCE_RESEARCH.md` 另有留存）。
- **ADR-0005 的「egui 耦合深度未知」重新生效**，并成为 Phase 0 的第一件事。
- **Phase 0 的 vendor spike 问题回到原样**（`ROADMAP.md` 里本来就还写着 mImageViewer 版）：
  统计 `src/` 下多少模块 `use egui`；验证 path 依赖跨 workspace 的 `[patch.crates-io]` 不传递。
- **v0.1 判据 A 的成本回升**：CBR 要从 mImageViewer 的 RAR 路径里抽出来，
  还要处理 `zip 8.2.0` 与 `zip 2` 的双份编译（`v0.1_acceptance.md` §4.4 记的账依然有效）。
- **「阅读视图归 Rossi 自己」不受影响**——那条来自 ADR-0003，与本次回退无关。
- **RAR 每页代价是 O(前面条目)，不是 O(1)**：跳过的实际开销取决于 libunrar 在非固实归档上
  走 seek 还是走解压。这个数**没测过**，列入 Phase 0 待测项（顺序读第 200 页 vs 整章落盘）。
- 许可不变：mImageViewer 是 MIT；UnRAR 条款的记账义务（`v0.1_acceptance.md` §4.2）不变。
