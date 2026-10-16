# 上游同步记录

## 操作绑定 v2 与公共 Rust 核心（2026-10-13）

Breeze 与 mImageViewer 当前可用实现没有同时覆盖 Rossi 的区域触屏、多上下文、轮盘与
配置迁移链路。继续沿用 Rossi 现有绑定实现，将通用模型、Context、匹配、冲突、诊断和
迁移抽为 `rust/operation_binding_core`；动作目录、九宫格和默认值升级保留薄适配。
不另建 Dart 解析器，不引入 Bevy，不实现 Node 适配器。Rust 生态库的实际适配边界与
keybinds 隔离实验见 `docs/operation-binding-rust-library-review.md`。

未版本化设置统一迁移为 v2，保留扩展字段、禁用与自定义操作，失败不覆盖原文；本机备份
不随云同步。鼠标和触屏区域分别配置，Flutter 胜出的单击一次交给 Rust 匹配。

## 2026-10-13

| 来源 | 先前内容基准 | 本次内容基准 |
|---|---|---|
| Breeze | `5853c2b4` | `68bebb2b83130c65ba3f6f709ca5413d2ae184d4` |
| mImageViewer | `8d95fffe`（v4.1.0） | `bb6ca0c665544da10b1acb061b590512acd0a4a4`（v4.6.0） |

本次按用户要求，重叠功能优先采用上游实现。Breeze 跟进 21 个提交，采用上游的
阅读设置组件、单本稀疏覆盖与 v12 迁移、章节分组、插件详情、图形验证码、自定义登录
标签、Freezed 状态及下载持续重试逻辑；QuickJS 原生二进制通道移除 JSON 兜底。
Rossi 独有的泳道弹窗、输入绑定、自适应背景、翻页预览、悬停、翻译和媒体控制保留在
独立扩展与薄适配中。下载队列的限流识别保留，操作内重试循环采用上游实现。

Flutter 配置跟到上游 3.47.6，Android minSdk 为 26，缺少签名密钥的 fork CI
采用上游的跳过逻辑。Rossi 包版本仍是 `0.1.0+1`，FRB 仍锁定 `2.12.0`，
代码生成脚本按项目锁定版本安装生成器，避免生成器与运行库不匹配。

mImageViewer 的 gitlink 与源码移植已同步；范围、跨平台差异和未接入功能见
[移植模块同步说明](local-core-vendored-modules.md)。不引入上游 Windows 应用的
UI、转换缓存或未具备消费者的 EPUB/LibRaw 链。

验证：统一代码生成完成；本地核心 462 项、QuickJS 原生通道 31 项、Flutter 相关
回归与 RAR 首卷识别 6 项通过；ObjectBox 旧实体/属性 UID 保留。静态分析没有 error，已有 warning/info
尚存。本机 Flutter 为 3.47.4（Dart 3.13.3），尚未验证 3.47.6 和各平台完整安装包。

## 展墙偏好同步扩展（2026-10-13）

展墙偏好沿用 `rossi.library.presentation.*`，通过现有 WebDAV / S3 设置同步新增
`libraryPresentation` 块；每个 scope 独立记录修改时间并合并，覆盖所有已保存位置与
完整展示参数。旧载荷缺项不清空本机，同步落盘后通知在场的展墙。该扩展接在上游
设置块协议上；上游没有本仓展墙及其 SharedPreferences 存储，无法直接复用对应实现。

同时修正书签、历史与页面列表的展墙持久化：底层列表样式恢复不再关闭并写回展墙，
只有用户明确选择普通视图才保存关闭状态；应用展墙设置会等待落盘完成。

验证：设置同步、按位置合并、旧键迁移、实时更新、面板重建与共享展墙回归 69 项通过，
本次修改文件静态分析无问题。使用 Flutter 3.47.4 / Dart 3.13.3；尚未连接真实云端验收。

## 键盘长按翻页节奏扩展（2026-10-13）

上游键盘仍以系统重复事件触发固定时长动画，没有可直接复用的应用级横翻长按速度控制。
Rossi 在原绑定解析与阅读设置（含本漫稀疏覆盖）上增加薄适配：默认 4 页/秒、
350ms 启动延迟，支持 0.5～15 页/秒和 100～2000ms 延迟；动画随连续翻页周期缩短。
显式 hold 绑定、ignoreRepeat、后续动作、视频上下文与条漫原行为继续由现有通道处理。
松手、方向切换、窗口失焦、编辑/模态上下文及卸载会停止计时；不补发错过的翻页。

验证：统一代码生成成功；键盘节奏、单本覆盖、绑定/滚轮、输入焦点与设置面板
回归 94 项通过；修改文件静态分析无问题；macOS Debug 构建成功。

## 下次同步

Breeze 在 GitButler 中作为内容提交集成，不新增上游 merge parent。因此 Git 的
`merge-base` 不能代替上表的内容基准；下次三方合并必须以 `68bebb2b` 为 base，
避免重复应用上次变更。不要覆盖 Rossi 独有接口或其他工作分支。

mImageViewer 更新 gitlink 后运行 `python3 script/sync_vendored_modules.py`，
检查所有 `PORTS` 差异并更新 `pinned_at`；同时人工审查未登记的 `path_key`、
`thumb_loader`、`catalog`、`fast_resize` 与显示几何切片。

## 文件管理器页签布局与创建策略（2026-10-13）

Rossi 的文件管理器在已有 Rust 会话、`FolderPaneState` 与目录列导航上扩展：
`LayoutMode` 是页签级的内容布局（内容、树、分栏），不并入六档条目样式，也不写入
目录级视图偏好。普通树把展开目录的条目直接融合进 `TreeSliver`，目录节点与文件
都使用六档共享卡片；网格档按视口宽度排列同级文件，不另挂独立列表。
搜索树根据已返回命中的真实路径补齐祖先节点，不为展示层级重新扫描磁盘。
同名文件按完整路径区分。

