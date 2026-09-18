# 工作台是泳道宿主：中央泳道就是 Reader，上游页面零侵入

## Context

2026-09-18 落地了一版「NeoView 式工作台」（`lib/workspace/`）：泳道 / 四边栏两种呈现、
拖拽分栏、Solo 独占、44dp 折叠轨、模式切换。它的第一版把三条泳道填成了
**书架页 / 发现页 / 辅助页**，中央泳道用一块假的「双页画板」占位。

对照 `Xiranite/docs/neoview-swimlane-ui.md`（neoview 的 swimlane 契约），
这版与契约有三处实证的偏差：

| 契约原文 | 第一版的做法 | 偏差 |
|---|---|---|
| `World: [ left panels ][ Reader ][ right panels ]` | 中央是发现页 / 假画板 | **中央泳道不是 Reader** |
| `Reader solo is a property of the Reader lane` | Solo 是任意泳道的通用属性 | Solo 没有「阅读器」这个语义中心 |
| `Panel lane widths are stored as absolute CSS pixels and are not clamped to the current window width. Reader is the exception: its ordinary width is stored as a viewport ratio` | 三条泳道都用绝对像素 | 改窗口大小会把阅读器撑爆视口 |
| `The workspace mode switch ... fused into the original Reader top chrome` | 挂在工作台自己的 AppBar 上 | 模式切换不随 Reader 走 |

更关键的是**中央泳道放什么**这件事在 Rossi 上有个额外约束（ADR-0002）：
上游 `main` 要能持续合并进来，所以**不许改动上游页面**。
而「点开一本漫画」的写法在上游是 `context.pushRoute(ComicReadRoute(...))`，
分散在书架、发现、历史、搜索等十几处。要让这些点击**读在中央泳道**，
既不能改调用点，也不能改阅读器页面本身。

## Decision

1. **三条泳道的身份定死**：
   - `left` 面板泳道 = 上游原版 `BookshelfPage`（`EmbeddedBookshelfLane` 只是宿主）；
   - `reader` 泳道 = **上游原版 `ComicReadPage`**（`WorkspaceReaderHost`），空闲时为画板空态；
   - `right` 面板泳道 = 图标轨 + 面板：上游 `DiscoverPage` / 「图源与本地」真实卡片 / 上游 `MorePage`，
     每个面板**按需构建、构建后保活**，各泳道各自记自己的激活面板。

   > 同日第二轮修正：`left` / `right` **都是面板泳道**，各自的**面板页签条长在泳道顶栏里**
   > （neoview 把 `ReaderPanelBar` portal 进 title slot，`dock: "top"`）；上游 `BookshelfPage`
   > 只是左泳道里的**一个面板**，不是整条泳道。见下文「面板 / 卡片分层」。

2. **「读在中央泳道」用根路由守卫改派，不改任何调用点。**
   `WorkspaceReaderBridge`（单例）由工作台挂载时登记回调、卸载时注销；
   `WorkspaceReaderGuard` 挂在 `AppRouter.guards` 上，只在**工作台在场**且推入的确是
   `ComicReadRoute` 时，把目标交给泳道并 `resolver.next(false)` 中止原本的全屏推入。
   **工作台不在场 → 一行都不生效**，全屏阅读器行为完全不变。

3. **上游零侵入的边界写清楚**：本次唯一改到的上游文件是 `lib/config/router/router.dart`
   的 `guards` 一行。上游页面（`bookshelf_page.dart` / `discover_page.dart` / `more.dart` /
   `comic_read/**`）**没有任何一处因为泳道而改动**。

4. **阅读器住进泳道的三件事全在泳道这一侧**（`WorkspaceReaderHost`）：
   - `MediaQuery.size` 改写成**泳道尺寸** —— 阅读器的版式（页宽、双页分割、底部工具条的宽窄分支）
     全部读 `MediaQuery.size`，给它一个正确的视口，而不是把它压缩；
   - 给一条**局部 `Navigator`** —— 否则顶栏自动返回按钮读的是工作台那条路由
     （`ModalRoute.canPop == true`），点一下退出的是整个工作台，底部的阅读设置面板也会铺满窗口；
   - widget key = `WorkspaceReaderTarget.identityKey`（`from + comicId + order + chapterId + …`），
     同书同章复用状态、换书换章整体重建。

5. **几何按泳道性质分开记**（neoview 契约）：
   - 面板泳道 = 绝对像素，**不按窗口宽夹取**；
   - 阅读器泳道 = **视口比例**（拖动改的是比例），落在 `[400, 2000]`；
   - 有富余宽度时**富余全给阅读器**；不够时**整条带横向滚动**（一条平面、泳道之间不重叠）；
   - 分隔条拖拽把宽度从**右侧泳道**挪给**左侧泳道**，且只应用**实际让得出的距离**
     （任一侧先撞到 min/max 时，分隔条不会漂离光标）。

