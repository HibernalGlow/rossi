# 工作台交互：激活泳道 / 非激活泳道吃掉第一下点击 / 两套驻留 / 面板栏摆放 / 跨侧插入位 / 持久化边界

这一轮要的是七件事的**行为**，不是版式：

1. **激活泳道**（点一下哪条泳道，交互就交给谁）；
2. **非激活泳道的第一下点击被吃掉**（它只用来激活，不透传给内容）；
3. **悬停驻留**（指针在非激活的 Reader 泳道里停够久 ⇒ 激活它）；
4. **边缘驻留揭示**（Reader 激活且独占时，指针停在视口左右边缘 ⇒ 把相邻泳道揭示出来）；
5. **面板栏的浮动与换边停靠**（`panelBarMode` / `panelBarConstrained`）；
6. **跨侧拖动的精确插入位**（拖到哪一格就落在哪一格，不是永远追加）；
7. **一切持久化**（模式 / 次序 / 宽度 / 折叠 / 激活面板与泳道 / 独占 / 三项延时 /
   面板栏记账 / 面板与卡片记账都活过重启；实时滚动与瞬态揭示**不**活过重启）。

契约以 neoview 的**源码**为准（`Xiranite/docs/neoview-swimlane-ui.md` 与
`src/nodes/neoview/features/panels/ReaderPanelBar.tsx`）。

## 事实

动手前这七件事**一件都还没有**，而且摸出五个具体的坏法 —— 都不是「差点意思」，
而是「按下去没反应」或「画面自己动」这一类用户会直接报上来的东西：

1. **solo 是另一套版式。** 独占时泳道走的是分支 `Expanded`（占满一行），
   于是条带上**没有可滚的余地** —— 第 4 件事（要知道「显出一条泳道靠移动条带」）
   在独占态下结构性地做不出来。改成：solo 只是「那条泳道这一档的宽度 = 可用宽」，
   仍然待在同一条条带里。
2. **`AbsorbPointer` 包住了整列（含栏头）。** 而它自己的注释写着「只包**内容**、
   不包栏头」。于是非激活泳道栏头上的折叠 / 独占按钮**第一下必然哑掉** ——
   用户按了「折叠」而什么都没发生。注释与实现不一致本身就是缺陷。
3. **栏头里的页签条被当成「浮层」摆。** `SwimlaneColumn` 给内联的 `PanelTabStrip`
   传了 `bounds`，而 `PanelBarPositioner` 是 `LayoutBuilder` + `CustomSingleChildLayout`
   （两者都**撑满**给它的约束），于是页签条恒定占满 `maxWidth`（260）。
   默认左泳道 380px：`18+4+4+260+4+40+40 = 370 > 360` ⇒ **出厂默认就溢出 10px**
   （右侧一道黄黑斜纹）。
4. **`canMove: false` 的页签不是落点。** 5 个面板里有 3 个（书架 / 发现 / 工具，
   都是上游整页）属于这一类，于是往它们身上拖会掉回外层那条
   「追加到末尾」的路 —— **第 6 件事要修的那个症状其实大半还在**。
   「不能移动」只表示它自己不能被拖走，不代表别的东西不能插到它前面。
5. **持久化的两个顺序 bug。** `Cubit` 的状态流是 `StreamController.broadcast()`
   ——**异步投递**，不是 `sync: true`。于是
   - 「正在还原」的旗子在 `restore()` 之后立刻撤 ⇒ 监听者拿到通知时旗子已经没了 ⇒
     守卫形同虚设，**每次启动都无端写一次盘**；
   - `_resetLayout` 先 `cubit.resetLayout()` 再 `persistence.reset()` ⇒ 那次重置的
     通知**后**到、重新排一次写盘 ⇒ 刚清掉的快照被默认值写回去。
     （重启结果一样，但那已经不是「作废磁盘」而是「写了一份默认的」。）
