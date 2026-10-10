# FlClash 导航壳搬入 Rossi：GPL-3.0 源码进仓，许可处置暂缓

用户要求把 Gilberta（`/Users/glow/Base/Code/Prometheus/Gilberta`，多模块工作区，
`upstreams/flclash` 是 FlClash 的 fork）里**对 FlClash 优化过的桌面侧栏与移动端 Dock**
搬到 Rossi 复用，并要求**连自定义导航一起带过来**（后续追加三条：窄屏自动切移动端、
做成可开关、窄屏阈值可自定义）。

本 ADR 记录这件事**带来的许可后果**，以及为什么`LICENSE` 这一轮不动。
界面本身的形态与判据不在这里 —— 见 `navigation_bar.dart` 与各组件文件头。

## 背景：搬的是什么、谁的

| 来源 | 内容 | 许可 |
|------|------|------|
| FlClash 上游正文（提交 `841d6035`「add a sidebar, floating dock, snap sheets and drag to go back」，作者 chen08209） | 桌面侧栏、悬浮 Dock、`snap sheets`、拖拽返回 | **GPL-3.0** |
| 同一 fork 里作者为 `HibernalGlow` 的提交（`23337390` / `48a490c0` / `b7e1318c`） | Arc 化侧栏、自定义导航弹窗 | **GPL-3.0**（见下） |
| `lib/icons/`（glyph 体系 + 129 个 glyph 的词汇表） | 自绘图标 | **GPL-3.0** |

**「作者是我」不改变许可。** 那三笔提交是在同一个 GPL 代码库、同一批
`lib/widgets/*` 上的演进，不是独立重写，因此仍是 FlClash 的衍生作品。
这条要写下来，是因为它最容易在下次「这段是我写的，可以直接搬」的判断里被误用。

搬过来的文件（**GPL-3.0 来源**）：

- `lib/icons/{glyph,glyph_painter,glyph_icon,animated_glyph,app_glyphs,icons}.dart`
- `lib/widgets/navigation/{navigation_shape,spring_curve,navigation_sidebar,navigation_dock}.dart`
- `lib/widgets/navigation/navigation_context.dart`（两个扩展 + 一个 `ScrollBehavior`，
  按本仓缺的那几处依赖**重写**，不是原文）
- `lib/widgets/navigation/navigation_customization_dialog.dart`（按本仓栈重写：riverpod → 草稿 +
  立即回调；`PageLabel` → `NavigationEntryId`；文案走 slang。**形态是重写，来源是同一个 fork 的
  `custom_navigation_dialog.dart`**，因此按 GPL 来源对待）

本仓**自有**代码（不属于上面那批，撤出时不必动）：

- `lib/widgets/navigation/navigation_layout.dart`（窄屏判定纯函数）、`navigation_entries.dart`（**条目**身份与清单：页面 + 动作）
- `lib/config/global/parts/global_setting_navigation_part.dart`、`lib/page/setting/global/parts/appearance_navigation_part.dart`
- `lib/page/navigation_bar.dart` 的改造、`test/widgets/navigation_pure_test.dart`

## 决定

1. **原文照搬**（用户拍板，2026-10-09）。相对原文的改动逐文件登记在各自文件头，
   另见下表「边界」。
2. **`LICENSE` 这一轮不动**（用户拍板）。仓库仍标 **MPL-2.0**。
   ⇒ **本 ADR 明确记下：当前仓库处于已知的许可不一致状态** —— 树里有 GPL-3.0 源码，
   而分发条款写的是 MPL-2.0。这份 MPL-2.0 声明对上面那批文件**不成立**。
   该状态被接受的前提是**本机自用、暂不对外分发**（ADR-0006 / Q1 的「个人自用」）。
