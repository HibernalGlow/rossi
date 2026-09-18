import 'package:auto_route/auto_route.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/reader/workspace_reader_bridge.dart';

/// 根路由守卫：工作台挂载期间，把 `ComicReadRoute` 的推入改派到阅读器泳道。
///
/// 这是「中央泳道 = Reader」在**不改上游任何页面**的前提下唯一能成立的位置：
/// 书架 / 发现 / 历史这些上游页面推 `ComicReadRoute` 的写法一个字都不用动，
/// 由这里统一决定「这一本读在哪儿」。
///
/// 三类不接管的情况（一律放行，行为与没有工作台时完全一致）：
/// - 工作台没挂载（`isAttached == false`）；
/// - 推入的不是 `ComicReadRoute`；
/// - 参数不是 `ComicReadRouteArgs`（例如按路径推入、没有类型化参数）。
///
/// 顺序上**先 `next(false)` 再交接**：泳道侧在交接后还要动一次路由栈
/// （把压在工作台上面的详情页弹掉，见 `BreezeWorkspacePage`），
/// 那次动栈要和这一次还没结束的导航错开。
class WorkspaceReaderGuard extends AutoRouteGuard {
  const WorkspaceReaderGuard();

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final args = resolver.route.args;
    final bridge = WorkspaceReaderBridge.instance;

    if (resolver.routeName == ComicReadRoute.name &&
        args is ComicReadRouteArgs &&
        bridge.isAttached) {
      // 中止原本的全屏推入，否则会同时出现两个阅读器。
      resolver.next(false);
      bridge.openInLane(WorkspaceReaderTarget.fromRouteArgs(args));
      return;
    }

    resolver.next(true);
  }
}
