# Rossi 文件管理器功能核对

核对日期：2026-09-19。目标是 NeoView 文件卡片与 mImageViewer 文件浏览能力的并集。
**当前尚未实现完整并集**；源码已存在、扩展名已识别、API 已暴露都不等于用户可以完成对应操作。

## 当前接通的操作

| 能力 | Rust 实现 | Flutter 入口与边界 |
|---|---|---|
| 多页签、切换、关闭、导航历史 | `FileManagerState`，最多 8 个页签 | 页签条（单页签时整行收起，新建与恢复改由「路径操作」菜单承担）；导航按钮 |
| 面包屑与路径编辑 | Rust 按平台路径组件投影；相对路径以当前页签为基准；所有成功跳转统一写入后退历史 | 点击祖先返回；点击当前段或「路径操作 → 编辑路径」输入路径；错误保留输入及旧目录；Esc 取消。行尾只有「路径操作」这一颗键；路径短就左对齐，放不下才滚到末尾 |
| 内联目录列导航 | Rust 每页签保持开关、投影目录和选中态；只枚举当前路径最后三层，关闭时不枚举 | 开关只有「路径操作 → 展开/收起目录列」一处（工具栏上那颗已删，同一件事不该有两个入口）；目录列可横向滚动，同样左对齐、放不下才滚到末尾；目录项点击跳转；使用 mImageViewer 适配层的自然排序与隐藏规则；暂不提供悬浮列宿主 |
| 固定、复制、关闭其他/左侧/右侧、恢复关闭 | 核心维护固定状态、关闭队列及能力标志；批量关闭跳过固定页签 | 页签菜单、恢复菜单；固定仅在当前会话有效 |
| 各页签搜索、筛选与视图独立 | 设置放在 Rust 的 `FileManagerTab` 中；复制和恢复带上设置及历史 | Dart 只保存快照和输入控件，不自行筛选或排序 |
| 目录级视图状态跨重启 | `FileManagerState` 维护 `view_states`（键为 `settings_db::view_state_key`）与脏集，改了就交出来；会话层落 `settings.db` 的 `file_manager_view_states` 表，新建会话时 hydrate，命中最长路径前缀就用该目录的偏好 | 由「设置 → 文件管理器 → 浏览视图」的「记住每个目录的视图与排序」开关控制（默认开）；关掉时既不读也不写，已存的行不删 |
| 名称搜索 | Rust 当前目录内、按上游 `search_query` 语法的词元匹配（空格分词求交、`-词` 排除、`"带空格"` 当一个词） | 输入即搜（180ms 防抖），回车只是提前提交；关闭时不递归 |
| 递归搜索 | `file_manager::search_entries`：广度优先、层数与条数上限、`AtomicBool` 取消 | 「含子目录」开关；结果写回页签，卡片不另存列表；中止保留已得命中 |
| 搜索结果页签 | 命中存在 `FileManagerTab.search` 里，`entries()` 直接交出它 | 「存为页签 / 回到目录」；标题变成「搜索: 词」；导航会离开结果视图 |
| 搜索历史 | `settings.db` 的 `file_manager_search_history`，按最近使用去重、裁剪到 20 条 | 搜索框展开时以词条形式显示前 8 条，点一下再搜；可清空。防抖那一路不进历史 |
| 类型筛选 | 文件夹、归档、图片、视频、音频 | 类型菜单；基础枚举仍只包含 mImageViewer 识别的媒体与目录 |
| 排序 | 名称、类型、大小；升降序；文件夹优先 | 排序菜单；名称比较直接使用 mImageViewer `filename_sort::SortNameKey` |
| 隐藏项开关 | 调用 mImageViewer `fs_entry::should_hide_fs_entry`；列表、子文件名、穿透使用同一策略 | 浏览设置；内部元数据目录与 AppleDouble 仍不显示 |
| 穿透与子文件名 | 唯一目录链/归档、媒体目录、深度和循环保护；显示一个/全部子项 | 单击打开；文件夹按钮强制进入；尚无 Neo 内联分支抽屉与完整终点策略 |
| 列表和网格 | Rust 保持模式 | Flutter 布局；网格内长子项列表可滚动 |
| 归档双击 | 调用 `file_manager_open_archive` 验证并返回来源路径 | 双击一次只发送一个打开动作；单击沿用已有打开行为 |
| 无效目录操作回滚 | 会话在动作与快照都成功后才提交 | 错误保留当前可操作快照；初始化读取失败重试复用原会话 |
| 文件树面板 | `FolderPaneState`、懒展开与 RAII 取消扫描、扁平行投影、游标键盘导航、激活路径同步 | 工具栏「文件树」开关；`file_manager_tree_snapshot` / `_toggle` 两个入口，行点击跳转、箭头展开。**游标键盘导航仍未接**（上游靠每帧驱动，这里改由「每次动作后同步一次 + 有待收时 80ms 后再问一次」驱动）|
| Material 外壳 | 无业务逻辑 | 卡片及控件统一使用 `material_ui`，卡片自身提供带圆角的 Material |

