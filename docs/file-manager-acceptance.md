# 文件管理器并集验收判据

> **范围口径在 [file-manager-parity.md](file-manager-parity.md)**：那张「已接通 / 未接通」表是范围的唯一真相，
> 本文件**不重复写范围**，只回答一件事 —— **怎么判定一条真的接通了**。
> 判据的作用与 [v0.1_acceptance.md](v0.1_acceptance.md) 相同：砍掉「看起来做了」的机会。

冻结信息：2026-09-19，冻结于 `HEAD = 2ec1fa03`。冻结时工作区另有**未提交**的文件管理器实现
（core / FRB / Dart / test 四处同批），因此**判据一律对着工作区跑**，不按 HEAD 判定。

## 0. 入库红线：这三件事不算完成

1. **扩展名已识别 ≠ 能打开。** `folder_tree::is_convertible_archive_path` 返回 true 只说明"认得这个后缀"。
2. **API 已暴露 ≠ 用户能用。** FRB 里多一个函数只说明桥接完成，不说明有任何 UI 能触达它。
3. **状态在 Dart 里重算 = 不通过。** 页签、排序、筛选、选中、树展开这类规则只要在 `.dart` 里出现第二份实现
   （`_selected`、`path.split(separator)`、在 widget 里排序列表），即判不通过 —— 这与并集的架构前提
   （状态在 Rust、Dart 只投影）相悖，也是 NeoView 契约的落地方式。

## 1. 判据

### 判据 F1 — 多选与文件操作

观察点：选中两项 → 剪切 → 换目录 → 粘贴；把一项拖进子目录；重命名一项；新建目录；删除一项；空白区双击。

| # | 通过判据 |
|---|---|
| a | 选中集合是 **core 状态**（快照里能读到选中项），Dart 不另存选中态 |
| b | 删除走**系统回收站**；core 内不得出现对**用户所选路径**的 `fs::remove_file` / `fs::remove_dir_all` 直删。平台不支持回收站时须**显式降级并在结果里标出**，不能装作删干净。<br>现有唯一先例是 `catalog::delete_old_cache` / `delete_all_cache`（只作用于 cache_dir 下的 `.db`），**不构成删用户文件的先例** |
| c | 失败可回滚：沿用 `with_session` 的「候选态 → 成功才提交」，一次失败的多选移动不得留下半移动的目录 |
| d | 拖拽在**触摸屏**要有非拖拽出口（ADR-0012 §12 的平台分流），不能只做 hover / drag |
| e | 空白区双击返回上一级，且与「单击进入目录」不互相吃掉 |

归属：core（选中集合、操作语义、回收站）+ FRB（动作与结果 DTO）+ Dart（多选手势、右键菜单、拖拽）
证据点：`local_core` 目前**零 fs 写操作**；`with_session` 的 clone-commit 事务已存在于 `rust/src/api/file_manager.rs`。

### 判据 F2 — 目录监听与自动刷新

| # | 通过判据 |
|---|---|
| a | 外部新建 / 删除 / 改名一个文件后，**不点刷新**，列表在**约定时限内**更新（时限要写死在判据里，建议 2 s） |
| b | 快照 `generation` 随外部变更自增，UI 用它区分"确实是新的一次" |
| c | watcher 生命周期跟会话：`file_manager_close` 之后不得残留监听线程或句柄 |
| d | **变异验证**：把 watcher 摘掉后本条必须变红。否则就是空转断言（参见 `MEMORY.md` 第 6 条） |

归属：core（监听 + revision）+ FRB（推送或轮询通道）+ Dart（刷新触发）
证据点：`rust/Cargo.toml`、`local_core/Cargo.toml` 目前**无 `notify` 依赖**。

### 判据 F3 — 归档转换、缓存、密码与进度

| # | 通过判据 |
|---|---|
| a | `archive_converter.rs` 里出现**真实转换实现**，而不是只有 `ArchiveFormat::from_extension` 与 `looks_like_non_first_rar_part` |
| b | 转换产物落缓存**并被复用**：同一归档第二次打开不再转换 |
| c | 缓存有失效与清理策略（源文件 mtime / size 变化即失效） |
| d | 密码：正确密码能读；**错误密码报错**，不得静默返回空目录 |
| e | 进度：转换过程有可观察的进度（快照字段或事件），长转换可取消 |
| f | **反例**：双击返回一个 7z/LZH 路径**不算通过** —— 只能由"Reader 真的把 7z/LZH 读到最后一页"来关闭这一条 |

归属：core（转换 + 缓存）+ FRB（进度 / 密码 DTO）+ Dart（进度与密码 UI）
证据点：`archive_converter.rs` 现 **31 行**，是扩展名判定适配。

### 判据 F4 — 面包屑（含编辑与列导航）

| # | 通过判据 |
|---|---|
| a | 路径分段由 **core 投影**（快照给"段 + 段路径"），Dart 不得自己 `split` 出段 |
| b | 每段可点回该层；可编辑（输入路径直接跳转）；非法路径要有明确失败，不能静默停在原地 |
| c | 面包屑跳转是否入 back 栈要有**唯一口径**并写死，不许"看情况" |

归属：core + Dart。2026-09-19 续作证据：`FileManagerSnapshot` 已提供 `breadcrumbs`、
`can_go_up`、`directory_columns_enabled` 与 `directory_columns`；路径编辑和列导航由 core
投影并处理，成功跳转统一进入后退栈。Rust 测试覆盖路径/历史/无效输入/符号链接，
Widget 测试覆盖窄栏点击与失败后保留输入。悬浮列宿主仍是未接通项，见范围表。

### 判据 F5 — 文件树（含 DFS 相邻目录）

