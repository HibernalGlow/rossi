// 全应用**唯一**的「选中态在目的地之间弹跳」实现。
//
// # 为什么要有这个文件
//
// 起点是 `lib/widgets/navigation/navigation_dock.dart` 的 `FloatingNavigationBar`
// （FlClash 搬来的）：Dock 胶囊底栏里那颗 lens 按住会随手指滑、松手按落点选中、
// 甩动按投射距离多走一格、划过两端橡皮筋回弹。那套手感此前**只长在 Dock 里**，
// 书架顶栏、泳道面板页签条各有各的 `AnimatedContainer` / `Material(color:)`。
//
// 这个文件把那套手感的**内核**抽出来，让各处 tab 栏共用同一份：
// 一根可重定向的弹簧（[SpringLensValue]）、一条越界收敛（[rubberBand]）、
// 一份槽位几何（[LensSlots]）、一颗画出来的选中态（[SpringLensIndicator]）。
// 手感档位全在 [LensMetrics] 一处，改它等于全应用一起改。
//
// # 关键约束：形变只发生在 paint 层
//
// lens 的位置、宽度、圆角全是**画**出来的，不参与布局。于是锚在某个 tab 上的
// tooltip / popup menu 看到的一直是静止位置，不会跟着 lens 飘。任何时候都不要
// 为了「让布局跟上形变」去改这里—— 那会把 Dock 那边一个刻意保住的性质弄丢。
//
// # 槽位为什么要自己算，而不是照抄 Dock
//
// Dock 那边的 lens 建立在**等宽**假设上：指针横坐标直接除以「总宽 ÷ 格数」。
// 而本仓要迁过去的书架顶栏那排 tab 是**按文字取宽**的，直接搬会落点全错。
// 所以这里引入 [LensSlots]：先量出每格的实际跨度，再在跨度上反查落点。
// 等宽那一档就是 [LensSlots.uniform]，与 Dock 逐字等价。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/widgets/control_shape.dart';

/// 越过边界时把超出量收敛掉，返回**实际**越过的距离。
///
/// 两处靠它收边：拖动越过两端时的橡皮筋（[LensMetrics.overdrag]），以及按住
/// 横向拖动时整条 bar 的跟手拉伸。所以它是这套 lens 的公共出口，不是某个组件
/// 的私有手感。
///
/// 数学上就是 iOS 那条 `f(x) = (1 - 1/(x·c/d + 1)) · d`：越拖越硬，永远到不了
/// 边界外 `limit` 那么远。
double rubberBand(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}

