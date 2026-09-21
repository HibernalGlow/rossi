// 全局设置

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// `JsonKey`（下面 `readerBackgroundMode` 上的跨版本降级要用）由 freezed_annotation
// 一并重导出，不必单独 import json_annotation。
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/json/converter.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';
import 'package:zephyr/util/text/tag_text.dart';

part 'global_setting.freezed.dart';
part 'global_setting.g.dart';

enum ReaderInfoVerticalPosition { top, bottom }

enum ReaderInfoHorizontalPosition { left, center, right }

/// 阅读背景档位。
///
/// `auto` 是「跟随主题明暗」，`adaptive` / `adaptiveEdge` 是「从当前画面取色」——
/// 两者不是一回事，所以 `adaptive` **不能**复用 `auto` 这个名字。
///
/// 后两档只在**本地漫画（GPU 上屏那条路）**生效：取色要的是已经解出来的页面像素，
/// 而那批像素只在呈现器里。在线漫画回落成 `auto` 的底色，见
/// [ReadSettingStateBackgroundColor.resolveReaderBackgroundColor]。
enum ReaderBackgroundMode { auto, black, white, grey, adaptive, adaptiveEdge }

enum ReaderTapPageTurnMode { fullScreen, leftHand, rightHand }

enum SyncServiceType { none, webdav, s3 }

/// 代理协议类型。
enum ProxyType { http, socks5 }

/// 提示条（toast）在屏幕上的停靠位置，九宫格。
///
/// 口径参考 neoview 的「提示悬浮窗」：位置可配、可调边距，
/// 对应关系 [ToastPosition.topLeft] → `Alignment.topLeft` 等。
enum ToastPosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

extension ToastPositionExtension on ToastPosition {
  String get label {
    switch (this) {
      case ToastPosition.topLeft:
        return t.settings.toastPositionTopLeft;
      case ToastPosition.topCenter:
        return t.settings.toastPositionTopCenter;
      case ToastPosition.topRight:
        return t.settings.toastPositionTopRight;
      case ToastPosition.middleLeft:
        return t.settings.toastPositionMiddleLeft;
      case ToastPosition.center:
        return t.settings.toastPositionCenter;
      case ToastPosition.middleRight:
        return t.settings.toastPositionMiddleRight;
      case ToastPosition.bottomLeft:
        return t.settings.toastPositionBottomLeft;
      case ToastPosition.bottomCenter:
        return t.settings.toastPositionBottomCenter;
      case ToastPosition.bottomRight:
        return t.settings.toastPositionBottomRight;
    }
  }
}

extension SyncServiceTypeExtension on SyncServiceType {
  String get label {
    switch (this) {
      case SyncServiceType.none:
        return t.common.disabled;
      case SyncServiceType.webdav:
        return 'WebDAV';
      case SyncServiceType.s3:
        return 'S3';
    }
  }
}

// 简繁转换模式:off 不转换;simplified 转简体;traditional 转繁体
enum ChineseConvertMode { off, simplified, traditional }

extension ChineseConvertModeExtension on ChineseConvertMode {
  String get label {
    switch (this) {
      case ChineseConvertMode.off:
        return t.settings.chineseConvertOff;
      case ChineseConvertMode.simplified:
        return t.settings.chineseConvertSimplified;
      case ChineseConvertMode.traditional:
        return t.settings.chineseConvertTraditional;
    }
  }

  // 对应的 OpenCC 配置文件名;off 时返回空字符串(不转换)
  String get openccConfig {
    switch (this) {
      case ChineseConvertMode.off:
        return '';
      case ChineseConvertMode.simplified:
        return 'tw2sp.json';
      case ChineseConvertMode.traditional:
        return 's2twp.json';
    }
  }
}

const Color readerBackgroundBlack = Colors.black;
const Color readerBackgroundWhite = Colors.white;
const Color readerBackgroundGrey = Color(0xFF2D2D2D);

extension ReadSettingStateBackgroundColor on ReadSettingState {
  /// **静态**底色。
  ///
  /// 自适应档位返回的是**兜底**底色而不是取色结果，这是刻意的：
  /// 取色是一条异步链路（翻页 → 呈现 → 探针 → 插值），它到得比首帧晚。
  /// 把动态色并进这个函数，就等于让"取色到了"变成一次
  /// `readSetting` 变化 —— 而所有 `context.select(readSetting)` 的地方
  /// （含整棵阅读子树）都会跟着重建。动态色只走
  /// `ReaderAmbientBackground` 那一层，见那里的说明。
  Color resolveReaderBackgroundColor(Brightness brightness) {
    switch (readerBackgroundMode) {
      case ReaderBackgroundMode.auto:
      // 自适应档位的兜底底色与 `auto` 同值：取色还没到、或这一本是在线漫画
      // （取色那条路不适用）时，看到的应当是一个**用户预期内的**颜色 ——
      // 跟随主题明暗就是那个颜色，而不是一块没来由的灰。
      case ReaderBackgroundMode.adaptive:
      case ReaderBackgroundMode.adaptiveEdge:
        return brightness == Brightness.dark
            ? readerBackgroundBlack
            : readerBackgroundWhite;
      case ReaderBackgroundMode.black:
        return readerBackgroundBlack;
      case ReaderBackgroundMode.white:
        return readerBackgroundWhite;
      case ReaderBackgroundMode.grey:
        return readerBackgroundGrey;
    }
  }

  Color resolveReaderForegroundColor(Brightness brightness) {
    final backgroundColor = resolveReaderBackgroundColor(brightness);
    return backgroundColor.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;
  }

