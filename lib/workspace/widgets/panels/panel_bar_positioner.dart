import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_panel_bar.dart';

/// 把面板操作栏摆到它该在的位置，并把**实际摆出来的位置**回报给调用方。
///
/// 为什么位置要「回报」而不是让调用方自己算一遍：
///
/// - 三条摆放规则（钉在某条边 / 悬浮在百分比处 / 拖动中跟着光标）各要一份
///   算术，其中两条还要用到浮层**自己的尺寸** —— 那个尺寸只有在布局里才存在。
///   在布局之外用公式复算，等于把「浮层有多大」猜一遍，猜错的表现是
///   **每次开始拖动它都会先跳一下**（跳的距离就是起点误差）。
/// - 拖动松手时要把「浮层中心在哪」换算成停靠边或百分比，用的是**画出来的**
///   那个位置。让渲染者把它交出来，坐标系就只有一份。
class PanelBarPositioner extends StatelessWidget {
  const PanelBarPositioner({
    super.key,
    required this.layout,
    required this.boundsOf,
    this.liveOffset,
    this.onPositioned,
    required this.child,
  });

  /// 这一档该怎么摆（钉 / 悬浮 + 百分比 + 停靠边）。
  final PanelBarLayout layout;

  /// 容器矩形随尺寸而定：钉住的面板栏容器是**这条泳道**，
  /// 「允许移出泳道」的悬浮面板栏容器是**整个工作台视口**。
  final PanelBarBounds Function(Size containerSize) boundsOf;

  /// 拖动中的实时位置（容器局部坐标）。非 `null` 时它优先 ——
  /// 拖动期间浮层跟的是光标，不是任何一条规则算出来的位置。
  final Offset? liveOffset;

  /// 布局完成后回报实际位置（容器局部坐标）。**只用来存值，不要 setState**。
  final ValueChanged<Offset>? onPositioned;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = boundsOf(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return CustomSingleChildLayout(
          delegate: _PanelBarLayoutDelegate(
            layout: layout,
            bounds: bounds,
            liveOffset: liveOffset,
            onPositioned: onPositioned,
          ),
          child: child,
        );
      },
    );
  }
}

class _PanelBarLayoutDelegate extends SingleChildLayoutDelegate {
  const _PanelBarLayoutDelegate({
    required this.layout,
    required this.bounds,
    required this.liveOffset,
    required this.onPositioned,
  });

  final PanelBarLayout layout;
  final PanelBarBounds bounds;
  final Offset? liveOffset;
  final ValueChanged<Offset>? onPositioned;

  /// 贴边留的缝 —— 面板栏不该和泳道的圆角边框糊在一起。
  static const double inset = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final live = liveOffset;
    final Offset offset;
    if (live != null) {
      offset = live;
    } else if (layout.mode == PanelBarMode.floating) {
      final floating = panelBarFloatingOffset(
        bounds: bounds,
        positionX: layout.positionX,
        positionY: layout.positionY,
        barWidth: childSize.width,
        barHeight: childSize.height,
      );
      offset = Offset(floating.left, floating.top);
    } else {
      offset = _dockedOffset(childSize);
    }
    // 只存值、不触发重建：这里在布局阶段，`setState` 会抛。
    onPositioned?.call(offset);
    return offset;
  }

  /// 钉在某条边：那条边上居中，并夹进容器。
  ///
  /// 夹取是必须的：泳道被拖得比面板栏还窄时，「居中」会算出负坐标，
  /// 浮层就被 `Stack` 裁掉一半。
  Offset _dockedOffset(Size childSize) {
    double clampBetween(double value, double low, double high) =>
        value.clamp(low, high < low ? low : high).toDouble();

    switch (layout.dock) {
      case PanelBarDock.left:
        return Offset(
          bounds.left + inset,
          clampBetween(
            bounds.top + (bounds.height - childSize.height) / 2,
            bounds.top + inset,
            bounds.bottom - childSize.height - inset,
          ),
        );
      case PanelBarDock.right:
        return Offset(
          clampBetween(
            bounds.right - childSize.width - inset,
            bounds.left + inset,
            bounds.right - childSize.width - inset,
          ),
          clampBetween(
            bounds.top + (bounds.height - childSize.height) / 2,
            bounds.top + inset,
            bounds.bottom - childSize.height - inset,
          ),
        );
      case PanelBarDock.top:
        return Offset(
          clampBetween(
            bounds.left + (bounds.width - childSize.width) / 2,
            bounds.left + inset,
            bounds.right - childSize.width - inset,
          ),
          bounds.top + inset,
        );
      case PanelBarDock.bottom:
        return Offset(
          clampBetween(
            bounds.left + (bounds.width - childSize.width) / 2,
            bounds.left + inset,
            bounds.right - childSize.width - inset,
          ),
          clampBetween(
            bounds.bottom - childSize.height - inset,
            bounds.top + inset,
            bounds.bottom - childSize.height - inset,
          ),
        );
    }
  }

  @override
  bool shouldRelayout(_PanelBarLayoutDelegate oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.liveOffset != liveOffset ||
      oldDelegate.bounds.left != bounds.left ||
      oldDelegate.bounds.top != bounds.top ||
      oldDelegate.bounds.width != bounds.width ||
      oldDelegate.bounds.height != bounds.height;
}