Flutter 树视口采用 SDK 的 `TreeSliver`，目录展开与后台扫描仍由 Rust 管理。
分栏导航复用原有投影并扩展到完整祖先路径，各栏复用 `LibraryEntryList`，前面的
父级栏保留封面与文件元数据，当前目录只显示一次。树和分栏导航保留所选条目样式。
普通目录只枚举已展开的层；搜索各栏使用命中及祖先投影，不追加磁盘扫描。
尺寸拖动交给 `multi_split_view`；
两种布局都占用主内容区，窄窗口可横向滚动。上游 Windows UI 不能直接用于 Flutter，
因此只做现有状态到官方树组件和分栏容器的数据适配，不另写树或分隔拖动控件。

新页签来源可选预设默认值、最近活跃页签、触发页签；未激活页签的“从此页签新建”
可显式指定触发来源。首个页签没有来源时使用预设，目录记忆仍可覆盖条目样式。
后续修改预设不覆盖已打开页签。继承浏览与搜索选项，不复制查询、结果、导航历史或
选中项；复制和恢复页签继续保留原有状态。搜索回车原子创建独立结果页签，达到上限
时源页签不变，从已保存结果再次发起搜索也保留原结果。

验证：统一代码生成成功；Flutter 文件管理器及页签会话回归 114 项、分栏尺寸回归
1 项、真实 Rust 桥接 1 项通过；Rust 文件管理器已有回归 47 项、新布局与页签策略
6 项通过；本次改动的 Flutter 静态分析无问题。尚未运行各平台安装包和桌面交互验收。

2026-10-13 视图兼容修正：移除普通树的双面板；六档卡片统一接入树节点与父级分栏。
补充六种样式在 260/700 宽度下的普通树与父级栏回归，以及真实桥接的普通目录
文件融合、纯文件目录收起/展开与父级文件元数据验证。
本次验证：统一生成成功；文件管理器与分栏控件 Flutter 回归 127 项、真实桥接
2 项通过；Rust 原有回归 47 项、布局集成回归 8 项通过。静态分析无问题。
尚未执行桌面交互验收。

## 阅读器展示适配（2026-10-13）

阅读设置继续复用上游设置读取、回调与本漫稀疏
覆盖写入，顶栏主行和二级行保留原有档位和全部功能入口。仅呈现层改为主题实色
Expressive 工具栏、进度轨道、缩略图选中形状与分组设置；宽屏分类使用现有
NavigationSidebar，窄屏使用 NavigationDock，分类、滚动位置和本漫写入目标在
窗口变化时保留。弹层进出和进度预览使用 CommonPopupRoute 的同一套托盘动画；
按压、悬停和选项切换复用 ElasticButton / ActionBubbleRegion / SpringLensBar。
增强入口统一采用 48dp tonal 按钮；超分保留本书启停与独立原图对比，翻译仍按
当前页归属、烘焙/叠层与原图旁路显示状态。超分、翻译与设置分别采用
cookie、slanted 与四瓣形状，沿用现有 Morph 路径和弹簧动效。二级工具栏
独立悬浮并按内容收紧，主行与二级行之间、工具栏两侧保留阅读画面；底栏
钉住常驻并移出更多菜单；窗口变化只调整排布，业务回调与存储作用域沿用原实现。

阅读设置的拖动/滚动交接直接使用 material_3_expressive 的
M3EBottomSheetScrollController。该版本 Frame 必带全屏标题和关闭按钮，没有
自定义标题接口，因此外壳采用薄适配：共享一套标题和关闭入口，以实际可见高度
布局正文，上拖先连续展开到全屏、之后滚正文，下拖收回；落位复用项目
SpringLensValue 与 LensMetrics，保留墨水屏、阅读无动画与系统减少动画设置。
技能安装在 .agents/skills/material3-expressive-flutter，来源提交记录在 SOURCE.json。
缩略图比例开关放在阅读设置的「界面 → 上下栏与边距」中，胶卷仅显示缩略图。
开关作为全局阅读偏好扩展，默认统一竖向卡片；开启后按原图比例
排列，极端长宽比保留完整图片。复用页面列表的 ReaderThumbnailWidget、共享
图片尺寸报告、320px 缩略图 LRU 与 Flutter ImageCache；本地同页生成请求合并。
可变宽胶卷使用 ListView 的 itemExtentBuilder 保留虚拟化与双向当前页居中。
验证见阅读设置、顶栏布局、缩略图、进度方向/防抖、视频组合底栏及共享弹层测试。

## 设置展示适配（2026-10-13）

设置仍采用 Breeze 的分类页、状态和持久化接口。其总览为单栏列表，没有可直接
复用的 Flutter Expressive 双栏设置浏览器；Rossi 在入口与公共外壳上添加展示适配，
使用 `material_3_expressive` 的 `M3EList` 分组和 `M3ECard` 主题选择，配色取现有
Material Theme（包含动态取色与导入主题），按设置面板的实际宽度选择单双栏。

详情区直接挂载原分类页，`SettingDetailScope` 只关闭该页的返回入口。下一层仍走
原路由和工作台守卫；阅读设置沿用上游共享面板。输入绑定页有未保存编辑的回退
保护，仍用原独立路由；不为了双栏绕过保存确认。保留超分、OCR 和工作台的平台
可用条件。新增搜索只检索分类名称、分组和当前摘要，不宣称能搜索所有设置项。

外观页仅重组原控件，主题预览写回原 `ThemeMode`；减少动画和墨水屏模式关闭
新增按压形变。分组、双栏、搜索、键盘与主题写回的回归见
`test/setting/setting_browser_test.dart`。

