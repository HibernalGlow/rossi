import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// 优先对 [DeferPointer] 进行命中测试，以便在父级布局之外渲染的元素
/// 仍可在容器范围内响应触摸与指针事件。
class DeferredPointerHandler extends StatefulWidget {
  final Widget child;

  const DeferredPointerHandler({super.key, required this.child});

  @override
  State<DeferredPointerHandler> createState() => _DeferredPointerHandlerState();
}

class _DeferredPointerHandlerState extends State<DeferredPointerHandler> {
  final _targets = <_RenderDeferPointer>[];

  @override
  Widget build(BuildContext context) {
    return _DeferredPointerScope(
      targets: _targets,
      child: _DeferredPointerHitTarget(targets: _targets, child: widget.child),
    );
  }
}

class _DeferredPointerScope extends InheritedWidget {
  final List<_RenderDeferPointer> targets;

  const _DeferredPointerScope({required this.targets, required super.child});

  static List<_RenderDeferPointer> of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_DeferredPointerScope>();
    assert(
      scope != null,
      'DeferPointer needs a DeferredPointerHandler above in the widget tree.',
    );
    return scope!.targets;
  }

  @override
  bool updateShouldNotify(_DeferredPointerScope oldWidget) {
    return targets != oldWidget.targets;
  }
}

class _DeferredPointerHitTarget extends SingleChildRenderObjectWidget {
  final List<_RenderDeferPointer> targets;

  const _DeferredPointerHitTarget({required this.targets, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDeferredPointerHitTarget(targets);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDeferredPointerHitTarget renderObject,
  ) {
    renderObject.targets = targets;
  }
}

class _RenderDeferredPointerHitTarget extends RenderProxyBox {
  List<_RenderDeferPointer> targets;

  _RenderDeferredPointerHitTarget(this.targets);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    for (final target in targets.reversed) {
      final child = target.child;
      if (child == null || !child.attached || !child.hasSize) {
        continue;
      }
      final hit = result.addWithPaintTransform(
        transform: child.getTransformTo(this),
        position: position,
        hitTest: (result, position) {
          return child.hitTest(result, position: position);
        },
      );
      if (hit) {
        return true;
      }
    }
    return super.hitTest(result, position: position);
  }
}

/// 将事件代理到最近的 [DeferredPointerHandler]，允许 [child] 在溢出边界时接收事件。
class DeferPointer extends SingleChildRenderObjectWidget {
  const DeferPointer({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDeferPointer(_DeferredPointerScope.of(context));
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDeferPointer).targets =
        _DeferredPointerScope.of(context);
  }
}

class _RenderDeferPointer extends RenderProxyBox {
  List<_RenderDeferPointer> _targets;

  _RenderDeferPointer(this._targets);

  set targets(List<_RenderDeferPointer> value) {
    if (identical(value, _targets)) {
      return;
    }
    _targets.remove(this);
    _targets = value;
    if (attached) {
      _targets.add(this);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _targets.add(this);
  }

  @override
  void detach() {
    _targets.remove(this);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}
