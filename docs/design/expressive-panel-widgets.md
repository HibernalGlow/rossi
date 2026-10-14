# 信息 / 控制 / 发现面板的 Expressive 小组件

洞察面板先按 MD3 Expressive 重做过一轮（非对称圆角、cookie 形图标座、弹簧驱动的
数值与进度、控件收进标题栏）。本文件记录那套语言里**与图表无关**的部分被抽成通用件、
并铺到另外三块面板上的口径，以及「发现」面板改为卡片模式这一处结构决定。

## 通用件落在哪

`lib/workspace/widgets/cards/expressive_widgets.dart`。信息卡继续从
`info_card_kit.dart` 拿东西（该文件 `export` 本文件），所以一张卡只需要一个 import。

- `ExpressiveTile`：非对称圆角 + 容器色分层 + 可选点击。内容里所有「格子」都是它。
  分层靠 `ColorScheme` 的 container 对，不描边不投影；选中才出现主色边框。
- `ExpressiveStatTile`：值得被读出来的数。与洞察的 `InsightMetric` 同一组圆角数
  （22 / 22 / 6 / 22）与同一档字号，两类卡并排时看不出一套还是两套。
- `ExpressiveFactTile` / `InfoRow`：一行键值。`InfoRow` 留在 `InfoFacts` 这块下沉底板里
  时不再自带背景（底板已提供分层），单独用才画格子。
- `ExpressiveGauge`：走 `M3EProgressIndicator.linear`，值由 `InsightSpringValue` 驱动，
  与洞察共用同一根弹簧而不是再写一条。
- `ExpressiveStatusPill`：一颗点或一个图标 + 一个词，颜色承载「就绪 / 进行中 / 失败」。
- `ExpressiveTileGrid`：按宽度决定列数。用 `SizedBox(width:)` 而不是 `Flexible` ——
  槽位尺寸由跨度决定，内容不能反过来把格子撑大（洞察那轮踩过的坑）。
- `ExpressiveSection`：卡内分节的小标题，替掉控制面板里手写的「图标 + 12px 主色文本」。

三条纪律：量不到的数一律画 `—`，不 fallback 成 0；每个件在 `LayoutBuilder` 里自选档，
窄槽位与全宽槽位都不溢出；`eInkInstantRoutes` 与「减少动态效果」下弹簧直接落位。

## 三块面板各自改了什么

- **信息**：五张卡（书籍 / 图像 / 存储 / 时间 / 预加载）外壳转 `expressive: true`，
  卡顶各加一排大数字格，次要事实收进 `InfoFacts`。时间卡的大数字改成「多久以前」
  （今天看时刻、今年看月日、再远看年份），完整时间戳降级为 caption ——
  绝对时间戳塞进大数字格会撑爆宽度，而读的人要的是远近。
  空态从一行灰字换成图标座 + 一句说明，并且**摆出这张卡自己要填的那几格**
  （`InfoEmpty.fields`，值全是 `—`）。这一条是针对截图右侧那个状态做的：
  四张空卡各自是一个大空盒里飘一行灰字，读起来像「这块面板没做完」而不是
  「还没开书」。字段名是卡片自己写死的静态项，不是编出来的数据 ——
  于是空卡与满卡是同一个形状，用户提前知道开书后这里会有哪几项、占多大地方。
- **控制**：切换提示 / AI 超分辨率 / 翻译 / 画面调节四张卡转 Expressive 外壳，
  切换提示的内部分节改用 `ExpressiveSection`。画面调节另加一排只读状态胶囊
  （滤镜 / 动画 / 墨水屏），读的是与正文 `ImageTuningSection` **同一份**
  `GlobalSettingCubit.state.readSetting`，不另开写入路径。
  超分与翻译**不加**这种状态条：它们的当前档要经 `RealSrBookScope.enabledFor()`
  这条异步解析（书级覆盖全局），在卡顶再解析一遍就是第二套平行实现，
  与 AGENTS §13 的口径冲突。
- **发现**：见下节。新增两张插件小组件 —— 插件运行状态、图源快捷入口。
  快捷入口只列 `isActive` 的插件：未启用的点了必然报错，画出来是骗人。
  状态卡把宿主自己报的 `lastLoadError` 原样带出来，不翻译成别的词。

## 面板标题行

「发现」转卡片模式后第一次露出 `PanelHeaderBar`（原先是 `exclusive`，没有这行），
而它还是改造前的样子：32×32 的 11 圆角方块图标座、两处 `BorderRadius.circular(14/16)`、
三处写死的 `Duration(milliseconds: 280)`。于是卡片是 Expressive 的、
卡片的标题行不是。一并收进同一套语言：

- 面板图标座改用 `ExpressiveIconBadge`（cookie 形），编辑态与非编辑态之间用
  `AnimatedSwitcher` 过渡，而不是硬切边长与圆角。
