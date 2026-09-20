# 详情页操作栏（桌面左右 rail + 移动端底部条）

> 状态：**方案，未开工**。所有条目都是 ⬜。
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

⚠️ 两条都躲不开 Rust：A 要改 catalog，且 `actionCatalog()` 是 FRB 生成的（`lib/src/rust/api/operation_binding.dart`），所以动完必须重跑代码生成。**没有纯 Dart 的注册表方案**。

## 3. 车道与顺序

| 车道 | 内容 | 判定 | 依赖 | 落点 |
|------|------|------|------|------|
| A | Rust：新增 `ActionCategory::ComicInfo` + `comic-info.*` 条目（未接线的一律 `implemented: false` 占位） | 需核心改 | — | `vocabulary.rs`（追加，不改既有条目：改 id 会让已发出去的绑定包失效，见该文件 `:15` 注释） |
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
- `:150` `Scaffold`，`:151` 普通 `AppBar`（不是 SliverAppBar）；body 是 `:414` `CustomScrollView`，首个 sliver `ComicPreviewSliver`（`:533`）
- `:572` `_constrainedSliver` 把内容居中限宽 1120 —— **rail 可以站在这 1120 之外的余量里**，宽窗口下不吃正文宽度
- 该页可内嵌为发现页标签：`lib/page/discover/service/discover_router.dart:321`、`:341`

**返回 / 顶栏那几颗**（全是本页自绘，不走共享顶栏）
- 返回 `comic_info.dart:152-158`，走 `popTabOrClose(context, otherwise: context.pop)` —— 住在标签里时关**当前标签**，直接 `context.pop()` 会弹掉压着详情页的那一整页
- 首页 `:162`（同样先问 `DiscoverTabScope.maybeOf`）、关注 `:177`、更多菜单 `FluentPopupMenuButton`
- `WorkspaceTopChrome`（`lib/workspace/widgets/chrome/workspace_top_chrome.dart:62`）**只服务工作台**，详情页与它无关

**动作全集**（rail 要照搬的就是这些）
- 操作行清单：`lib/page/comic_info/widgets/comic_operation.dart:132-180` —— 点赞 `:134`、评论 `:141`、收藏 `:147`（本地 `:123` / 云端 `:117` 二选一）、阅读卡 `:150-159`（仅 `widget.onRead != null` 时出现）、下载 `:160-170`（**带长按选章节** `onLongPress: _openDownloadChapterPicker`）、磁力复制 `:173-179`（`magnet.isEmpty` 时整项不渲染）
- 页内私有方法：`_startReading:362`、`_toggleFollow:757`、`_toggleFollowFromMenu:780`、`_handleExport:696`、`_toggleOrder:755`
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

## 7. 待决策（我不替你定）

1. **车道顺序**是否按 §3 的最小闭环走（先跑通不可自定义的默认 rail）。
2. **左右 rail 的默认内容**：建议 左=返回、首页；右=开始阅读、收藏、下载、点赞、评论、磁力。也可以反过来，或只留右侧一条（左 rail 默认空）。
3. **配置同步归属**：`docs/settings-sync-scope.md` 的块表里建议挂到 `shell` 块（它就是 UI 外壳偏好）。注意两条反例口径——工作台把「布局快照」明确排除在同步外，而 `favoriteArtistSetting` 是用户点名不出本机。rail 的条目序列属于偏好还是属于本机布局？
4. **塌缩阈值**：复用 `comic_operation.dart:186` 的 `>= 900`，还是 `comic_info.dart` 那处 960，还是新开一个具名常量。**建议新开一个常量**并在两处留注释，别再增加第四套字面量。
5. **发现页标签内嵌时**是否画 rail：那时顶部已有一行标签 chrome，底部可能压着标签条。
6. **触摸端底部条上的下载**：长按选章节这个语义在底部条上还保不保（长按在移动端是常见的菜单入口，但底部条空间紧）。

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

`git status` 当前 **82 个文件未提交（+4973 / −3130）**，其中正好包括本方案的落点：

`lib/page/comic_info/view/comic_info.dart`、`widgets/comic_operation.dart`、`widgets/comic_preview.dart`、`lib/config/global/global_setting.dart`（含 `.freezed.dart` / `.g.dart`）、`lib/network/sync/sync_service.dart`、`docs/settings-sync-scope.md`、`lib/i18n/en_US.i18n.json` + `zh_CN.i18n.json` + 三份 `strings_*.g.dart`、`lib/page/discover/*`。

车道 D（设置块 + 同步范围）与车道 I（i18n）和这批改动**必冲突**。开工前先确认这批在途改动落地或提交；否则先把上面的行号当近似值，动手前对目标文件重跑一次 `git diff --stat`。

> 2026-09-21 实测订正：这批不是冲突，是**另一件事正在写**（`comic_read_button.dart` / `comic_quick_read.dart` / 各 `search_bar.dart` / `library_entry*` = 卡片直接阅读按钮，见 `docs/cover-read-button-acceptance.md`）。仓库当时**没有任何冲突状态**（无 `MERGE_HEAD`/rebase/未合并路径，`main` 与 `origin/main` 为 0/0），`flutter analyze lib` 也是 No issues。上面「必冲突」的判断按字面读是错的，留在这里当提醒：**没核对过 `git ls-files -u` 之前不要把「脏」说成「冲突」。**

## 10. 顺手记下的既有债（与本方案无关，别去追）

- `test/reader/page_split_test.dart` 在 **HEAD 上就是红的**：它引用的 `buildReadModeSinglePageSlots` 与 `ReadModeSlotItem.slice` 在 HEAD 的 `lib/` 里同样不存在（该测试最后由 `fda895ca` 2026-09-19 改动，签名后来变了）。所以 `flutter test` 里这几条失败**不是**并发改动弄坏的，也不是 ObjectBox 环境假红，是真的存量债。本方案不动它。
- `poc/texture-bridge/**` 有整片 `package:flutter/material.dart` 找不到的错误：那个 POC 是独立工程，不在根 `pubspec.yaml` 的解析范围内，属正常噪声。
- 两条下划线开头的探针测试仍在仓库里（`test/workspace/_lane_wheel_probe_test.dart`、`test/comic_read/_wheel_probe_test.dart`），刻意保留还是待清不由本方案判断。
