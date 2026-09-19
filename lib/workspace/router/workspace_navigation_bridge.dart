import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';

/// 工作台与**全局导航**之间的窄接口。
///
/// # 为什么需要这一层
///
/// Rossi 的泳道里跑的是**上游原版页面**（书架、发现、设置……），它们打开下一个
/// 页面的方式是 `context.pushRoute(XxxRoute())`。这些推入默认落在**根导航栈**上，
/// 于是「在工作台里点一下设置」会把整个工作台盖掉。
///
/// neoview 的语义不是这样：泳道里的东西开在**这条泳道里**。要在不改动上游任何一个
/// 文件、也不给上游新增一条跳转就失效的前提下做到这件事，只能在**导航这一层**接住：
/// 根路由的守卫（`WorkspaceRouteGuard`）把推入改派到这里，由工作台决定开在哪儿。
///
/// # 两条通道
///
/// 1. **阅读器通道**（[openReaderInLane]）：`ComicReadRoute` 一律改派进**中央泳道**
///    ——「中央泳道 = Reader」是工作台的第一条契约，它不跟着点击位置走；
/// 2. **面板通道**（[pushInLane]）：其余推入落进**发起交互的那个面板**自己的
///    局部 `Navigator` 里（落点由纯记账 [WorkspaceLaneDispatch] 决定）。
///    落点不明时返回 `false`，调用方**原样放行全屏** ——
///    宁可全屏，也不要把页面开进一个用户看不见的地方。
///
/// # 没有工作台时
///
/// [isAttached] 为假时守卫**逐字放行**，行为与改造前完全一致（全屏推入）。
class WorkspaceNavigationBridge {
  WorkspaceNavigationBridge._();

  static final WorkspaceNavigationBridge instance =
      WorkspaceNavigationBridge._();

  // ── 阅读器通道 ─────────────────────────────────────────────────────────

  void Function(WorkspaceReaderTarget target)? _openReader;

  /// 当前是否有工作台挂载（守卫据此决定要不要接管）。
  bool get isAttached => _openReader != null;

  /// 工作台挂载时登记「在阅读器泳道里打开」的回调。
  void attachReader(void Function(WorkspaceReaderTarget target) openReader) {
    _openReader = openReader;
  }

  /// 工作台卸载时注销。只注销自己登记的那个回调，
  /// 避免把后来者（例如重建后的另一个工作台实例）的回调抹掉。
  void detachReader(void Function(WorkspaceReaderTarget target) openReader) {
    if (identical(_openReader, openReader)) {
      _openReader = null;
    }
  }

  /// 交给工作台在阅读器泳道里打开；没有工作台时返回 `false`。
  bool openReaderInLane(WorkspaceReaderTarget target) {
    final open = _openReader;
    if (open == null) return false;
    open(target);
    return true;
  }

  // ── 面板通道 ───────────────────────────────────────────────────────────

  final Map<WorkspaceLaneHost, GlobalKey<NavigatorState>> _laneNavigators =
      <WorkspaceLaneHost, GlobalKey<NavigatorState>>{};

  /// 一个面板**成为本泳道当前可见的那一个**时登记它自己的导航器。
  ///
  /// 两个动作必须成对发生，所以合成一个入口：登记导航器 + 在纯记账里登记活主机。
  /// 分开写的话，早晚有人只做一半 —— 那时页面会开进一个有导航器但没登记的
  /// 面板（表现为「点了没反应」）。
  void attachLaneHost(
    WorkspaceLaneHost host,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    _laneNavigators[host] = navigatorKey;
    WorkspaceLaneDispatch.instance.registerHost(host);
  }

  /// 面板不再可见 / 被卸载时注销。**只注销自己登记的那一个** ——
  /// 正在做退出动画的旧面板不能抹掉刚上来的新面板。
  void detachLaneHost(
    WorkspaceLaneHost host,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    if (_laneNavigators[host] == navigatorKey) {
      _laneNavigators.remove(host);
      WorkspaceLaneDispatch.instance.unregisterHost(host);
    }
  }

  /// 用户在这个面板里按下指针时上报（落点的唯一来源）。
  void noteLaneInteraction(WorkspaceLaneHost host) {
    WorkspaceLaneDispatch.instance.noteInteraction(host);
  }

  /// 把守卫拦下的一次推入放进「发起交互的那个面板」。
  ///
  /// [routeBuilder] 只在**已经确定落点**之后才被调用 —— 守卫那边因此不必
  /// 为每一次推入都白造一个页面对象。返回 `false` = 没接管，
  /// 守卫必须原样放行这一次推入。
  bool pushInLane(Route<dynamic> Function(BuildContext context) routeBuilder) {
    final host = WorkspaceLaneDispatch.instance.resolveTarget();
    if (host == null) return false;

    final key = _laneNavigators[host];
    final navigator = key?.currentState;
    final context = key?.currentContext;
    if (navigator == null || context == null) return false;

    navigator.push(routeBuilder(context));
    return true;
  }
}

/// 把一个被守卫拦下的 `RouteMatch` 造成**可以被任意 `Navigator` 渲染**的 `Page`。
///
/// 这是「把上游的一条推入改派到别处」的关键一步：`RouteMatch` 只是「匹配到哪条
/// 路由 + 参数是什么」，它自己不会造页面；造页面要用路由表里的 builder，
/// 而那条路只有 `RouteMatch.buildPage(RouteData)` 一个公开入口 —— 所以这里
/// 手工拼一个 `RouteData` 交给它。三点说明：
///
/// - `router` 用**发起这次推入的那个路由**（守卫拿得到）。页面被弹出时
///   `AutoRoutePage.onPopInvoked` 会拿它调一次 `onPopPage`，而 `onPopPage`
///   对不在自己栈里的页面是**空操作**（`if (!_pages.remove(page)) return;`），
///   所以这里传根路由是安全的；
/// - `stackKey` 只在 `Page.canUpdate` 里参与比较，而我们是**命令式 push**
///   （不是 declarative pages），用不上，给一个新的即可；
/// - `type` / `pendingChildren` 的取法**照抄 auto_route 自己的
///   `RoutingController._createRouteData`**（`route.type ?? root.defaultRouteType`），
///   免得这里的页面与根路由推出来的页面在过渡动画上不一致。
Page<dynamic> buildLanePage(RouteMatch match, StackRouter router) {
  final data = RouteData<dynamic>(
    route: match,
    router: router,
    stackKey: UniqueKey(),
    pendingChildren: match.children ?? const <RouteMatch>[],
    type:
        match.type ??
        (router is RootStackRouter
            ? router.defaultRouteType
            : const RouteType.material(enablePredictiveBackGesture: false)),
  );
  return data.buildPage<dynamic>();
}