6. **轨内换位完全不可达。** 插入位的接受条件写的是 `draggedId != _dragging` ——
   而 `_dragging` 装的**正是**被拖的那个面板 id，于是每个落点都把
   「本条自己正在拖」这一支拒掉；外层 `DragTarget` 又只接跨侧
   （`draggedId == _dragging` 直接 false）。合起来：**拖动同一个页签条里的页签，
   整串手势静默失败** —— 每个落点都不接、松手什么都不发生，界面上看不出任何异常。
   这一条是**变异验证逼出来的**：最初为它写的判据只断言「次序不变」，
   而「什么都没发生」时次序当然不变 —— 假绿。补上「先证明这一拖真的被接住」之后，
   变异体 M26 才变红。（同一个道理让「抑制期间不发」那条驻留判据也是空转的：
   进入抑制时待发项已被清掉，`isDue` 里那个 `_suppressed` 根本没被验到。）

## 决定

1. **激活泳道是一个状态**：`WorkspaceState.activeLaneId`，初始 `null` = 「还没定过」。
   这一档**不吞任何点击** —— 冷启动不该因为一个默认激活项就把用户在左泳道里的
   第一次点击无声吃掉。
2. **吃掉的只有内容**。非激活泳道的**内容**用一个 `AbsorbPointer` 吃掉第一下点击
   （契约：`That click is consumed by the workspace and must not reach Reader area
   bindings, page navigation, video controls, or the radial menu`）；
   **栏头不进吸收范围** —— 栏头的按钮是这条泳道自己的控件，第一下就该生效。
   两条都由外层 `Listener.onPointerDown` 顺带完成激活，互不冲突。
   用 `AbsorbPointer` 而不是在外层拦手势：命中测试整个失败只有一个是非项，
   不依赖任何子控件恰好没注册某个手势识别器。
3. **三套延时互相独立**（契约明确要求，且**都不是**四边栏那套边缘抽屉的延时）：
   悬停聚焦 420ms / 边缘揭示 320ms / 揭示恢复 600ms，都进快照。
   驻留原语 `WorkspaceDwell` 是**纯逻辑**：时间由调用方以毫秒传入、不自己起 `Timer`，
   于是「到点前不发 / 到点发一次 / 离开只取消自己 / 被抑制时不补发」可以在
   `dart run` 里拨快拨慢地断言。widget 侧用 `Stopwatch` 喂真实时钟
   （**不用** `DateTime.now()`：NTP 校正会让 wall clock 往后跳，表现为「悬停聚焦偶尔失灵」），
   并且只在有待发项时才开那个 16ms 的轮询定时器。
4. **悬停聚焦只认 Reader 泳道**（契约原文 `inside an inactive **Reader** lane`）。
   对所有泳道都生效的话，用户把指针挪到面板泳道上方想看一眼就绪状态，
   激活态会自己跑掉 —— 而那正是「谁被激活」的全部意义。
5. **边缘揭示的前提是「Reader 激活且独占」**；它是**瞬态**的：
   不进 cubit、不进快照，指针离开被揭示的泳道后延时收回。
   契约：`Transient edge reveal and live scroll offset are not persisted`，
   而且 `does not change the active lane`。
6. **solo 是 Reader 泳道自己的属性**，生效宽度以「它**同时**是激活泳道」为前提
   （`WorkspaceState.effectiveSoloLaneId`）。把这条判断放在**一个地方**，
   是因为条带宽度分配与滚动落点都要问同一个问题 —— 两处各写一遍必然在某个边界分叉。
7. **条带滚动是受控的**：偏移由几何（`WorkspaceLaneFocusGeometry`）算出，不由用户拖动决定。
   聚焦遵守「**最小**水平移动」——一条已经完整可见的泳道不动（把「居中」当「聚焦」
   是最容易犯的错：用户点一条本来就眼前的泳道，画面却横移一下，那是抖动不是聚焦）；
   比视口宽的泳道对齐**最近的边**。