  /// 当前档位是不是「从当前画面取色」那一类。
  ///
  /// 抽成纯函数而不是在调用点写 `mode == adaptive || mode == adaptiveEdge`：
  /// 调用点有两处（呈现链路决定要不要去读探针、背景层决定要不要用调色板），
  /// 而**这两处必须同时为真**功能才成立 —— 分开写就会出现
  /// 「读了探针但背景层不理」这种白花钱的组合。
  bool get readerAmbientEnabled =>
      readerBackgroundMode == ReaderBackgroundMode.adaptive ||
      readerBackgroundMode == ReaderBackgroundMode.adaptiveEdge;

  /// 取色后铺成「边缘渐变」还是「单色」。
  bool get readerAmbientEdge =>
      readerBackgroundMode == ReaderBackgroundMode.adaptiveEdge;
}

/// 自适应背景的**压暗程度**允许范围与默认值。
///
/// 默认 45（= 保留 55% 亮度）取自参考实现的实测档位：neoview 的
/// `ReaderBackgroundLayer.css` 用的是 `brightness(0.48)`（流光溢彩）与
/// `brightness(0.56)`（自动匹配）。取色来自页面**边沿**，而漫画页的边沿常常就是
/// 白纸 —— 不压暗的话，白底漫画在暗环境里就是一块刺眼的光斑。
const int readerAmbientDimPercentMin = 0;
const int readerAmbientDimPercentMax = 85;
const int readerAmbientDimPercentDefault = 45;

/// 阅读设置的读入口（**不依赖 `BuildContext`**）。
///
/// 与 [toastSetting] 同一口径：调用点（呈现链路在翻页后决定要不要去读探针）
/// 拿不到 Cubit，而这里读的只是一份内存里的本地库快照。
/// 本地库还没起来（启动早期）或已关闭时回落到默认值 ——
/// 绝不让「读设置」本身把取色链路炸掉。
ReadSettingState get readSettingSnapshot {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.readSetting ??
        const ReadSettingState();
  } catch (_) {
    return const ReadSettingState();
  }
}

GlobalSettingState get globalSetting {
  return objectbox.userSettingBox.get(1)!.globalSetting;
}

/// 提示条设置的读入口。
///
/// 提示（toast）会在**任意时刻**被触发（后台下载完成、同步失败……），
/// 这些调用点多半拿不到 `BuildContext`/Cubit，所以这里直接从本地库读；
/// 本地库还没起来（启动早期）或已关闭时回落到默认样式 ——
/// 绝不让「读设置」本身把提示炸掉。
ToastSettingState get toastSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.toastSetting ??
        const ToastSettingState();
  } catch (_) {
    return const ToastSettingState();
  }
}

@freezed
abstract class GlobalSettingState with _$GlobalSettingState {
  const factory GlobalSettingState({
    @Default(true) bool dynamicColor,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool isAMOLED,
    @ColorConverter() @Default(Color(0xFFEF5350)) Color seedColor,
    // 导入的 tweakcn / shadcn 主题：`TweakcnTheme.encode()` 的 JSON 串，空串 = 未导入。
    // 存**解析后的 token 表**而不是原始 CSS：解析只在导入那一次发生，
    // 每次主题重建只是 jsonDecode，且同步 / 导出时人能直接读懂。
    @Default('') String tweakcnThemeJson,
    // 导入的主题是否生效。与 [tweakcnThemeJson] 分开，是为了「先导入存着、随时开关」。
    @Default(false) bool tweakcnThemeEnabled,
    @Default(0) int themeInitState,
    @LocaleConverter() @Default(Locale('zh', 'CN')) Locale locale,
    @Default(true) bool localeFollowsSystem,
    @Default(0) int welcomePageNum,
    @Default(SyncSettingState()) SyncSettingState syncSetting,
    @Default([]) List<String> maskedKeywords,
    @Default(true) bool socks5ProxyEnabled,
    @Default('') String socks5Proxy,
    @Default(false) bool needCleanCache,
    @Default(1) int comicChoice,
    @Default(false) bool disableBika,
    @Default(false) bool enableMemoryDebug,
    @Default(false) bool blockRustHttpRequests,
    @Default('') String logAddress,
    // 布局溢出时那条「黄黑斜纹」画不画。默认开 ＝ Flutter 原生行为（改造前的行为）。
    // 关掉只覆盖**我们自己造的 Flex** 与错误上报 —— 框架没有全局开关，
    // 口径与适用范围见 `lib/util/layout/layout_overflow_guard.dart` 顶部。
    @Default(true) bool showLayoutOverflowStripes,
    @Default(false) bool forceEnableImpeller,
    @Default(false) bool androidKeepAliveEnabled,
    @Default(false) bool backPressExitEnabled,
    @Default(true) bool updateAccelerate,
    @Default(true) bool retryDownloadUntilSuccess,
    @Default(3) int downloadConcurrency,
    @Default(150) int downloadDelayMs,
    @Default(3) int downloadAutoRetryCount,
    @Default(false) bool oldPageRollbackEnabled,
    @Default(false) bool cloudFavoritePreferred,
    @Default(false) bool autoFollowOnCollect,
    @Default(false) bool autoFavoriteOnDownload,
    // 下载完成后是否在下载目录的漫画根目录留下元数据 JSON（见 download_metadata_writer.dart）。
    // 默认关：下载目录本来就是「hash 目录 + hash 文件名」，只有 ObjectBox 认得，
    // 多写两份 JSON 属于用户主动要的可移植性，不该默认改变磁盘内容。
    @Default(false) bool writeDownloadMetadataFile,
    @Default(false) bool leftHandModeEnabled,
    @Default(false) bool clickCoverToStartReading,
    // 详情页「阅读」入口：桌面端放进操作行（「下载」旁边），并撤掉右下角的悬浮按钮。
    // 触摸端不受这个开关影响 —— 那边只有悬浮按钮一种落点。
    @Default(true) bool comicInfoInlineReadButton,
    // 详情页左右那颗悬浮胶囊用液态玻璃还是实底（`surfaceContainerHigh`）。
    //
    // **默认开**，与 `ToastSettingState.liquidGlass`（默认关）不一致，理由是刻意的：
    // 提示条那条要保住改造前的观感，而 rail 是新控件、没有旧观感可保护，且用户
    // 2026-09-21 点名要玻璃。关掉仍然能看清本体（实底 + 描边 + elevation）。
    @Default(true) bool comicInfoRailLiquidGlass,
    // 启动后是否直接进工作台（泳道 / 四边栏）。默认关 = 改造前的行为（落在导航栏）。
    // 只在**真有工作台入口**的布局（平板 / 桌面四边栏）落地，手机端忽略 ——
    // 判定收在 `lib/workspace/model/workspace_startup.dart`。
    @Default(false) bool startWithWorkspace,
    // 桌面端自制标题栏（`lib/widgets/desktop/custom_title_bar.dart`）改不改成
    // **透明浮层**：不再占那 40px，内容顶到窗口顶部，标题栏只把应用名与窗口按钮
    // 浮在画面上。口径照 JHenTai 桌面端的 `TitleBarStyle.hidden` + 透明窗口背景。
    //
    // 默认关 = 改造前的样子（一条 40px 的实色栏占在内容之上），没进过设置页的
    // 用户零感知。桌面三平台之外不读它（手机端根本没有这条栏）。
    // 摆放判定收在 `resolveDesktopTitleBarPlacement`，判据不用起整个 app。
    @Default(false) bool transparentDesktopTitleBar,
    // 透明标题栏的**摆放方式**：false = 独立行（栏仍占一行、只是不带底色，
    // 与页面背景连成一体，JHenTai 桌面端自制标题栏就是这一档），true =
    // 融合浮层（内容顶到窗口顶部，栏浮在画面上）。默认独立行。
    // 只在 transparentDesktopTitleBar 打开时才被读到；关着时它是死数据。
    @Default(false) bool transparentTitleBarFused,
    @Default([]) List<String> searchHistory,
    @Default(ProxySettingState()) ProxySettingState proxySetting,
    @Default(1280.0) double windowWidth,
    @Default(720.0) double windowHeight,
    @Default(0) double windowX,
    @Default(0) double windowY,
    @Default(ReadSettingState()) ReadSettingState readSetting,
    @Default('') String customExportPath,
    @Default(AppLockSettingState()) AppLockSettingState appLockSetting,
    @Default("") String compatibleVersion,
    @Default(CacheSettingState()) CacheSettingState cacheSetting,
    @Default(ChineseConvertMode.off) ChineseConvertMode chineseConvertMode,
    @Default(BookshelfSettingState()) BookshelfSettingState bookshelfSetting,
    @Default(FavoriteArtistSettingState())
    FavoriteArtistSettingState favoriteArtistSetting,
    @Default(FavoriteTagSettingState())
    FavoriteTagSettingState favoriteTagSetting,
    @Default(ComicCardSettingState()) ComicCardSettingState comicCardSetting,
    @Default(ToastSettingState()) ToastSettingState toastSetting,
    @Default(SwitchToastSettingState())
    SwitchToastSettingState switchToastSetting,
    @Default(FileManagerSettingState())
    FileManagerSettingState fileManagerSetting,
    @Default(DiscoverSettingState()) DiscoverSettingState discoverSetting,
    @Default(OperationBindingSettingState())
    OperationBindingSettingState operationBindingSetting,
  }) = _GlobalSettingState;