设置动效继续使用本仓统一组件：`CommonPopupRoute` 承担设置子页面、居中确认框和下拉菜单的进出场；`ActionBubbleRegion` / `ActionBubbleTarget` 在分类、主题预览与分组条目之间连续移动悬停高亮；`RetainedPanelSwitcher` 用 `SpringLensValue` 与 `LensMetrics` 承接连续切换的当前位置和速度，并保留已访问详情的滚动与输入状态。没有引入另一套弹出曲线。输入绑定仍经 auto_route 守卫与 PopScope 保存保护；墨水屏和系统减少动画模式跳过空间动画。

验证：设置导航、搜索、主题持久化、键盘导航、字号缩放、连续悬停与反向、保留详情、PopScope 返回保护、共享弹层返回值、菜单根层摆位与关闭生命周期、子菜单及保留面板绘制预算的 widget 测试；Flutter 3.47.4 / Dart 3.13.3 环境运行（仓库锁定 Flutter 3.47.6）。

## 设置分组统一与折叠大标题（2026-10-14）

`同步` 原先是唯一留在旧形态上的设置页：行直接坐在页面底色（浅色主题即纯白）上，用
`Divider` 分段；其余设置页已在 `SettingGroup`（`M3EList`，`surfaceContainerLow` 主题色表面）上。
本轮把剩下的设置页与两处二级页（字体设置、主题色）逐页并入同一口径：一律
`SettingPageShell` + `SettingSectionCard`，去掉 `Divider`，页边距统一 `kSettingPagePadding`。
分组后设置行的定位不变：`SettingEntryList` 的 id 会穿进分组卡（`flattenSettingEntries`），
落到卡内那一行用 `Scrollable.ensureVisible` 补挪 —— 包按下标收敛时，卡比视口高会让
`ListObserverController.animateTo` 永不完成（实测补挪步骤不执行且 `pumpAndSettle` 挂满超时）。

超分（RealSR）三份文件不参与统一：用户口径为「超分设置没有特定风格」，其条件是阅读端与工作台
共用的自定义面板。该排除写在门禁脚本里并每次运行打印理由，不是静默跳过。

独立成页的设置页改用折叠大标题：`SettingPageShell` 的外层换成 `NestedScrollView`，header 是
`material_3_expressive` 的 `M3EAppBar.sliver(variant: largeFlexible)`，各页仍只传 `child`，
不必改成 sliver。上游已有该组件，因此不另写 `SliverAppBar.large`。双栏右栏
（`SettingDetailScope.isEmbedded`）保留原实色小栏，避免左栏选中项与右栏大标题同屏两遍。
折叠只给二级页：设置总入口（一级页）传 `collapsingTitle: false`，它下面已经有双栏总览卡；
门禁对这一条也做了断言。
三条实测边界写进代码注释，别当参数调：该 sliver 不自动推导返回键（要显式
`leading: BackButton()`）；flexible 档的标题列是定高且 `M3EAppBarDensity` 没有更高一档，
360×800 / textScale 2 下钳到 1.2 仍溢出 1px，故标题区不跟随系统字号、正文照常放大；
展开带子的余量（同一探针，宽度 360 与 800 数字相同，说明它与宽度无关）：单行标题 132、
单行标题＋单行介绍 164，标题换成两行在 132 档 `overflowed by 36`、164 档 `overflowed by 28`
—— 所以「大标题自然换行」在上游实现里放不下，标题只能一行＋省略号（本页标题最长 6 个汉字，
实测远不到省略号阈值）。
「长句子完整可读」这一条改由介绍满足：它不再占 `subtitle`，而是外层 header 的第二条
`SliverToBoxAdapter`，按内容定高，因此能自然换行、跟随系统字号，并随内容卷走（顶栏只留常驻
小标题）。它本来就是原来那一句介绍，不是为折叠动画新造的内容。挪进 header 后唯一的视觉风险
是「小栏常驻时介绍画在它上面」，这条也不用等真机：pinned header 向后一条 sliver 报的通道在本
SDK 叫 `SliverConstraints.overlap`（由 `SliverGeometry.maxScrollObstructionExtent` 供），实测
进页面 0、滚过收起幅度后 >0，即介绍被压在小栏底下。
介绍文案只复用既有 `*Subtitle` 词条（12 页），没有为凑格式新造句子；缺介绍的工具页
（存储、缓存、调试等）保持只有大标题。

门禁：`python3 script/check_setting_group_style.py --strict` —— 按内容（不是文件名）取设置页范围，
四条硬红线：自带 `Scaffold` 未走外壳、还有 `Divider`、页面自己搭 `AppBar`/滚动视图（绕开折叠）、
有设置行却没有分组卡；外壳丢失折叠顶栏同样不合格。回归：`test/setting/setting_group_style_test.dart`
（13 页逐行「无行落在卡外」+ 阳性对照）、`test/setting/setting_collapsing_title_test.dart`
（展开高度、滚 320 后收起幅度、收起后标题常驻、应用真实弹层路由、textScale 2 窄面板不顶穿、
短页不为折叠造内容、双栏右栏不挂大标题），以及只 import 外壳的合成页
`test/setting/shell_collapsing_title_test.dart`（真页夹具要过 `GlobalSettingCubit` → `main.dart`
的整棵 import 图，别的会话在 `lib/page/comic_read/**` 留编不过的在途代码时，那份连编译都进不去，
这份仍然可跑）：折叠幅度、介绍换行后仍随内容卷走、以及「标题一行放不放得下」——后者拿
`RenderParagraph` 实宽与整句单行宽比，并用 22 字的假标题作阳性对照，证明这把尺看得见截断。
OCR 与按键绑定两页需过桥 dylib 才能 pump
（`./script/refresh_release_dylib.sh` 后加回表内），当前只由上述文件级门禁覆盖。