6. **模式切换属于 Reader 的 chrome**：泳道模式下它挂在**阅读器泳道栏头**；
   工作台级别的动作（退出 / 重置布局 / 切换模式 / 当前书名 / 关闭漫画）
   收在**悬停揭示的工作台顶栏**里（见第 10 条）。

7. **四边栏模式的抽屉换成真实卡片**：收藏 / 历史 / 下载 / 图源 / 本地，
   数据来自 ObjectBox 与插件注册表；原先的占位卡片（`*_placeholder.dart`）与本轮被取代的
   假画板（`workspace_reader_lane.dart`、`reader_canvas_placeholder.dart`）一并删除。

8. **顺带修掉一处已知缺陷**：`favorite_shelf_card.dart` / `history_shelf_card.dart` 原先无条件
   推 `ComicInfoRoute`，本地漫画（`source == 'local'`、`comicId` 是文件路径）会被当成
   「插件 id = local」去问 qjs 运行时，界面只剩「加载失败」。
   统一改成 `open_comic_item.dart`：本地直接推 `ComicReadRoute`（由守卫决定读在哪），
   插件走详情页 —— 与 `ComicEntryWidget` / `ComicSimplifyEntry` 的两条分支保持一致。

9. **面板 / 卡片分层（同日第二轮）** —— 把「泳道里装什么」拆成三张注册表，
   与 neoview 的 `ReaderPanelDefinition` / `ReaderCardDefinition` / `ReaderPanelBar` 同构：

   - **泳道（lane）**：横向条带上的一条，`left` / `reader` / `right`；
   - **面板（panel）**：泳道内的一个功能位，**由停在泳道顶栏的页签条切换**；
   - **卡片（card）**：面板内的一块内容，成员关系**泳道与四边栏共享**。

   三张注册表（各只有一份清单，别处不得再抄一遍）：

   | 文件 | 管什么 |
   |---|---|
   | `registry/workspace_ids.dart` | 面板 id 常量（两张注册表互不 import，也不会有环） |
   | `registry/workspace_panel_registry.dart` | 面板定义：标题 / 图标 / 归属侧 / 默认次序 / 是否独占 / 可否搬移 / 可否收起 / 是否由卡片填充 |
   | `registry/workspace_card_registry.dart` | 卡片定义：默认面板 / 默认次序 / 默认展开 / 可否收起 / builder |

   - **面板切换工具栏在顶栏**（`widgets/panels/panel_tab_strip.dart`）：
     左 / 右两条泳道各挂一条，用的是**同一个控件**。三个手势各占一个入口 ——
     左键切面板、**按住拖动**在轨内重排（拖到另一条泳道的页签条上则把面板搬过去，
     即 neoview 的 `moveReaderPanel`）、右键收起（页签条右侧的「已收起」入口恢复）。
     页签条自身可横向滚动，泳道拖窄时不溢出、不换行。
   - **布局记账是真的数据**（`model/workspace_board_layout.dart`，**纯 Dart**）：
     `panels{visible, order, side}` + `cards{panelId, visible, order, expanded}`，
     **只存被改动过的项**，没记录的项回落到注册表里的默认值 ——
     于是「加一个新面板 / 新卡片」不需要写迁移，也不会被旧记录挡住。
     「重置布局」= 把记账清空。
   - **判据放在纯 Dart 里跑**（`test/workspace/board_layout_check.dart`，30 条）：
     本机 `flutter test` 起不来，所以能从 widget 里抽出来的断言都抽出来，
     `dart run test/workspace/board_layout_check.dart` 直接跑。
   - **面板的两种内容来源（本项目对 neoview 的有意扩展）**：
     `acceptsCards` 为真的面板由卡片注册表填充；为假的面板装**一整张上游原版页面**
     （`page` builder）。于是「上游 0 侵入 + 功能 100% 保留」与
     「卡片可增删重排」两件事同时成立 —— 上游页面**不被拆成卡片重写一遍**。

