// 按下时**跟着手指走**的物理形变 —— 全应用按钮共用的那一份。
//
// # 是什么
//
// 按住一颗按钮：它先鼓一下（`lift`），手指按住继续拖，它就朝手指方向被**拽**
// 一点并沿那一轴拉长（`pull`），松手弹回。越拽越沉 —— 越界部分走橡皮筋，
// 所以拽过头有阻尼，不会脱手。
//
// 弹簧与橡皮筋都取自 `spring_lens_value.dart`（与 Dock 的 lens 同一份内核），
// 所以「按钮的手感」与「tab 切换的手感」出自同一条曲线。
//
// # 为什么形变只在 paint 层
//
// [ElasticPress] 内部是 [Listener] + 一个自绘的 `Matrix4` 变换，**不改布局**。
// 于是锚在这颗按钮上的 tooltip / popup menu 看到的一直是静止位置的按钮，
// 不会在按下的过程中飘走或跳位 —— 这与 lens 那条约束是同一条。
//
// # 谁在用
//
// - `navigation_dock.dart` 的 `ElasticPress` / `ElasticButton`（已改成本文件的
//   公开实现，Dock 那份不再自带一份）；
// - `widgets/action_group.dart` 的 `ActionIconButton` / `ActionToggleButton`
//   —— 工具条上每颗图标钮（书架右上角的搜索/筛选、Dock 旁那颗「更多」、
//   文件管理器工具栏、侧栏底部动作区…）都经它，于是**全应用按钮的手感统一**。
//
// 官方 `IconButton` 只有一层 `overlayColor` 水波纹：按下时那颗圈会淡一下，
// 但图形本身不动。所以这里把 `IconButton` 的水波纹关掉（[ElasticPress.buttonStyle]），
// 由形变来承担「被按下了」这个反馈 —— 两者叠加会显得脏。

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

/// 按下时鼓起来、跟着手指被拽走、松手弹回。
///
/// 包在按钮外面即可。**关掉按钮自己的水波纹**（[buttonStyle]），
/// 否则两套反馈会叠在一起。
class ElasticPress extends StatefulWidget {
  const ElasticPress({super.key, this.enabled = true, required this.child});

  /// 关掉 `IconButton` / `FilledButton` 的水波纹与按压高亮。
  ///
  /// 「按下了」这件事已经由形变本身表达（鼓 + 被拽），再叠一层圆形水波纹会
  /// 让按钮看起来脏。两处合成一份 `ButtonStyle`，各调用点直接
  /// `.merge(...)` 进去。
  static const buttonStyle = ButtonStyle(
    splashFactory: NoSplash.splashFactory,
    overlayColor: WidgetStateMapper<Color?>({
      WidgetState.pressed: Colors.transparent,
    }),
  );

  final bool enabled;
  final Widget child;

  @override
  State<ElasticPress> createState() => _ElasticPressState();
}

class _ElasticPressState extends State<ElasticPress>
    with TickerProviderStateMixin {
  late final SpringLensValue _lift = SpringLensValue(this, 0);
  late final SpringLensValue _pullX = SpringLensValue(this, 0);
  late final SpringLensValue _pullY = SpringLensValue(this, 0);
  late final Listenable _motion = Listenable.merge([_lift, _pullX, _pullY]);

  int? _pointer;
  Offset _origin = Offset.zero;

  @override
  void dispose() {
    _lift.dispose();
    _pullX.dispose();
    _pullY.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _origin = event.localPosition;
    _lift.springTo(1, LensMetrics.press);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final size = context.size;
    if (size == null || size.isEmpty) return;
    // 越界量按「最短边的一档」收 —— 按钮都很小，用绝对像素当上限会让大按钮
    // 拽不动、小按钮一下就脱手。
    final limit = size.shortestSide * LensMetrics.pullLimit;
    final pull = event.localPosition - _origin;
    _pullX.springTo(rubberBand(pull.dx, limit), LensMetrics.track);
    _pullY.springTo(rubberBand(pull.dy, limit), LensMetrics.track);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _lift.springTo(0, LensMetrics.settle);
    _pullX.springTo(0, LensMetrics.settle);
    _pullY.springTo(0, LensMetrics.settle);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (_, child) => PressTransform(
          lift: _lift.value,
          pull: Offset(_pullX.value, _pullY.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// 把 [ElasticPress] 的形变套给子树，并在这一层把按钮自己的水波纹关掉。
///
/// 与 `navigation_dock.dart` 里原先那个 `ElasticButton` 同一份实现；Dock 那边的
/// `ElasticPress` / `ElasticButton` 现在是本文件的转发。
class ElasticButton extends StatelessWidget {
  const ElasticButton({super.key, this.enabled = true, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElasticPress(
      enabled: enabled,
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: IconTheme(
          data: IconTheme.of(context),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: ElasticPress.buttonStyle.merge(
                IconButtonTheme.of(context).style,
              ),
            ),
            child: FilledButtonTheme(
              data: FilledButtonThemeData(
                style: ElasticPress.buttonStyle.merge(
                  FilledButtonTheme.of(context).style,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 只在 paint 层施加形变的自绘层。布局与命中测试始终按静止位置算。
class PressTransform extends SingleChildRenderObjectWidget {
  const PressTransform({
    super.key,
    required this.lift,
    required this.pull,
    super.child,
  });

  /// 按下程度（0..1）：鼓起多少。
  final double lift;

  /// 被手指拽走的量（像素）。
  final Offset pull;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPressTransform(lift: lift, pull: pull);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPressTransform renderObject,
  ) {
    renderObject
      ..lift = lift
      ..pull = pull;
  }
}

class RenderPressTransform extends RenderProxyBox {
  RenderPressTransform({required this._lift, required Offset pull})
    : _pull = pull;

  double _lift;
  Offset _pull;

  set lift(double value) {
    if (value == _lift) return;
    _lift = value;
    markNeedsPaint();
  }

  set pull(Offset value) {
    if (value == _pull) return;
    _pull = value;
    markNeedsPaint();
  }

  /// 鼓起 + 沿被拽方向拉长 + 朝被拽方向平移。
  ///
  /// 平移那两项 `center.dx * (1 - scaleX)` 是为了**绕中心缩放**：少了它们，
  /// 形变会把按钮朝左上角拽（缩放的原点在左上），而形变过程中按钮看起来就在
  /// 原地膨胀 —— 这正是我们不想要的「跟着手指走」。
  Matrix4 get _transform {
    final swell =
        1 +
        _lift *
            math.min(
              LensMetrics.pressGrowth * 2,
              LensMetrics.maxPressGrowth / size.longestSide,
            );
    final scaleX =
        swell * (1 + _pull.dx.abs() / size.width * LensMetrics.pullStretch);
    final scaleY =
        swell * (1 + _pull.dy.abs() / size.height * LensMetrics.pullStretch);
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)..setTranslationRaw(
      center.dx * (1 - scaleX) + _pull.dx,
      center.dy * (1 - scaleY) + _pull.dy,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty || (_lift == 0 && _pull == .zero)) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}