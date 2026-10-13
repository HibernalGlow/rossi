import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

/// 工具按钮、搜索入口共用的瞬时反馈。只观察指针和焦点，不认领拖动，
/// 不把「搜索 / 设置」当成页签，也不影响输入框的选词手势。
class ActionBubbleRegion extends StatefulWidget {
  const ActionBubbleRegion({super.key, required this.child});
  final Widget child;

  static bool contains(BuildContext context) =>
      context.findAncestorStateOfType<_ActionBubbleRegionState>() != null;

  @override
  State<ActionBubbleRegion> createState() => _ActionBubbleRegionState();
}

class _ActionBubbleRegionState extends State<ActionBubbleRegion>
    with TickerProviderStateMixin {
  final _key = GlobalKey();
  late final _x = SpringLensValue(this, 0);
  late final _y = SpringLensValue(this, 0);
  late final _width = SpringLensValue(this, 0);
  late final _height = SpringLensValue(this, 0);
  late final _alpha = SpringLensValue(this, 0);
  late final _corner = SpringLensValue(this, ControlShape.corner);
  late final _motion = Listenable.merge([
    _x,
    _y,
    _width,
    _height,
    _alpha,
    _corner,
  ]);
  _ActionBubbleTargetState? _hovered;
  _ActionBubbleTargetState? _focused;
  bool _positioned = false;

  void show(
    _ActionBubbleTargetState target, {
    bool focus = false,
    Offset? point,
  }) {
    if (focus) {
      _focused = target;
    } else {
      _hovered = target;
    }
    _move(target, point: point);
  }

  void _move(_ActionBubbleTargetState target, {Offset? point}) {
    final box = target.context.findRenderObject();
    final region = _key.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        region is! RenderBox ||
        !region.hasSize) {
      return;
    }
    var local = Offset.zero & box.size;
    if (point != null && target.widget.rectAt != null) {
      local = target.widget.rectAt!(box.globalToLocal(point), box.size);
    }
    final origin = region.globalToLocal(box.localToGlobal(local.topLeft));
    final rect = origin & local.size;
    final reduced = MediaQuery.disableAnimationsOf(context);
    void update(SpringLensValue value, double destination) {
      if (!_positioned || reduced) {
        value.jumpTo(destination);
      } else if (value.target != destination) {
        value.springTo(destination, LensMetrics.settle);
      }
    }

    update(_corner, target.widget.corner);
    update(_x, rect.center.dx);
    update(_y, rect.center.dy);
    update(_width, rect.width);
    update(_height, rect.height);
    _positioned = true;
    if (reduced) {
      _alpha.jumpTo(1);
    } else if (_alpha.target != 1) {
      _alpha.springTo(1, LensMetrics.track);
    }
  }

  void hide(_ActionBubbleTargetState target, {bool focus = false}) {
    if (focus && _focused == target) _focused = null;
    if (!focus && _hovered == target) _hovered = null;
    final remaining = _hovered ?? _focused;
    if (remaining != null && remaining.mounted) {
      _move(remaining);
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _alpha.jumpTo(0);
    } else {
      _alpha.springTo(0, LensMetrics.track);
    }
  }

  void forget(_ActionBubbleTargetState target) {
    if (_hovered == target) _hovered = null;
    if (_focused == target) _focused = null;
    if (_hovered == null && _focused == null) {
      _alpha.jumpTo(0);
    }
  }

  @override
  void dispose() {
    for (final value in [_x, _y, _width, _height, _alpha, _corner]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: _key,
    foregroundPainter: ActionBubblePainter(
      motion: _motion,
      rect: () => Rect.fromCenter(
        center: Offset(_x.value, _y.value),
        width: _width.value.clamp(0, double.infinity),
        height: _height.value.clamp(0, double.infinity),
      ),
      alpha: () => _alpha.value.clamp(0, 1),
      color: Theme.of(context).colorScheme.primary,
      corner: () => _corner.value,
    ),
    child: widget.child,
  );
}

class ActionBubblePainter extends CustomPainter {
  ActionBubblePainter({
    required Listenable motion,
    required this.rect,
    required this.alpha,
    required this.color,
    required this.corner,
  }) : super(repaint: motion);
  final Rect Function() rect;
  final double Function() alpha;
  final Color color;
  final double Function() corner;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha() <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect(), Radius.circular(corner().clamp(0, 1000))),
      Paint()..color = color.withValues(alpha: .10 * alpha()),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ActionBubblePainter oldDelegate) => true;
}

class ActionBubbleTarget extends StatefulWidget {
  const ActionBubbleTarget({
    super.key,
    required this.child,
    this.enabled = true,
    this.observeFocus = true,
    this.rectAt,
    this.corner = ControlShape.corner,
  });
  final Widget child;
  final bool enabled;

  /// 外层组件已经管理键盘焦点时，不额外插入焦点节点。
  final bool observeFocus;
  final double corner;

  /// 多个页签共用一个入口时，按指针位置返回某一格的静止几何。
  final Rect Function(Offset position, Size size)? rectAt;

  @override
  State<ActionBubbleTarget> createState() => _ActionBubbleTargetState();
}

class _ActionBubbleTargetState extends State<ActionBubbleTarget> {
  _ActionBubbleRegionState? _region;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _region = context.findAncestorStateOfType<_ActionBubbleRegionState>();
  }

  @override
  void deactivate() {
    _region?.forget(this);
    _region = null;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: widget.enabled
        ? (event) => _region?.show(this, point: event.position)
        : null,
    onHover: widget.enabled
        ? (event) => _region?.show(this, point: event.position)
        : null,
    onExit: (_) => _region?.hide(this),
    child: widget.observeFocus
        ? Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (focused && widget.enabled) {
                _region?.show(this, focus: true);
              } else {
                _region?.hide(this, focus: true);
              }
            },
            child: _pointerFeedback(),
          )
        : _pointerFeedback(),
  );

  Widget _pointerFeedback() => Listener(
    onPointerDown: widget.enabled
        ? (event) => _region?.show(this, point: event.position)
        : null,
    onPointerUp: (event) {
      if (event.kind != PointerDeviceKind.mouse) _region?.hide(this);
    },
    onPointerCancel: (_) => _region?.hide(this),
    child: widget.child,
  );
}