## 搜索组件历史适配（2026-10-13）

复用 `material_ui` 已包含的 Flutter 官方 `Autocomplete` 默认建议视图与
`PopupMenuButton` 历史菜单，不另写建议浮层、列表或键盘导航。共用组件仅适配
现有输入框、回调和存储。普通回车提交当前输入，方向键选择后回车接受历史；
点历史立即重搜。空输入聚焦展示最近记录，支持按输入过滤与清空当前用途的历史。

图源与聚合搜索继续读写 Breeze 的 `GlobalSettingState.searchHistory`，按来源
隔离；归属未知的旧历史留在原历史页。结果页改为从写入时的当前状态更新，避免
延迟保存旧列表覆盖其他页签的新历史。文件管理器复用 Rust 的 SettingsDb API，
成功创建搜索页签后才记录；移除旧历史 chip 行，改用同一套现成组件。

书架各模式、工作台书签和阅读历史、页码/文件名筛选、插件商店、字体选择、收藏
画师/标签、输入绑定及设置分类筛选使用已有 `shared_preferences`，各用途独立键。
本地筛选只在提交、失焦或结束编辑时保存完整词，保留原来的实时过滤；去重、最近
优先且每用途最多 50 条，共用写队列避免多个卡片覆盖。历史存储故障不阻断搜索。
上游只有图源搜索的历史页，没有上述跨搜索组件的自动完成接入，因此这是接在
上游历史模型与现成组件上的展示适配。

## 文件管理器面包屑展示适配（2026-10-13）

两种样式共用 `PathBreadcrumb`，继续消费 Rust 快照中的 breadcrumbs；不维护第二套
路径状态或祖先推导。克制型采用规整圆角与当前项文字强调，强表现型在轮廓带加入
轻微起伏，根节点及当前项使用 `material_3_expressive` 的形状。宽度不足时保留首尾，
中间祖先在现有 `CommonPopupBox` / `CommonPopupRoute` 中跳转；当前项仍编辑完整路径。
按压和跨项悬停复用 `ElasticPress` 与 `ActionBubbleRegion` 的物理弹簧，减少动画及墨水屏
模式遵守原开关。样式写入原 `FileManagerSettingState`，旧数据及未知枚举值降级为克制型。
该功能仅是现有文件管理导航上的 Flutter 展示扩展；mImageViewer 的原生文件管理界面
不能直接作为 Flutter 控件使用，Breeze 没有该工作台文件管理组件。

## 2026-10-13 藏书展示扩展

共用 `LibraryEntry`、`FolderShelfBloc`、`ComicInfo` 与文件管理器树快照，增加可组合的
M3 Expressive 展墙及原位详情，不另建导航、下载或阅读实现。目录数量/体积的异步扫描仅
为展示面积提供度量：现有核心快照的 `childNames` 是预览而非总数，没有可用于此展示的
完整数量/字节接口，因此使用可取消、带缓存的 Dart 薄展示服务。行为、边界与验证见
[藏书展示设计](design/library-expressive.md)。

原位详情使用专门的操作、Tag、简介、章节与预览布局，复用原有业务状态；不直接嵌入旧页。
原图比例选项共用于藏书、书签、历史、文件与页面列表，设置集中在既有顶栏弹出菜单。
展墙卡片使用完整等比封面与融合文字遮罩，宽卡增加真实标签和状态容量，标题不随面积放大。
原位详情首帧创建既有业务宿主，展墙和普通列表复用几何，不为展开重算权重排布；
多项详情独立保留状态，包括书签/历史时间线。已收起详情仅缓存最近 8 项，打开数量不受此限制。
文件夹合成保留既有候选规则，仅把中心裁切改成完整等比置入并升级策略缓存键；
实现与回归记录见 docs/local-core-vendored-modules.md。

## 阅读轮盘蜂窝展示适配（2026-10-13）

继续使用本仓 `flutter_ray_menu` 的条目、槽位和指针/键盘流程，以及原 Rust
操作绑定解析器；新增 surfaceBuilder、visualHitTest 和指针观察接口承载 Flutter
展示。按用户确定的 Apple Watch 应用视图方向，从中心填满紧凑蜂窝格点，
阅读时不为空槽保留视觉占位。逻辑 id、层号和槽位不变，视觉位置不再表达旧
扇区方向；编辑器仍能选择空槽。Breeze 没有可直接复用的上述 Flutter 展示。

指针局部放大、有限平移与选中态沿用 SpringLensValue/LensMetrics，浮层进出
沿用 CommonPopupOverlayMotion，图标选择器沿用 CommonPopupRoute。实际绘制
与命中共用变形几何；按下冻结几何，原指针路由继续负责松手去重与动作派发。
阅读图标通过原解析器按 reader/video 上下文匹配，编辑器提供可选的 iconId
展示覆盖，随 JSON 保存。Rust 的 NeoView 轮盘文档仅增加可选展示字段，未改变
槽位、动作与验证规则；该模型不是 mImageViewer 的直接源码或 PORTS 移植模块。

验证记录见 docs/design/reader-radial-menu-expressive.md 与 operation_binding 下的
聚焦几何、展示、图标、编辑器和阅读浮层回归，以及原 RayMenu 与 Rust 轮盘测试。

## 工作台设置与工具入口适配（2026-10-13）

工作台 `tools` 面板使用 `WorkspaceToolsPanel` 呈现入口，不再嵌入上游 `MorePage`
的品牌头。设置放在首屏顶部，外观、共享阅读设置和工作台布局提供快捷入口；
下载任务、同步和追更共享常用分组，更新日志与关于保留在次级分组。按面板实际
宽度和字号决定是否并排，不改变面板 id、已保存布局或独立模式的更多页。

