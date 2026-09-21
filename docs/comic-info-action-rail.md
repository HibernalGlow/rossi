# 详情页操作栏（桌面左右 rail + 移动端底部条）

> 状态：**车道 A / B / C-1 / E / F 已落地（🟡 自动化测试过、未实机），C-2 / G / H / I / J 未开工**。2026-09-21 的三个决定见 §7.1，落地记录见 §7.5（A）与 §7.6（B/C-1/E/F）。
> 2026-09-21 用户提出：「进入漫画当前要想要返回之前的界面，只能点左上角的返回，然后开始阅读也是只能点击特定的按键，操作不太方便，而且鼠标跨度很大。」

## 0. 状态图例

| 标记 | 含义 |
|------|------|
| 🟢 | 代码做了 **且** 实机验过 |
| 🟡 | 代码做了，未实机（这台机器跑不了 GUI，宿主 UI 改动最高只到这一档） |
| ⬜ | 未开工 |
| ⛔ | 明确不做（理由见 §6） |

## 1. 已钉死的口径

| # | 问题 | 决定 |
|---|------|------|
| 1 | 位置与显隐 | 桌面**左右两条 rail 都能放**，且每侧条目**可自定义**；移动端底部常驻条 |
| 2 | 动作范围 | **整份操作行照搬**（不是只做返回+阅读两颗） |
| 3 | 接线口径 | **先开 `comicInfo` context**，按钮来自注册表，不做第二份真相 |
| 4 | 自定义入口 | **设置页新开一页**（复用操作绑定那种两栏编辑器） |
| 5 | 原横排操作行 | **保留**，rail 只做加速层 |
| 6 | 移动端 | 底部条**直接替掉** `FloatingActionButton` |

## 2. 一个必须先挑明的分歧：`context` ≠ `动作清单`

第 3 条口径字面上说的是 `InputContext`，但 rail 真正需要的是 `ACTION_CATALOG`。注册表里这是两件独立的事：

- **(A) 动作目录** —— `rust/local_core/src/operation_binding/vocabulary.rs:367` 的 `ACTION_CATALOG`，每条是 `{id, label, category, implemented}`（同文件 `:342`）。这是 rail 上「有哪些按钮、叫什么名、能不能点」的唯一真相。`implemented: false` 的条目已经有一套置灰机制（`BindingActionInfo.implemented`，`lib/service/operation_binding/operation_binding_store.dart:332`），正好用来放占位入口。
- **(B) 输入 context** —— 同文件 `:33` 的 `InputContext`（7 个变体：`global/reader/video/panel/shell/editor/modal`，`:21` 全集、`:67` 优先级、`:81` 全局隔离）。它回答的是「这根输入该归谁」，只有当详情页**也要吃键盘/鼠标绑定**时才用得上。

当前 47 条 id 前缀全是 `reader.* / radial.* / video.*`，Dart 侧活跃集合写死 `['reader']`（`operation_binding_store.dart:20`，注释注明 v0.1 只接阅读器）。

**建议的切法**：A 先做（rail 能落地、能自定义、能置灰），B 单独一条车道。理由是 B 一开就要回答两个新问题——详情页按 `Esc` 是什么、`comicInfo` 算不算 `isolates_global`（`vocabulary.rs:81` 那条断言有测试在守，`:678`）——而这两个问题跟「鼠标跨度大」这个原始痛点无关。

⚠️ 两条都要动 Rust：A 改 `ACTION_CATALOG`，B 加 `InputContext` 变体。**没有纯 Dart 的注册表方案**（清单权威在 Rust，Dart 抄一份就是第二份真相）。但**车道 A 不需要重跑 FRB** —— `operationBindingActionCatalog()` 返回的是 JSON 串，追加条目不改签名，实测只重编 crate 就够（见 §7.5）；真正需要重跑生成的是 B（动 enum）。

## 3. 车道与顺序