  factory GlobalSettingState.fromJson(Map<String, dynamic> json) =>
      _$GlobalSettingStateFromJson(json);
}

/// 文件管理器卡片（工作台里的本地文件浏览）的跨重启偏好。
///
/// 为什么这些不放卡片的 State，而放全局设置：工作台的卡片会被整棵重建
/// （换布局、收起再展开、重启），住在 `State` 里的值表现为「一换布局就重置」。
/// 需要「设了以后一直在」的东西一律走这里。
///
/// - [homeEnabled]：工具栏是否显示主页键。默认开。
/// - [homePath]：主页目录，空串表示未设置。真正的校验在 Rust 侧
///   （`FileManagerState::set_home_path` 只接受存在的目录），这里只保存用户的选择。
/// - [openHomeOnStart]：新建会话时是否直接落在主页目录。默认关 = 落在系统默认目录。
///   与 [homeEnabled] 同样只在主页键开着时生效 —— 那一节整体关掉后，
///   启动落点不该偷偷跟着走。
/// - [rememberViewState]：记住每个目录的视图与排序（写进 `settings.db` 的
///   `file_manager_view_states` 表）。默认开；关掉之后浏览照常，只是不再读写目录偏好。
/// - [fileOperations]：**写操作的总开关**（复制 / 移动 / 重命名 / 新建 / 删除）。
///   默认开；关掉之后文件浏览器回到「只看不改」—— 没有右键菜单、没有多选、
///   没有操作条。之所以给它一个总开关而不是逐个动作给：这一层第一次具备了
///   **修改用户磁盘**的能力，而这类能力的方向应该是「默认给了，但随时能整个收回去」，
///   不是「一样一样地关」（那样关到一半是最糟的状态）。
@freezed
abstract class FileManagerSettingState with _$FileManagerSettingState {
  const factory FileManagerSettingState({
    @Default(true) bool homeEnabled,
    @Default('') String homePath,
    @Default(false) bool openHomeOnStart,
    @Default(true) bool rememberViewState,
    @Default(true) bool fileOperations,
  }) = _FileManagerSettingState;

  factory FileManagerSettingState.fromJson(Map<String, dynamic> json) =>
      _$FileManagerSettingStateFromJson(json);
}

/// 发现页标签条摆在哪一条边上。
///
/// 与 `plat` 的 `TabBarSide` 一一对应，但**不在这里 import 那个包**：
/// 设置模型是持久层，不该被一个 UI 依赖拖着走（哪天换掉那个包，
/// 用户存的值不该跟着变成一串读不出来的整数）。
enum DiscoverTabBarSide {
  /// 横向：标签条就是发现页顶栏那一行。
  top('横向（顶栏）'),