- 两颗按钮（图标档与带文字档）都走 `StadiumBorder`；「恢复被收起的卡片」那颗
  的圆角从 14 提到 18，与卡内那批状态胶囊同形。
- 时长与曲线改读 `ExpressiveMotion.spatialDuration` / `spatialCurve`，
  并在 `eInkInstantRoutes` 下归零 —— 与卡片外壳同一口径。

`iconOnly = width < 360`、`showHiddenCount = width >= 420` 两条断点与
`自定义布局` / `完成布局` 的文案、tooltip 全部不变：`information_widgets_test`
与 `lane_panel_layout_test` 是按这三条找按钮的，改形状不能改寻址。

## 发现面板改为卡片模式

原先是 `acceptsCards: false` + `exclusive: true` + `page:`，整页复用上游 `DiscoverPage`。
`LanePanelHost` 的两种内容模式互斥：`acceptsCards: false` 只画整页、不画卡片。
要「挂自己的小组件」就得改成卡片模式，而改成卡片模式就会丢掉整页。

决定：**把整页降级成一张不可收起的全宽卡**（`discover_board`，`canHide: false`，
`scrollContent: false`）。于是「上游 0 侵入 + 功能 100% 保留」与「这块面板可以挂卡片」
同时成立，并且拿到与其他卡片面板一样的 `自定义布局` 标题行。
`scrollContent` 关掉是因为 `DiscoverPage` 自己有滚动视图，再套一层会出现两个滚动条。
整页卡 `canHide: false`，所以这张面板永远至少有一张卡，不会被 `panelsForSide`
的空面板规则摘掉页签。

局部导航栈不用另接：卡片分支本来就整块包在 `EmbeddedUpstreamPage` 里，
从卡里点开的东西仍然开在这块面板里。

## 验证结果

`flutter test` 编的是整个 `lib/` 闭包，而这条共用工作树在别的 lane 在途改动期间会反复失配
（实测同一轮里全仓 error 从 12 → 0 → 24 摆动，破损还会换层：Dart 侧干净后卡在
`rossi_local_core` 的 Rust 编译上）。以下取自树干净那两次窗口。

**`test/workspace/` 12 个文件：78 通过 / 1 失败**，那 1 条不是本功能的：

- 失败点是 `control_panel_settings_cards_test.dart` 的 `超分卡与翻译卡 (setUpAll)`，
  报 `Content hash on Dart side (1679418916) is different from Rust side (407762454)`。
  出处：另一条 lane 正在加 `margin_fit`，**跨了 FRB 边界** —— `rust/src/api/margin_fit.rs`
  与 `lib/src/rust/api/margin_fit.dart` 都是新增，四份 `frb_generated.*` 全被改过。
  本功能零 Rust、零生成物改动。
- 同一个文件**另外 9 条全过**，其中包括 `画面调节卡 渲染三颗开关，拨动写回 cubit`
  与 `独占面板（没有折叠外壳）时闸门照样生效` —— 也就是本轮改过的控制面板内容
  是被真实跑过的，不是「被挡所以没验」。
- `./script/refresh_release_dylib.sh` 搬过 dylib 仍然不一致 ⇒ 是生成物与 Rust 源码两侧
  不同源，不是缓存陈旧。

**跑绿的**：

- `expressive_widget_kit_test.dart` 4 条、`discover_panel_widgets_test.dart` 6 条（本轮新增，共 10 条）。
- `information_widgets_test.dart` —— 五张信息卡在 320 / 640 / 960 三档下排布、
  标题折叠、`自定义布局` 入口、拖拽改尺寸、收起的卡不轮询。
- `lane_panel_layout_test.dart`（含 `PanelHeaderBar` 高度 == 44，所以标题行改 Expressive
  没改坏按钮寻址）、`lane_header_fit_test.dart`、`card_header_actions_test.dart`、
  `insight_cards_responsive_test.dart`（洞察 17 条 —— 参照面板本身没被抽件抽坏）、
  `layout_persistence_test.dart`、`workspace_panels_test.dart`（页签拖放次序，含 discover）、
  `history_insight_activity_test.dart`、`super_grid_editing_test.dart`。

**这一轮测试抓到的真 bug（不是先写对再跑绿的）**：`ExpressiveFactTile` 的 `onTap`
在**值那一块面积上静默失效**。归因用一次性探针：点 label 计数 +1、点 value 不动 ⇒
`SelectableRegion` 的 tap 识别器在 arena 里赢了外层 `InkWell`。
修法是可点的格子不套 `SelectionArea`（可点＝控件，不可点＝复制路径 / ID 的数据，
二者只能选一个），并把用例改成「必须点在值上才算过」当回归锁。

**上游整页卡（本轮唯一的结构性改动）已证**：`find.byType(DiscoverPage)` 命中一次
（阳性对照 —— 少了这条，「卡片画了但内容没建」也会全绿），卡片外框 ≥ 3 个单位高
（展开态而非折成一行），640 与 320 两档泳道宽下 `takeException()` 都是 null。
零插件时两张插件卡各自画诚实空态（`ExpressiveEmptyState` 命中 2 次）而不是抛异常或留白。