3. **退出条件两条，随时可执行，二选一**：
   - **A 转 GPL-3.0**：改 `LICENSE`、根目录补 GPL-3.0 正文副本、README 徽章与
     `CONTEXT.md` / `docs/ROADMAP.md` 的口径同步改。Breeze 来源文件仍按 MPL-2.0
     （MPL-2.0 §3.3 允按二级许可分发，GPL-3.0 在允许列表内），整仓对外按 GPL-3.0。
   - **B 撤出**：删掉上表那批 GPL 文件，改走「读它的设计 + 自行重写」——
     弹簧 lens、拖拽选页、惯性投射、橡皮筋过拉、悬停磁吸这几套动效要重做，
     自绘 glyph 词汇表要重画（不是换图标）。
4. **在决出 A/B 之前不再新增 GPL 源码进仓。** 一进一出不是一个动作：
   待决范围每扩大一次，B 路的成本就抬一次。

## 边界：相对原文改了哪几处

逐文件的完整清单在文件头。汇总（**都是为了能在本仓编译**，不是为了改行为）：

| 处 | 改法 |
|----|------|
| import 路径 | `fl_clash/*` → `zephyr/*` |
| `context.colorScheme` / `context.textTheme` | 上游在 `fl_clash/common/*` 里聚合导出；本仓走 `navigation_context.dart` 的两个扩展，**调用写法与原文一字不差** |
| `HiddenBarScrollBehavior` | 它拖着本仓没有的 `CommonScrollBar`；按语义重写为 `NavigationHiddenBarScrollBehavior`（`buildScrollbar` 直接返回 child） |
| `SpringCurve` / `AppShape` | 上游在 `common/motion.dart` / `common/shape.dart`（后者带本仓没有的表单依赖）⇒ 拆出 `spring_curve.dart` / `navigation_shape.dart`，只保留导航用到的那几档圆角 |
| 侧栏底部那颗「自定义导航」 | 原文直接 `CustomNavigationDialog.show(context)`，把侧栏与弹窗绑死 ⇒ 改成参数（`onCustomize` + `customizeLabel`）。**2026-10-10 起本仓调用点传 `null`** —— 那颗写死的按钮退役了，「自定义导航」改成一条普通动作条目（见下），参数留着只为不离上游太远 |
| 侧栏底部动作区 | **新增** `SidebarAction` + `actions`：本仓原本挂在 `NavigationRail.trailing` 的四颗按钮要有新家，而它们与 destination 的差别只是「点了不换页」 |
| 动作区**怎么画** | 原文复用 `_SidebarButton` + `_DestinationRow`（图标 + 文案的整行，展开时带标签）。**2026-10-10 起本仓改画成「一只分组槽 + 图标键」**：侧栏 `ActionGroup(axis: Axis.vertical)`、Dock 尾部 `ActionGroup(axis: Axis.horizontal)` —— 同一份清单在两支里只换排布方向，文字退到 tooltip。度量与槽收在 `widgets/action_group.dart` 一处，与文件管理器工具栏、书架页右上角共用（判据 `test/widgets/action_group_test.dart` 钉住横竖两档的几何） |
| Dock 尾部的溢出弹层 | 先前是「一颗 FAB 弹 `showModalBottomSheet` 的竖排列表」；上一条改动之后这条弹层（`navigation_bar.dart` 的 `_showDockActions`）**退役**，底部快捷区直接横排在胶囊尾部（清单为空时整槽不出现） |
| 弹出菜单动画（2026-10-10 追加，**同日晚间修订**） | 第一轮把工作台弹层从 M2 `showMenu` 迁到了本仓手搓的 `FluentPopupMenu`（淡入 + 从锚点缩放开）—— 但那不是 FlClash 的动画。**用户指出后原文搬入 `lib/widgets/popup.dart` 为 `common_popup.dart`**：`CommonPopupRoute` + `_RenderPopupMorph`（一块托盘从锚点胶囊沿弧线飞出、长成卡片，内容在里面缩放/淡入/由糊变清，关闭先收缩再飞回）+ `CommonPopupBox`（触发键快照随托盘飞）+ `CommonPopupMenu`（多级原地展开）。相对原文三处偏离：import 路径、`Color.opacity30/10` 两档私有扩展、`CommonPopupMenuItem` 加 `content`（项内嵌输入框）与 `isDivider`（分节线）。已接入：泳道 ⋮（左键 + 右键两条路）、文件管理器工具栏的视图 / 排序 / 更多 / 主页 / 路径操作五个菜单。**面板级菜单与书架、漫画详情的弹层还在 `FluentPopupMenu` 上**，换动画是后续独立一步 |
| 图标语汇（2026-10-10 追加，**同日晚间修订**） | 随 `ActionGroup` 一起搬来的还有 FlClash 的自绘图标词汇表 `AppGlyphs`（纯数据，GPL 同源）。工具条动作面从 Material `Icons` 换成 `GlyphIcon(AppGlyphs.*)`；第一轮曾对「词表没有的语义」留 Material `icon:` 兜底，**用户否决（不许新旧混用）** ⇒ 同风格新增 10 个符号（`arrowForward` / `home` / `folder` / `book` / `tree` / `passThrough` / `fold` / `unfold` / `rowsTwo` / `resize`，见 `app_glyphs.dart` 尾部「本仓新增」一节），动作面上的 Material 兜底清零（泳道栏头三颗键与紧凑轨身份图标、文件管理器导航五颗键与掌形控件、时间线 / 文件树 / 穿透 / 停靠分栏、「打开 / 在文件管理器打开」全部 glyph 化）。**约束写进词表注释：词表已有同语义符号时复用旧符号，不许同一语义长两颗图标** |
| 文案 | 上游 `appLocalizations.showLess/showMore` → slang `t.navigation.*` |
| Dock 的调用点 | 原文用 `Positioned` 浮在整页内容之上、各页自己按 `insetOf` 垫脚；本仓摆进 `Scaffold.bottomNavigationBar` + **`extendBody: true`**，由框架负责「内容铺满 + 给内容留位」（理由见 `navigation_dock.dart` 头 §4：`PersistentTabView.custom` 的底栏插槽会在那一带铺一层不透明底色，而 `extendBody` 把留位交给 `MediaQuery.padding.bottom`，不必逐页改滚动内边距） |
| Dock 的尺寸 | 原文那套是给 FlClash 调的，本仓页面更密、照原尺寸压人 ⇒ 条高 62→52、格子 72→62、图标 24→22、尾部图标 28→24、左右留边 21→14、阴影留白 8→6、lens 涨幅 14→11、尾部间距 8→6。**唯一一处纯观感改动**，要回到原文手感把这几个数改回去即可 |