8. **面板栏记账四项一起改**（`mode` / `dock` / `positionX` / `positionY` / `constrained`）：
   它们是**一次手势的两种结局**，分两次写账会让中间态被渲染出来（先闪一下再跳到新位置）。
   悬浮态下 `dock` **仍然有意义**（「钉回去该钉在哪条边」），所以悬浮 + 任意停靠边是
   合法组合。摆位语义取 neoview 的 `barStyle`：`left: p%` 配合 `translate(-50%,-50%)`
   ⇒ 浮层的**中心**落在容器的 p% 处 —— 这**不等于** `Align`（`Align` 是「子节点左边缘
   从容器左边扫到右边」），两者只在 50% 处重合，在 10% / 90% 处差半个浮层宽。
   位置由渲染者**回报**（`onPositioned`），拖动起点就是它 —— 在布局之外用公式复算，
   等于把「浮层有多大」猜一遍，猜错的表现是**每次开始拖动它都会先跳一下**。
9. **落点不区分页签能不能移动**：每个页签**自己**就是「插到我前面」的一个位置
   （下标 = 它在序列里的位置），插入位由命中测试给出，不去拿光标和每个页签的矩形复算。
   只有页签**之外**的空白区域才是「追加到末尾」。
   **接受条件只能是「这个面板能不能移动」**，不许拿 `_dragging` 去比 ——
   `_dragging` 是「本条正在拖谁」，不是「能不能接」；
   也不能拿它判「是不是跨侧」（跨侧时对面的 `_dragging` 是 `null`，
   每个 `PanelTabStrip` 各有各的 State，本条根本不知道谁在拖）。
   同序列换位要把**自己那一格**扣掉（拖动时自己还在序列里，不扣就偏一格）。
10. **持久化边界写在一处**（`WorkspaceLayoutSnapshot` 的文档里）：
    **进**：模式、泳道顺序、面板宽度 / Reader 宽度比例、折叠、激活面板、四边栏抽屉、
    激活泳道、Reader solo 偏好、三项延时与悬停开关、每条泳道的面板栏记账、
    面板与卡片记账。
    **不进**：实时滚动偏移（由几何在每次激活时算出）、瞬态的揭示、
    当前在读的那一本（`WorkspaceReaderTarget` 带着 cubit 与页面参数，
    「冷启动要不要恢复上次那本」是**阅读历史**的职责 —— 混进来会让
    「重置布局」把书也关掉）。
11. **写盘去抖 420ms，退出前 flush**；写入是**原子的**（先写 `.tmp` 再 `rename`：
    直接覆写时一次崩溃留下的半截 JSON 会让下次启动整套布局回到出厂）。
    **「重置布局」= 状态回默认 + 磁盘那份作废**，两件事的**顺序**是反直觉的那一头：
    作废必须排在 `resetLayout()` 那次 `emit` 的**投递之后**（`scheduleMicrotask`）——
    通知是异步的，它会给去抖器排一次写盘；排在前面的话刚清掉的快照会被默认值写回去。
    同理，「正在还原」的旗子也要等那次投递之后才撤。

## 后续修订（2026-09-21）：悬停聚焦扩到面板泳道、揭示到点即接管

上面「决定」第 4、5 两条把范围按 neoview 契约钉死在 Reader 上。用户实机用下来判为
**缺东西**（「泳道悬停自动聚焦只有 reader 做了」），这一轮改口，两处都留了退回口：

1. **面板泳道吃不吃悬停聚焦 = 独立的一颗开关** `panelHoverFocusEnabled`（默认**开**），
   与 Reader 的 `hoverFocusEnabled` **共用** `hoverFocusDelayMs`。
   - 为什么分两颗而不是一根总闸：契约那句「指针挪到面板泳道上方想看一眼就绪状态，
     激活态会自己跑掉」的顾虑是**真的**，只是这一轮的口径是「要这个手感，不想要的人自己关」。
     合成一颗会让「只想让 Reader 灵一点」这种配置表达不出来。
   - 为什么不再起第四套延时：两处的差别在**吃不吃**，不在**多久**。
   - **折叠成 44px 紧凑轨的泳道一律跳过**（含 Reader 独占时那条切换栏轨）：
     轨已经在当切换把手用，读数时指针扫过去是常事，「停一下就跳焦点」会把它变成陷阱。