| 车道 | 内容 | 判定 | 依赖 | 落点 |
|------|------|------|------|------|
| A 🟡 | **已落地**：Rust 新增 `ActionCategory::ComicInfo` + 13 条 `comic-info.*`（全部 `implemented: false` 占位）+ 阅读器绑定表整族排除。详见 §7.5 | 需核心改 | — | `vocabulary.rs`（追加，不改既有条目：改 id 会让已发出去的绑定包失效，见该文件 `:15` 注释） |
| B | FRB 重生成 + Dart 出入口按 context/分类过滤 | 需宿主小改 | A | 生成物 + `operation_binding_store.dart` |
| C | 执行体：详情页动作全部**有状态**，需要一个 scope 对象 | 需宿主大改 | A,B | 新文件 `lib/page/comic_info/action/comic_info_action_dispatcher.dart`，对照 `lib/page/comic_read/controller/reader_action_dispatcher.dart:139` 的 `switch (actionId)` 形状 |
| D | 配置存储：左右两条 rail 的 id 序列 + 开关 | 需宿主小改 | A | `GlobalSetting` 新子对象 + **同步范围归属**（§7.3） |
| E | rail 外壳 widget（竖向、塌缩、让位） | 需宿主小改 | C | 新文件 `lib/page/comic_info/widgets/comic_info_action_rail.dart` |
| F | 挂进 `ComicInfoPage` | 需宿主小改 | E | `lib/page/comic_info/view/comic_info.dart`（**最小挂载点**，见 §5） |
| G | 移动端底部条 + FAB 退役 | 需宿主小改 | C | 新文件 `.../comic_info_action_bar.dart` + 改 `read_entry_placement.dart` 不变式（§4） |
| H | 设置页编辑器（左候选/右当前，拖拽排序 + 左/右归属） | 需宿主大改 | D | 新页面 `lib/page/setting/comic_info/`，样式照 `lib/page/setting/operation_binding/operation_binding_setting_page.dart:68` |
| I | i18n：`en_US.i18n.json` + `zh_CN.i18n.json` + `strings` 生成 | 需宿主小改 | A | 动作显示名走注册表的中文 label（Rust 侧就是中文），rail 的 tooltip 与设置页文案走 i18n |
| J | 测试 | — | C,D,E | 纯 Dart 判据测试（不 import flutter 的可直接 `dart run`）+ `flutter test` widget 测试 |

**先跑通的最小闭环**：A → B → C → E → F，此时左右 rail 上**默认那份**动作全部可点，自定义还没有；再补 D → H 变成可编辑，最后 G 收尾移动端。这样每一步都有可看的产物，不用攒到最后一次验。

## 4. 车道 G 会撞上一条既有不变式

`lib/page/comic_info/models/read_entry_placement.dart:36` 写死了：**「任何时刻只有一个入口」**——桌面 `inlineCard` 顶掉 FAB，触摸 `floatingButton` 顶掉卡片。而第 5 条口径选了「原操作行保留」，第 6 条选了「底部条替掉 FAB」。合起来：

- 触摸端：FAB 退役 → `floatingButton` 这个档位在移动端失去意义；`comicInfoInlineReadButton=false` 时的回退路径变成「底部条」而不是「FAB」。
- 桌面端：rail 里的「开始阅读」+ 操作行里那张卡片（`comic_operation.dart:150-159`）= **同屏两颗**。这条不变式要么改成「同一个动作在一屏内最多一处」，要么在 rail 出现时把行内那张压掉。

这条是本次改动里唯一会**推翻既有设计意图**的地方，单独列出来，不要顺手改掉。

## 5. 现状依据盘点（已逐条核对）

**页面结构**
- `lib/page/comic_info/view/comic_info.dart:37` `ComicInfoPage`（`@RoutePage`, Stateless）→ `MultiBlocProvider:58` → `_ComicInfo`，build 在 `:138`
- `:150` `Scaffold`，`:151` 普通 `AppBar`（不是 SliverAppBar）；body 是 `:404` `CustomScrollView`，首个 sliver `ComicPreviewSliver`（`:523`）
- `:562` `_constrainedSliver` 把内容居中限宽 1120 —— **rail 可以站在这 1120 之外的余量里**，宽窗口下不吃正文宽度
- 该页可内嵌为发现页标签：`lib/page/discover/service/discover_router.dart:321`、`:341`