`windowControls` 参数原样保留（上游侧栏要避开系统标题栏；本仓桌面端用的是自制标题栏，
调用点传 `Size.zero`）。

### 本仓自己加的一层：动作也能进清单（2026-10-09 追加）

用户口径：「自定义只有这 3 个，我没有办法添加任何别的。按理来说，工作台那些也可以
作为自定义添加的」。于是 `NavigationPageId` 改名 **`NavigationEntryId`**（文件跟着改名
`navigation_entries.dart`），并加了**动作**条目 —— `workspace` / `openLocalComic` /
`gpuPresent` / `search`。动作点了**推路由、不换当前视图**（Dock 那颗 lens 留在原地），
页面才切视图。

### 再进一步：一段变两段（2026-10-10 追加）

用户口径：「底下的那些自定义项也可以调整，比如可以隐藏和调整顺序，包括这个『自定义
导航』—— 设置里面有入口，也没有必要一定要保留在下面，也可以加入到这个自定义里面。」

指的是侧栏底部那块：它过去是**写死的固定区**（`NavigationSidebar.actions` 装「没被摆进
清单的动作」，外加一颗硬编码的「自定义导航」按钮），藏不掉、排不了序，手机端更拿不到。
现在改成**两段各自可编辑**（两条路里用户选了「两段各自可编辑」）：