## 直接复用的源函数与平台适配

来源为 `vendor/mimageviewer/src/folder_tree.rs`、`folder_pane.rs`、`fs_entry.rs`、`filename_sort.rs` 的源码副本，
沿用原模块与函数名，详见 [溯源清单](local-core-vendored-modules.md)。
本次增加的适配为：非 Windows 路径不折叠大小写/反斜杠；Unix 符号链接跟随目标分类；
穿透与上游 DFS 的循环键仍先 canonicalize，在 Unix 上保留路径大小写/反斜杠；Windows 补齐自然排序所需的
`Win32_Globalization` feature；文件树面板（`folder_pane`）委托 `file_tree::get_available_roots()` 获取跨平台挂载卷与主目录，
单元测试支持 Unix 路径等效验证。数据库已有 `path_key` 的键格式未改动。

`archive_converter.rs` 目前只是扩展名判定适配，**没有搬入实际的归档转换器**。
双击返回 7z/LZH/PDF 路径不代表 Reader 已能读取它们。现有 LocalSource 为图片目录、ZIP/CBZ、
非固实且未加密 RAR/CBR 提供读取；视频/音频仍缺阅读器适配。

## 尚未接通的并集项

| 来源范围 | 尚缺的能力 |
|---|---|
| Neo 页签与导航 | 页签布局/宽度与跨重启持久化、最近访问页签策略、搜索/EFU 受保护页签、列导航的悬浮宿主/复制路径操作、文件树的游标键盘导航 |
| Neo 搜索与排序 | 标签条件（`#tag` 语法在 Rust 里能解析，但 Rossi 没有标签库可判）、索引式搜索（M-18）、评分/日期等排序来源、目录专属排序设置 |
| Neo 穿透 | 内联分支展开、分支数量限制、完整终点类型选择及激活身份跟踪 |
| Neo 展示 | 封面、横幅、详情、多图/马赛克、缩略图与悬停预览、尺寸/标题换行偏好 |
| Neo 文件操作 | 键盘操作、目录监听（外部变化自动刷新）、拖拽、空白区双击返回。~~多选、剪切/复制/粘贴、移动/重命名/新建/回收站~~ **已于 2026-09-20 接通，见下节** |
| Neo 扩展信息 | 标签、评分、EMM、Clipm 等源功能及对应服务适配 |
| mImageViewer | DFS 相邻目录 UI、书签/历史/标签/评分/智能文件夹/全局搜索入口、系统文件操作与拖放 |
| mImageViewer 格式 | 实际归档转换/密码/进度/缓存、完整 PDF/音视频打开流程与各平台依赖 |
| 移动端 | Android 权限/SAF，iOS Documents/安全作用域访问；不能用桌面根目录枚举代替 |

Neo 对照入口：`Xiranite/src/nodes/neoview/features/panels/cards/folder/` 的
`FolderTabsHost`、`FolderTabBar`、`FolderToolbar`、`FolderSearchPanel`、`FolderTreePanel`、
`FolderContextActions`、`FolderInlineBranchPanel` 等。mImageViewer 对照入口除上述源函数外还有
`archive_converter`、`archive_cache`、`global_search`、`bookmark_browser` 等；这些尚未接入的模块
不能计入 Rossi 已完成能力。

## 验证范围

Rust 测试覆盖页签空操作、批量关闭保护、复制/恢复的设置和历史、失效目录回滚、
搜索/筛选/排序、隐藏策略一致性、子文件名目标、Unix 符号链接循环、
面包屑/路径编辑的统一历史与错误回滚、相对路径和符号链接父目录、列导航的按页签独立状态。
Widget 测试使用真实文件卡片、应用同款 Material 根和 FRB 替身，验证不同卡片宽度、
多条子文件名、搜索转发、页签操作、按钮能力、会话重试和单击/双击互斥，
以及面包屑/目录列点击转发、窄卡片路径编辑和错误恢复。
这不替代五个平台的实际运行验证，也不验证未接通的 Reader 格式。

