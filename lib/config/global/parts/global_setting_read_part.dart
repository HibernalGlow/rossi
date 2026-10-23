part of '../global_setting.dart';

@freezed
abstract class ReadSettingState with _$ReadSettingState {
  const factory ReadSettingState({
    @Default(false) bool noAnimation,

    /// 横翻键盘长按的应用级节奏；不依赖系统按键重复速度。
    @Default(4.0) double keyboardPageTurnPagesPerSecond,
    @Default(350) int keyboardPageTurnHoldDelayMs,
    @Default(true) bool comicReadTopContainer,
    @Default(0) int readMode,
    @Default(ReaderTapPageTurnMode.rightHand)
    ReaderTapPageTurnMode tapPageTurnMode,
    @Default(false) bool tapPageTurnInWebtoon,
    @Default(false) bool reverseHorizontalPageTurn,
    // 跨版本同步的**降级**约束，不是可选的讲究：这一份 JSON 是云同步 `reader` 块的
    // 整个载荷，而 `$enumDecode` 碰到不认识的枚举名会**抛异常**（不是忽略该字段）。
    // 一个老客户端同步到 `adaptive` 之后，那台设备**所有**阅读设置都读不出来。
    // `unknownEnumValue` 让它降级成 `auto` —— 与老客户端自己的能力相符，
    // 它下次上传也只是把这个值写成 `auto`，不会把新值写坏。
    @JsonKey(unknownEnumValue: ReaderBackgroundMode.auto)
    @Default(ReaderBackgroundMode.auto)
    ReaderBackgroundMode readerBackgroundMode,
    // 自适应背景的压暗程度（0..85）。默认值见 [readerAmbientDimPercentDefault]。
    //
    // **必须住在全局设置里**：阅读页每个 route 一份 State，换书、换章都会重建，
    // 这个值得跨书、跨重启保持（与 `showThumbnailStrip` 同一条口径）。
    @Default(readerAmbientDimPercentDefault) int readerAmbientDimPercent,
    @Default(true) bool readFilterEnabled,
    @Default(50) int readFilterOpacityPercent,
    @Default(false) bool einkOptimization,
    @Default(120) int einkDelayMs,
    // 自动裁页面四周的白/黑余白：**显示时**放大内容区，一个像素都不改。
    //
    // 检测算法是 mImageViewer `margin_fit.rs` 的移植（Rust 侧
    // `rossi_local_core::margin_fit`），检测不了 / 满版出血 / 灰色背景一律返回
    // 「不裁」。放这里而不是阅读器 State：阅读页每个 route 一份 State，换书换章
    // 就重建，而这个值得跨书保持，并且要能被「本漫独立设置」逐本覆盖。
    @Default(false) bool autoTrimPageMargins,
    @Default(false) bool autoScroll,
    @Default(false) bool autoScrollHidePauseButton,
    @Default(false) bool autoScrollSmooth,
    @Default(1600) int autoScrollColumnIntervalMs,
    @Default(3000) int autoScrollPageIntervalMs,
    @Default(72) int autoScrollColumnDistancePercent,
    @Default(3) int preloadImageCount,
    @Default(1) int preloadChapterCount,
    @Default(true) bool readWhileDownloading,
    @Default(false) bool landscapeReader,
    @Default(false) bool doublePageMode,
    @Default(false) bool doublePageSeamless,
    @Default(false) bool doublePageLeadingBlank,
    @Default(false) bool splitLandscapePages,
    @Default(0) int landscapeSplitDirection,
    @Default(false) bool sidePaddingEnabled,
    @Default(10) int sidePaddingPercent,
    @Default(true) bool volumeKeyPageTurn,
    @Default(72) int volumeKeyPageTurnDistancePercent,
    @Default(false) bool doubleTapZoom,
    @Default(false) bool doubleTapOpenMenu,
    @Default(true) bool pageInfoShowPage,
    @Default(true) bool pageInfoShowNetwork,
    @Default(false) bool pageInfoShowBattery,
    @Default(true) bool pageInfoShowTime,
    @Default(ReaderInfoVerticalPosition.bottom)
    ReaderInfoVerticalPosition pageInfoVerticalPosition,
    @Default(false) bool pageInfoTopInStatusBar,
    @Default(ReaderInfoHorizontalPosition.left)
    ReaderInfoHorizontalPosition pageInfoHorizontalPosition,
    @Default(12) int pageInfoEdgePadding,
    @Default(82) int pageInfoOpacityPercent,
    @Default(12) int pageInfoFontSize,
    // 视口底边那颗常驻进度条（neo `ReaderProgressLayer` 的「翻页进度」那一轨）：
    // 3 逻辑像素高的全宽细条，压在漫画上，**不随上下栏收起**、也不可拖动。
    //
    // 与上面那颗信息胶囊**各管各的开关**（照 neo 的 `pageInfoVisible` /
    // `progressBarVisible` 两颗独立 toggle）：谁也不覆盖谁，可以同开、同关。
    // 默认关 —— 这条横条压在画面上，是看得见的改动，没进设置页的人不该被改观感。
    @Default(false) bool showBottomProgressBar,
    // 进度条填充端的一圈荧光（neo 的 `progressBarGlow`）。只在横条开着时有意义，
    // 所以默认开不会给没启用横条的用户带来任何变化。
    @Default(true) bool bottomProgressBarGlow,
    @Default(true) bool hoverRevealEnabled,
    @Default(true) bool hoverRevealTop,
    @Default(true) bool hoverRevealBottom,
    @Default(32) int hoverTriggerAreaTop,
    @Default(32) int hoverTriggerAreaBottom,
    @Default(500) int hoverHideDelayMs,
    @Default(false) bool hoverShowVisualIndicator,
    // 「点击阅读区唤出/收起上下栏」。关掉后单击不再显隐上下栏 —— 只能靠桌面端
    // 边缘悬停、或（若开着）双击打开操作栏唤出；条漫模式下「点哪儿都算中间」
    // 的那一条也一并关掉。
    // 默认 true = 改造前的行为，没进过设置页的用户零感知。
    @Default(true) bool centerTapToggleBars,
    // 顶栏 / 底栏「钉住」。口径照 neo 的 edge `pinned`（`ReaderShellControlStore`）：
    // 钉住 = 常开，点中间收起、离开边缘都不再能动它；取消钉住 = 交还给
    // 「点中间 + 边缘悬停」那套自动收起。
    //
    // 与 `showThumbnailStrip` 同样**必须住在全局设置里**：阅读页每个 route 一份
    // State，换书、换章都会重建，钉没钉住得跨书、跨重启保持。
    @Default(false) bool topBarPinned,
    @Default(false) bool bottomBarPinned,
    // 底部缩略图条是否展开（与进度条同处一块玻璃面板）。
    //
    // **必须住在全局设置里，不能放阅读页的 State**：阅读页每个 route 一份
    // `_BottomWidgetState`，换书（`router.replace` 会换 key 重建整棵子树）、
    // 甚至同一本换章都会重建，开关会被「重置」回默认值。放这里则跟其他阅读
    // 设置一样持久化、跨书跨重启保持。
    @Default(false) bool showThumbnailStrip,
    // 默认统一竖向卡片；开启后完整显示原图比例，跨书、重启与同步保持。
    @Default(false) bool thumbnailStripOriginalAspectRatio,
    // 顶栏「透明」档：跳过液态玻璃，改为一层半透明蒙层铺在画面上
    // （口径照 JHenTai 阅读页的 `readPageMenuColor = black 85%`），
    // 画面从顶栏底下透出来，顶栏不再是一块「材质」。
    //
    // 默认关 = 改造前的观感（最实的一档玻璃）。蒙层颜色取主题的 `surface`，
    // 于是**文字与图标一个都不用改色**（onSurface 对 surface 的对比度天然成立）；
    // 不透明度见 [topBarScrimOpacityPercent]。
    //
    // 与 `topBarPinned` / `showThumbnailStrip` 同样必须住在全局设置里：
    // 换书、换章都会重建阅读页那棵子树，住在页面 State 里会被重置。
    @Default(false) bool transparentTopBar,
    // 透明档下蒙层的不透明度（%）。0 = 完全透明 —— 顶栏只剩文字浮在画面上。
    // 只在 [transparentTopBar] 打开时有意义；默认 85 与 JHenTai 同一档
    // （可读性优先，想要真透明就往下拖）。读的时候一律再夹一次，
    // 因为这个值可能来自云端同步或旧版本。
    @Default(85) int topBarScrimOpacityPercent,
    // 顶栏「阅读方向」切换按钮（左开 ⇄ 右开）。
    //
    // 只在横翻模式（readMode 1/2）下可用：单击切换方向，**不动阅读位置**
    // （两个模式同属 RowModeWidget，槽位含义不变，方向只是翻页语义反过来）。
    // 条漫（readMode 0）没有左右翻页方向，按钮置灰。
    // 默认 true = neo 的行为：方向是阅读里的高频操作，值得一个常驻入口。
    @Default(true) bool readingDirectionToggle,
    // ── 顶栏缩放/旋转面板（neo N-11）的可持久化那一半 ──────────────────────
    //
    // 口径照 neoview 的 `viewDefaults` 分界：只有「看完这一页还想保持」的三档
    // 落盘，**手动缩放比例与手动旋转角度刻意不在这里** —— 那边把它们记成
    // session-only，因为「这一页放大看个细节」不该跟到下一本书去。
    // 那两个住在 `ReaderPresentationCubit`（阅读页一份，换书即重置）。
    @Default(ReaderFitMode.fit) ReaderFitMode readerFitMode,
    @Default(ReaderAutoRotation.none) ReaderAutoRotation readerAutoRotation,
    // 默认 `none` = 改造前的样子（双页各画各的，两张图高低不齐）。
    // neo 的默认是 `uniform-height`，那是它把整帧当一个单位铺排的结果；
    // 这里先按不回归既有观感取值，想要 neo 那一档在顶栏面板里点一下就有。
    @Default(ReaderWidePageStretch.none)
    ReaderWidePageStretch readerWidePageStretch,
    // 翻页时**每个槽位都画这一页自己的位图**，不再用「大字页码」占位。
    //
    // 要解决的问题：共享纹理只有一张、且归当前页用，而滑动期间旧页与新页
    // 谁都不是当前页 —— 于是翻页时先看到半个屏幕的大字号码（`fontSize: 150`），
    // 等滑动过半、当前页落定、`present` 回来才换成画面。
    //
    // 打开之后：进场那一半在它还是邻页时就把位图解好了，退场那一半在它还是
    // 当前页时顺手留了一份，两边都有像素，全程没有号码、也没有空窗。
    //
    // **代价说清楚**：每页多解一次「视口宽度」的位图（不是全尺寸），并且在上屏
    // 期间留着它。所以这一项是**可关**的，而且默认开 = 用户要的「直接出图」，
    // 关掉即回到改制前的行为（邻页只画号码，上屏成功就释放位图）。
    @Default(true) bool swipePreviewEnabled,
    // ── 页面排序（顶栏「排序」面板）────────────────────────────────────────
    //
    // 只存**档位**；手动那一档的具体排列活在阅读会话里
    // （`ReaderPageOrderCubit`）。理由是排列是按「这一章的页表」下标写的，
    // 换一本书、甚至图源重新给出页表，那些下标就不再指向同一页 —— 落盘等于
    // 把一份对不上号的索引留给下一本书。
    @JsonKey(unknownEnumValue: ReaderPageOrderMode.source)
    @Default(ReaderPageOrderMode.source)
    ReaderPageOrderMode readerPageOrderMode,
    // ── 幻灯片（顶栏「幻灯片」面板）────────────────────────────────────────
    //
    // 与上面那组 `autoScroll*` **各管各的**：自动滚屏是按像素连续滚，
    // 幻灯片是「一页停 N 秒」整页推进，并且带结束策略（停 / 循环本章 / 续下一章）。
    // 两者可以同时开着读同一份阅读模式，但计时器各自独立，不会互相抢翻页。
    @Default(false) bool slideshowEnabled,
    @JsonKey(unknownEnumValue: ReaderSlideshowEndAction.stop)
    @Default(ReaderSlideshowEndAction.stop)
    ReaderSlideshowEndAction slideshowEndAction,
    @Default(4000) int slideshowIntervalMs,
    @Default(100) int slideshowColumnStepPercent,
    // 放映时的页码驻留指示：放映需要一个「现在放到第几页 / 还有多久」的回读，
    // 否则开关是否真的生效只能靠猜（与缩略图条、进度条同一口径）。
    @Default(true) bool slideshowShowProgress,
    // ── 放大镜（顶栏「放大镜」面板）──────────────────────────────────────
    @Default(false) bool magnifierEnabled,
    @JsonKey(unknownEnumValue: ReaderMagnifierMode.auto)
    @Default(ReaderMagnifierMode.auto)
    ReaderMagnifierMode magnifierMode,
    // 倍率取整数百分比而不是 double：这一份要进云同步 JSON，
    // 而 float 在不同编解码器之间的末位差异会让「同步回来的设置」和上传的不完全等值。
    @Default(300) int magnifierZoomPercent,
    @Default(220) int magnifierSizeLogical,
    // 锁止 = 松手/移开鼠标后窗口不消失，靠拖窗口本身移动。
    // 检端部细节时这才有意义：不锁的话指针一挪出页面，取样窗口跟着没了。
    @Default(false) bool magnifierLocked,
  }) = _ReadSettingState;