  /// 竖向：标签轨在内容左边。
  left('竖向（左侧）'),

  /// 竖向：标签轨在内容右边。
  right('竖向（右侧）');

  const DiscoverTabBarSide(this.label);

  /// 设置项上的中文名（这个枚举只有三个值，不值得走 i18n 词条）。
  final String label;
}

/// 发现页**标签条**的显示口径。
///
/// 为什么放全局而不是页面的 State：标签条在发现页活着的时候才画得出来，
/// 而用户调完这几颗想看的效果是「以后每次都是这样」—— 关掉应用再开不该弹回去。
///
/// - [tabIconEnabled]：标签上画不画插件图标。关掉之后只剩文字，窄轨上能多塞几条。
/// - [tabPluginShortEnabled]：标签上画不画插件名缩写（「绅士 · 排行」里那截「绅士」）。
///   两个都关掉就只剩功能名 —— 那时同一功能的多个标签只能靠序号分辨。
/// - [tabSide]：标签条的朝向与靠边（见 [DiscoverTabBarSide]）。
@freezed
abstract class DiscoverSettingState with _$DiscoverSettingState {
  const factory DiscoverSettingState({
    @Default(true) bool tabIconEnabled,
    @Default(true) bool tabPluginShortEnabled,
    @Default(DiscoverTabBarSide.top) DiscoverTabBarSide tabSide,
  }) = _DiscoverSettingState;

  factory DiscoverSettingState.fromJson(Map<String, dynamic> json) =>
      _$DiscoverSettingStateFromJson(json);
}

/// 操作绑定（ADR-0015）的持久化。
///
/// [bindingsJson] 存的是**引擎的绑定包**（`InputBindingsConfig` 的 JSON，
/// schema 的权威在 `rossi_local_core::operation_binding`）：Dart 侧只当字符串拿着，
/// 需要时整串喂给 FRB。这里**不建**一套 Dart 强类型镜像 —— 建了就得跟着 schema 改生成物，
/// 而 ADR-0015 要的是「换外壳时绑定表零改动」。
///
/// 空串 = 还没播种（首次启动会用出厂预设填上）。播种前后 [bindingsRuntime]
/// 判定都要能成立，所以运行时的回退是「表是空的 → 走改造前的硬编码分区」，
/// 而不是「什么都不做」—— 那等于把阅读器锁死。
@freezed
abstract class OperationBindingSettingState
    with _$OperationBindingSettingState {
  const factory OperationBindingSettingState({
    /// 总开关：开=按键/点击经绑定表解析；关=走改造前的硬编码判断。
    @Default(true) bool bindingsRuntime,
    @Default('') String bindingsJson,

    /// 轮盘的**形状**（核心 `RadialConfig` 的 JSON：几个轮盘 / 几层 / 半径 /
    /// 生效项，外加轮盘自己的总开关）。
    ///
    /// 为什么不并进 [bindingsJson]：两者是两件事 —— 这份只有形状，槽位「干什么」
    /// 仍然是绑定表里那些 `device: radial` 的行。于是轮盘与键盘、点击同权，
    /// 共用同一个解析器与同一套冲突判定，不需要为它写第二遍判断。
    /// 空串 = 还没播种（首次启动用核心的出厂值填上）。
    @Default('') String radialJson,
  }) = _OperationBindingSettingState;

  factory OperationBindingSettingState.fromJson(Map<String, dynamic> json) =>
      _$OperationBindingSettingStateFromJson(json);
}

/// 提示条（toast）的位置、时长与外观。
///
/// 字段口径（对齐 neoview 的 switchToast 配置，落到 Flutter 的九宫格 + 尺寸）：
/// - [position] / [edgePadding]：停靠位置与距屏幕边缘的安全留白；
/// - [durationMs]：自动关闭时长，`0` 表示常驻（只能手动关闭）；
/// - [maxWidth]：卡片最大宽度（手机端还会被屏幕宽度再夹一次）；
/// - [opacityPercent]：整卡不透明度；
/// - [maxVisible]：同屏最多堆叠条数，超出时挤掉最旧的一条；
/// - [animationDurationMs]：进出场动画时长；
/// - [liquidGlass]：液态玻璃（模糊 + 半透明）背景；
/// - [showProgressBar] / [showIcon] / [showCloseButton]：进度条、类型图标、关闭按钮。
@freezed
abstract class ToastSettingState with _$ToastSettingState {
  const factory ToastSettingState({
    @Default(ToastPosition.topRight) ToastPosition position,
    @Default(12) int edgePadding,
    @Default(3000) int durationMs,
    @Default(400) int maxWidth,
    @Default(100) int opacityPercent,
    @Default(3) int maxVisible,
    @Default(220) int animationDurationMs,
    @Default(false) bool liquidGlass,
    @Default(true) bool showProgressBar,
    @Default(true) bool showIcon,
    @Default(true) bool showCloseButton,
  }) = _ToastSettingState;

  factory ToastSettingState.fromJson(Map<String, dynamic> json) =>
      _$ToastSettingStateFromJson(json);
}