2026-09-19 本机验证结果：

- `cargo test -p rossi_local_core -p windcore --lib --quiet`：173 + 27 项通过。
- `flutter test test/workspace/file_manager_card_test.dart --reporter expanded`：14 项通过。
  包括 260/340/700 像素宽度、260/760 像素独立面板高度；低高度面板工具区可滚动。
- 文件卡片、卡片外壳和对应测试的 `dart analyze`：无问题。
- `python3 script/sync_vendored_modules.py`：五份源码与固定版本的差异均已登记。
- `cargo build -p windcore --release`：成功，更新本地启动时会加载的动态库。

## 2026-09-19 夜：工具栏对齐（主页 + 五向导航掌）

对照 `Xiranite/src/nodes/neoview/features/panels/cards/folder/FolderToolbar.tsx`
逐条核对后的收口。**此前「设置主页」并非缺失**：Rust 侧 `FileManagerState.home_path`、
`file_manager_set_home_path`、卡片的右键/长按手势和测试都在，问题有两个 ——
它只活在内存会话里（`FILE_MANAGER_SESSIONS` 是 `DashMap`，重启即丢），
而且桌面上不可发现（Tooltip 走 tap 触发，可按钮在未设主页时是禁用的，点不出提示）。

本次收口：

| 能力 | 实现 | 边界 |
|---|---|---|
| 主页持久化 | 全局设置新增 `FileManagerSettingState{homeEnabled, homePath}`（ObjectBox）；`file_manager_create` 新增 `home_path` 形参 + `seed_home_path` 注入收口 | 失效路径（目录被删 / 移动盘没插）由核心的 `set_home_path` 拒绝并静默忽略；UI 用「持久化非空但 `snapshot.homePath` 为空」判定失效 |
| 主页入口 | 单击（未设过＝把当前目录设为主页）/ 长按 / 右键菜单（回到主页、设为主页、清除主页） | 落盘的是**核心接受后**的路径，不是用户点的那一下 |
| 主页设置页 | `FileManagerSettingRoute`，含开关、路径展示、失效提示、选择目录、清除 | `file_selector` 的 `getDirectoryPath` 在 iOS 不可用，已兜住异常并提示 |
| 导航（五向） | `file_manager_toolbar.dart` 的 `FileManagerNavigation` 按卡片宽度二选一：≥550 摊开成后退/前进/上一级/主页/刷新五颗标准键，否则收成 `file_manager_navigation_pad.dart` 的 40px 掌形（四片 `ClipPath` 多边形 + 中心圆刷新） | `ClipPath` 同时裁绘制与命中测试，五个方向互不抢事件；中心圆压在四片之上。两种画法共用同一批动作与同一份 tooltip 文案，主页那颗的长按/右键菜单在两种形态下都可达 |
| 工具栏 MD3 口径 | 整行只有 `FileManagerToolbarMetrics` 一份几何：图标钮 40 见方、图标 20、组内间距 4、组间一条 `outlineVariant` 竖线；选中态 `secondaryContainer`，禁用 `onSurfaceVariant` 38% | 三颗菜单触发键（视图/排序/更多）走 `FluentPopupMenuButton.style` 传进去的同一份 `ButtonStyle`，不再各自写 `size: 18` + `visualDensity: compact` |

仍未接通（沿用上一节的「尚未接通的并集项」）：文件树的游标键盘导航、
空白区行为、悬停预览、缩略图重载、内容/缩略图/横幅宽度、标签显示、标题换行、EFU、
目录监听、拖拽。（**多选与删除模式已于 2026-09-20 接通**，见下节。）

2026-09-19 夜本机验证结果：

- `cargo test -p windcore --lib file_manager`：9 项通过（含新增
  `seed_home_path_ignores_stale_persisted_paths`）。
- `flutter test test/workspace/file_manager_card_test.dart --reporter expanded`：42 项通过，
  含导航掌五向派发、主页单击/菜单/开关/会话注入五条新判据。
- `dart analyze lib/`：无问题。
- 注意：改动期间有**并发写入方**在同一批文件上工作（`file_manager_card.dart`、
  本测试文件、`rust/local_core/src/{file_manager,settings_db}.rs`），
  中间态会出现「lib 编译不过」或「`flutter test` 因 native assets 构建失败而起不来」，
  那不是本次改动的问题 —— 先确认报错文件不在自己的改动清单里再动手。

## 2026-09-20：文件树接通到卡片