**返回 / 顶栏那几颗**（全是本页自绘，不走共享顶栏）
- 返回 `comic_info.dart:152-158`，走 `popTabOrClose(context, otherwise: context.pop)` —— 住在标签里时关**当前标签**，直接 `context.pop()` 会弹掉压着详情页的那一整页
- 首页 `:162-172`（同样先问 `DiscoverTabScope.maybeOf`）、关注 `:174-189`、更多菜单 `FluentPopupMenuButton:190`
- `WorkspaceTopChrome`（`lib/workspace/widgets/chrome/workspace_top_chrome.dart:62`）**只服务工作台**，详情页与它无关

**动作全集**（rail 要照搬的就是这些）
- 操作行清单：`lib/page/comic_info/widgets/comic_operation.dart:132-180` —— 点赞 `:134`、评论 `:141`、收藏 `:147`（本地 `:123` / 云端 `:117` 二选一）、阅读卡 `:150-159`（仅 `widget.onRead != null` 时出现）、下载 `:160-170`（**带长按选章节** `onLongPress: _openDownloadChapterPicker`）、磁力复制 `:173-179`（`magnet.isEmpty` 时整项不渲染）
- 页内私有方法：`_startReading:352`、`_handleExport:686`、`_toggleOrder:745`、`_toggleFollow:747`、`_toggleFollowFromMenu:770`
- 触摸端「阅读」那颗悬浮按钮：`floatingActionButton:334`（`floatingActionButtonLocation:328`），内嵌 `:1187` 另有一处 `>= 960` 阈值
- 可用性来自状态：`allowLike` / `allowComments` / `allowDownload` / `isCollected` / `hasHistory` / `isLiked`

**rail / 底部条的先例**
- `lib/page/navigation_bar.dart:263` 已在用 `NavigationRail`（`:252` 平板 vs `:197` 手机），判据 `hasWorkspaceEntry`（`lib/workspace/model/workspace_startup.dart:47`）
- 工作台侧：`PanelTabStrip`、`PanelBarPositioner`、四边抽屉 `lib/workspace/widgets/edges/controlled_edge_shell.dart:23`、阅读器工具条 `lib/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart`
- **响应式判据现存三套**：指针判据（`read_entry_placement.dart:25`、`WorkspaceTopChromeMode.forTargetPlatform`）、`LayoutBuilder` 宽度阈值（`comic_operation.dart:186` 是 900、`comic_info.dart` 另有一处 960）、`Platform.isX`（`lib/platform/desktop/window_logic.dart:14`）。加 rail 是第四处，**必须先选边**（§7.4）。
- 开关先例：`GlobalSetting.comicInfoInlineReadButton`（设置 UI 在 `lib/page/setting/global/app_behavior_setting_page.dart:83`）

**注册表现状**
- `ACTION_CATALOG` 47 条，无一条详情页动作；`ActionDefinition` **没有** context 字段（context 挂在绑定行上，不是动作上）
- 执行体：`lib/page/comic_read/controller/reader_action_dispatcher.dart:139`
- 显示名：`lib/service/operation_binding/action_labels.dart:16`；id 常量：`binding_doc.dart:44-77`
- 工作台另有两份独立注册表（`lib/workspace/registry/workspace_panel_registry.dart:64`、`workspace_card_registry.dart`），**都是工作台专用**，详情页不要复用

**改法约定**（本仓是深度改造过的 fork，仍按 core+adapter 收口）
- 上游文件只留最小挂载点：`comic_info.dart` 期望侵入 ≤ +10/−5（一行 import + body 包一层 `Row` + `floatingActionButton:` 那一段换掉）；其余全在新文件
- `global_setting.dart` 只加一个子对象（freezed/g 是生成物）

## 6. 明确不做