**测试自己也被证伪过一次**：`expect(find.byType(ExpressiveStatTile), findsWidgets)`
在零插件下是**红的** —— 状态卡那时正确地短路成空态（没有东西可数，画三颗 0 是噪声）。
断言改成 `ExpressiveTile` 才对上真实行为。

## 出图验收

`test/workspace/panel_expressive_preview_test.dart` 沿用
`library_design_preview_test.dart` 那套出图方式：

```
ROSSI_UI_PREVIEW_DIR=/tmp/rossi-preview \
  flutter test --no-pub --timeout 120s test/workspace/panel_expressive_preview_test.dart
```

五张图：`info-empty` / `info-filled` / `control` / `discover` / `info-narrow`（暗色 +
仓里那支墨红 `0xff8b4148` 当种子）。看过的结论：

- cookie 图标座、非对称圆角、primaryContainer 高亮格、底部进度条、状态胶囊
  在暗底上分层清楚，与洞察面板并排看不出一套还是两套。
- 320 窄泳道：卡片退到全宽单列、`InfoFacts` 的行改成上下排、标题行的
  `自定义布局` 收成图标档，三处都没有横向溢出。
- 空态摆字段格子这件事**看得出效果**：空卡与满卡是同一个形状，不再是
  大空盒里飘一行字。

出图**看出两个原来没发现的问题**（静态分析和 widget 测试都盖不到）：

1. **出图一开始是豆腐块**，字重/行高根本判不了。注册霞鹜文楷才算数：
   `ui.loadFontFromList(File('asset/fonts/LXGWWenKaiLite-Regular.ttf').readAsBytesSync(), fontFamily: 'PreviewCJK')`
   （参数名是 `fontFamily` 不是 `family`），再把主题 `fontFamily` 指过去。
2. **`AI 超分辨率` / `翻译` 两张卡的标题出现了两遍** —— 卡片外壳的标题一行，
   共享节自己那行组标题又一行（`translate_section.dart` 的 `title: t.ocr.title`）。
   已修：给共享的 `SettingsSection` 加一个 `bool showTitle = true`，
   两个节透传，控制面板那两张卡传 `false`。默认 `true` 保证阅读设置面板一字不动 ——
   这是 ADR-0023 / AGENTS §13 说的「挂在上游实现上的薄扩展点」，不是第二套实现。
   `test/comic_read/settings_section_title_test.dart` 把两侧都钉住（默认画 / 关掉不画且不留空白行），
   改完重出图确认 `AI 超分辨率` 只剩卡片标题那一处。
   （几何判据用的正文高度而不是「有没有那个 widget」—— 标题行就算不画文字，
   `Padding(14,8)` 还会留一行空白，只断文字会假绿。）

另外「图像信息」第三颗格子（像素尺寸）掉到第二行、被槽位裁掉 —— 这不是 bug：
卡片正文本来就可滚动（`scrollContent` 默认 true），要么往下滚、要么把卡片拖高。

出图还踩到两个坑，都记下来（下次做渲染台别再踩）：

1. **`MaterialUiCompatibilityBridge` 必须放在 `MaterialApp` 里面**。放外面直接抛
   `'a Localizations ancestor was not found'`；而**完全不放**更坏 —— 嵌入的上游
   发现页顶栏会画成一条**白带子**（plat 的 legacy Material 回退到 Flutter 浅色主题），
   出图看着像坏了，其实是夹具不忠实。同理要带 `supportedLocales` +
   `GlobalMaterialLocalizations.delegates`，否则 `PopupMenuButton` 先抛
   `No MaterialLocalizations`，它的 ErrorWidget 再把布局撑歪。
2. **出图不要用 `pumpAndSettle`**。控制面板里共享的翻译节挂着不定进度转圈，
   settle 永远等不到（实测 `pumpAndSettle timed out`）。固定拍三下
   （0 / 500ms / 500ms）拿到「弹簧落位后的一帧」，且对无限动画免疫。
   另外 `debugShowCheckedModeBanner: false` 要关掉 —— 那条 DEBUG 斜缎带会被拍进图里，
   测试环境文字渲染成方块，看上去像一处溢出。

**仍未验的**只剩真机观感：真实字体下的字重与行高、大字号档、墨水屏档下换色
是否真的没有过渡动画。这些要么在设备上看，要么给出图夹具注册 pubspec 字体。

`test/discover/` 那 8 条红与本功能无关：失败栈顶是
`objectbox (package:zephyr/main.dart:72)` → `globalSetting` → `convertChineseForDisplay`，
而这三个测试文件**从来没调用过** `TestObjectBoxHelper.setUpTestObjectBox`；
`lib/main.dart` 当时正被别的 lane 改。本功能文件没有一处出现在那些栈里。