`folder_pane.rs` 的状态机早就搬好了，缺的只有「桥 + 列表」。本次补上：

| 层 | 落点 | 边界 |
|---|---|---|
| 会话层 | `rust/src/api/file_manager.rs`：`FILE_MANAGER_PANES`（`Mutex<HashMap>`）+ `with_pane` + `file_manager_tree_snapshot` / `_toggle` | 面板**不**挂在 `FileManagerState` 上：那个结构每次动作前要 `clone` 做事务回滚，而面板揣着 `mpsc::Receiver`。`file_manager_close` 一并回收面板，`Drop` 随即取消在跑的枚举 |
| 驱动方式 | 每次动作后 `sync_to_active` + `poll_pending` 一次；`has_pending` 为真时 Dart 隔 80ms 再问 | 上游是 egui 每帧驱动，这里没有帧循环。展开/懒扫描/取消/深度上限仍全在核心 |
| 展开入口 | 核心没有「按路径改展开态」的公开入口，于是 `set_cursor` + 键盘左/右键 | 与方向键操作共用同一套 `user_expanded` / `user_collapsed` 记账，不出现第二套 |
| 卡片 | 工具栏「文件树」开关 → 200px 高的 `ListTile` 列表；行点击跳转、箭头展开 | 「开树就关列」：两者回答同一个问题，同时开着只会把不高的卡片挤成两半。开关本身是 Dart 的 UI 状态，不像目录列那样进页签设置 |
| 跟随当前目录 | `build` 里比对 `snapshot.generation`，变了就排一帧去取树 | 改当前目录的入口有七八个（页签/面包屑/导航掌/根目录/双击/外部新页签），逐个埋刷新迟早漏 |

游标键盘导航（`handle_tree_key` 的 Up/Down/Enter）核心具备、UI 未接。

2026-09-20 本机验证结果：

- `cargo test -p windcore --lib file_manager`：10 项通过（新增
  `pane_follows_the_session_directory_and_projects_only_directories`：会话当前目录 →
  面板祖先链 → 展开后的行深度，并确认树里只有目录没有文件）。
  该用例必须 `show_hidden_files = true`，因为 `tempfile` 的目录名是 `.tmpXXXX`，
  按面板的隐藏项策略本来就不该出现在树里。
- `dart analyze lib/workspace/widgets/cards/file_manager_card.dart`
  与 `test/workspace/file_manager_card_test.dart`：无问题。
- **Widget 测试未跑通**：`flutter test test/workspace/file_manager_card_test.dart`
  在加载期即失败，报错全在本次改动清单之外
  （`workspace_layout_setting_page.dart` 的 `Icons.swipe_horizontal_outlined`、
  `panel_tab_strip.dart` 的 `SingleChildScrollView.shrinkWrap`、
  `reader_input_controller.dart` 缺 `onOpenRadialMenu` 实参）。
  新增的 3 条树判据（默认关闭 / 缩进与箭头 / 点行才跳转、开树顺带关列）**尚未执行过**。
- 另需注意：`flutter_rust_bridge_codegen generate` 是**整 crate** 生效的，本次重跑
  顺带把并发方尚未生成的 `operation_binding` 轮盘接口写进了
  `frb_generated.{dart,io,web}.dart` 与 `rust/src/frb_generated.rs`。
  这不是本次的功能，但会出现在同一份 diff 里。

## 2026-09-20：搜索从「整串子串匹配」升级成可搜索

问题不是搜索没做好，而是它只有一个「当前目录内、把整个查询当一个 needle 的
`contains`」。所以 `春 日`、`chapter 3` 这类多词查询必然 0 结果，`summer photo`
也搜不到 `summer_photo.jpg`，子目录里的书永远搜不到，而且只有回车才动。

