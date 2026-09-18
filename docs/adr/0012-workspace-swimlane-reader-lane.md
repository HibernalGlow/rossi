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
     能从 widget 里抽出来的断言都抽出来，`dart run test/workspace/board_layout_check.dart` 直接跑
     —— 快、不依赖 Flutter、不用起测试宿主。
     （当时写的理由是「本机 `flutter test` 起不来」，那个根因判断后来被推翻，见文末「验证状态」；
     但抽离本身作为快判据仍然成立，故保留。）
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


11. **面板里点开的东西开在面板里（同日第四轮）—— 守卫从「只管阅读」泛化成「管所有推入」。**

    「在工作台里点设置」原先会把**整个工作台盖掉**：上游推下一个页面的写法是
    `context.pushRoute(...)`，它落在**根导航栈**上。neoview 的语义不是这样 ——
    泳道里的东西开在**这条泳道里**。

    做法（仍然零侵入，`router.dart` 的 guards 一行不变）：

    - **落点记账**（`router/workspace_lane_dispatch.dart`，**纯 Dart**）：
      两条输入一条输出 ——「**活着的主机**」（每条泳道当前可见的那个面板登记，
      同泳道后者顶前者；这条不变量是结构性的，不靠调用方自觉：`IndexedStack`
      会把访问过的面板都留在树里）∩「**最后一次指针交互**」→ `resolveTarget()`。
      **落点不明时返回 `null`**，调用方必须原样放行全屏推入：把页面开进一个用户
      看不见的地方（现象是「点了没反应」）**比全屏更糟**。
    - **桥**（`router/workspace_navigation_bridge.dart`）两条通道：阅读器通道保持原语义
      （`ComicReadRoute` 一律进中央泳道，**不跟点击位置走**）；面板通道把其余推入
      交给发起交互那块内容的局部 `Navigator`。
    - **容器**（`widgets/containers/embedded_upstream_page.dart`）：局部 `Navigator`
      （页面收在卡片里，返回箭头弹的是这一页而非整个工作台）+ `Listener` 上报指针按下
      （上游的点击点太散 —— `ListTile.onTap` / 图标按钮 / 长按菜单 ——
      只有「按下」是它们共同的、绕不过的一步）+ `isVisible` 才登记自己
      （没有这条，留在树里的隐藏面板就能抢走推入）。
    - **泛化后的改名**：`WorkspaceReaderBridge` / `WorkspaceReaderGuard` →
      `WorkspaceNavigationBridge` / `WorkspaceRouteGuard`（旧名只剩「阅读器」一层含义，
      已经管不住实际职责了）。
    - **已知残留**：只有 `pushRoute` 被守卫接管，`context.router.pop()` / `maybePop()`
      仍然作用在根栈上。卡片自己的「返回列表」若走那两个 API，会把整个工作台弹掉。
      阅读器那侧的退出路径走的是「关闭当前漫画」，不受影响。

    **判据**：`test/workspace/lane_dispatch_check.dart`（31 条，纯 Dart，验落点记账）+
    `test/workspace/route_guard_test.dart`（5 条 widget test，验页面的矩形与卡片严丝合缝、
    返回箭头出现在卡片里、没有工作台时照旧全屏）。两者都由
    `test/workspace/mutation_check.py` 做过**变异验证**：11 个变异体全部被捕获
    （且区分「判据失败」与「编译错」，后者不算证据）。


