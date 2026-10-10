// 「侧栏 / Dock 走哪一支」的判定。
//
// 抽成纯函数是刻意的：这条判据至少有三个消费方（导航栏的布局分支、
// 「设置 → 布局」里那颗「进入工作台」是否要出现、以及窄屏自动切的开关），
// 而它们**必须同源** —— 各写一遍迟早分叉，表现是「设置里开着、界面上却没入口」。
// 纯函数还让真值表能直接断言，不必起整个 app。

/// 导航栏走哪一支。
enum NavigationLayout {
  /// 左侧栏（桌面 / 平板，也是本仓改造前在桌面上的样子）。
  sidebar,

  /// 移动端：底部 Dock 栏 / 底栏。
  mobile,
}

/// 窄屏自动切换的**默认**阈值（逻辑像素）。
///
/// 600 这个数与 `isTablet` 的平板阈值对齐（见 `lib/util/debouncer.dart`）——
/// 一处口径，两个用法，不再各自拍一个数。
const double kDefaultNarrowNavigationWidth = 600;

/// 阈值的可调范围。
///
/// 下限 320：再窄已经小于任何在售手机的逻辑宽度，把阈值拖到那里等于
/// 「永远走移动端」，而那本来就该用旁边的开关表达，不该靠拖滑块。
/// 上限 1600：超过常见桌面窗口宽度的阈值同样等于「永远走移动端」，同上。
const double kMinNarrowNavigationWidth = 320;
const double kMaxNarrowNavigationWidth = 1600;

double clampNarrowNavigationWidth(double width) =>
    width.clamp(kMinNarrowNavigationWidth, kMaxNarrowNavigationWidth);

/// 该走哪一支。
///
/// [sidebarCapable] 是**平台能力**（当前实现里就是 `hasWorkspaceEntry`：
/// 平板或桌面三平台）。它回答的是「这台设备有没有侧栏这种东西」，
/// 而不是「现在这一屏有多宽」—— 后者由 [width] 与开关回答。
///
/// 判定顺序有讲究：平台本来就不适合侧栏时（手机）不读宽度，也就不会因为
/// 「横屏变宽」突然长出一条侧栏；反过来，平台够格但窗口被拉窄（桌面小窗、
/// 平板分屏）时，[autoSwitchOnNarrow] 打开就切移动端。
NavigationLayout resolveNavigationLayout({
  required bool sidebarCapable,
  required double width,
  required bool autoSwitchOnNarrow,
  required double narrowWidth,
}) {
  if (!sidebarCapable) return NavigationLayout.mobile;
  if (!autoSwitchOnNarrow) return NavigationLayout.sidebar;
  return width < clampNarrowNavigationWidth(narrowWidth)
      ? NavigationLayout.mobile
      : NavigationLayout.sidebar;
}