这是原功能上的展示扩展：所有页面继续由现有 auto_route 路由、工作台守卫和
局部 Navigator 打开与返回；阅读设置仍使用共享 `showReaderSettingsSheet`。
不另建设置状态、下载队列或追更模型，主题摘要与追更数量读原 Cubit。
分组复用 `SettingGroup` / `M3EList`，主入口采用主题容器与 M3E 形状，
按压、跨入口悬停和弹层沿用统一组件；减少动画和墨水屏遵守原开关。
验证入口顺序、完整回调、窄面板与大字号、RTL、更新徽标、键盘和共享悬停。

## 阅读洞察展示与布局适配（2026-10-13）

原有近七日趋势、连续阅读、星期与小时热力、来源拆分继续使用
`history_insights.dart` 的聚合与 `HistoryInsightsWindow` 的 ObjectBox 有界查询。
新增概览、连续 28 日日历、星期节奏和六小时分布仅扩展同一份最近 500 条样本；
统一标注为漫画的最后阅读记录，不把 `lastReadAt` 当作完整访问日志或阅读时长。
来源归一仍调用 `classifyHistorySource`，日期使用原本的本地日历工具。
Breeze 没有该工作台统计面板；mImageViewer 的原生统计面板统计缩略图缓存、
文件格式与加载性能，依赖 egui 和原生应用状态，不能替代 Flutter 阅读历史洞察。

强表现集中在摘要字号、异形图标徽章、主指标色块、选中反馈和来源环图。
热力格、数值行和柱图保持一致几何；时段选择使用原 `CommonPopupBox`，
按压、悬停与数据变化使用 `ElasticPress`、`ActionBubbleRegion` 和
`SpringLensValue`，减少动画和墨水屏时跳过新增空间动画。

小尺寸连续阅读改用摘要 / 趋势分段；热力图按宽度汇总时段并保留全七行，
极小槽位显示摘要和统一弹层展开入口。切段箭头、段名 / 进度与热力粒度、
展开入口均在原卡片标题栏内适配宽度，不另占底部一行。正文状态通过帧尾绑定
更新标题操作，移除正文时释放绑定。两者通过内容适配消费实际高度，
不在卡片内嵌套滚动。设计与数据边界见 [洞察卡片内容适配](design/insight-card-content.md)。

显式网格跨度现在使用紧约束，固定宽高不再因内容多少改变。
`CollapsibleCard` 在有界槽位中保留标题和调整手柄，内容在内部滚动；
折叠复用 `RetainedPanelSwitcher` 的可重定向弹簧，保留内容状态和历史订阅，
外框尺寸不变。
独立自然高度卡片继续沿用原折叠行为。低高度编辑态预留的手柄空间按可用高度
收敛，避免最小档位溢出。新增分析卡注册在原工作台注册表，沿用布局持久化、
跨面板移动、隐藏和恢复，不引入第二套布局模型。

回归覆盖日期跨年与窗口边界、未来记录过滤、六小时时段、来源 UUID 归一、
180–760dp 卡宽、96–384dp 卡高、两倍字号、横纵网格同跨度对齐、内容刷新后
槽位不变、最小档编辑、真实统计面板调整与历史订阅保留、统一弹层时段选择。

## 发现页与通用展墙调整（2026-10-13）

发现列表继续使用 Breeze `68bebb2b` 的场景、插件筛选、分页 Cubit 和详情导航，
该基准的列表只有普通网格，没有可直接复用的 Flutter 展墙。展示层接入工作台
已有的 `LibraryEditorialCanvas`，保留刷新、分页失败重试、合集目标和发现页签导航。
筛选使用右下角主题色扩展 FAB，保留安全区、文字提示和当前筛选标记。

所有展墙设置收进宿主原有标题或工具栏的一颗按钮，通过统一弹出面板调整。
发现、书签、阅读历史、书架、文件管理器和阅读页列表不再在正文前单独铺设置行。
发现列表住在页签内时移除重复的页面标题栏，设置登记到所属页签组的工具栏；
横向标签条和竖向标签轨共用一份入口，切换、关闭与分屏按各组当前标签取工具。
独立列表路由仍保留自己的 AppBar。展墙入口改为调色盘图标，与条目视图模式区分。
卡片目标宽度、高度、间距与图片尺寸保存到原来的各用途偏好键，列数按面板实际
宽度计算。原图比例继续用已有图片解码结果，不新增图片请求或另写布局算法。
宽度调节前置到设置首组，范围为 80～420dp，并显示当前每行格数；2～6 格快捷项
按实际内容宽度反算目标尺寸，不存第二份固定列数。宽卡占两格，三格可排两格宽卡
与一格普通卡，缩窄窗口自动减列。发现默认目标宽度使用通用的 140dp。

设置面板使用 M3E 分组列表、滑杆与动作按钮，数值独立标记，尺寸/布局/权重按组
收纳。面积依据复用既有 CommonPopupBox/Menu 的锚点托盘弹簧，不使用 Flutter
原生下拉路由；减少动画、键盘选择、取消/应用与原偏好持久化继续保留。

发现页补接现有 `LibraryBookDetails` / `EmbeddedComicInfo`，封面右下角信息键直接
原位展开，与封面打开发现新页签共存。通用展墙设置增加「点击封面」的两种行为：
向下展开详情，或交还宿主打开详情页；书签、历史沿用原有详情视图，发现沿用现有
页签导航。选择按原来的位置键持久化并参与展示偏好同步，旧数据缺项时保持宿主
原先默认。展墙、自定义封面的内层手势与普通列表/网格共用同一判决，信息键独立
展开；文件夹仍然导航，禁用态不响应。发现内联详情同时传递合集目标，避免展开
后收藏操作丢失上下文，详情加载、章节和下载仍复用已有实现。