| 项 | 理由 |
|----|------|
| rail 就地编辑（长按/右键拖排） | 口径 4 选了设置页。就地编辑还要处理边缘弹层定位，收益不抵成本 |
| 自动拆重（进了 rail 就从操作行移除） | 口径 5 选了保留原行。代价是一屏两处重复，这是**用户看过选项后选的** |
| 完全废掉横向操作行 | 同上，且触摸端等于丢一整屏信息 |
| 移动端底部条可折叠 / 可关 | 口径 6 选了直接替掉 FAB，不留退路。若实机手感不对再回来补开关 |
| rail 出现在顶部或做成悬浮 | 口径 1 只有左/右/底部 |
| 复用 `WorkspacePanelRegistry` / `WorkspacePanelSide` | 那是工作台面板专用，语义是「面板停靠」不是「按钮集合」 |
| 给详情页动作加 `area` 九宫格绑定 | 九宫格（`vocabulary.rs:96`）是阅读画面分区，详情页没有这个语义 |
| 出厂绑定表里预先塞 `comic-info.*` 行 | 车道 B 未通前塞进去等于给用户一张点了没反应的表 |
| rail 条目的图标自定义 | 范围外。图标先跟注册表条目走，需要改名再单列 |

## 7. 决策

### 7.1 已拍（2026-09-21，用户「拍完 §7 的三个决定再开车道 A」）

| # | 议题 | 决定 | 依据 |
|---|------|------|------|
| 2 | 左右 rail 默认内容 | 左 = 返回、回首页；右 = 阅读、收藏、下载、点赞、评论、磁力（6 颗）。注册表一次登记 **13 条**（另含关注、选章节下载、章节倒序、导出、更多），让车道 H 的候选清单是全集 | 痛点只有两颗，默认摆 6 颗是加速层不是搬家；其余 5 条只登记不上默认轨，免得 rail 变长 |
| 3 | rail 配置进不进同步 | **进 `shell` 块** | 判例是 `e08c948e feat(desktop): 透明标题栏三态并纳入同步` —— 同为「桌面 UI 外壳偏好」。与「工作台布局快照不同步」不矛盾：那边排除的是**瞬态**偏移与边缘揭示，rail 的 id 序列是用户手工排的持久偏好；`favoriteArtistSetting` 那种「点名不出本机」的例外不适用 |
| 4 | 用哪套响应式判据 | **主分支不用宽度**，用本页已有的指针判据 `comicInfoPlatformHasPointer`（`read_entry_placement.dart:25`，其注释已声明口径与 `WorkspaceTopChromeMode.forTargetPlatform` 一致）：有指针 ⇒ 左右 rail，无指针 ⇒ 底部条。宽度**只**决定一个新问题：rail 上画不画文字（新增一个具名常量） | 「rail 还是底栏」本质是输入设备问题不是视口宽度问题；这样 `comic_operation.dart:186` 的 900 与 `comic_info.dart:1187` 的 960 两处都不动，也不引入第四套字面量判据 |

车道顺序按 §3 的最小闭环走（A → B → C → E → F 先跑通默认 rail，再 D → H 补自定义，最后 G 收尾移动端）。

### 7.2 仍未拍

1. **发现页标签内嵌时**是否画 rail：那时顶部已有一行标签 chrome，底部可能压着标签条。
2. **触摸端底部条上的下载**：长按选章节这个语义在底部条上还保不保（长按在移动端是常见的菜单入口，但底部条空间紧）。

## 7.5 车道 A 已落地（2026-09-21）

`rust/local_core/src/operation_binding/vocabulary.rs`：

- 新增 `ActionCategory::ComicInfo`（`as_str() == "comic-info"`，显示名「详情页」）
- `mod action` 追加 13 个 `comic-info.*` id 常量，`ACTION_CATALOG` **47 → 60**，全部 `implemented: false`
- 新用例 `comic_info_family_is_registered_with_stable_names`：钉住条目数、独立前缀、`comic-info` 这个**过滤键字符串**，并断言「排除这一族之后阅读器仍有可执行动作」

`lib/service/operation_binding/operation_binding_store.dart` 与 `.../operation_binding_setting_page.dart:68`：

