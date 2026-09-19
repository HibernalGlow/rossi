import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/util/debouncer.dart';

/// 启动后第一眼落在哪儿。
enum StartupLanding {
  /// 导航栏（底部标签 / 四边栏），改造前的老行为。
  navigationBar,

  /// 工作台。
  workspace,
}

/// 启动落点判定：开关 + 「本机有没有工作台入口」，两个都成立才去工作台。
///
/// 抽成纯函数是为了让这两条能直接断言，而不必把 `NavigationBar` 挂起来
/// （那一层依赖 ObjectBox、通知、下载队列，判据里起不来）：
/// - 开关关着 ⇒ 永远是导航栏（默认关，所以没动过设置的用户零感知）；
/// - 本机**没有**工作台入口 ⇒ 开关开着也仍然落在导航栏。手机（既不是平板宽度、
///   也不是桌面）的导航栏上根本没有那个按钮，在那边自动打开只会开出一个
///   只能靠返回键退出的整页 —— 设置页同样不摆这个开关
///   （与 `comicInfoInlineReadButton` 的口径一致：不给点了没反应的开关）。
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

/// 当前设备有没有工作台入口 —— 即「导航栏走不走四边栏布局」，
/// 因为那个按钮就挂在四边栏布局的 `trailing` 上（见 `navigation_bar.dart`）。
///
/// **两处必须同源**（导航栏的布局分支、设置页的开关可见性、启动落点判定），
/// 否则会出现「设置里开着、导航栏上却没入口」这类各说各话。
bool hasWorkspaceEntry(BuildContext context) =>
    isTablet(context) || isWorkspaceDesktopPlatform(defaultTargetPlatform);

/// 开屏页下拉里「工作台」那一项的值。
///
/// 标签页占 `0..n-1`，所以工作台用 `-1` 这个哨兵 —— 它不占标签页的编号空间，
/// 也不会与 `welcomePageNum` 的既有取值（含云端同步来的旧值）撞车。
/// 下拉的键用**编号**而不是显示名：用显示名当键时，改一次文案就会把选中项对丢。
const int splashWorkspaceOption = -1;

/// 开屏页下拉**当前该显示哪一项**。
///
/// 本机没有工作台入口（手机）时即使字段是 `true` 也显示标签页：那边导航栏上
/// 根本没有工作台按钮，显示成「工作台」会让人以为下次启动会进去，而实际不会。
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