本轮封面行为验证：共享展墙、普通视图、设置持久化/同步、发现页签与详情回归
共 98 项通过；220dp 暗色大字号及减少动画设置可用，静态分析无问题。
本轮 macOS Debug 构建通过；尚未进行真实图源手动验收。

通用层只接收稳定 id 到数值的信号，以及宿主声明的标签名、默认权重。发现层
沿用现有喜欢标签、画师与汉化匹配器提供信号，默认权重为 3、2、1；用户可改为
0～10，0 关闭。多项命中取最强信号，标签只改变面积、保持图源原顺序；单列也
通过高度体现层级。未知信号保留，后续新增种类无需修改展墙的判决算法。

验证：相关 widget/单元回归 177 项通过，另有 3 项明暗主题、窄屏和大字号预览通过；
本次文件静态分析无问题；macOS Debug
构建成功。本机 Flutter 3.47.4 / Dart 3.13.3，仓库锁定 3.47.6。扩大到整个发现模块
时另有 6 项既有测试失败，涉及插件胶囊测试未初始化 ObjectBox 与页签关闭悬停
查找器。尚未进行真实图源与各平台交互验收。

## 发现列表滚动与浏览位置扩展（2026-10-16）

继续复用 Breeze `68bebb2b` 的插件分页 Cubit、请求封装与筛选状态，在其上增加
直接请求目标页、请求代次隔离与可见条目页码索引。该基准没有浏览位置恢复与
通用浏览菜单；本仓以薄宿主接入已有展墙及普通视图，不新增平行分页状态机。
右下角菜单收纳筛选、展示设置、上一页/下一页、快速跳页和恢复上次位置；
总页数仅采用插件明确返回的 totalPages/pageCount，未知时只显示当前页。
位置按插件、函数和筛选参数隔离，自动保存页码、首个可见条目及视口偏移，
恢复直接请求该页。记录最多保留 128 组，不保存封面或漫画列表。

macOS Profile 现场采样显示主线程反复在封面布局中解析喜欢画师名单。沿用原
匹配优先级，缓存当前名单的解析与索引、分模式兜底词和最多 512 条文字匹配结果，
名单内容改变即失效。发现 scheme 的纵向内容改用同一 CustomScrollView 的
SliverList/SliverGrid，避免 shrinkWrap 嵌套网格全量创建。展墙继续使用已有懒列表，
只登记实际挂载的卡片锚点，替换页时清理旧比例与锚点。

验证：45 项定向测试通过，覆盖 2000 条内容持续滚动时视口外回收、直接跳页、
迟到响应隔离、真实可见页码、条目偏移恢复、重新进入不覆盖旧记录、菜单验证
和 Dock 避让。macOS Profile 包构建成功。尚未重启用户正在运行的应用进行真实
图源滚动帧率复测。本机仍为 Flutter 3.47.4，仓库锁定 3.47.6。

扩大回归还遇到未涉及路径的测试问题：发现详情测试的页签 mock 缺少新封面参数；
时间线查找器把同名分组与卡片文字一起计数；图片比例测试让装饰拼贴覆盖了主卡片
几何回报，或把装饰图的 cover 与主图的 contain 混为一谈。保留这些失败记录，
不将本轮定向通过解释为全仓测试通过。


## 本地设置与数据备份适配（2026-10-13）

沿用 Breeze 的 ZIP 备份、文件选择和 Rust 流式打包接口，增加同步页内直接操作和
设置首页「本地导入/导出」入口；无需配置 WebDAV / S3。没有另建归档协议或备份页面。

全局设置导出、导入复用同步设置块白名单；ObjectBox 输出的字符串与解码对象同时过滤。
旧全量备份导入也先过滤，本机路径、代理、应用锁、同步凭据和窗口几何保留。
工作台和展墙偏好分别复用 WorkspaceSyncCodec 与 LibraryPresentationPreferences；
移动端沿用同步规则保留本机工作台几何与临时状态。

导入前校验格式、ObjectBox 实体及附加设置，数据库替换放在同一写事务中。
不包含下载文件时保留本机下载记录、下载目录和链接，不引入备份设备的下载记录。
继续支持上游无格式版本字段的旧备份，以及可选的漫画文件备份。

## 展墙空隙填充（2026-10-14）

展墙的行高取同行最高的一块，宽卡又占两格，于是矮卡下方与行尾都会留下不规则空白。
新增 `LibraryPresentation.gapFill` 四档（不填充 / 随机图形 / 小组件 / 组件 + 图形，默认最后一档），
**并且每一项都能单独开关**：`gapShapes` 单独管随机图形，`gapWidgets` 是一张
`id → bool` 表管每一款组件（缺键 = 开，所以以后新增组件不需要迁移）。设置弹层里
先选总口径、再列子开关，子开关只在当前口径下真能改变输出时才出现 ——
选了「不填充」还留一颗「随机图形」开关就是装饰品。生效口径的换算在
`libraryGapMode`（shapes 档关掉图形 = 不填；both 档关掉图形 = 只剩组件），
套件过滤在 `libraryGapKit`，两者都是纯函数并有全表测试。
与其它展墙偏好同走 `rossi.library.presentation.*`；旧载荷缺该键按默认档解析，
只带该键的记录也算「可用」（`LibraryPresentationPreferences.parsePresentation`），
`gapWidgets` 的键在合并前按 id 排序，插入顺序不影响合并结果。

* 随机图形复用本仓已有的 `ExpressiveBlob`（种子决定轮廓，同一位置永远同一形状）
  加一枚语义中性图标；轮廓只在槽位矩形内侧变形，不压相邻卡片。
