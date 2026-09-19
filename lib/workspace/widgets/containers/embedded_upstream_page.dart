import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';

/// 面板里那块**上游整页**的容器：给它一条**自己的局部导航栈**。
///
/// 上游页面推下一个页面用的是 `context.pushRoute(XxxRoute())`，默认落在根导航栈上
/// —— 于是在工作台里点「设置」会把整个工作台盖掉。这一层让这件事变成
/// 「开在这块卡片里」：
///
/// 1. **局部 `Navigator`**：守卫把被拦下的推入交给这里，页面就在面板内容区里出现，
///    返回箭头（上游 `AppBar` 自动插的那个）弹的是**这一页**，不是整个工作台；
///    顺带 `showModalBottomSheet` 这类默认不 `useRootNavigator` 的浮层也收在面板里。
/// 2. **指针交互上报**：用户在哪儿按下指针，就是「下一次推入开在哪儿」的唯一依据
///    （[WorkspaceLaneDispatch]）。放在 `Listener` 上而不是点击回调里，是因为
///    上游的点击点太散（`ListTile.onTap`、图标按钮、长按菜单……），
///    而「按下」是它们共同的、无法绕过的一步。
/// 3. **可见性登记**：[isVisible] 为真（它就是本泳道当前显示的那个面板）时才登记
///    自己，成为推入的候选落点。`IndexedStack` 会把访问过的面板都留在树里，
///    不可见的面板也在跑 —— 没有这条约束，隐藏面板会抢走推入
///    （用户看到的是「点了没反应」）。
/// 4. **实例身份**：[instanceKey] 做内容 key。同样一块面板换了一份内容（例如换一本
///    漫画）时整体重建，不残留上一份的状态。
class EmbeddedUpstreamPage extends StatefulWidget {
  const EmbeddedUpstreamPage({
    super.key,
    required this.host,
    required this.instanceKey,
    required this.isVisible,
    required this.builder,
  });

  /// 这个面板的身份（泳道 + 面板）。
  final WorkspaceLaneHost host;

  /// 内容身份：变了就整体重建。
  final String instanceKey;

  /// 它是本泳道**当前显示**的那一个面板吗。
  final bool isVisible;

  /// 上游整页。
  final WidgetBuilder builder;

  @override
  State<EmbeddedUpstreamPage> createState() => _EmbeddedUpstreamPageState();
}

class _EmbeddedUpstreamPageState extends State<EmbeddedUpstreamPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _attach();
  }

  @override
  void didUpdateWidget(EmbeddedUpstreamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.host == oldWidget.host &&
        widget.isVisible == oldWidget.isVisible) {
      return;
    }
    // 换泳道 / 换可见性：先退掉旧的登记（注销是**只认自己**的，
    // 所以即使在同一帧里被新面板接管，也不会互相抹掉）。
    if (oldWidget.isVisible) {
      WorkspaceNavigationBridge.instance.detachLaneHost(
        oldWidget.host,
        _navigatorKey,
      );
    }
    if (widget.isVisible) _attach();
  }

  @override
  void dispose() {
    WorkspaceNavigationBridge.instance.detachLaneHost(
      widget.host,
      _navigatorKey,
    );
    super.dispose();
  }

  void _attach() {
    WorkspaceNavigationBridge.instance.attachLaneHost(
      widget.host,
      _navigatorKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // translucent：面板的空白处按下也算「用户在这块卡片里」，
      // 但不抢子节点的命中（上游页面自己的点击照旧）。
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          WorkspaceNavigationBridge.instance.noteLaneInteraction(widget.host),
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => KeyedSubtree(
            key: ValueKey<String>('embedded-page:${widget.instanceKey}'),
            child: widget.builder(context),
          ),
        ),
      ),
    );
  }
}