/// 「切换提示」（neoview N-17 switch-toast）的触发开关与文案模板。
///
/// 上游卡片里「提示悬浮窗」那一节（X/Y、透明度、液态玻璃）**不在这里** ——
/// Rossi 的提示条外观统一由 [ToastSettingState] 的九宫格 + 尺寸负责
/// （见 `toast_setting_page`），本设置只管「什么时候提示、提示什么」。
/// 上游的 `enableAction` / `enableBoundaryToast` 在 Rossi 还没有统一的
/// 按键执行 / 边界翻页挂点，本轮不搬（口径登记在 `docs/ROADMAP.md`）。
@freezed
abstract class SwitchToastSettingState with _$SwitchToastSettingState {
  const factory SwitchToastSettingState({
    /// 切换书籍（含首次进入一本书）时显示提示。上游同款：默认关。
    @Default(false) bool enableBook,

    /// 翻页时显示提示。
    @Default(false) bool enablePage,

    /// 模板变量为 `{{book.*}}` / `{{page.*}}`，语义与上游
    /// `renderReaderSwitchToastTemplate` 逐条对照（见
    /// `lib/util/toast/switch_toast_template.dart`）。
    @Default(
      '已切换到 {{book.displayName}}（第 {{book.currentPageDisplay}} / {{book.totalPages}} 页）',
    )
    String bookTitleTemplate,
    @Default('路径：{{book.path}}') String bookDescriptionTemplate,
    @Default('第 {{page.indexDisplay}} / {{book.totalPages}} 页')
    String pageTitleTemplate,

    /// 上游默认是「分辨率 + 文件大小」，但 Rossi 的页表（`Doc`）没有这两项，
    /// 换成页文件名 —— 刻意偏离，见 `docs/ROADMAP.md`。
    @Default('{{page.name}}') String pageDescriptionTemplate,
  }) = _SwitchToastSettingState;

  factory SwitchToastSettingState.fromJson(Map<String, dynamic> json) =>
      _$SwitchToastSettingStateFromJson(json);
}

/// 切换提示设置的读入口（非 widget 上下文也能读）。
///
/// 与 [toastSetting] 同理：运行时在**任意时刻**由会话总线触发，拿不到 Cubit，
/// 「读设置」本身绝不能把提示炸掉。
SwitchToastSettingState get switchToastSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.switchToastSetting ??
        const SwitchToastSettingState();
  } catch (_) {
    return const SwitchToastSettingState();
  }
}

@freezed
abstract class FavoriteArtistSettingState with _$FavoriteArtistSettingState {
  const factory FavoriteArtistSettingState({
    @Default(true) bool highlightEnabled,
    @Default([]) List<String> artists,
    // 社团名算不算命中。默认 fallbackOnly：只有这条本子拿不出画师证据时才认社团，
    // 因为社团名最容易撞上汉化组与活动名。口径见 `FavoriteArtistCircleMode`。
    @Default(FavoriteArtistCircleMode.fallbackOnly)
    FavoriteArtistCircleMode circleMode,
  }) = _FavoriteArtistSettingState;

  factory FavoriteArtistSettingState.fromJson(Map<String, dynamic> json) =>
      _$FavoriteArtistSettingStateFromJson(json);
}

/// 一条收藏的 tag。
///
/// [name] 是给用户看的本名（也是高亮徽标上写的那个词），[aliases] 是同一个 tag
/// 在各个图源里的其它写法。别名必须是显式登记的：匹配只做归一化后的整串相等
/// （见 `TagText.normalize`），刻意不做子串兜底 —— `lolita` 命中 `school_lolita`
/// 那种放宽在画师上尚可、在 tag 上会把列表刷成一片琥珀色。
///
/// 为什么需要别名：同一含义在不同网站拼法不同（`school_lolita` / `School Lolita` /
/// `学校萝莉`），插件给回的原始串对不上就没有高亮。归一化已经吃掉了大小写、
/// 全半角和 `_`／空格这三类差异，剩下的是真正的不同词，只能由用户登记。
@freezed
abstract class FavoriteTag with _$FavoriteTag {
  const factory FavoriteTag({
    @Default('') String name,
    @Default([]) List<String> aliases,
  }) = _FavoriteTag;

  factory FavoriteTag.fromJson(Map<String, dynamic> json) =>
      _$FavoriteTagFromJson(json);
}

@freezed
abstract class FavoriteTagSettingState with _$FavoriteTagSettingState {
  const factory FavoriteTagSettingState({
    @Default(true) bool highlightEnabled,
    @Default([]) List<FavoriteTag> tags,
  }) = _FavoriteTagSettingState;

  factory FavoriteTagSettingState.fromJson(Map<String, dynamic> json) =>
      _$FavoriteTagSettingStateFromJson(json);
}

/// 归一化键 → 条目，用于收藏 tag 的去重与定位。
///
/// 比较一律走 [TagText.normalize]：添加、删除、批量导入与匹配必须同一个口径，
/// 否则「列表里看着是两条、匹配时算成一条」这类裂缝就会出现（喜欢画师那份就留了
/// 这个裂缝，见 `FavoriteArtistMatcher.normalizeArtist` 与 `addFavoriteArtist`）。
int? _indexOfFavoriteTag(List<FavoriteTag> tags, String key) {
  if (key.isEmpty) return null;
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    if (TagText.normalize(tag.name) == key) return i;
    if (tag.aliases.any((a) => TagText.normalize(a) == key)) return i;
  }
  return null;
}

/// 洗一条别名列表：去空白、按归一化键去重、丢掉与本名同形的那条。
List<String> _cleanTagAliases(
  Iterable<String> aliases, {
  required String nameKey,
}) {
  final seen = <String>{};
  final cleaned = <String>[];
  for (final alias in aliases) {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) continue;
    final key = TagText.normalize(trimmed);
    // 归一化后与本名相同的别名是纯噪声（匹配本来就等价），留着只会让列表变长。
    if (key.isEmpty || key == nameKey) continue;
    if (seen.add(key)) cleaned.add(trimmed);
  }
  return cleaned;
}

/// 整表规整：同名（归一化后）条目合并成一条，后来的那条只并进它的别名，空名条目丢弃。
List<FavoriteTag> _dedupeFavoriteTags(Iterable<FavoriteTag> input) {
  final byKey = <String, FavoriteTag>{};
  final order = <String>[];
  for (final tag in input) {
    final name = tag.name.trim();
    final key = TagText.normalize(name);
    if (name.isEmpty || key.isEmpty) continue;
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = FavoriteTag(
        name: name,
        aliases: _cleanTagAliases(tag.aliases, nameKey: key),
      );
      order.add(key);
      continue;
    }
    byKey[key] = existing.copyWith(
      aliases: _cleanTagAliases([
        ...existing.aliases,
        ...tag.aliases,
      ], nameKey: key),
    );
  }
  return [for (final key in order) byKey[key]!];
}