/// 一根能被手指每帧改目标的弹簧。
///
/// 为什么不用 `AnimationController.animateWith`：它每次调用都会**重启** ticker，
/// 而重启后的第一帧读不到经过的时间，于是每帧重定目标会让值**原地不动** ——
/// 手指按住横移时 lens 卡在原地。这里自己记 `_now` / `_start`，重定目标时只把
/// `_start` 挪到当前时刻，值本身保持连续。
///
/// 同时实现 [ValueListenable]：订阅它的只有画 lens 的那一个 `AnimatedBuilder`，
/// 于是底下那排内容不跟着每帧重绘。
class SpringLensValue extends ChangeNotifier
    implements ValueListenable<double> {
  SpringLensValue(TickerProvider vsync, this._value) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  double _now = 0;
  double _start = 0;

  @override
  double get value => _value;

  /// 正在奔向的落点（已经静止时就是它自己）。
  double get target => _simulation == null ? _value : _target;

  /// 当前速度（格/秒）。果冻拉伸读它。
  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  void springTo(double target, SpringDescription spring) {
    _simulation = SpringSimulation(spring, _value, target, velocity);
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  /// 立刻落位，不播动画（初始化与首帧用）。
  void jumpTo(double value) {
    _simulation = null;
    _ticker.stop();
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// 一条 bar 上那几格的**实际几何**。
///
/// 存在的理由见文件头：Dock 的 lens 假定等宽，而按内容取宽的 tab 栏不能沿用那个
/// 假定。量出每格跨度之后，lens 的落点、宽度、以及「这一格有多宽」才有一份
/// 共同的账—— 画图的与命中测试读的是同一份数。
///
/// 轴向也在这里（[axis]）：Dock 只做横轨，可泳道面板页签条有竖轨，
/// 竖着排的那份不能另写一套换算。
@immutable
class LensSlots {
  const LensSlots({
    required this.starts,
    required this.spans,
    this.crossStart = 0,
    this.crossSize = 0,
    this.axis = Axis.horizontal,
  }) : assert(starts.length == spans.length);

  /// 每格**近端**在主轴上的坐标（第一格通常不是 0 —— 那是 bar 的内边距）。
  final List<double> starts;

  /// 每格起点到下一格起点的距离。
  ///
  /// 最后一格后面的插缝没有下一个格子跟着，它的跨度是 `0`：落点换算会跳过它，
  /// 但 [length] 仍要算进去（它是轨道的一部分）。
  final List<double> spans;

  /// 内容在**副轴**上的起点（通常是 bar 的那一圈内边距）。
  final double crossStart;

  /// 槽的副轴尺寸：横轨时是槽高，竖轨时是槽宽。
  final double crossSize;

  final Axis axis;

  bool get isEmpty => starts.isEmpty;

  int get count => starts.length;

  /// 轨道总长（最后一格起点 + 它的跨度）。
  double get length => starts.isEmpty ? 0 : starts.last + spans.last;

  double startOf(int index) => starts[index];

  double spanOf(int index) => index < spans.length ? spans[index] : 0;

  double centerOf(int index) => starts[index] + spanOf(index) / 2;

  /// 等宽一档。`leading` 是轨道起点（通常是那条 bar 的内边距）。
  factory LensSlots.uniform({
    required int count,
    required double extent,
    double leading = 0,
    double crossStart = 0,
    double crossSize = 0,
    Axis axis = Axis.horizontal,
  }) {
    return LensSlots(
      starts: [for (var i = 0; i < count; i++) leading + extent * i],
      spans: [for (var i = 0; i < count; i++) extent],
      crossStart: crossStart,
      crossSize: crossSize,
      axis: axis,
    );
  }

  /// 按内容取宽一档：给每格的跨度，按顺序排。
  factory LensSlots.sized({
    required List<double> sizes,
    double leading = 0,
    double crossStart = 0,
    double crossSize = 0,
    Axis axis = Axis.horizontal,
  }) {
    final starts = <double>[];
    final spans = <double>[];
    var cursor = leading;
    for (final size in sizes) {
      starts.add(cursor);
      spans.add(size);
      cursor += size;
    }
    return LensSlots(
      starts: starts,
      spans: spans,
      crossStart: crossStart,
      crossSize: crossSize,
      axis: axis,
    );
  }

  /// 主轴坐标 → **格位**（可以是小数：0.5 = 第一格与第二格正中）。
  ///
  /// # 格位的原点是格**中心**，不是格起点
  ///
  /// 整数就落在那一格的中心上，于是 `0.5` 恰好是两格正中、`-0.5` 是第一格的
  /// 近端。这与 Dock 那份 `_positionAt`（`(dx - padding) / extent - 0.5`）是同一套
  /// 约定 —— 两者能共用同一个 [lensRect] 就靠这一点。
  ///
  /// 越界部分按 [overdrag] 收进橡皮筋，于是拖过头时落点仍然连续，只是越挪越沉
  /// —— 这是「划过两端回弹」的落点侧。
  double positionAt(double along, {double overdrag = 0.35}) {
    if (starts.isEmpty) return 0;
    // 轨道之前：**从第一格的近端接着往回折**（近端本身是格位 -0.5）。
    // 别直接把越界像素喂给橡皮筋就返回 —— 那样 −10px 会得 −0.33 格，
    // 反而比近端的 −0.5 更靠内，落点会「跳回轨道里」，橡皮筋等于白做。
    if (along < starts.first) {
      return _rubberBandFrom(
        index: 0,
        edge: starts.first,
        edgePosition: -0.5,
        along: along,
        span: spanOf(0),
        overdrag: overdrag,
        towardsLeft: true,
      );
    }
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      if (along < start) {
        // 落在某一格**之前**的空隙里（插缝、间距）：归到上一格去折算。
        return _positionIn(i - 1, along, overdrag);
      }
      final span = spanOf(i);
      if (along <= start + span) {
        return _positionIn(i, along, overdrag);
      }
    }
    // 末尾之后：同样从末格的远端接着往外折。
    final last = starts.length - 1;
    return _rubberBandFrom(
      index: last,
      edge: starts[last] + spanOf(last),
      edgePosition: last + 0.5,
      along: along,
      span: spanOf(last),
      overdrag: overdrag,
      towardsLeft: false,
    );
  }

  /// 从某一格的**边沿**（[edgePosition] 那个格位）往外用橡皮筋折算。
  ///
  /// 关键是橡皮筋量出来的是**像素**，除以该格跨度才回到格位 —— 于是越界拖动
  /// 与格内拖动的「每像素多少格」是同一个比例，手感连续。
  double _rubberBandFrom({
    required int index,
    required double edge,
    required double edgePosition,
    required double along,
    required double span,
    required double overdrag,
    required bool towardsLeft,
  }) {
    if (span <= 0) return edgePosition;
    final beyond = towardsLeft ? edge - along : along - edge;
    // 往左越界时橡皮筋要**减**：edgePosition 是 −0.5，再往下就该更负。
    // 直接加会让 −10px 折出 −0.4967（反而退回轨道内侧），橡皮筋等于白做。
    final band = rubberBand(beyond, overdrag) / span;
    return towardsLeft ? edgePosition - band : edgePosition + band;
  }

  /// 第 [index] 格内（或其外）的一点折算成格位：格中心 = 整数。
  ///
  /// 格内线性；越出远端才上橡皮筋 —— 越界收敛只该作用在**真正出了轨道**的那段
  /// 上，格内的 0.3、0.7 必须原样线性给出去（否则等宽 bar 上拖动会有「先粘住
  /// 一下再动」的手感）。
  double _positionIn(int index, double along, double overdrag) {
    final span = spanOf(index);
    if (span <= 0) return index.toDouble();
    final center = centerOf(index);
    final far = center + span / 2;
    if (along <= far) {
      return index + (along - center) / span;
    }
    return index + 0.5 + rubberBand(along - far, overdrag) / span;
  }

  /// **格位** → 最近的一格下标（越界夹取）。
  int indexAt(double position) =>
      position.round().clamp(0, math.max(0, starts.length - 1));

  /// 把副轴上那两个「当时还不知道是多少」的数，按 [size] 补齐。
  ///
  /// 存在的理由：横轨常常被放进 `Column` / 无限高的 `ListView` 里，那一维的
  /// 约束是 `infinity` —— 布局期拿不到「lens 该铺多高」。而绘制期一定拿得到
  /// （`CustomPaint` 的 `size` 是解完约束的实值）。于是构造时副轴先填 0，
  /// 画的时候用这份 `size` 补出来。
  ///
  /// 返回 `null` 表示**量不出来**（size 为空），此时不该画任何东西。
  LensSlots? resolvedTo(Size size) {
    if (size.isEmpty || crossSize > 0) return this;
    final along = axis == Axis.horizontal ? size.width : size.height;
    final cross = axis == Axis.horizontal ? size.height : size.width;
    if (cross <= 0 || along <= 0) return null;
    return LensSlots(
      starts: starts,
      spans: spans,
      crossStart: crossStart,
      crossSize: cross,
      axis: axis,
    );
  }
}

/// lens 的手感常量。
///
/// 数值取自 Dock 那份搬来的实现（见 `navigation_dock.dart` 顶部注释里的尺寸档）。
/// 收在一处是为了让「Dock 与别处切换的手感**一样**」这件事有账可查。
abstract final class LensMetrics {
  /// 按下时 lens 相对静止位置的涨幅。
  static const double growth = 11;

  /// 按下时底下那颗内容的放大倍率（0.12 = 最多放大一成二）。
  static const double magnify = 0.12;

  /// 速度到这个数（格/秒）时果冻拉伸到最大。
  static const double jellySpeed = 8;

  /// 果冻拉伸比例（越快越「拉长」）。
  static const double jellyStretch = 0.25;

  /// 拖动越过两端时，越界量收敛到几个格宽。
  static const double overdrag = 0.35;

  /// 按住沿主轴拖动时，整条 bar 跟手拉伸的比例。
  static const double barPullStretch = 0.5;

  /// 鼠标悬停高亮的透明度。
  static const double hoverAlpha = 0.08;

  /// 悬停时被指着的那格追过去的比例。
  static const double hoverMagnet = 0.2;

  /// 内容视差：底下内容追过去的比例（比 [hoverMagnet] 小，所以有层次）。
  static const double hoverParallax = 0.5;

  /// 悬停时整条 bar 的鼓起。
  static const double hoverSwell = 0.4;

  /// 甩动投射：取松手前 [flingProjection] 内的位移当作额外的格数。
  static const Duration flingProjection = Duration(milliseconds: 100);

  // ── 按钮按压（`ElasticPress`） ─────────────────────────────────────────
  //
  // 这一档不是 lens 的，是按钮的：按下时鼓多少、被手指拽出界时按什么收边。
  // 与上面几档并列放在这里，是为了让「整套物理」只有一份档位表。

  /// 按下时鼓起一档。
  static const double pressGrowth = 1 / 8;

  /// 鼓起的上限（防止极小的按钮被按成两倍）。
  static const double maxPressGrowth = 16;

  /// 沿主轴被拽出去时，最多拽出「最短边 × 该比例」。
  static const double pullLimit = 7 / 32;

  /// 被拽出的那部分再拉长多少（沿被拽方向的那一轴）。
  static const double pullStretch = 0.5;

  // ── 弹簧 ───────────────────────────────────────────────────────────────
  //
  // 四根分工：跟手（短、要跟）、落位（长、带一点过冲）、悬停（软）、淡入淡出
  //（最短）。档位照Dock 那份，别随手改其中一根而不看另外三根。

  /// 跟手：手指按住拖动时逐帧重定目标的那一根。
  static final SpringDescription track =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 120),
      );

  /// 抬起 / 切档落位。
  static final SpringDescription settle =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 500),
        bounce: 0.32,
      );

  /// 悬停的磁吸。
  static final SpringDescription hover =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 260),
        bounce: 0.18,
      );

  /// 淡入淡出（悬停高亮）。
  static final SpringDescription fade = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 200),
  );

  /// 按钮按下鼓起（`ElasticPress` 的 `lift`）：比 [track] 慢一点，好让「鼓」
  /// 这件事看得见；带一点过冲，手感才不死。
  static final SpringDescription press =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 280),
        bounce: 0.2,
      );
}