2. **边缘揭示到点即接管交互** = `revealFocusesLane`（默认**开**）。关掉才是契约原味的
   `does not change the active lane` + 「离开 600ms 收回 Reader」。
   - 落点是 `activateLane`，于是条带位置由**聚焦**几何给出（最小移动 + 给 Reader
     留一条 `readerPeekWidth` 的缝），而不是揭示几何的「整条推进视口、Reader 该挤多少
     挤多少」。那条缝是回独占的唯一出口，不能省。
   - 「离开未激活的揭示就收回」在开关打开后**自然走不到**（`revealed == activeLaneId`
     被既有守卫挡掉），不是为此新加的判断。
3. **老快照缺这两个键 ⇒ 升级之后默认生效** —— 这是「坏一项退一项」的直接后果。
   快照版本**没升**：这是产品口径变化，不是语义或单位变了。代价记在这儿，别当没看见。
4. **判据跟着反转**：原来那条「指针停在面板泳道上多久都不激活」验的是**契约**，
   现在结论正好相反，于是它被拆成「面板默认吃」「面板那颗关掉只影响面板（Reader 照旧）」
   「紧凑轨不吃」三条；揭示那两条拆成「默认即接管」「接管后不收回」「关掉后仍是瞬态」。
   变异体 **M20/M22 的锚点随之改写**（旧锚点 `if (laneId != LaneId.reader) return;`
   已经不在源码里，留着就是 `PATTERN-NOT-FOUND`），并补 **M44**（删 `isRail` 守卫）、
   **M45/M46**（`revealFocusesLane` 的两个方向各一个）。
   「关掉后是瞬态」那条**同时关掉** Reader 悬停聚焦 —— 否则指针落回 Reader 之后，
   「收回」到底是恢复计时干的还是驻留聚焦干的，判据答不上来（假绿的一种典型形状）。

### 这一轮的判据（2026-09-21，本机实跑）

| 判据 | 结果 |
|---|---|
| `flutter test test/workspace/swimlane_runtime_test.dart` | **11 passed**（上表那 8 条里「只认 Reader」一条被拆成三条，揭示那条拆成三条） |
| `dart run test/workspace/layout_snapshot_check.dart` | **67 checks passed**（含两个新键的往返与「缺键退回开」） |
| `dart run test/network/sync/workspace_sync_codec_check.dart` | **56 checks passed**（两个新键取云端） |
| `python3 test/workspace/mutation_check.py swimlane_runtime` | M20 / M21 / M22 / M23 / **M44** 由判据捕获；**M45 / M46** 单独跑过（各撞对那条断言：`Expected: 'left'` 与 `Expected: 'reader'`），当时整组重跑被**别人的**一次中间提交打断（`lib/page/comic_read/widgets/chrome/app_bar.dart` 编译不过），所以那两行在组报告里显示成「只触发编译错」 |

`dart analyze lib/workspace/ lib/page/setting/global/workspace_layout_setting_page.dart test/workspace/ test/network/sync/` ⇒ 本方的文件无问题。
实机清单：`docs/lane-hover-focus-acceptance.md`。


| 判据 | 结果 |
|---|---|
| `flutter test test/workspace/swimlane_runtime_test.dart` | **8 passed**（激活 / 吃点击 / 栏头不吃 / 悬停驻留 / 只认 Reader / 开关 / 边缘揭示 / 揭示收回） |
| `flutter test test/workspace/workspace_panels_test.dart` | **6 passed**（跨侧精确插入 / 不可移动页签也是落点 / 轨内换位真的能动 / 轨内换位不偏格 / 悬浮摆放 / 拖动跟手） |
| `flutter test test/workspace/layout_persistence_test.dart` | **7 passed**（去抖 / flush / 重置两半 / 冷启动读盘 / 全新安装不写盘 / 改动落盘 / 重置作废磁盘） |
| `flutter test test/workspace/top_chrome_test.dart` | **6 passed**（形态映射穷举 / 触摸屏三条 / 桌面一条 / 揭示形态一条）—— 非桌面常驻顶栏，见 ADR-0012 第 12 条 |
| `flutter test test/workspace/`（整目录） | **32 passed**（含既有的 `route_guard_test.dart` 5 与后来补的 `top_chrome_test.dart` 6） |
| `dart run test/workspace/{lane_focus,dwell,panel_bar,layout_snapshot}_check.dart` | **170 checks passed**（46 / 32 / 39 / 53） |
| `python3 test/workspace/mutation_check.py` | **42/43 捕获 + 1 个已备案的冗余兜底**（全是判据失败，无编译错；EXIT=0） |
| `dart analyze lib/workspace/ test/workspace/` | **No issues found** |