- 新增 `OperationBindingStore.readerBindableCatalog()` 与 `comicInfoCategory` 常量，按分类**整族排除** `comic-info`；阅读器绑定页改用它
- 为什么这步不能省：实测 `binding_action_presentation.dart:31` 的 `bindingActionGroup` 对未知分类一路 fallthrough 到 `BindingActionGroup.view`、`bindingActionIcon` 落到 `Icons.touch_app_outlined` —— 不排除的话 13 条**没有执行端**的条目会伪装成「视图」组里的阅读器动作（正是「登记了就得端到端可达」那条的反面）。`radial_binding_editor.dart:68` 因为已经过滤 `implemented`，本来就不会显示它们
- **车道 H 注意**：详情页自己的候选清单要另取全量 `actionCatalog()`（或按 `comicInfoCategory` **只**取这一族），别误用 `readerBindableCatalog()`

**验证状态**：Rust 侧 `cargo test -p rossi_local_core --lib` **423 passed / 0 failed**（含既有的 id 唯一性、导出形状、context 优先级三条断言）；两个 Dart 文件 `dart analyze` No issues。🟡 未实机。

**FRB 不用重跑**：`operationBindingActionCatalog()` 签名没变（返回 JSON 串），追加条目只是数据 —— §2 那句「动完必须重跑代码生成」对**车道 A 这一半**是过强的，实测不成立。车道 B 剩下的实际工作只有「确认这 13 条过桥后 Dart 读得出」+ 要不要补 i18n 译文（`action_labels.dart:41` 的 `_ => entry.label` 会兜底成注册表中文，英文界面露中文；但这一族目前只在 H 的候选清单里出现，等 H 一起做）。

## 7.6 车道 B / C-1 / E / F 已落地（2026-09-21，同一晚）

**B（过桥）**：`test/operation_binding/comic_info_catalog_bridge_test.dart` —— 真起 `RustLib.init()`（不是 `initMock`），逐字逐序比对那 13 个 id、比对 `implemented` 的分布、并断言 `readerBindableCatalog()` 看不到这一族而阅读器那几条仍在。跑之前要 `cd rust && cargo build --release -p windcore`（`frb_generated.dart:93` 的 `ioDirectory: 'rust/target/release/'` 就是加载点，那条测试顺带是 hash 一致性的守门人）。

**C-1（执行端）**：`lib/page/comic_info/action/`
- `comic_info_action_entry.dart` —— `ComicInfoActionEntry`（带注册表 `actionId` 的渲染+执行数据）与 `ComicInfoActionIds`（13 个 id 的 Dart 侧镜像，正确性由上面那条过桥测试钉）
- `comic_info_action_scope.dart` —— `ComicInfoActionScope`（3 个能力）+ **一处** `dispatchComicInfoAction` 的 `switch`，未接的 id 返回 `false`，调用方不许静默吞

**为什么不叫 `ComicInfoActionItem`**：那个名字已被插件 JSON 的一条动态动作占了（`json/normal/normal_comic_all_info.dart:38`，`{name, onTap, extern}`，走 `models/comic_info_action.dart`）。同名会让人把「标签点下去开搜索」读成「rail 上那颗」。

**C-1 只接了 3 条，是刻意的收窄**：口径 2 定的默认清单里，右 rail 那 6 颗有 5 颗（收藏/下载/点赞/评论/磁力）的状态挂在 `ComicOperationWidget` 自己的 `setState` 上，要等 C-2 把状态提到 Cubit。中途我一度把关注/章节倒序/导出也写进接口，但它们**不在口径 2 的默认清单里**、rail 上没人渲染它们，等于三棵死分支，已收回（`wiredComicInfoActions` 现在只有 3 条）。**`implemented` 的判据是「端到端可达」**：注册表里只把 `back` / `home` / `read` 翻成 `true`，Rust 用例与 Dart 过桥测试各钉一份这个名单，接一条同时改两处。