| 层 | 改动 |
|---|---|
| 词法 | 搬入上游 `search_query.rs` + `search_norm.rs`（M-15，零偏离逐字拷贝，见 [溯源清单](local-core-vendored-modules.md)）。空格分词 AND、`-词` 排除、`"短语"`、OR 模式；查询期与后置过滤共用 `normalize_for_match` |
| 匹配面 | hay 从「条目名」扩到「相对搜索根的目录 + 条目名」。**只喂相对路径** —— 父目录名不该让它的所有子项都命中（单层浏览时相对段为空，所以这一项在不开递归时不改变结果） |
| 递归 | `file_manager::search_entries`：广度优先（撞上条数上限时保留的是最近的命中，而不是某一条分支的最深处）、层数夹到 12、命中夹到 512、`AtomicBool` 取消。未命中的条目不付 syscall：先按 `file_name()` 预筛，命中项和候选目录才构造完整节点 |
| 单一策略出口 | `file_tree` 的逐条分类抽成 `node_for_dir_entry`，整目录列举与递归搜索共用 ⇒ 搜索结果里不会出现列表里根本不存在的条目 |
| 真本归属 | 命中写进 `FileManagerTab.search`，`entries()` 直接交出它。Dart 不揣第二份列表：重建卡片结果还在，陈旧判定也能用会话的 `search_request() == expected` 回声。页签标题变「搜索: 词」，导航即离开结果视图 |
| 交互 | 输入即搜（180ms 防抖），搜索请求走不受 `_busy` 门控的独立通道（原来 `TextField: enabled: !_busy` 会让输入框每次请求期间禁打）；核心 trim 过的查询不回显到聚焦中的输入框，否则打不进空格；显式动作先 `_cancelPendingSearch()`，免得晚到的防抖把点击的快照当陈旧数据丢掉 |
| 历史 | `settings.db` 新表 `file_manager_search_history`，20 条按最近使用裁剪；搜索框展开时以词条呈现前 8 条，点一下再搜。**只有回车与点历史词进历史**，防抖那一路不进 |

### 两处口径选择

- **「含子目录」默认关**：一次键入就扫整棵树的第一印象太差（无命中时要扫到深度上限才停）。
  递归与否留在搜索行上那颗开关里，可被看见、可被关掉。
- **`#标签` 语法能解析但没有判定依据**：上游把 tag token 交给 `fts_meta.db` 的 tags 列做
  完全一致判定，Rossi 没有标签库。当前它退化成普通子串词元（`#原神` 就是找带 `#原神`
  的文件名），不算接通，见上表「尚未接通」。

### 验证

见本文末尾的「2026-09-20 本机验证结果」。

## 2026-09-20 本机验证结果（搜索）

- `cargo test -p rossi_local_core -p windcore --lib --quiet`：351 + 34 项通过。
  搜索新增 7 项：词元语法与 OR、`search_in_path` 不让搜索根名污染子项、
  递归命中与相对目录、路径词元 + 深度上限、隐藏项/类型筛选/取消、上限截断、
  历史落盘的「去重 + 按最近使用裁剪」。
- `python3 script/sync_vendored_modules.py`：九份源码与 pin 版一致，两份新搬入的
  搜索模块**零代码偏离**（只有文件头注释差异）。
- `cargo fmt --check`：干净。
- `flutter test test/workspace/file_manager_card_test.dart`：47 项通过，含新增 6 项
  搜索判据（输入即搜跨过防抖才提交、飞行中输入框仍可打字、trim 回显不吃空格、
  含子目录触发遍历、结果页签的相对目录副标题 + 两个出口、历史词条点击与清空）。
  **另有 3 项失败，全部在本次改动之外**：`文件树默认关闭…`、`树里点箭头…`、
  `打开文件树时顺手关掉目录列…`，失败点是 `_openTree` 里 `pumpAndSettle timed out`，
  单跑也复现 —— 属于文件树 UI 那条线尚未跑通的判据。
- `dart analyze` 卡片、测试：无问题。
- 顺带修的测试夹具：`tearDown(RustLib.dispose)` 在 FRB 2.12 下**不清** `_EntrypointState`
  （`dispose()` 只关 port manager），于是每个用例的 `initMock` 都撞
  「Should not initialize flutter_rust_bridge twice」，整个文件只有第一个用例能跑。
  改成 `dispose()` + `RustLib.instance.resetState()` 之后，本次之前被这条级联
  掩住的用例（含上面那 3 项文件树判据）才第一次真正被执行过。
- 递归搜索的**真实盘表现没有验证**：这台机器没有 Xcode，Flutter UI 跑不起来，
  以上都是单元与 Widget 层结论。深度上限、512 条截断与「无命中时扫到上限才停」
  的耗时感受需要在目标平台上按一个大库实测。

## 2026-09-20：文件操作与多选接通（ADR-0017）

差异核对里那块「**写不出去**」——`local_core` 生产代码一处用户路径写操作都没有——本次补齐。
上游 `delete_worker.rs` / `cut_clipboard.rs` / `shell_file_ops.rs` **一份都没搬**：
三份的 `use` 头只有 `std`，函数体内却分别有 21 / 11 / 14 处 Windows API（`IFileOperation`、
`hwnd: Option<isize>`），按 ADR-0011 的教训，这是 T4（平台等效重写）不是 T1（原文搬）。

