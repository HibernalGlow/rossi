import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/workspace/model/workspace_pointer_mode.dart';

/// 启动后第一眼落在哪儿。
enum StartupLanding {
  /// 导航栏（底部标签 / 四边栏），改造前的老行为。
  navigationBar,

  /// 工作台。
  workspace,
}

/// 启动落点判定：开关 + 「本机能不能用工作台」，两个都成立才去工作台。
///
/// 抽成纯函数是为了让这两条能直接断言，而不必把 `NavigationBar` 挂起来
/// （那一层依赖 ObjectBox、通知、下载队列，判据里起不来）：
/// - 开关关着 ⇒ 永远是导航栏（默认关，所以没动过设置的用户零感知）；
/// - 本机用不了工作台 ⇒ 开关开着也仍然落在导航栏。传进来的应当是
///   [workspaceAvailableOnDevice]，**不是** [hasWorkspaceEntry]：后者只说
///   「侧栏布局上有没有那颗按钮」，手机上没有按钮但工作台进得去也出得来。
///   这条守卫不是摆设：「能不能用」以后要按视口宽度收紧时（竖屏手机摆三条泳道
///   本来就挤），改的是 [workspaceAvailableOnDevice] 那一处，这里照旧生效。
StartupLanding resolveStartupLanding({
  required bool startWithWorkspace,
  required bool workspaceEntryAvailable,
}) {
  if (!startWithWorkspace || !workspaceEntryAvailable) {
    return StartupLanding.navigationBar;
  }
  return StartupLanding.workspace;
}

/// 平台是不是「桌面三平台」—— 这三平台一律走四边栏布局。
///
/// 用 [TargetPlatform] 而不是 `dart:io` 的 `Platform`：真机上两者同值，
/// 但测试里可以用 `debugDefaultTargetPlatformOverride` 覆写。
bool isWorkspaceDesktopPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.linux ||
    platform == TargetPlatform.macOS;

/// 当前设备**导航栏**有没有工作台入口 —— 即「导航栏走不走四边栏布局」，
/// 因为那颗按钮就挂在四边栏布局的 `NavigationRail.trailing` 上
/// （见 `navigation_bar.dart`）。
///
/// **两处必须同源**（导航栏的布局分支、这条判据），否则会出现
/// 「设置里开着、导航栏上却没入口」这类各说各话。
///
/// 这条只管**布局**。别把它当成「这台设备能不能用工作台」——那是
/// [workspaceAvailableOnDevice]，见那里的说明（手机上没有这颗按钮，
/// 但工作台照样能进）。
bool hasWorkspaceEntry(BuildContext context) =>
    isTablet(context) || isWorkspaceDesktopPlatform(defaultTargetPlatform);

/// 工作台在这台设备上**给不给用**。
///
/// 与 [hasWorkspaceEntry] 分成两条，是因为它们回答的不是一个问题：
/// - `hasWorkspaceEntry` 问的是「侧栏布局的 trailing 上有没有那颗按钮」；
/// - 这里问的是「用户有没有办法进去、并且出得来」。
///
/// 焊在一起的历史代价：手机端因为「没有那颗按钮」被判定成不能用工作台，
/// 而真机上其实有三条进出路 —— 系统返回键、泳道「更多」菜单里的「退出工作台」，
/// 以及「设置 → 布局」里那张「进入工作台」按钮（触摸屏专用，见
/// `workspace_layout_setting_page.dart`）。把按钮加进底部导航倒是不用另找入口，
/// 但那会把手机端的 tab 信息架构改掉，而 `navigation_bar.dart` 里已经写明这是
/// **「动作不是视图」**，不该因为换了个平台就改变性质。
///
/// 触摸那一路的条件用 [WorkspacePointerMode]，与顶栏形态、泳道切换轨同一个
/// 判据 —— 三处都在问「这台设备有没有悬停指针」，各写一遍迟早分叉。
bool workspaceAvailableOnDevice(BuildContext context) =>
    hasWorkspaceEntry(context) ||
    WorkspacePointerMode.forTargetPlatform(defaultTargetPlatform) ==
        WorkspacePointerMode.touchOnly;

/// 开屏页下拉里「工作台」那一项的值。
///
/// 标签页占 `0..n-1`，所以工作台用 `-1` 这个哨兵 —— 它不占标签页的编号空间，
/// 也不会与 `welcomePageNum` 的既有取值（含云端同步来的旧值）撞车。
/// 下拉的键用**编号**而不是显示名：用显示名当键时，改一次文案就会把选中项对丢。
const int splashWorkspaceOption = -1;

/// 开屏页下拉**当前该显示哪一项**。
///
/// [workspaceEntryAvailable] 传 [workspaceAvailableOnDevice] 的结果。它为假时
/// 即使字段是 `true` 也显示标签页：那边根本进不去，显示成「工作台」会让人
/// 以为下次启动会进去，而实际不会。
int resolveSplashDropdownValue({
  required bool startWithWorkspace,
  required bool workspaceEntryAvailable,
  required int welcomePageNum,
}) => (startWithWorkspace && workspaceEntryAvailable)
    ? splashWorkspaceOption
    : welcomePageNum;

/// 用户在下拉里选了 [selected] 之后，两个字段各该变成什么。
///
/// 选「工作台」时**不动** [currentWelcomePageNum]：那个值是退出工作台之后落回的
/// 标签页，来回切几次不该把它弄丢。
({bool startWithWorkspace, int welcomePageNum}) resolveSplashSelection({
  required int selected,
  required int currentWelcomePageNum,
}) => selected == splashWorkspaceOption
    ? (startWithWorkspace: true, welcomePageNum: currentWelcomePageNum)
    : (startWithWorkspace: false, welcomePageNum: selected);