**E + F（渲染与挂载）**：
- `widgets/comic_info_action_rail.dart` —— 不持状态、不判断「这条该干什么」，点击一律走 `dispatchComicInfoAction`
- `comic_info.dart` 的 `_ComicInfoState implements ComicInfoActionScope`；`body` 包一层 `_withActionRails(child:)`
- 判据按**口径 4**：`comicInfoPlatformHasPointer(defaultTargetPlatform)` ⇒ 左右各浮一颗胶囊，触摸端原样返回（底部条是车道 G，还没做）
- 默认左 = 返回 / 回首页，右 = 阅读。`_loadingComplete` 之前阅读那颗**不出现**（与那颗悬浮按钮同口径），而不是画一颗点不动的
- **实机第一版被打回一次（2026-09-21）**：原本用 `Row` 把 rail 做成正文两侧各一条 52px 的列，截图里漫画正文被挤窄 104px、而那一列除了顶上两颗之外整截是空的。用户口径：**「应该是纵向悬浮胶囊，符合 MD3 规范，不能挤占漫画显示空间」**。改成 `Stack` + `Positioned`（`left/right: 8`、`top:0/bottom:0` + `Center`）⇒ **不占布局宽度**，胶囊按内容多高就多高、垂直居中贴边
- 造型不自己发明，跟阅读器顶栏那套已有的悬浮语言对齐（`reader_toolbar_shell.dart`）：`surfaceContainerHigh` 底 + `outlineVariant` 描边 + stadium 圆角 + `secondaryContainer` 选中态 + 禁用 `onSurfaceVariant` 38% 透明；按钮 40 见方、图标 20。承底用 [Material] 而不是 `BoxDecoration`，否则 `IconButton` 的水波纹画在胶囊背后的页面上。数值与 `ReaderToolbarMetrics` 一致但**不 import** 它（那个类属于阅读器 chrome，依赖过去等于把两个界面的改期绑一起）
- 胶囊内条目多到一屏放不下时自己滚（`LayoutBuilder` 限高 + `SingleChildScrollView`），不裁掉最后几颗
- 文案没造新 i18n 键：`t.reader.backToHome` 复用现成的，「章节倒序」没有现成键所以干脆不端上 rail —— 造键要重跑 slang，那是全仓共享的生成物
- 回归判据：`test/comic_info/comic_info_action_rail_test.dart` 里「胶囊按内容多高就多高，不铺满一列」那条会量 rail 自己的尺寸（两颗 ⇒ 高 <140、宽 <60）。**Row 版本当场红**，所以它专门钉这件事

**验证状态**：`cargo test -p rossi_local_core --lib operation_binding::vocabulary` 6 passed；`test/comic_info/comic_info_action_rail_test.dart` 4 条 + 过桥 3 条全绿；`dart analyze`（我这 4 个文件）No issues。🟡 **未实机** —— rail 长什么样、让不让位、宽窗口下吃不吃正文宽度，都还得你在真窗口里看（§8 的 D1–D7）。

## 8. 验收清单（交付时逐条报编号 + 状态，缺哪条说哪条）

桌面端
| # | 验什么 |
|---|--------|
| D1 | 左右 rail 上的「返回」与左上角箭头行为完全一致，含**内嵌在发现页标签时关的是标签、不是整个工作台** |
| D2 | rail 上「开始阅读 / 继续阅读」的文案与图标跟随 `hasHistory` |
| D3 | `allowLike=false` 的图源上点赞那颗是**置灰**，不是「点了没反应」 |
| D4 | 磁力条目只在有磁力时出现（换一个没磁力的图源对比） |
| D5 | 下载那颗长按仍能开章节选择器 |
| D6 | 设置页编辑器里改完顺序/归属，回详情页立即生效，重启后保持 |
| D7 | 把窗口拖窄到阈值以下，rail 塌缩成底部条且不挡正文 |
| D8 | Windows / Linux release 能编过（本仓 `cfg(windows)` 的 Rust 路径历史上没人编过） |

移动端
| # | 验什么 |
|---|--------|
| M1 | 底部条常驻，FAB 不再出现 |
| M2 | 底部条不遮正文最后一段（原 FAB 会盖） |
| M3 | 横屏 / 小屏下条目不溢出 |
| M4 | `comicInfoInlineReadButton` 关掉后不出现两个阅读入口 |

回归
| # | 验什么 |
|---|--------|
| R1 | 封面下方那横排操作行行为与外观不变 |
| R2 | 已发出的绑定包仍能加载（catalog 只追加，没改既有 id） |
| R3 | 两台设备同步不互相顶掉 rail 配置 |
| R4 | `flutter test` 不比改动前更红（ObjectBox 相关的大面积红是本机环境假红） |

## 9. 开工前必读：并发风险