/// 漫画卡片上的封面角标显示开关。
///
/// 约定：**新加的卡片角标一律要在这里有一个开关**，默认开，
/// 用户随时能在「设置 → 书架 → 卡片角标」关掉（见 `.workbuddy/memory/MEMORY.md`）。
/// 组件自身的 `showXxx` 参数是**给具体页面**用的（某页不想要角标），
/// 这里是**给用户**用的总开关，两者是「与」的关系。
@freezed
abstract class ComicCardSettingState with _$ComicCardSettingState {
  const factory ComicCardSettingState({
    @Default(true) bool downloadBadgeEnabled,
    @Default(true) bool translationBadgeEnabled,

    /// 封面正中间的「直接阅读」按钮。关掉后点封面仍然只进详情页。
    @Default(true) bool readButtonEnabled,

    /// 封面左上角的「收藏 tag」角标。
    @Default(true) bool favoriteTagBadgeEnabled,
  }) = _ComicCardSettingState;

  factory ComicCardSettingState.fromJson(Map<String, dynamic> json) =>
      _$ComicCardSettingStateFromJson(json);
}

/// 角标开关的读入口（非 widget 上下文也能读）。
///
/// 同 [toastSetting]：读设置这件事本身不能把调用方炸掉。
ComicCardSettingState get comicCardSetting {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.comicCardSetting ??
        const ComicCardSettingState();
  } catch (_) {
    return const ComicCardSettingState();
  }
}

@freezed
abstract class CacheSettingState with _$CacheSettingState {
  const factory CacheSettingState({
    @Default(true) bool autoCleanCache,
    @Default(1073741824) int cacheSizeLimit,
  }) = _CacheSettingState;

  factory CacheSettingState.fromJson(Map<String, dynamic> json) =>
      _$CacheSettingStateFromJson(json);
}

@freezed
abstract class AppLockSettingState with _$AppLockSettingState {
  const AppLockSettingState._();

  const factory AppLockSettingState({
    @Default(false) bool enabled,
    @Default('') String gesturePasswordHash,
    @Default('') String resetPinHash,
  }) = _AppLockSettingState;

  factory AppLockSettingState.fromJson(Map<String, dynamic> json) =>
      _$AppLockSettingStateFromJson(json);

  bool get hasGesturePassword => gesturePasswordHash.trim().isNotEmpty;

  bool get hasResetPin => resetPinHash.trim().isNotEmpty;

  bool get isReady => hasGesturePassword && hasResetPin;
}

@freezed
abstract class ProxySettingState with _$ProxySettingState {
  const factory ProxySettingState({
    @Default(false) bool enabled,
    @Default(ProxyType.http) ProxyType type,
    @Default('') String address,
  }) = _ProxySettingState;

  factory ProxySettingState.fromJson(Map<String, dynamic> json) =>
      _$ProxySettingStateFromJson(json);
}

@freezed
abstract class WebDavSettingState with _$WebDavSettingState {
  const factory WebDavSettingState({
    @Default('') String host,
    @Default('') String username,
    @Default('') String password,
  }) = _WebDavSettingState;

  factory WebDavSettingState.fromJson(Map<String, dynamic> json) =>
      _$WebDavSettingStateFromJson(json);
}

@freezed
abstract class S3SettingState with _$S3SettingState {
  const factory S3SettingState({
    @Default('') String endpoint,
    @Default('') String accessKey,
    @Default('') String secretKey,
    @Default('') String bucket,
    @Default('') String region,
    @Default(true) bool useSSL,
    @Default(0) int port,
    @Default(false) bool pathStyle,
  }) = _S3SettingState;

  factory S3SettingState.fromJson(Map<String, dynamic> json) =>
      _$S3SettingStateFromJson(json);
}

@freezed
abstract class SyncSettingState with _$SyncSettingState {
  const factory SyncSettingState({
    @Default(SyncServiceType.none) SyncServiceType syncServiceType,
    @Default(WebDavSettingState()) WebDavSettingState webdavSetting,
    @Default(S3SettingState()) S3SettingState s3Setting,
    @Default(false) bool syncSettings,
    @Default(false) bool syncPlugins,
    @Default(true) bool autoSync,
    @Default(true) bool syncNotify,
    @Default(0) int settingsSyncTime,
  }) = _SyncSettingState;

  factory SyncSettingState.fromJson(Map<String, dynamic> json) =>
      _$SyncSettingStateFromJson(json);
}

@freezed
abstract class ReadSettingState with _$ReadSettingState {
  const factory ReadSettingState({
    @Default(false) bool noAnimation,
    @Default(true) bool comicReadTopContainer,
    @Default(0) int readMode,
    @Default(ReaderTapPageTurnMode.rightHand)
    ReaderTapPageTurnMode tapPageTurnMode,
    @Default(false) bool tapPageTurnInWebtoon,
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
  }) = _ReadSettingState;

  factory ReadSettingState.fromJson(Map<String, dynamic> json) =>
      _$ReadSettingStateFromJson(json);
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
    // 收藏 / 历史卡片的条目右键菜单（触摸端长按）。默认开 —— 默认值取「改造后的
    // 行为」，因为菜单本身不改动任何既有交互（单击打开照旧），关掉即回到纯点击。
    @Default(true) bool shelfCardContextMenu,
  }) = _BookshelfSettingState;

  factory BookshelfSettingState.fromJson(Map<String, dynamic> json) =>
      _$BookshelfSettingStateFromJson(json);
}

class GlobalSettingCubit extends Cubit<GlobalSettingState> {
  // 构造函数，传入由 freezed 生成的默认 state
  GlobalSettingCubit() : super(const GlobalSettingState());

