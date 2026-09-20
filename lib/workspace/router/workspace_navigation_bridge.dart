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
/// # 三条通道
///
/// 1. **阅读器通道**（[openReaderInLane]）：`ComicReadRoute` 一律改派进**中央泳道**
///    ——「中央泳道 = Reader」是工作台的第一条契约，它不跟着点击位置走；
/// 2. **面板通道**（[pushInLane]）：其余推入落进**发起交互的那个面板**自己的
///    局部 `Navigator` 里（落点由纯记账 [WorkspaceLaneDispatch] 决定）。
///    落点不明时返回 `false`，调用方**原样放行全屏** ——
///    宁可全屏，也不要把页面开进一个用户看不见的地方。
/// 3. **回退通道**（[handleBackInLane]）：**与推入对称的那一半**。守卫管得住
///    `context.pushRoute(...)`，却管不住 `context.pop()` / `context.maybePop()`
///    —— 后两者走的是 `AutoRouter.of(context)`，就近的 `StackRouterScope` 是
///    **根路由**，于是面板里的一下「返回」弹掉的是根栈顶页 = 整个工作台。
///    这里把根路由的 `pop` / `maybePop` 接过来，退**落点面板里**那一页。
///
/// 另有一条**出口通道**（[exitWorkspace]）：工作台顶栏默认不画之后，
/// 泳道「更多」菜单里那颗「退出工作台」走的正是它。
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

  /// 一块**有内容、但没有自己的局部导航栈**的泳道内容成为落点。
  ///
  /// 目前只有阅读器泳道用它。它和 [attachLaneHost] 的差别只有一半：
  /// **登记落点，不上报导航器** —— 阅读器泳道里没有「推入开在这块内容里」这件需求
  /// （那边只有一条上游页面），但它**必须参与落点记账**：用户在阅读器里按下指针之后，
  /// 落点要跟过来。不跟过来的话，阅读器里的一下「返回」会按上一次在**面板**里的
  /// 落点算，退掉那块面板里的一页 —— 退错了对象。
  void attachLaneContent(WorkspaceLaneHost host) {
    WorkspaceLaneDispatch.instance.registerHost(host);
  }

  /// 那块内容不再是当前那一个（空画布 / 被卸载）时注销。只注销自己登记的那一个。
  void detachLaneContent(WorkspaceLaneHost host) {
    WorkspaceLaneDispatch.instance.unregisterHost(host);
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

  // ── 回退通道 ───────────────────────────────────────────────────────────

  /// 工作台那一整页自己的 [ModalRoute]（挂载时登记）。
  ModalRoute<dynamic>? _workspaceRoute;

  /// 工作台那一页**是不是根栈顶**。
  ///
  /// 判据用 `ModalRoute.isCurrent`（与 `BreezeWorkspacePage._exitWorkspace`
  /// 同一个判据），而不是「工作台挂载了没有」：对话框、`showDialog` 出来的那一层、
  /// 以及「落点不明时宁可全屏」推上来的整页，都可能正压在工作台上面 ——
  /// 那时候 `context.pop()` 想弹的是**它们**，工作台不该抢。
  bool get workspaceIsOnTop {
    final route = _workspaceRoute;
    return route != null && route.isCurrent;
  }

  /// 工作台挂载时登记自己那一页。
  void attachWorkspaceRoute(ModalRoute<dynamic> route) {
    _workspaceRoute = route;
  }

  /// 工作台卸载时注销。只注销自己登记的那一个。
  void detachWorkspaceRoute(ModalRoute<dynamic> route) {
    if (identical(_workspaceRoute, route)) {
      _workspaceRoute = null;
    }
  }

  /// 根路由收到一次 `pop` / `maybePop` 时先问这里：**这是泳道里的一下「返回」吗。**
  ///
  /// 返回 `true` = 已经由泳道处理掉了，调用方**不要再动根栈**；
  /// 返回 `false` = 没接管（工作台不在、工作台被压在别的页下面、落点不明、
  /// 或者面板里已经没得更退），调用方原样走根栈 —— 逐级退到最后退出工作台，
  /// 这条出口必须留着（`Esc` 与鼠标侧键走的也是这里）。
  ///
  /// 「点开的东西退得回原处」与「推入开在哪儿」共用同一份落点记账：用户在哪儿
  /// 按下指针，就是哪儿（[WorkspaceLaneDispatch]）。点返回按钮那一下本身就是按下，
  /// 所以落点必然是被点的那块面板 —— 不需要另造一套判据。
  bool handleBackInLane([Object? result]) {
    if (!workspaceIsOnTop) return false;

    final host = WorkspaceLaneDispatch.instance.resolveTarget();
    if (host == null) return false;

    final navigator = _laneNavigators[host]?.currentState;
    if (navigator == null) return false;

    // 面板里只有摊在屏幕上的那一页 ⇒ 没得更退，把这次返回还给根栈。
    if (!navigator.canPop()) return false;

    navigator.pop(result);
    return true;
  }

  // ── 出口通道 ───────────────────────────────────────────────────────────

  VoidCallback? _exitWorkspace;

  /// 工作台挂载时登记「退出工作台」这一件事**页面自己怎么做**。
  ///
  /// 为什么不在泳道菜单里直接 `Navigator.maybePop()`：退出这一步在页面上还捎带
  /// 两条判断 —— 阅读器正全屏铺满时先退全屏、工作台不是栈顶时什么都不做。
  /// 抄一份到菜单里就有两个地方会各自漂移，而症状是「有时候按返回什么也不会发生」。
  void attachWorkspaceExit(VoidCallback exit) {
    _exitWorkspace = exit;
  }

  /// 工作台卸载时注销。只注销自己登记的那一个（同 [detachReader]）。
  void detachWorkspaceExit(VoidCallback exit) {
    if (identical(_exitWorkspace, exit)) {
      _exitWorkspace = null;
    }
  }

  /// 请工作台退出（泳道「更多」菜单里那颗「退出工作台」）。
  ///
  /// 没有工作台在场时是**空操作**而不是抛：菜单项在页面已经拆掉的同一帧里
  /// 被点到的概率不为零，那时用户看到的应当是「什么都没发生」，不是红屏。
  void exitWorkspace() => _exitWorkspace?.call();
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
