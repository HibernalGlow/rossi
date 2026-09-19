import 'package:auto_route/auto_route.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';

/// **回退通道的接线端**：把根路由收到的 `pop` / `maybePop` 先交给工作台问一句。
///
/// # 为什么必须有这一端
///
/// 守卫（`WorkspaceRouteGuard`）能拦住推入，是因为所有推入都要过它。**回退不过守卫**：
/// 面板里的上游页面写的是 `context.pop()` / `context.maybePop()`，它们走
/// `AutoRouter.of(context)` → 就近的 `StackRouterScope` —— 而面板里那条局部
/// `Navigator` 上方没有自己的 scope，就近的就是**根路由**。于是「插件的界面」
/// 里那一下返回，弹掉的是根栈顶页 = **整个工作台**（症状：直接退出整个泳道，
/// 回到主页面）。
///
/// # 为什么是 mixin 而不是直接写在 `AppRouter` 里
///
/// 判据要用一个**缩微版路由**（`test/workspace/route_guard_test.dart` 里的
/// `_TestRouter`）把整条链路挂起来 —— 真 `AppRouter` 要拖进整张路由表、图源注册表、
/// ObjectBox，判据里起不来。接缝写在 mixin 里，生产路由与判据路由**用的是同一份**
/// 覆写；写在 `AppRouter` 里的话，判据就只能自己再造一个同款覆写，
/// 那验的是判据自己的实现，不是这一段。
///
/// # 只做一件事
///
/// 问 [WorkspaceNavigationBridge.handleBackInLane]：**这是泳道里的一下「返回」吗。**
/// 是 → 退掉落点面板里那一页，并告诉根栈「别再动」；不是 → 原样 `super`。
/// 判据、边界与「什么时候不接管」全在那边的文档里，这里一个字都不重复。
mixin WorkspaceBackInterceptor on StackRouter {
  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    if (WorkspaceNavigationBridge.instance.handleBackInLane(result)) {
      return true;
    }
    return super.maybePop<T>(result);
  }

  @override
  void pop<T extends Object?>([T? result]) {
    if (WorkspaceNavigationBridge.instance.handleBackInLane(result)) {
      return;
    }
    super.pop<T>(result);
  }
}