/// 选中态那颗 lens 的盒子，**已经按 [LensSlots.axis] 摆正**（可以直接喂给
/// `Positioned` / `PositionedDirectional`）。
///
/// # 位置与宽度都按**格边沿**插值，不按格中心
///
/// 格位是以格中心为原点的（[LensSlots.positionAt]），所以格位 `i + 0.5` 落在
/// 「第 i 格的远端」，而那里正是「第 i+1 格的近端」。于是把格位换算回像素时，
/// 要在**相邻两格的边沿**之间插值：
///
/// - 位置 = lerp(本格近端, 邻格近端, 小数位 × 2 − 0.5 的映射)；
/// - 宽度 = lerp(本格跨度, 邻格跨度, 同一份小数位)。
///
/// 这样等宽 bar 上得到的是「恒宽平移」（与 Dock 那份逐字等价），而不等宽 bar
/// 上得到的是**lens 自己变宽变窄**—— 书架顶栏那排文字 tab 的手感就从这里来。
///
/// [velocity] 驱动果冻拉伸：越快越拉长，停下来立刻收回。
/// [lift] 是按下程度：lens 鼓起，底下内容跟着放大（放大在 `_MotionTransform`）。
Rect lensRect({
  required LensSlots slots,
  required double position,
  required double velocity,
  required double lift,
}) {
  if (slots.isEmpty) return Rect.zero;
  final stretch =
      (velocity.abs() / LensMetrics.jellySpeed).clamp(0.0, 1.0) *
      LensMetrics.jellyStretch;
  final growth = LensMetrics.growth * 2 * lift.clamp(0.0, 1.0);

  final last = math.max(0, slots.count - 1);
  // **格位约定**：整数 i 恒等于第 i 格的**中心**（由 `positionAt` 保证）。
  // 要在「第 i 格内」插值，就得先把格位平移半格：`u = position + 0.5` 让
  // `u == i` 正好落在第 i 格的**近端**。这一句是整个插值模型的枢轴 ——
  // 少了它，`floor` 与 `round` 两套取整就会各说各话。
  final u = position + 0.5;
  // 用 `floor` 而不是 `round`：`u == 0.75` 落在第 0 格内的后半段，若按 `round`
  // 归到第 1 格再插值，格位与像素就不再互为逆运算。
  final int index = u.floor().clamp(0, last);
  final t = (u - index).clamp(0.0, 1.0);
  final int neighbour = math.min(index + 1, last);

  final spanFrom = slots.spanOf(index);
  final spanTo = slots.spanOf(neighbour);
  // 末格没有「下一格」：它的远端就是自己的近端 + 自己的跨度。用 `neighbour`
  // 的起点会让 `along` 退化成格子的近端（lens 掉到格子左边），这一行是那个坑。
  final near = slots.startOf(index);
  final nearOther = neighbour > index
      ? slots.startOf(neighbour)
      : near + spanFrom;
  final along = near + (nearOther - near) * t;

  // 宽度是**帐篷形**：格心处最宽（就是本格的跨度），向两边各走到与邻格跨度的
  // 均值。写成 `spanFrom + Δ右·max(0, t−0.5) + Δ左·max(0, 0.5−t)` 是因为
  // 「格位↔像素」在这套约定下不是仿射的（格位 0 是**中心**而不是近端）。
  // 等宽时两个 Δ 都是 0 ⇒ 恒宽平移，与 Dock 那份逐字等价。
  final spanPrev = slots.spanOf(math.max(0, index - 1));
  final width =
      (spanFrom +
          (spanTo - spanFrom) * math.max(0.0, t - 0.5) +
          (spanPrev - spanFrom) * math.max(0.0, 0.5 - t) +
          growth) *
      (1 + stretch);

  final crossSize = slots.crossSize;
  final cross = (crossSize + growth) * (1 - stretch / 2);
  final crossOffset = slots.crossStart + (crossSize - cross) / 2;

  return slots.axis == Axis.horizontal
      ? Rect.fromLTWH(along - width / 2, crossOffset, width, cross)
      : Rect.fromLTWH(crossOffset, along - width / 2, cross, width);
}

/// 选中态的那颗 lens。
///
/// 只**画**，不布局：它覆盖在内容底下，而内容始终按静止位置排布 ——
/// 所以锚在某个 tab 上的 tooltip / popup 不会跟着 lens 飘。
///
/// 颜色由调用方给（本仓各处统一走 `secondaryContainer` 那一档，见
/// `widgets/action_group.dart` 的 `selected` 口径），这里不替调用方决定外观。
class SpringLensIndicator extends StatelessWidget {
  const SpringLensIndicator({
    super.key,
    required this.slots,
    required this.position,
    required this.velocity,
    required this.lift,
    required this.color,
    this.corner,
  });

  final LensSlots slots;
  final double position;
  final double velocity;
  final double lift;
  final Color color;

  /// 圆角；默认使用与页签、筛选相同的圆角矩形。
  final double? corner;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final rect = lensRect(
      slots: slots,
      position: position,
      velocity: velocity,
      lift: lift,
    );
    final child = DecoratedBox(
      decoration: ShapeDecoration(
        color: color,
        shape: ControlShape.withCorner(corner),
      ),
    );
    return slots.axis == Axis.horizontal
        ? PositionedDirectional(
            start: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: child,
          )
        : Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: child,
          );
  }
}