- **主区**（`desktopPageIds` / `mobilePageIds`，沿用原字段名 —— 改名会破云同步载荷）：
  页面与动作都能放，顺序即显示顺序；
- **底部快捷区**（**新增** `desktopActionIds` / `mobileActionIds`）：**只放动作**，
  对应侧栏底部那排按钮 / Dock 尾部那颗按钮弹出来的溢出菜单；
- **「自定义导航」从写死按钮降格成一条普通动作**
  （`NavigationEntryId.customizeNavigation`，默认摆在底部快捷区里）—— 于是它能被隐藏、
  也能被拖到主区。侧栏那颗硬编码按钮随之退役（`onCustomize` 传 `null`）；
- 待添加池里的胶囊按**类型的自然归属**落下（页面 → 主区，动作 → 底部快捷区），
  想换位置用行上的箭头在两段之间搬。

配套的三条规矩：

1. **两段互斥**：`bottomEntries = 底部清单 − 主区已有的`，一个入口只出现在一处；
2. **`null` 与 `[]` 必须分得开**：底部那一段「用户没动过」（`null` ⇒ 出厂四条）与
   「用户全隐藏了」（`[]` ⇒ 底部整块不出现）是两件事。默认给 `[]` 的话用户永远关不掉
   底部那块 —— 那正是这次要修的东西。主区那一段反而不能这样：空清单必须落回出厂
   （一条都没有的导航栏没有意义）；
3. **主区的下限从「两条条目」改成「两条页面」**：旧版手机底栏走 `PersistentTabView`，
   它只渲染页面、构造断言又要求 2..6 条 —— 「一条页面 + 一条动作」会让那一支直接断言
   失败。这是个**在此之前就存在的潜伏 bug**（上一轮放开「动作进清单」时才种下）。

**Dock 尾部那颗按钮不再按平台门禁。** 以前它由 `showsDockActionOverflow`（=「够格走侧栏
但被宽度挤成移动端」）控制，理由是「手机端一直都没有它们」。现在它由**用户那段清单**驱动：
有内容就出现、全隐藏就消失。副作用是**手机端默认也会看到那颗按钮**（默认四条动作在那
一段里）—— 不想要就在「移动端 Dock → 底部快捷区」里隐藏。`showsDockActionOverflow`
连同它的两条判据一起删掉了（一个按平台静默失效的开关，正是用户抱怨的那类东西）。

**旧布局（`NavigationRail`）那一支读的是「全部动作」而不是用户那段清单**：它是「关掉
开关 = 回到改造前那一屏」的退路，而改造前那一屏就是栏底一排动作；更要紧的是主区里
已经有的动作在旧布局里没有位置（`NavigationRail` 只画页面），只读底部段会让那些动作
整个消失。搜索仍然剔掉 —— 那一支本来就在栏底单独挂了它一颗按钮（以前会画两遍，顺手修了）。

这一整层都是**本仓自有代码**（`navigation_entries.dart` 在「本仓自有」那张表里），与许可
无关。持久化契约也没破：五个页面的 `name` 与改造前逐字相同，老客户端与云端旧载荷照常
解析；新增的两段出厂值是 `null`（= 没设置过），老用户读到的就是与改造前一致的底部那块。

## Considered Options

- **撤出重写（= 退出条件 B），现在就做**：许可最干净。否决的理由是成本与收益不成比例 ——
  要重做的正是那几套「写对了才不像玩具」的动效（半隐式欧拉弹簧、按位置与速度决定的
  lens 落点、100ms 惯性投射、橡皮筋过拉），重写等于用另一种写法再赌一次同样的手感。
- **连 `LICENSE` 一起转 GPL-3.0（= 退出条件 A），现在就做**：一次收口。
  否决的理由是**这个决定不该由一次 UI 搬运来触发** —— 它把整个仓库的分发条款交给
  「搬了两个导航组件」这一件事。ADR-0008 §许可搁置原本的措辞（「拨动它是一个独立的、
  需要单独决策的决定」）在这里仍然成立，所以推迟到有人真的需要那份自由度的时候。
