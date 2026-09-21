import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 把「这一格给内容留了多大」报给宿主的探针。
///
/// # 为什么不是 `LayoutBuilder`
///
/// `LayoutBuilder` 的 builder 跑在 **layout 回调**里：套在标签内容上等于把整棵子树
/// 搬进布局相构建。那一页里的 `didChangeDependencies`（auto_route 的观察者、
/// `InheritedProvider` 之类）会在布局中途挂 widget / 查路由，实测直接抛
/// 「RouterScope operation requested with a context that does not include a
/// RouterScope」并连带报一串 RenderFlex 溢出。而布局相里抛异常正是
/// `MouseTracker._debugDuringDeviceUpdate` 不复位那套「每帧刷断言直到卡死」的引信。
///
/// 这里要的是同一个数（传进来的约束有多大），但要**只往一张表里写**、不动 widget 树，
/// 所以自己下一个 `RenderProxyBox`：它是纯透明的透传盒，布局与命中都照子节点来。
///
/// # 为什么不回调 `setState`
///
/// 尺寸只在用户右键那一刻才要用（判断「再切一半还摆得下吗」），所以写表就够 ——
/// 菜单侧按「现问」拿（见 `RossiPlatTabMenuRegion.paneSize`）。在布局相里 setState
/// 是另一类自激：那一帧正在排布，重排请求会把它拖成无限重建。
class RossiPlatPaneProbe extends SingleChildRenderObjectWidget {
  const RossiPlatPaneProbe({super.key, required this.onSize, required super.child});

  /// 约束变了才调（同一格反复布局不会重复报）。
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPaneProbe(onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // `RenderProxyBox` 而不是那个私有子类：`library_private_types_in_public_api`
    // 不许把私有的东西摆进公开签名里，而协变收窄本身要的就是这个父类型。
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _RenderPaneProbe).onSize = onSize;
  }
}

class _RenderPaneProbe extends RenderProxyBox {
  _RenderPaneProbe(this.onSize);

  ValueChanged<Size> onSize;

  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final pane = constraints.biggest;
    if (pane == _reported) return;
    _reported = pane;
    onSize(pane);
  }
}
