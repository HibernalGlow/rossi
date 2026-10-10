// 导航组件（侧栏 / Dock）从 FlClash 搬过来时依赖的几个本仓没有的小东西。
//
// 三件都不是业务逻辑，是**适配层**：让原文那两千行里的
// `context.colorScheme` / `context.textTheme` / `HiddenBarScrollBehavior`
// 在本仓能原样编译，从而不必把每一处调用点都改写成 `context.theme.xxx`
// —— 逐处改写会让"对照上游看差异"这件事失效，而这份搬运的价值恰恰在于
// 以后还能对着上游读。
//
// 只在这个目录下的文件里 import 它。

import 'package:material_ui/material_ui.dart';

/// 与 FlClash 的 `lib/common/context.dart` 同形的两个取色 / 字体入口。
///
/// 本仓的既有写法是 `context.theme.colorScheme`（见
/// `lib/util/context/context_extensions.dart`），两者并存：新代码仍可走
/// `context.theme`，这里只是给搬来的组件一个**逐字不用改**的入口。
extension NavigationContextX on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;
}

/// 不画滚动条的滚动行为。侧栏那条导航列表用它（条目本来就少、又窄，
/// 挂一条滚动条只会贴着图标）。
///
/// 对应 FlClash 的 `HiddenBarScrollBehavior`（`lib/common/scroll.dart`）。
/// 那个类的基类 `BaseScrollBehavior` 还带着「桌面端允许鼠标拖动滚动」
/// 与「用 CommonScrollBar」两条本仓没有的依赖，所以这里取它的**语义**重写：
/// `MaterialScrollBehavior` + 直接把 child 交出去，效果与
/// 「`showScrollbar` 恒为 false 的那条分支」逐字等价。
class NavigationHiddenBarScrollBehavior extends MaterialScrollBehavior {
  const NavigationHiddenBarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