  // 用于获取 freezed 中定义的默认值的便捷实例
  static const _defaults = GlobalSettingState();
  // colorThemeList[6].color 是动态的，不能在 const 中，单独处理
  late final Color _defaultSeedColor = colorThemeList[6].color;

  Future<void> initBox() async {
    final persisted = objectbox.userSettingBox.get(1)!.globalSetting;
    _applyLayoutOverflowGuard(persisted);
    emit(persisted);
  }

  GlobalSettingState get defaults =>
      _defaults.copyWith(seedColor: _defaultSeedColor);

  void updateALl(GlobalSettingState state) {
    _persistAndEmit(state);
  }

  void updateState(
    GlobalSettingState Function(GlobalSettingState current) updates,
  ) {
    final newState = updates(state);
    _persistAndEmit(newState);
  }

  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(readSetting: updates(current.readSetting)),
    );
  }

  void updateSyncSetting(
    SyncSettingState Function(SyncSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(syncSetting: updates(current.syncSetting)),
    );
  }

  void updateCacheSetting(
    CacheSettingState Function(CacheSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(cacheSetting: updates(current.cacheSetting)),
    );
  }

  void updateBookshelfSetting(
    BookshelfSettingState Function(BookshelfSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(bookshelfSetting: updates(current.bookshelfSetting)),
    );
  }

  void updateToastSetting(
    ToastSettingState Function(ToastSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(toastSetting: updates(current.toastSetting)),
    );
  }

  void updateSwitchToastSetting(
    SwitchToastSettingState Function(SwitchToastSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        switchToastSetting: updates(current.switchToastSetting),
      ),
    );
  }

  void updateComicCardSetting(
    ComicCardSettingState Function(ComicCardSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(comicCardSetting: updates(current.comicCardSetting)),
    );
  }

  void updateFileManagerSetting(
    FileManagerSettingState Function(FileManagerSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        fileManagerSetting: updates(current.fileManagerSetting),
      ),
    );
  }

  void updateDiscoverSetting(
    DiscoverSettingState Function(DiscoverSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(discoverSetting: updates(current.discoverSetting)),
    );
  }

  void updateOperationBindingSetting(
    OperationBindingSettingState Function(OperationBindingSettingState current)
    updates,
  ) {
    updateState(
      (current) => current.copyWith(
        operationBindingSetting: updates(current.operationBindingSetting),
      ),
    );
  }

  void updateFavoriteArtistSetting(
    FavoriteArtistSettingState Function(FavoriteArtistSettingState current)
    updates,
  ) {
    updateState(
      (current) => current.copyWith(
        favoriteArtistSetting: updates(current.favoriteArtistSetting),
      ),
    );
  }

  void addFavoriteArtist(String artist) {
    final trimmed = artist.trim();
    if (trimmed.isEmpty) return;
    updateFavoriteArtistSetting((current) {
      // 去重口径与匹配同一个（剥括号 + 小写），否则 `[X]` 与 `X` 会存成两条，
      // 列表里看着重复、徽标却只亮一次。
      final key = FavoriteArtistMatcher.normalizeArtist(trimmed);
      if (current.artists.any(
        (a) => FavoriteArtistMatcher.normalizeArtist(a) == key,
      )) {
        return current;
      }
      return current.copyWith(artists: [...current.artists, trimmed]);
    });
  }

  void removeFavoriteArtist(String artist) {
    final key = FavoriteArtistMatcher.normalizeArtist(artist);
    updateFavoriteArtistSetting((current) {
      return current.copyWith(
        artists: current.artists
            .where((a) => FavoriteArtistMatcher.normalizeArtist(a) != key)
            .toList(),
      );
    });
  }

  void setFavoriteArtists(List<String> artists) {
    final seen = <String>{};
    final unique = <String>[];
    for (final a in artists) {
      final t = a.trim();
      final key = FavoriteArtistMatcher.normalizeArtist(t);
      if (t.isNotEmpty && key.isNotEmpty && seen.add(key)) {
        unique.add(t);
      }
    }
    updateFavoriteArtistSetting((current) => current.copyWith(artists: unique));
  }

  void toggleHighlightFavoriteArtists(bool enabled) {
    updateFavoriteArtistSetting(
      (current) => current.copyWith(highlightEnabled: enabled),
    );
  }

  void setFavoriteArtistCircleMode(FavoriteArtistCircleMode mode) {
    updateFavoriteArtistSetting(
      (current) => current.copyWith(circleMode: mode),
    );
  }

  void updateFavoriteTagSetting(
    FavoriteTagSettingState Function(FavoriteTagSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        favoriteTagSetting: updates(current.favoriteTagSetting),
      ),
    );
  }

  /// 收藏一个 tag。[raw] 与已有条目的本名或别名归一化后相同时不重复添加。
  ///
  /// 详情页胶囊长按与设置页输入框都走这里，所以「长按第二次不该出现两条同名」。
  void addFavoriteTag(String raw) {
    final name = raw.trim();
    final key = TagText.normalize(name);
    if (key.isEmpty) return;
    updateFavoriteTagSetting((current) {
      if (_indexOfFavoriteTag(current.tags, key) != null) return current;
      return current.copyWith(
        tags: [
          ...current.tags,
          FavoriteTag(name: name),
        ],
      );
    });
  }

  /// 取消收藏：[raw] 对上某条的本名或任一别名，就删掉那一条。
  void removeFavoriteTag(String raw) {
    final key = TagText.normalize(raw);
    if (key.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final next = [...current.tags]..removeAt(index);
      return current.copyWith(tags: next);
    });
  }

  /// 整表替换（批量导入、清空、编辑别名后回写都走这里）。
  void setFavoriteTags(List<FavoriteTag> tags) {
    updateFavoriteTagSetting(
      (current) => current.copyWith(tags: _dedupeFavoriteTags(tags)),
    );
  }

  /// 给某条收藏加一个别名。[raw] 定位条目（本名或别名均可）。
  void addFavoriteTagAlias(String raw, String alias) {
    final key = TagText.normalize(raw);
    final aliasText = alias.trim();
    if (key.isEmpty || aliasText.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final tag = current.tags[index];
      final nameKey = TagText.normalize(tag.name);
      final aliasKey = TagText.normalize(aliasText);
      // 与本名同形的别名是噪声（归一化后本来就等价），与别的条目撞号则会把
      // 两条收藏并成一个命中，两处都要挡掉。
      if (aliasKey.isEmpty || aliasKey == nameKey) return current;
      if (aliasKey != key &&
          _indexOfFavoriteTag(current.tags, aliasKey) != null) {
        return current;
      }
      final cleaned = _cleanTagAliases([
        ...tag.aliases,
        aliasText,
      ], nameKey: nameKey);
      final next = [...current.tags];
      next[index] = tag.copyWith(aliases: cleaned);
      return current.copyWith(tags: next);
    });
  }

  void removeFavoriteTagAlias(String raw, String alias) {
    final key = TagText.normalize(raw);
    final aliasKey = TagText.normalize(alias);
    if (key.isEmpty || aliasKey.isEmpty) return;
    updateFavoriteTagSetting((current) {
      final index = _indexOfFavoriteTag(current.tags, key);
      if (index == null) return current;
      final tag = current.tags[index];
      final next = [...current.tags];
      next[index] = tag.copyWith(
        aliases: tag.aliases
            .where((a) => TagText.normalize(a) != aliasKey)
            .toList(),
      );
      return current.copyWith(tags: next);
    });
  }

  void toggleHighlightFavoriteTags(bool enabled) {
    updateFavoriteTagSetting(
      (current) => current.copyWith(highlightEnabled: enabled),
    );
  }

  /// 设置应用显示语言。
  ///
  /// [locale] 为目标 Flutter Locale；[followsSystem] 为 true 时表示跟随系统。
  /// 该方法会自动持久化、切换 slang 当前 locale，并同步 Rust 侧错误消息语言。
  /// 如果 [locale] 无法匹配到已支持的语言，则回退到英文。
  Future<void> setLocale(Locale locale, {bool followsSystem = false}) async {
    final appLocale = I18nHelper.toAppLocale(locale) ?? AppLocale.enUs;

    await LocaleSettings.setLocale(appLocale);
    I18nHelper.setRustErrorLanguage(appLocale);

    updateState(
      (current) => current.copyWith(
        locale: I18nHelper.toFlutterLocale(appLocale),
        localeFollowsSystem: followsSystem,
      ),
    );
  }

  /// 根据系统 locale 设置应用语言。
  /// 无法匹配时由 [setLocale] 自动回退到英文。
  Future<void> setSystemLocale(Locale systemLocale) async {
    await setLocale(systemLocale, followsSystem: true);
  }

  void updateWebDavSetting(
    WebDavSettingState Function(WebDavSettingState current) updates,
  ) {
    updateSyncSetting(
      (current) =>
          current.copyWith(webdavSetting: updates(current.webdavSetting)),
    );
  }

  void resetState(
    GlobalSettingState Function(
      GlobalSettingState current,
      GlobalSettingState defaults,
    )
    updates,
  ) {
    final newState = updates(state, defaults);
    _persistAndEmit(newState);
  }

  void _persistAndEmit(GlobalSettingState newState) {
    final normalizedState = _preserveCompatibleVersion(newState, state);
    if (_withoutSettingsSyncTime(normalizedState) ==
        _withoutSettingsSyncTime(state)) {
      return;
    }

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final persistedState = normalizedState.copyWith(
      syncSetting: normalizedState.syncSetting.copyWith(
        settingsSyncTime: nowMs,
      ),
    );
    _updateDataBase(persistedState);
    _applyLayoutOverflowGuard(persistedState);
    emit(persistedState);
  }

  void applySyncedState(GlobalSettingState value) {
    final normalized = _preserveCompatibleVersion(value, state);
    _updateDataBase(normalized);
    _applyLayoutOverflowGuard(normalized);
    emit(normalized);
  }

  /// 把「黄黑溢出斜纹」开关同步到全局标志上。
  ///
  /// 绘制路径每帧都要读它，不能去查数据库（`initBox` / `_persistAndEmit` /
  /// `applySyncedState` 三条 emit 路径都得过一遍，否则云同步回来的值不生效）。
  void _applyLayoutOverflowGuard(GlobalSettingState state) {
    setLayoutOverflowStripesEnabled(enabled: state.showLayoutOverflowStripes);
  }

  GlobalSettingState _preserveCompatibleVersion(
    GlobalSettingState incoming,
    GlobalSettingState fallback,
  ) {
    if (incoming.compatibleVersion.trim().isNotEmpty) {
      return incoming;
    }
    final preserved = fallback.compatibleVersion.trim();
    if (preserved.isEmpty) {
      return incoming;
    }
    return incoming.copyWith(compatibleVersion: preserved);
  }

  GlobalSettingState _withoutSettingsSyncTime(GlobalSettingState value) {
    return value.copyWith(
      syncSetting: value.syncSetting.copyWith(settingsSyncTime: 0),
    );
  }

  void _updateDataBase(GlobalSettingState state) {
    // logger.d(state.toJson());
    final userBox = objectbox.userSettingBox;
    var dbSettings = userBox.get(1)!;
    var toSave = state;
    final existingVersion = dbSettings.globalSetting.compatibleVersion.trim();
    if (toSave.compatibleVersion.trim().isEmpty && existingVersion.isNotEmpty) {
      toSave = toSave.copyWith(compatibleVersion: existingVersion);
    }
    dbSettings.globalSetting = toSave;
    userBox.put(dbSettings);
  }
}