* 小组件是**按空隙尺寸现算的汇总卡**，共 11 款（封面拼贴 / 接着看 / 连续天数 /
  近 7 日 / 时段 / 常见标签 / 在读 / 来源 / 近 3 天 / 体积 / 条目数），
  只读 `LibraryEntry` 已有字段，不查 ObjectBox、不接 Bloc。
* 没有复用卡片注册表里的洞察卡，三条都量过：`CollapsibleCard` 的标题行约 48 高，
  而竖向余量常见只有 64~120；`DailyTrendView` 写死柱区 `height: 124`、
  且 `maxWidth < 364` 时按 364 起横向滚动，两张 `InsightMetric` 是 padding 14 +
  `headlineMedium` 没有降级分支；数据侧 `HistoryInsightsWindow` 直连
  `objectbox.unifiedHistoryBox`，并把 `insight_components.dart → global_setting.dart`
  拖进依赖链，而「前 7 日 / deltaPercent」要的整库窗口一墙条目里根本没有。
  ⇒ 注册卡在这一层**不可用**（尺寸与依赖两条都不满足），不是同名模块的平行实现。
* 注入点只有一个：`LibraryEditorialCanvas.gapWidgets`（宿主可整替换或传 `const []` 只留图形），
  `defaultLibraryGapWidgets()` 返回 `List.unmodifiable`。
* 并存档里每款组件一面墙最多出现一次，装不下或已经用过的槽位改用随机图形 ——
  「防止小组件重复出现」落在这一条，判据在 `libraryGapChoices`。

验证：`test/workspace/library_gap_fill_test.dart` 13 项（槽位几何、三档口径、组件去重、
偏好往返与坏值回退、每款组件在自己下限尺寸 + 2 倍字号下不溢出）；
展墙端到端三档对照写在 `test/workspace/library_gap_wall_fill_test.dart`。

## 阅读器三块：页面排序 / 幻灯片 / 放大镜（2026-10-14）

顶栏 `_kReaderComingSoon` 里那三颗占位（页面排序、幻灯片、放大镜）接成了真面板。
上游 `deretame/Breeze` 没有这三块（`git grep -iE "magnif|loupe|slideshow" upstream/main -- lib` 零命中），
所以按 AGENTS §13 第 3 条属本地新建；但**判据尽量取上游 mImageViewer 那份**，取不到的原因逐块写明。

### 放大镜：几何照抄上游，只有像素来源换了

`lib/page/comic_read/model/reader_magnifier.dart` 是 `vendor/mimageviewer/src/ui_fullscreen.rs`
里那套 loupe 的逐行移植：常数 `LOUPE_SIZE/ZOOM/OFFSET`（`:328-333`）、
`loupe_sample_mapping`（`:3821-3846`，边缘收缩绘制矩形以保持单位屏幕像素的倍率不变）、
窗口落点与出屏翻转（`:41811-41822`）、「帧没就位/旋转页不做」这类闸门（`:41794-41797`）。
行为规格也照上游的测试（`:66142-66175`）在 Dart 侧复写了一份。

上游那份**不能直接搬**：它画的是 egui `painter.image(id, image_rect, uv_rect)`，
消费的是显存纹理 handle；本仓的对应物是 `Canvas.drawImageRect` + 一份 `ui.Image`。
换的是取样端，不是判据。两处有意的偏离：窗口形状从方框改成圆形（触屏优先的读法，
圆镜头一眼就是「放大镜」），以及上游的全景模式闸门在这里没有对应物（本仓还没有那一档）。

### 幻灯片：计时复用本仓那套控制器纪律，策略取上游

结束策略三档取自 `vendor/mimageviewer/src/settings.rs` 的
`SlideshowEndAction { Stop, LoopFolder, NextFolder }`，第三档在本仓的对应物是「续下一章」
（无缝拼接已经把邻章接进来了，不需要新机制）。「帧没解出来就别推进」照
`current_slideshow_frame_ready`（`:35644`）落成 `ReaderSlideshowTick.hold`。
计时器不复用 `ReaderAutoReadController`，而是**同纪律另建一个**
（`controller/reader_slideshow_controller.dart`）：两者节奏不同 ——
一个是按像素连续滚，一个是整页驻留，共用一张表会让改间隔连带改掉滚屏节奏。
自动滚屏那一份原样保留，没有缩它的功能。

### 页面排序：章节内页序，本仓与上游都没有对应物

上游没有「章内页重排」这一块：mImageViewer 的 `display_order: &[usize]` 是**索引间接层**
（`ui_helpers.rs:1987` 的 `adjacent_slideshow_idx` 那条路径），本仓借的正是这个「不改页表、
只加一层排列」的形状 —— 每一页仍带自己的 `chapterPageIndex`（源下标），
所以尺寸缓存、历史、预取、OCR 覆盖层都不必知道排序存在。

自然序那一档的**算法**与 `rust/local_core/src/ui_helpers.rs` 的 `natural_sort_key` 同源，
但在 Dart 侧另写了一份（`model/reader_page_order.dart`）。不可用的理由是可达性而不是能力：
这一档要在 `buildColumnEntries` / `buildRowEntries` 里每次构建都被问一遍，
走 Rust 就得为它新开一条 `#[frb(sync)]` 桥、并让每次条目构建都过一次 FFI；
而页表最长几百个名字，纯 Dart 的比较代价低于那条桥。两份实现的口径差异写在了函数注释里
（`local_core` 保留「数字块先于文本块」，Dart 这份跟它一致）。
后续若把章内排序下沉到 Rust，这两份必须收敛成一份，判据以 Rust 侧为准。