几条**判别方法**上值得留下的东西：

- **「没变」这种断言必须配一条「真的发生过」的断言。** 断言「次序不变」在
  「整个手势被拒、什么都没发生」时照样通过 —— 变异体 M26 就是靠这一点活下来的
  （它只有在落点真的接受时才改变行为）。补法不是把断言写得更细，而是**先证明这一拖
  真的被接住了**（落点接受后会把面板切成当前面板：`state.activePanel['right'] == 拖过去的那个`）。
  同一个坑在纯逻辑那侧也有：`dwell_check` 里「抑制期间不发」原本是空转的
  （进入抑制时待发项已被清掉，`isDue` 里的 `_suppressed` 根本没被读到），
  要**在抑制状态里新排一次驻留**才验得到。
- **驻留必须用真实时钟等，不能靠 `pump(Duration)` 假装。** 被测代码读 `Stopwatch`，
  而 `tester.pump(Duration)` 推的是**测试**时钟 —— 推不动 `Stopwatch`。
  所以判据用 `tester.runAsync` 真等够延时，再 `pump` 一帧让那个 16ms 的轮询定时器醒来。
  两半缺一不可。用假时钟「模拟等够」，验的是判据自己的算术。
- **「吃掉了没有」用状态 + 副作用两条断言**，不是只查 `absorbing` 的值：
  第一下点击之后 ①激活泳道变了、②内容的 `GestureDetector` **一次都没收到**；
  第二下点击之后内容的回调**收到了** —— 吃掉只该发生一次。
- **「揭示发生了没有」看泳道的实际矩形**：左泳道被 Reader 挤出视口时它的中心是**负数**，
  揭示后变成正数。这比「读一个 `_revealedLaneId`」强：后者哪怕条带一动不动也会通过
  （M22 就是这条）。
- **浮层位置用相对位移断言**（`barRect.center - containerRect.topLeft`），不写死屏幕坐标 ——
  容器落在窗口哪儿与这条判据无关。
- **拖动要用真实的 `LongPressDraggable` ＋ 三次动作**：先过它自己的 220ms 长按延时，
  再给一次超过 slop 的位移（`DelayedMultiDragGestureRecognizer` 认的是
  「延时到了 **且** 指针动过」），最后落到目标上再松手。
- **落盘判据必须走一次 `pump`**：它们只依赖 `Timer`（去抖窗口），
  `tester.pump(Duration)` 就能推；但**没有** `pump` 的话定时器不触发，
  判据会「绿得莫名其妙」。
- **本轮的判据自己也过了一遍变异验证**：为这七件事新加的 20 个变异体
  （M17–M36，四组：泳道运行时 / 面板栏 / 持久化 / 驻留，覆盖到「吸收范围、
  栏头约束、悬停范围、揭示真的移了条带、揭示会收回、落点的接受条件、
  悬浮的中心语义、拖动跟手、旗子与作废的顺序、去抖窗口、flush 判空、
  驻留的清项 / 取消范围 / 抑制 / 换目标重排」）**全部被捕获**。
  （后来补的常驻顶栏又加了 7 个，M37–M43，见 ADR-0012 第 12 条；
  连起来共 **42/43 捕获 + 1 个已备案的冗余兜底**。）
  其中 **M26 / M35 是第一轮活下来的两个** —— 它们逼出了上面那条
  「『没变』必须配『真的发生过』」的修法，也是这一轮唯一两处**真 bug**
  （轨内换位不可达、抑制分支从未被读到）。

### 为判据加的两个口子（明确记账）

`flutter_tester` 起不了真实内容 —— `BreezeWorkspacePage` 建到
`LanePanelHost` 就会去构造上游的 `BookshelfPage` / `ComicReadPage`，
那需要 ObjectBox、图源注册表、应用数据目录。于是加了两个**转手**参数：