  factory ReadSettingState.fromJson(Map<String, dynamic> json) =>
      _$ReadSettingStateFromJson(json);
}

@freezed
abstract class EInkSettingState with _$EInkSettingState {
  const EInkSettingState._();

  const factory EInkSettingState({
    /// 墨水屏模式总开关。命中 e-ink 设备时首启自动打开，用户手动关掉后不再自动开启。
    @Default(false) bool enabled,

    /// 设备检测是否已经处理过一次，避免每次启动都覆盖用户的选择。
    @Default(false) bool detectionHandled,

    /// 页面跳转不做滑动/淡入动画，直接出图。
    @Default(true) bool noRouteTransition,

    /// 滚动到边界不回弹。
    @Default(true) bool noScrollBounce,

    /// 图片加载占位不转圈（转圈会驱动墨水屏持续局刷，残影很重）。
    @Default(true) bool noLoadingSpinner,

    @Default(EinkRefreshMode.fullFlash) EinkRefreshMode refreshMode,

    /// 每翻多少页自动整屏刷新一次；0 表示不自动刷新。
    @Default(5) int autoRefreshEveryNTurns,

    @Default(true) bool showRefreshButton,
  }) = _EInkSettingState;

  factory EInkSettingState.fromJson(Map<String, dynamic> json) =>
      _$EInkSettingStateFromJson(json);