| # | 通过判据 |
|---|---|
| a | 展开集合是 core 状态，Dart 只画 |
| b | 树与列表联动：在列表里进入目录，树上对应节点展开并高亮 |
| c | 按需展开，**不得**在打开卡片时遍历整盘 |
| d | **反例**：十万文件量级的大目录下打开树不得阻塞 UI |

归属：core + Dart。

### 判据 F6 — 展示视图

| # | 通过判据 |
|---|---|
| a | `ViewMode` 扩到 > 2 档，且**每一档在 `file_manager_card.dart` 有对应布局分支**；枚举加了而 UI 没分支 = 不通过 |
| b | 缩略图走**既有缩略图管线与缓存**，不得每个条目现解码原图 |
| c | 悬停预览：桌面 hover 触发；触摸屏必须有非 hover 出口 |
| d | 尺寸 / 标题换行偏好属于 core 设置，并**沿用现有的每页签独立**语义 |

归属：core（枚举 + 偏好）+ Dart（布局）。证据点：`ViewMode` 现仅 `List` / `Grid` 两档。

### 判据 F7 — 搜索增强

| # | 通过判据 |
|---|---|
| a | 明确区分「当前目录子串」与「递归」两种模式，且**模式对用户可见**（用户知道自己在搜什么范围） |
| b | 递归搜索可取消，取消后不写回半结果 |
| c | 大目录递归时 UI 不卡死：循环必须在 Rust 侧，Dart 主 isolate 里不得出现逐项匹配 |
| d | 条件与历史（路径 / 标签条件、历史记录）落 core |

现状口径：`matches_entry` 现在是**当前目录内、不区分大小写的名称子串匹配**，不是递归搜索。

### 判据 F8 — 穿透的完整策略

| # | 通过判据 |
|---|---|
| a | `PenetrationResult::Branch` **不再是终点**：UI 能就地展开分支候选（Neo 的内联分支抽屉），而不是只提示"请进目录自己选" |
| b | 分支数量有限制且可配 |
| c | 终点类型可选（目录 / 归档 / 媒体），而非现在写死的两条 Terminal 分支 |
| d | 激活身份跟踪：同一目标经不同路径抵达时，激活态判定唯一 |

现状：`resolve_penetration_inner` 只写死"唯一归档 → Terminal(归档)"与"纯媒体目录 → Terminal(自身)"，
其余多候选一律 `Branch`。

### 判据 F9 — 页签布局与持久化

| # | 通过判据 |
|---|---|
| a | 跨重启恢复，且**恢复范围要写死**：页签集合、顺序、固定状态、每页签的路径 / 设置 / 历史里，哪些恢复、哪些不恢复 |
| b | 页签宽度 / 布局可拖且持久化 |
| c | **证伪点**：`WorkspaceLayoutSnapshot` 里必须真的出现文件管理器条目；声称已持久化而快照里没有对应字段 → 不通过 |

证据点：`workspace_layout_store.dart` 与 `WorkspaceLayoutSnapshot` 现在**没有**任何文件管理器字段。

### 判据 F10 — Reader 打开面

| # | 通过判据 |
|---|---|
| a | 视频能播放、音频能播、PDF 能分页 |
| b | 打不开的类型必须有明确提示，不得静默失败 |

现状：`open_entry` 对非漫画归档 / 非图片扩展名**一律报错**「当前 Reader 暂不支持直接打开」。

### 判据 F11 — 移动端存储访问

| # | 通过判据 |
|---|---|
| a | `file_tree.rs` 出现 `android` / `ios` 分支：Android 走运行时权限 + SAF（选中的 tree uri 能真正列目录），iOS 走 Documents + 安全作用域书签 |
| b | **用桌面根目录枚举顶替一律不算** |

现状：`get_available_roots` 只有 `windows` / `macos` / `not(any(...))` 三个分支。

## 2. 判据怎么跑

| 判据类型 | 命令 | 备注 |
|---|---|---|
| Dart 静态 | `dart analyze lib/` | **连目录跑**；文件管理器相关看 `lib/workspace/` + `lib/src/rust/` |
| Widget | `env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test test/workspace/` | 本机必须解沙箱代理，否则报 `Invalid WebSocket upgrade request` |
| Rust | `cd rust && cargo test -p rossi_local_core` | **`local_core` 不在 default-members**，裸 `cargo test` 只跑 windcore，跑不到本判据 |
| 变异验证 | `python3 test/workspace/mutation_check.py` | 每个变异体**从干净基线出发**（前一个残留会造假红），并区分"判据失败"与"编译错" |
| 实机 | 五个平台各跑一次 | 模拟器 / 桌面枚举不能顶替移动端（见 F11-b） |

## 3. 明确不算判据

1. 桌面根目录枚举通过 ≠ 移动端可用。
2. 单测绿 ≠ 用户能用：每条判据都必须有一条**能点到的入口**。
3. 扩展名识别、API 暴露、枚举值新增 —— 三者本身都不算。
4. Dart 侧的补充断言不得用来证明 core 的判据（那属于 §0-3）。

## 4. 判定

**F1–F11 全部通过才算并集完成。** 当前未通过项与 [file-manager-parity.md](file-manager-parity.md)
「尚未接通」表的每一行一一对应；那张表删掉一行，本文件相应判据才有资格转绿。

## 5. 冻结后变更规则

- 本文件是**判据**，可随实现调整；但它不是 ADR，**不得**为了"好过"而放宽某条。
- 放宽或删除某条，必须在提交信息里写明原因（哪条、为什么、替代判据是什么）。
- 新增并集项时**先加判据再加实现**，顺序反了就会出现"实现完了才发现没法判定"。