10. **工作台没有常驻顶栏：`Scaffold.appBar` 撤掉，顶栏改为悬停揭示（同日第三轮）。**

    泳道模式下每条泳道已经自带栏头（neoview：`lane header owns collapse, reorder, focus, width`），
    工作台再压一条自己的 `AppBar` 就是**第二层顶栏** —— 窗口最上面还叠着 macOS 原生标题栏，
    连着三条横杠白占一行高度。所以本页改成**内容从顶上铺满**：

    - **`WorkspaceTopChrome`（`widgets/chrome/workspace_top_chrome.dart`）**：
      高度 46（与泳道栏头同高，揭示时正好接管那一行），默认 `opacity: 0` +
      `IgnorePointer`，**不占高度也不吃鼠标**。
    - **揭示靠两段 hover**：触发带 = 窗口最顶端 10px，**垫在顶栏下层** ——
      顶栏不可见时鼠标穿得到它，可见时被顶栏自己接住（顶栏也是 `MouseRegion`），
      于是不会出现「从触发带滑到顶栏上就收起来」的抖动。
      触发带**必须矮**：顶栏一出现就盖住泳道栏头，触发带太高会让操作栏头时反复闪现。
    - **顶栏里放的是工作台级别的事**：退出 / 当前书名 / 关闭当前漫画 / 切换模式 / 重置布局。
    - **`Esc` = 退出工作台**（`CallbackShortcuts` + `Focus(autofocus)`）：
      工作台是 `Navigator.push` 上来的整页，**没有系统返回按钮**，
      顶栏一撤它就是唯一出口。只在 `ModalRoute.isCurrent` 时才弹，
      详情页之类压在上面时不把用户弹走。
    - **四边栏模式里那条常驻的顶部浮动胶囊一并删除**：它（模式切换 / 当前书名 / 关闭漫画）
      与新顶栏**逐项重复**，留着就是沉浸模式下凭空多一条 chrome。


## Considered Options
- **嵌套 `AutoRouter` / 让每条泳道各有一条导航栈**：更"正统"，但要让上游页面的
  `pushRoute` 落到嵌套路由器上，就得给面板泳道声明一整份路由表；上游日后新增一处跳转，
  这里就会在运行时抛「route not found」。**与 ADR-0002 的合并目标直接冲突。**
- **改上游调用点**（把十几处 `pushRoute(ComicReadRoute)` 逐个改成分支）：与「零侵入」直接矛盾，
  且每合并一次上游都要重来一遍。
- **中央泳道只放工作台自己打开的漫画**（继续阅读 / 本地漫画），上游点击仍然全屏：
  最省事，但「中央泳道是 Reader」就只剩一半 —— 书架里点一本仍然跳出工作台。
- **根路由守卫改派（本 ADR）**：侵入面是一行 `guards`，语义是「这一本读在哪儿由宿主决定」，
  工作台不在场时完全不生效。

## Consequences

- **合并上游的成本**：`router.dart` 的 guards 一行是唯一的冲突面。
  上游若给 `ComicReadRoute` 改名 / 改参数类名，守卫会退化为"不接管"（放行全屏），
  是**安静降级**而不是崩：判据是 `resolver.routeName == ComicReadRoute.name` 且
  `args is ComicReadRouteArgs`。
- **阅读器跑在泳道里，但它的系统级行为没变**：`ReaderOrientationController` 仍按全局阅读设置
  切横屏（`landscapeReader`），`ReaderLifecycleController` 仍管全屏。泳道与全屏阅读在这个层面
  **不是两套行为**——这是有意的（同一份阅读体验），但**没在真机上验证过**。
- **未做的部分（明确记账）**：
  - neoview 的**激活泳道（active lane）**概念：点击阅读器泳道先"激活并恢复 Solo"、
    非激活泳道的第一次点击被工作区吃掉、悬停聚焦 dwell、边缘 dwell 揭示相邻泳道 —— 都没有实现；
  - **面板操作栏（`ReaderPanelBar`）其余的形态**：面板栏的**浮动 / 停靠到别的边**
    （`panelBarMode: floating`、拖到 left/right/top/bottom）、「限制在本泳道」开关
    （`panelBarConstrained`）、栏高与栏位持久化 —— 都只做了**停靠在顶栏**这一种；
  - **面板/卡片跨侧拖动的插入位**：拖到另一条泳道时固定插到末尾（拖到页签条上即换泳道），
    还没有「落在某一格之间」的精确落点；
  - **持久化**：泳道顺序、宽度、折叠状态、激活面板、面板次序与可见性、
    卡片次序与可见性/展开态、Solo 都只在内存里，重启即回默认；
  - 面板泳道宽于视口时的「聚焦到最近可用边缘」：只能靠手动横向滚动；
  - 阅读器泳道折叠成 44dp 轨时，栏头里的控件（含模式切换）随之不可达，
    此时只能切到四边栏模式、再靠悬停揭示的工作台顶栏切回来；
  - **移动端（最低适配）现在没有常驻出口**：顶栏是 hover 揭示的，触摸屏上唤不出来，
    `Esc` 也用不上。桌面端不受影响（macOS / Windows / Linux 的 `MediaQuery.padding` 为 0，
    撤销 `appBar` 后内容直接顶到窗口顶端）。若日后要管移动端，给非桌面平台保留常驻顶栏即可。
- **验证状态**：`dart analyze lib/` 全量 0 error / 0 warning。
  **没有跑真机**——本机 `flutter test` 起不来（`flutter_tester` 的 WebSocket 升级被拦），
  且泳道的行为（拖拽、Solo、改派）本来就只能在真机上看。所以上面每一条"成立"都是**代码级**的，
  不是实测的。