12. **顶栏按「平台有没有指针」分流：桌面悬停揭示，触摸屏常驻（同日第五轮）。**

    第 10 条把顶栏改成悬停揭示，代价写在当时那条残留里：**触摸屏上没有出口**。
    现在把它补掉 —— 这一轮改的就是那一条。

    - **事实**：揭示靠 `MouseRegion`，而触摸屏**没有 hover**，那两个回调永远不触发。
      工作台又是 `Navigator.push` 上来的整页、**没有系统返回按钮**，
      `Esc` 更是只在键盘上存在。三条加起来 = 用户在 Android / iOS 上
      **进得来出不去**（上一轮文档里记的是「没有常驻出口」，实际症状比这更硬）。
    - **决定：不是把顶栏统一改成常驻，而是按平台分流。** 第 10 条的理由
      （每条泳道已经自带栏头 + 上面还叠着系统标题栏 ⇒ 再压一条常驻顶栏就是
      第二层顶栏）在桌面端**依然成立**，一个字不改。
    - **判据是「这个平台有没有鼠标指针」，不是「名字里带不带 desk」**
      （`WorkspaceTopChromeMode.forTargetPlatform`）：带触摸屏的 Windows 笔记本
      仍然有指针 ⇒ 揭示；手机浏览器（web 也走 `defaultTargetPlatform`，
      它按宿主系统给答案）⇒ 常驻。用 `defaultTargetPlatform` 而不是 `dart:io` 的
      `Platform` 还让判据能用 `TargetPlatformVariant` 把两种形态各跑一遍 ——
      `Platform` 在测试里改不动。
    - **常驻形态三条硬要求**（三条都不是「好看」，是坏掉就看得见）：
      ① **顶栏进正常流、内容从它下面开始**，不是叠上去 —— 常驻却把内容压在下面的话，
      用户永远看不见内容的第一行；② **顶栏底色要铺到状态栏下面**：状态栏内边距加在
      **容器自己**身上，而不是把 `SafeArea` 套在整列外面 —— 后者会让状态栏那一条露出
      `Scaffold` 的底色，与顶栏之间出现一道色差；③ **总高精确等于那一行 + 状态栏**
      （`BoxDecoration` 的边框会占掉内容盒的 1px —— `Container` 把边框宽度算进自己的
      内边距，所以只写 `padding` + `decoration` 的话总高会变成 47；界面上看不出来，
      只有判据抓得住）。
    - **拆成两个 widget**：`WorkspaceTopChrome` = **本体**（两种形态共用同一份内容，
      只有「有没有投影 / 让不让状态栏 / 定不定高」三处差异），
      `WorkspaceTopChromeReveal` = **揭示形态的容器**（触发带 + 两段 hover + 淡入，
      返回 `Positioned`，必须放在 `Stack` 里）。原来那个 widget 既是本体又是浮层，
      两种形态塞在一起会让「谁负责摆它」变得含糊。
    - **判据**：`test/workspace/top_chrome_test.dart`（6 条：形态映射穷举 +
      触摸屏三条 + 桌面一条 + 揭示形态一条）。判别用**矩形**而不是 `findsOneWidget`
      —— 两种形态里顶栏**都**在树上，区别只在矩形。另有一条成对断言：
      揭示形态「召唤前点不着、召唤后点得着」，触摸屏「按一下路由真的被弹掉」。
    - **残留（明确记账）**：
      - **点按目标 40dp**：那一行高 46，里面的 `IconButton` 带 `VisualDensity.compact`
        （40×40）才放得下 —— 比 Material 对触摸屏建议的 48dp 小一圈。
        要改就得**连那一行的高度一起改**（56 才够），那是版式选择，不该顺手定。
      - **三档触摸只实测了 android 一个代表**：`iOS` / `fuchsia` 与桌面三档走的是
        同一段代码、同一份布局，**映射**由纯逻辑判据穷举（第 0 节跑
        `TargetPlatform.values` 全部六档）。跑六遍 widget 判据买不到新信息。
      - 真机手感（状态栏实测高度、系统返回手势与本顶栏的配合）仍然没验 —— 本机无 Xcode。


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
  - ~~**移动端（最低适配）现在没有常驻出口**：顶栏是 hover 揭示的，触摸屏上唤不出来，
    `Esc` 也用不上。桌面端不受影响（macOS / Windows / Linux 的 `MediaQuery.padding` 为 0，
    撤销 `appBar` 后内容直接顶到窗口顶端）。若日后要管移动端，给非桌面平台保留常驻顶栏即可。~~
    **已补（同日第五轮，见第 12 条）**：非桌面平台改为**常驻**顶栏（占一行真实高度、
    底色铺到状态栏下面），桌面端保持揭示。仍**没在真机上验过** ——
    本机无 Xcode，验到的是「平台 → 形态 → 布局」这三步。
    点按目标的残留见第 12 条末尾。
- **验证状态（2026-09-18 更正）**：`dart analyze lib/ test/ integration_test/` 全量 0 issue。
  本文第 9 / 10 条原先写着「本机 `flutter test` 起不来（`flutter_tester` 的 WebSocket 升级被拦）」，
  **根因判断是错的**：真正的原因是本机设了沙箱代理
  （`HTTP_PROXY=http://127.0.0.1:55577`），它劫持了 `flutter_tester` 的 WebSocket 握手。
  **解掉代理变量后 `flutter test` 完全可用**：

  ```bash
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test <path>
  ```

  所以「把断言抽成纯 Dart 脚本」不再是**唯一**手段（它作为「快、不依赖 Flutter」的判据仍然有价值，
  第 9 条的抽离照旧保留）。导航这类**框架层**行为现在有真跑的判据：
  `test/workspace/route_guard_test.dart` 在 `flutter_tester` 上实测通过
  （布局与导航由 `RenderObject` / `Navigator` 决定，与引擎的解码器无关，
  这与「判解码能力只能用真机引擎」不矛盾）。
  **仍然没验证的**：拖拽分栏、Solo、跨侧拖动的插入位、悬停 dwell ——
  这些是交互手感，只能在真机上看；以及本文所有「未做的部分」照旧未做。
