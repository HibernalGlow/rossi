import 'package:flutter/widgets.dart';

/// 泳道自动定位沿用真实滚动活动，重复请求不重启，换目标承接当前速度。
/// 用户的点击、拖动和滚轮仍可通过标准 ScrollPosition 中断它。
class WorkspaceLaneScrollController extends ScrollController {
  bool get isPositioning =>
      hasClients && (position as _LaneScrollPosition).isPositioning;

  void positionTo(double target) {
    if (hasClients) (position as _LaneScrollPosition).positionTo(target);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _LaneScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _LaneScrollPosition extends ScrollPositionWithSingleContext {
  _LaneScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 900,
    ratio: 1,
  );

  bool get isPositioning => activity is _LanePositioningActivity;

  void positionTo(double requested, {bool force = false}) {
    final target = requested.clamp(minScrollExtent, maxScrollExtent).toDouble();
    final current = activity;
    if (!force &&
        current is _LanePositioningActivity &&
        (current.target - target).abs() < .5) {
      return;
    }
    final velocity = current?.velocity ?? 0;
    if ((pixels - target).abs() < .25 && velocity.abs() < 2) {
      goIdle();
      return;
    }
    beginActivity(
      _LanePositioningActivity(
        this,
        target,
        ScrollSpringSimulation(
          _spring,
          pixels,
          target,
          velocity,
          tolerance: const Tolerance(distance: .25, velocity: 2),
        ),
      ),
    );
  }
}

class _LanePositioningActivity extends BallisticScrollActivity {
  _LanePositioningActivity(
    _LaneScrollPosition position,
    this.target,
    Simulation simulation,
  ) : super(position, simulation, position.context.vsync, false);

  final double target;
  _LaneScrollPosition get _position => delegate as _LaneScrollPosition;

  @override
  void resetActivity() => _position.positionTo(target, force: true);

  @override
  void applyNewDimensions() => resetActivity();

  @override
  bool applyMoveTo(double value) => super.applyMoveTo(
    value
        .clamp(_position.minScrollExtent, _position.maxScrollExtent)
        .toDouble(),
  );
}