验证：`test/comic_read/reader_page_order_test.dart`（自然序与排列校验、按章隔离、
页表变短退回原样）、`test/comic_read/reader_slideshow_policy_test.dart`（结束策略与
帧就绪顺序）、`test/comic_read/reader_slideshow_controller_test.dart`（分派与计时器不重启）、
`test/comic_read/reader_magnifier_test.dart`（取样几何与边缘不改变倍率）。

## 自动裁边与 JPEG 降噪高级设置（2026-10-14）

沿用 mImageViewer `margin_fit.rs` 和 RealPLKSR 1× 分块执行器；未复制 egui UI。
Flutter 新增 `AutoTrimSettings` 薄适配：容差交给已有 Rust 检测入口，裁切上限与
安全留边只能向外扩大内容矩形，默认保持上游 24 / 20% / 0.6%。检测参数变更
会使结果缓存与显示几何失效。条漫上下边保留完整，列表项同步按内容宽高比重排，
位图、GPU 与译文叠层共用 `PageTrimTransform`，放大镜取样也使用裁边后的 UV。

JPEG 降噪新增独立分块档位与按文件头选择仅 JPEG；在线原图解析后由
`EnhancedOnlinePage` 观察设置并切换另存的结果。本地呈现器使用相同降噪参数。
缓存身份包含源文件版本、模型修订、参数和阶段顺序；通用在线下载管线不再覆写
原文件。模型管理状态跨面板共享，包含进度（总长度未知时不定进度）、校验、
已安装大小、失败/重试及移除。权重版本固定为 vendor 的 bb6ca0c6，28.2 MiB；
SHA-256 校验通过后才安装，更新失败保留旧权重。

UI 使用 Material 3 Expressive 分组、主题色、胶囊操作、弹簧展开、触觉反馈，
支持系统减少动画与大字号。上游没有 Flutter 跨在线/本地的缓存显示与设置宿主，
因此保留这层适配；并未宣称移植上游完整模型管理、TensorRT 或全部后处理。
当前 RealPLKSR 推理后端支持 macOS / iOS / Windows / Linux；Android 入口明确
披露未具备该后端。拆分出的半页仍按既有安全策略不裁边。

两张设置卡的预览默认折叠，不加载位图。展开时从当前阅读页读取已经应用的内容矩形
与增强结果，只在没有当前页时加载内置示例。预览缩略图最长边 720，收起、换页和退出
时释放；不重新运行裁边检测或整页 AI 推理。示例素材及来源仍记录在
`asset/image/processing_examples/`，可用 `script/generate_image_processing_examples.py`
重新生成。

2026-10-14 显示裁边修正：继续复用上游检测器，Flutter GPU 合成层对已有 Texture
按内容区裁剪、等比变换和居中，无需修改原图或重写纹理。高度受限、倍率为 1 时也要
裁掉区外余白，不能用“是否放大”代替“是否裁边”的判断。GPU 检测采样改为最长边
1000；CPU/GPU 检测共享请求身份，过期结果丢弃。当前页检查读取阅读器的有效书级
开关与布局矩形，区分未开启、待检测、无需裁边和已应用，避免预览另算一份结果却
宣称已经上屏。文件版本切换时清除旧布局结果。验证覆盖像素裁剪、GPU 节点切换/
重复重建、长条采样、请求去重/过期、预览懒加载与既有原生检测。

## 阅读器悬停唤出修正（2026-10-14）

悬停唤出是本仓的 Flutter 扩展；当前 Breeze 上游没有对应感应层，mImageViewer 的
egui 输入体系不能用于 Flutter 命中测试。保留现有控制器与延时策略，以
`ReaderHoverStack` 统一把感应层放在阅读叠层最后，解决页码信息底板等兄弟节点
截断命中后无法唤出的问题。提示装饰使用 IgnorePointer，感应带透传按钮、点击与
滚动；带内移动可恢复唤出状态。控制器与感应几何共用已经合并的本漫有效设置，
不在鼠标每次移动时重算整份设置。

验证：悬停控制器与 widget 回归共 28 项通过，覆盖实际 PageCountWidget 顶部/底部
底板、栏体阴影、按钮点击、滚动透传、本漫覆盖、状态恢复及动画开关下的连续显隐。
连续显隐测试同时推进模拟时钟与更新页码；尚未实测高负载下的桌面窗口长期运行。


## 阅读泳道返回后的界面更新修正（2026-10-14）

现场在 macOS Profile 捕获：ReaderHoverController 与 ReaderCubit 已响应进入/离开，
ReaderChromeTransition 的 visible 却保持旧值。WorkspaceReaderHost 的 LayoutBuilder
作用域积压 dirty elements，渲染对象为 needsRebuild=true、needsLayout=false；改变
泳道尺寸才会再次执行回调。这是布局期间子树通知引发的调度问题，键盘归属与阴影
均不能解释该现场；输入绑定升级增加的泳道高亮/尺寸切换会暴露这条路径。

ReaderViewport 继续使用 Flutter AbstractLayoutBuilder 的约束、构造与重建作用域，
只将自身 performLayout 期间收到的再次布局回调合并到帧尾，下一帧正常处理。
不依赖定时轮询，不重挂局部 Navigator，不改变键盘编辑、模态或滚轮归属。
这是本仓工作台宿主的薄适配：Breeze 和 mImageViewer 没有可用于该 Flutter
布局调度场景的现成宿主。Flutter 修正相同调度后可移除此适配。

验证：布局期间通知的回归先在普通 LayoutBuilder 失败、替换视口后通过；47 项
定向测试涵盖真实阅读顶栏与实际透明度、跨泳道返回、输入框持有焦点、泳道内容
重建预算、点击/滚动及栏体连续显隐。独立 macOS Profile 场景中，普通 LayoutBuilder
的通知值到 2 而显示仍为 0；ReaderViewport 的通知与显示均到 2。应用 Profile 包
构建成功，静态分析通过。
