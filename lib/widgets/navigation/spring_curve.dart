// 来源：FlClash（https://github.com/chen08209/FlClash），GPL-3.0。
// 原文：`lib/common/motion.dart`，只搬 `SpringCurve` 这一个类
// （同文件的 `fadeTabDuration` / `fadeTabCurve` 是标签页动画，本仓不用）。
//
// 为什么需要它：`AnimatedSize` / `AnimatedSwitcher` 只吃 `Curve`，而 Dock 尾部
// 那颗按钮进出时要的是**弹簧**（`_slotSizeCurve` / `_slotPopCurve`）。
// 直接把 `SpringSimulation` 包成 `Curve` 的难点是弹簧在上报「结束」时通常还没
// 走完 —— 这里用「剩余量按 t 线性补齐」收尾，曲线因此仍然精确落在 1。

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Plays [spring] over the first [seconds] of an animation, easing out the
/// remaining residual so the curve still ends exactly at 1.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  final double seconds;
  final SpringSimulation _simulation;

  late final double _residual = 1 - _simulation.x(seconds);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}