  bool get shouldRemoveRouteTransition => enabled && noRouteTransition;

  bool get shouldRemoveScrollBounce => enabled && noScrollBounce;

  bool get shouldRemoveLoadingSpinner => enabled && noLoadingSpinner;

  bool get canFullRefresh => enabled && refreshMode != EinkRefreshMode.none;

  int get autoRefreshTurns => autoRefreshEveryNTurns.clamp(0, 50);
}

@freezed
abstract class BookshelfSettingState with _$BookshelfSettingState {
  const factory BookshelfSettingState({
    @Default(0) int homePageIndex,
    @Default(false) bool rememberFavoriteSort,
    @Default('dd') String favoriteSort,
    @Default(false) bool rememberHistorySort,
    @Default('dd') String historySort,
    @Default(false) bool rememberDownloadSort,
    @Default('dd') String downloadSort,
    // 漫画列表横排详情样式（web 风）：开启后列表显示为含作者/分类的横排详情行。
    // 默认关，保持网格观感；上游在设置-外观页放了开关。
    @Default(false) bool detailLayout,
    // 漫画详情页章节列表默认倒序显示。
    @Default(false) bool reverseChapters,
    // 收藏 / 历史卡片的条目右键菜单（触摸端长按）。默认开 —— 默认值取「改造后的
    // 行为」，因为菜单本身不改动任何既有交互（单击打开照旧），关掉即回到纯点击。
    @Default(true) bool shelfCardContextMenu,
  }) = _BookshelfSettingState;

  factory BookshelfSettingState.fromJson(Map<String, dynamic> json) =>
      _$BookshelfSettingStateFromJson(json);
}