- **只搬动效参数，不搬代码**：不成立。这套手感的可搬部分恰恰是**结构和时序**
  （弹簧常量挂在 `SpringDescription.withDurationAndBounce` 上、lens 的静止位置由
  布局算而不是 paint 算），参数离开结构就没有意义。
- **先搬、许可以后再想**：这就是上面的决定 2，但**必须**配可见的记录（本 ADR）
  与一条「不再扩大」的栅栏（决定 4），否则待决状态会静默变成永久状态。

## Consequences

- **ADR-0008 §许可搁置那条规则从「不进仓」变成「进仓待决」**，与本树直接冲突。
  已在 ADR-0008、ADR-0018 §许可搁置、`docs/ROADMAP.md`「明确不做」、
  `CONTEXT.md` §许可边界、`docs/feature-migration-spec.md` B1 就近加了指回本 ADR 的更正注。
  **注意更正注不是「规则已改」**：那几条规则的其余部分（AGPL / 权重不随包 / 上色与 Anime4K
  仍冻结）原样有效，本 ADR 只覆盖「FlClash 导航壳」这一件。
- **合规动作里做了的**：每个搬来的文件头部写明来源项目 + 上游提交 + 相对原文的改动清单。
- **合规动作里没做的**：根目录没有 GPL-3.0 的许可证副本。GPL-3.0 §4 要求分发时随附副本，
  而现在连「哪一部分是 GPL」都只写在文件头。**分发前必须补**（这也是退出条件 A 的一半工作）。
- 自绘图标体系是**整份词汇表**（129 个 glyph）跟着进来的，实际用到十来个。
  许可待决期间这属于「顺手把待决范围喂大」；走 B 路时这一份的替换成本最高。
- 导航的**状态记账改成「身份（id）而非下标」**：两支布局各有一份可增删排序的清单，
  同一页在两边下标不同，记下标会在切布局或改清单时指到别的页上。这是本仓自有的改造，
  与许可无关，但它是这次搬运里唯一改到**既有行为**的地方（`_selectedIndex` → `_currentPageId`）。
- **条目池扩容（页面 + 动作）与「一段变两段」都是本仓自有改造**，见上面两节。
  它们与状态记账同一根线：动作不是视图，所以「当前页」的记账要能把它们排除在外，
  而底部快捷区那一段又只放动作。
- **新增的两个底部字段跟着云同步走**（它们在 `navigationSetting` 里，见
  `sync_service_rossi_part.dart` 的 `shell` 块）：那两段是「用户偏好」，不是
  「这一台机器的事实」。
- **一个潜伏 bug 顺手修了**：上一轮放开「动作进清单」时没有同步收紧主区的下限，于是
  「一条页面 + 一条动作」能存进去，而旧版手机底栏那一支会直接断言失败。下限改成按
  **页面数**算（`kMinNavigationPageCount`）。
- **手机端会多一颗 Dock 尾部按钮**（溢出菜单，默认是那四条动作），是把
  `showsDockActionOverflow` 那套平台门禁换成「清单驱动」的直接后果。取这个方向的理由：
  一个按平台静默失效的开关，比一颗能一键隐藏的按钮更糟 —— 后者正是用户在抱怨的东西。
- **Dock 尺寸收小**是本仓对 GPL 文件唯一一处纯观感改动，已登记在边界表里；
  `navigation_dock.dart` 那一组常量前的注释也写明了「要回原文手感就改这几个数」。
- `navigation_dock.dart` 留了 8 条 `prefer_initializing_formals` 的 info 不修：
  那是原文写法（私有字段 + 具名参数），而 lint 建议的 `this._lift` 在 Dart 里**不可表达**
  （具名参数不能以下划线开头）。不为了消 lint 去改原文 —— 那会让「相对原文改了哪几处」
  这张清单多出一条纯噪声。