- `SwimlaneWorkspace.debugLaneContentBuilder`（只换内容，泳道结构一字未动）；
- `BreezeWorkspacePage.debugLaneContentBuilder`（把上面那个转手给泳道，
  好让「启动读盘 / 变化落盘 / 重置作废」这三条接线本身可断言）。

这与 `BreezeWorkspacePage.store` 是同一条先例（那个口子就是为了让「重启回来的是不是
同一套布局」能在测试里验完）。**应用路径永不传它们**，传与不传的差别只有「内容由谁构造」。

## 残留（明确记账）

- **手感只能在真机上看。** 这一轮把「事件 → 状态 → 几何」全钉住了，但「顺手不顺手」
  （驻留延时的默认值、揭示的动画时长、拖动时的视觉反馈）本机验不了 ——
  本机**没有 Xcode**，`flutter test … -d macos` 报 `Xcode not installed`。
  这与 ADR-0012 结尾那条「只能在真机上看」并不冲突：那里说的是**手感**，
  这一轮补的是它前面那些**框架层**行为。
- **上一轮文档里这句话要更正**：ADR-0012 结尾写着「仍然没验证的：拖拽分栏、Solo、
  跨侧拖动的插入位、悬停 dwell」。前三条里，「跨侧拖动的插入位」与「悬停 dwell」
  现在**有**判据了（`flutter_tester` 上实测通过，见上表）；
  拖拽分栏与 Solo 的**几何**由纯 Dart 判据钉住（`strip_metrics_check` / `lane_focus_check`），
  **手势本身**仍只有真机可验。
- **窄栏头还会挤。** 右泳道拖到自己的下限（280px）时，栏头那一行
  （把手 18 + 标题 + 宽度徽标 ~38 + 页签条 + 独占 40 + 折叠 40）会差几个像素 ——
  徽标是那一行里唯一不能收缩的东西。**本轮没改**：它只在极窄档出现（默认档 380/360 不缺），
  而且改法（徽标改缩放 / 标题与徽标换优先级）属于版式选择，不该顺手定。
  留待：给徽标加 `Flexible` + `FittedBox(scaleDown)`，或按可用宽在「标题 / 徽标」之间取舍。
- **面板栏的换边停靠**只在**模型**与**摆放**两层验到了（`panelBarDockCandidate` 的阈值判定
  在 `panel_bar_check`，摆放在 `workspace_panels_test`）；**真的按住把手拖到泳道边上**
  这一串手势没验（把手是 `GestureDetector` 的 pan，属于手感）。
- ~~**移动端仍然没有常驻出口**（照旧，见 ADR-0012）：顶栏悬停揭示，触摸屏唤不出来。
  桌面端不受影响。~~ **已补（同日，见 ADR-0012 第 12 条）**：非桌面平台改为**常驻**顶栏
  （占一行真实高度、底色铺到状态栏下面、内容从它下面开始），桌面端保持揭示。
  判据 `test/workspace/top_chrome_test.dart`（6 条）。
- **`WorkspaceDwell.setSuppressed` 目前没有被 widget 调用**：生产路径用的是
  「按下就把三个驻留全部 `cancel()` + 用 `_pointerDown` 挡住新驻留」，
  抑制这件事是在**交互发生的地方**落实的，不是靠这个开关。
  契约里那几项（指针捕获 / 正在拖动 / 输入法组合 / 弹层 / 浮动菜单）前两项由此覆盖，
  弹层与组合则由「弹层会把指针事件从条带上拿走」间接覆盖。
  这个开关作为契约的原语留着、由纯 Dart 判据钉住；**将来谁要在别处用它，
  得先想清楚「抑制是闸不是清」**：进入抑制会清掉待发项，但抑制期间**新排**的驻留
  会在解除后立刻发（判据把这条也钉住了，免得不小心当成 bug「修」掉）。
- **Windows / Linux 侧未实测**：这一轮全是 Dart 层的行为，与平台无关；
  但真机手感同 macOS 一样没验。