| 层 | 落点 | 边界 |
|---|---|---|
| 选中模型 | `rust/local_core/src/file_ops/selection.rs` | T3，逐行翻译 neoview `DirectorySelection.ts`。`generation` 直接取文件管理器的 `generation()` —— 选中按**列表下标**表达，下标只在某一份 `entries()` 上有意义。全选态下 `ranges` 的含义与未全选时**相反**（那一段是「被取消的」） |
| 执行层 | `.../file_ops/execute.rs` | T4。回收站走 `trash` crate 5（MIT，纯 Rust，内部按平台分流）；其余走 `std::fs`。默认冲突策略 `Fail`（撞名 `EEXIST`），另给 `Overwrite` / `KeepBoth`。逐条结果 + `cancelled` + 聚合摘要，**一条失败后其余停下** |
| 剪贴板 | `.../file_ops/clipboard.rs` | T3，对齐 neoview `FolderClipboard`。两步式：`cut` 粘完清空、`copy` 保留；拒绝「把目录粘进自己的子孙」 |
| FRB 桥 | `rust/src/api/file_ops.rs` | 会话状态（选中/剪贴板/撤销栈，上限 50）与文件管理器共用同一个 `id`；`file_manager_close` 与 `file_ops_close` 成对调用 |
| 纯规格 | `lib/workspace/model/file_manager_entry_menu_spec.dart` | **零 import** 的纯 Dart：菜单有哪些项、哪一项置灰、要不要二次确认、点一下算哪种手势。判据 `dart run test/workspace/file_manager_entry_menu_check.dart`（**145 条**） |
| 交互 | `lib/workspace/widgets/cards/file_manager_entry_context_menu.dart` | MD3：`MenuAnchor` + `MenuItemButton` + `md3MenuStyle()`（`surfaceContainer` / 2dp / 4dp 圆角 / 纵向 8dp）。仓里既有的 `shelf_entry_context_menu.dart` 仍是 M2 的 `showMenu`，**没动** |
| 问与说 | `lib/workspace/method/file_manager_actions.dart` | 对话框（重命名 / 新建 / 不可撤销删除的确认）、系统剪贴板、提示条文案 |
| 总开关 | `fileManagerSetting.fileOperations`（默认开） | 关掉后没有右键菜单、没有多选、没有操作条。两个入口：卡片「更多」菜单 + 设置页「文件操作」节 |

三条刻意的决定（细节与理由见 ADR-0017）：

1. **确认策略是两个布尔**（`destructive` 要确认 / `dangerous` 上色），与
   `flutter-list-entry-context-menu` 技能的唯一偏离。回收站的保护是**撤销通道**不是确认框，
   并成一个布尔就会要么每次删都弹框、要么永久删除少了确认。
2. **`paste` / `createFolder` 的落点是被右键的那个目录**，所以两处桥各加了一个可选落点参数。
   原先只认「当前目录」——照原样接起来就是菜单在说谎。
3. **打开了「写」这一层，但没做 crash-safe**：批量中途崩溃会停在半路（撤销日志随进程丢失）。
   G-03（`book_fs_journal.rs` 的 forward/rollback 自证）仍是独立候选，
   **不能因为 G-30 落地就把它划掉**。

本机验证结果：

- `cargo test -p rossi_local_core`：**422 项通过**（改动前的基线是 379，新增 43 项：
  选中 17、执行 23、剪贴板 8，含一条**真的往系统回收站删了一次**再自己收尾的判据）。
- `cargo check -p rossi_local_core -p windcore`：0 error、0 warning。
- `dart analyze lib/`：无问题。
- 菜单规格判据：`file_manager_entry_menu_check: 145 checks passed`。
- `flutter pub run build_runner build` / `flutter pub run slang` 均已重跑，生成物与源码同快照。
- **没有在真机上点过**：这台机器的 Flutter UI 跑不起来（沙箱里 `dart`/`flutter` 不在 PATH，
  且 macOS 侧构建要 Xcode）。菜单观感、右键时序、多选手感都还没有人眼确认，
  要按 ADR-0017 的判据在目标平台上过一遍。
- `flutter test test/workspace/file_manager_card_test.dart` **本次没跑**：
  `dart run` / `flutter test` 会先触发 native asset hook 去编 windcore（几分钟），
  而该测试文件里本来就有 3 项 FileTree 判据是红的（见上一节）。
