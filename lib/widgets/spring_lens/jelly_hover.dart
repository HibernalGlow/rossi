// 悬停时的**果冻回弹** —— 与 Dock / tab 条同一份弹簧档位，只是触发源是鼠标。
//
// # 为什么要单独一颗组件
//
// `SpringLensBar`（tab 条）与 `NavigationDock` 的悬停手感是**顺带**长在整条 bar
// 里的：它们要的是「lens 朝指针那一格磁吸」，所以悬停事件先汇到 bar，再分给格子。
// 而书签面板那条分类轨里每一颗是独立控件（`ChoiceChip`），没有 bar 可以汇。
// 这一份把同一套物理（[LensMetrics] 的两根弹簧）搬到**单颗控件**上，于是
// 「鼠标悬停在 tab 上有果冻回弹」这件事在两种容器里是同一个手感，而不是各写
// 一遍曲线。
//
// # 两根弹簧分管两轴
//
// 果冻的关键不是「放大」，是**两轴不同步**：横轴先追上去、纵轴慢半拍再跟上，
// 于是离开时能看到一下轻微的扭捏。横轴走 [LensMetrics.hover]（260ms /
// bounce 0.18，tab 条磁吸用的那一根），纵轴走 [LensMetrics.settle]（500ms /
// bounce 0.32，落位用的那一根）—— 档位不新造，两根都是从现有表里取的。
//
// # 形变只走 paint 层
//
// 变换用 `Transform`（`transformHitTests: false`），布局与命中测试始终按静止
// 矩形算。于是悬停放大时 tooltip 的锚点不会飘，相邻控件的点击区也不会被挤走
// —— 与 `elastic_press.dart` 顶部那条约束是同一个理由。
//
// # 为什么把值交给 builder 而不是包一层自绘
//
// 调用方除了缩放还要**形状**（悬停时轮廓收成一半）。自绘层只能改矩阵，改不了
// 子树里那颗 `ShapeBorder`。所以这里交回数值，让调用方自己组装。代价是悬停
// 期间子树每帧重建一次 —— 一次只有一颗在被悬停，且这条轨上的控件都很小。

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

/// 把子树悬停时的形变量算出来交回给 [builder]。
///
/// 两个值都是 0..约 1.1（弹簧过冲会越过 1）。[swellX] 快、[swellY] 慢，
/// 两者的差就是「果冻」；缩放与形状各自取用（形状那一侧自己会夹到 1，
/// 过冲留给缩放表达）。
class JellyHover extends StatefulWidget {
  const JellyHover({
    super.key,
    required this.builder,
    this.strength = JellyHover.hoverScale,
    this.enabled = true,
  });

  /// 满悬停缩放 = 按下那一档（[LensMetrics.pressGrowth]，12.5%）的一半。
  /// 悬停必须比按下轻，否则两态在视觉上分不开（M3E 的 state layer 同理：
  /// hover 的叠加量低于 pressed）。
  static const double hoverScale = LensMetrics.pressGrowth / 2;

  final Widget Function(BuildContext context, double swellX, double swellY)
  builder;

  final double strength;

  /// 关掉时不挂任何弹簧：尊重系统「减少动画」，也让触摸端不出现悬停残留。
  final bool enabled;

  @override
  State<JellyHover> createState() => _JellyHoverState();
}

class _JellyHoverState extends State<JellyHover> with TickerProviderStateMixin {
  late final SpringLensValue _x = SpringLensValue(this, 0);
  late final SpringLensValue _y = SpringLensValue(this, 0);
  late final Listenable _motion = Listenable.merge([_x, _y]);

  bool _hovered = false;

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (!widget.enabled || _hovered == hovered) return;
    _hovered = hovered;
    if (hovered) {
      _x.springTo(1, LensMetrics.hover);
      _y.springTo(1, LensMetrics.settle);
    } else {
      _x.springTo(0, LensMetrics.settle);
      _y.springTo(0, LensMetrics.settle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strength;
    return MouseRegion(
      // opaque: false —— 这颗壳子不该把悬停从祖先的 MouseRegion 手里抢走。
      opaque: false,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => Transform(
          // `alignment: center` 负责把缩放原点挪到中心，矩阵本身只带缩放。
          transform: Matrix4.diagonal3Values(
            1 + _x.value * s,
            1 + _y.value * s,
            1,
          ),
          alignment: Alignment.center,
          transformHitTests: false,
          child: widget.builder(context, _x.value, _y.value),
        ),
      ),
    );
  }

  /// 引擎在触摸落下前会**合成**一次进入/悬停，而那只触摸指针会一直留着 ——
  /// 不认设备的话，手指点完一下这颗控件会永久停在悬停那一档。
  /// 判据与 tab 条 / Dock 同一句：触摸这一支整个不接。
  void _handleEnter(PointerEnterEvent event) {
    if (event.kind == PointerDeviceKind.touch) return;
    _setHovered(true);
  }

  void _handleExit(PointerExitEvent event) {
    if (event.kind == PointerDeviceKind.touch) return;
    _setHovered(false);
  }
}