`git status` 当时 **82 个文件未提交（+4973 / −3130）**，覆盖本方案的全部落点。01:42 复验时那批已被**另一会话自己提交掉了**：`1b400912..HEAD` 共 14 个提交、97 文件 / +11006 / −3045，含 `feat(debug): 可关的布局溢出斜纹与 QuietRow`、`feat(comic_info): 磁力链接复制入口`、`feat(binding): 滚轮输入按实测设备录入`、`refactor(discover): 标签落到 plat 的标签组`。

仓库**从头到尾没有过冲突状态**：无 `MERGE_HEAD` / rebase / 未合并路径，`git diff --diff-filter=U` 与 `git ls-files -u` 都空，`main` 对 `origin/main` 只是本地领先（无远端分叉），`flutter analyze lib` 为 No issues。**教训：没核对过 `git ls-files -u` 之前，不要把「脏」说成「冲突」。** 上面那句「必冲突」按字面读是错的，原文留在 §9 历史里当提醒。

本节行号已按 14 个提交落地后的树重定（`comic_info.dart` 里 `_startReading` 及其以下整体前移 10 行）。但**另一会话还在提交**（`36692730` 落在 01:42:29，比我最后一次 mtime 检查只晚 20 秒 —— mtime 静默检测看不见 `git commit`），开工前必须重跑：

- `git log -1 --format='%h %cd'` + `git diff --stat 1b400912..HEAD` 确认有没有又落了新东西；
- 对目标文件重跑 `git diff --stat`，行号当近似值用。

**当前在途的那件事本方案不要去碰**：「卡片/封面直接阅读按钮」= `lib/widgets/comic_simplify_entry/comic_read_button.dart`、`lib/util/comic/comic_quick_read.dart`、`comic_simplify_entry.dart`、`library_entry*`、`favorite_shelf_card.dart`、`history_shelf_card.dart`、`comic_follow_page.dart`、`all_chip.dart`、`go_to_comic_read.dart`、`comic_card_badge_policy.dart` + 各自测试，验收在 `docs/cover-read-button-acceptance.md`。车道 F 与 G 要改 `comic_info.dart` 的 `floatingActionButton:` 那一段 —— **等它落地再动**，否则两边改同一处。

## 10. 顺手记下的既有债（与本方案无关，别去追）

- `test/reader/page_split_test.dart` 在 **HEAD 上就是红的**：它引用的 `buildReadModeSinglePageSlots` 与 `ReadModeSlotItem.slice` 在 HEAD 的 `lib/` 里同样不存在（该测试最后由 `fda895ca` 2026-09-19 改动，签名后来变了）。所以 `flutter test` 里这几条失败**不是**并发改动弄坏的，也不是 ObjectBox 环境假红，是真的存量债。本方案不动它。
- `poc/texture-bridge/**` 有整片 `package:flutter/material.dart` 找不到的错误：那个 POC 是独立工程，不在根 `pubspec.yaml` 的解析范围内，属正常噪声。
- 两条下划线开头的探针测试仍在仓库里（`test/workspace/_lane_wheel_probe_test.dart`、`test/comic_read/_wheel_probe_test.dart`），刻意保留还是待清不由本方案判断。
- **`test/operation_binding/operation_binding_store_test.dart` 3 条 + `radial_binding_editor_test.dart` 1 条已红**（2026-09-21）。做过归因实验：把 `operation_binding_store.dart` 与 `operation_binding_setting_page.dart` 退回**车道 A 之前**那个提交（`e2e0c304^`）再跑，失败一模一样 ⇒ 与本方案无关。**最可能的成因**是那 3 条都在测「播种 / 升级出厂绑定表」，而 `rust/local_core/src/operation_binding/factory.rs`（+149/−3）与 `neo_defaults.json` 当时正被另一会话改着；`flutter test` 加载的是 `rust/target/release/libwindcore.dylib`，我为了跑过桥判据重建过一次，于是把他们没写完的 Rust 一起编进了测试用的那份库。**推论**：在这棵树上看到 `operation_binding` 的播种类判据变红，先怀疑库里有别人的在飞改动，不要怀疑注册表。
