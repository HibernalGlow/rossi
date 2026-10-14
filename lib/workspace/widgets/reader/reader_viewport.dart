import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 为阅读器提供泳道的实际视口，保留局部 Navigator 的实例。
///
/// Flutter 3.47 的 LayoutBuilder 在自己的 performLayout 中再次收到重建请求时，
/// 会留下 needsRebuild=true、needsLayout=false，子树的更新一直等到约束再改变。
/// 泳道输入高亮改变边框尺寸后可以触发它：悬停 Cubit 已更新，栏体却仍显示旧值。
/// 这里沿用框架的布局作用域，仅把布局期间的再次请求合并到下一帧。
class ReaderViewport extends StatelessWidget {
  const ReaderViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _ViewportLayoutBuilder(
    builder: (context, constraints) {
      final fallback = MediaQuery.sizeOf(context);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : fallback.width,
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : fallback.height,
          ),
        ),
        child: child,
      );
    },
  );
}

class _ViewportLayoutBuilder extends AbstractLayoutBuilder<BoxConstraints> {
  const _ViewportLayoutBuilder({required this.builder});

  @override
  final Widget Function(BuildContext, BoxConstraints) builder;

  @override
  RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox>
  createRenderObject(BuildContext context) => _RenderViewportLayout();
}

/// 子树构造、dirty element 列表与约束比较仍由 AbstractLayoutBuilder 管理。
class _RenderViewportLayout extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> {
  bool _inLayout = false;
  bool _deferred = false;

  @override
  void scheduleLayoutCallback() {
    if (!_inLayout) {
      super.scheduleLayoutCallback();
      return;
    }
    if (_deferred) return;
    _deferred = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _deferred = false;
      if (attached) super.scheduleLayoutCallback();
    });
  }

  @override
  void performLayout() {
    _inLayout = true;
    try {
      runLayoutCallback();
      if (child == null) {
        size = constraints.biggest;
      } else {
        child!.layout(constraints, parentUsesSize: true);
        size = constraints.constrain(child!.size);
      }
    } finally {
      _inLayout = false;
    }
  }

  // 与 LayoutBuilder 相同：尚未构造子树时不能猜测它的固有尺寸。
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(debugCannotComputeDryLayout(reason: '阅读视口需要先运行布局回调，不能推测尚未构造的子树。'));
    return Size.zero;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    assert(debugCannotComputeDryLayout(reason: '阅读视口需要先运行布局回调，不能推测尚未构造的子树。'));
    return null;
  }
}
