import 'package:auto_route/auto_route.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';

/// 根路由守卫：**工作台挂载期间，工作台里发起的推入一律不铺满整个应用**。
///
/// 这是「泳道里的东西开在泳道里」在**不改上游任何页面**的前提下唯一能成立的位置：
/// 书架 / 发现 / 设置这些上游页面推下一个页面的写法一个字都不用动
/// （`context.pushRoute(XxxRoute())`），由这里统一决定「它开在哪儿」。
///
/// 两条去向：
/// 1. `ComicReadRoute` → **阅读器泳道**（「中央泳道 = Reader」不跟着点击位置走）；
/// 2. 其余 → **发起交互的那个面板**（`WorkspaceNavigationBridge.pushInLane`）。
///
/// 放行的四种情况（行为与没有工作台时**逐字一致**）：
/// - 工作台没挂载（`isAttached == false`）；
/// - 推的是工作台自己那一页（`BreezeWorkspaceRoute`）—— 它只能是整页；
/// - `ComicReadRoute` 的参数不是 `ComicReadRouteArgs`（例如按路径推入、没有类型化参数）；
/// - 落点不明（用户还没在任何一个面板里点过、那条泳道已经换面板 / 收起、
///   面板正在卸载）—— 这时候**宁可全屏**：把页面开进一个用户看不见的地方，
///   表现为「点了没反应」，比全屏更糟。
///
/// 顺序上**先 `next(false)` 再交接**：泳道侧在交接后还要动一次路由栈
/// （把压在工作台上面的详情页弹掉，见 `BreezeWorkspacePage`），
/// 那次动栈要和这一次还没结束的导航错开。
///
/// `resolver.next(false)` 且没传 `onFailure` 时，auto_route 的推入是**静默返回 null**、
/// 不抛异常 —— 所以上游那些 `context.pushRoute(...)` 不用加 try/catch。
class WorkspaceRouteGuard extends AutoRouteGuard {
  const WorkspaceRouteGuard();

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final bridge = WorkspaceNavigationBridge.instance;
    if (!bridge.isAttached) {
      resolver.next(true);
      return;
    }

    final match = resolver.route;
    final args = match.args;

    // 0. 工作台自己：**永远整页**。它一旦被当成「别的东西」塞进某条面板，
    //    用户看到的就是套在工作台里的第二层工作台，而落点记账会把「返回」算错。
    //    生产里入口在工作台背后（`NavigationBar` 那颗按钮），此刻够不到；
    //    但守卫接的是**每一次**推入，所以先把这个口子堵上，
    //    以后从泳道里新增一个「打开工作台」不必再踩一遍。
    if (match.name == BreezeWorkspaceRoute.name) {
      resolver.next(true);
      return;
    }

    // 1. 阅读：一律进中央泳道。
    if (match.name == ComicReadRoute.name && args is ComicReadRouteArgs) {
      // 中止原本的全屏推入，否则会同时出现两个阅读器。
      resolver.next(false);
      bridge.openReaderInLane(WorkspaceReaderTarget.fromRouteArgs(args));
      return;
    }

    // 2. 其余：落进发起交互的那个面板的局部导航栈。
    //    没落点时不接管 —— pushInLane 返回 false，下面照常放行。
    if (bridge.pushInLane(
      (context) => buildLanePage(match, router).createRoute(context),
    )) {
      resolver.next(false);
      return;
    }

    resolver.next(true);
  }
}
