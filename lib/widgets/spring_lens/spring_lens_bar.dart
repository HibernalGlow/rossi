// 带弹簧 lens 的 tab 栏 —— 全应用 tab 切换的统一落点。
//
// # 是什么
//
// 一条 bar，选中态是一颗在目的地之间弹跳的 lens（`SpringLensIndicator`）。
// 点一下切换时lens 弹过去；按住可以**拖着走**、跨格有触感回馈、甩一下按投射
// 距离多走一格、越过两端橡皮筋回弹。这套手感原本只长在 Dock 里，现在共用
// `spring_lens_value.dart` 那份内核。
//
// # 与 Dock 那份的关系
//
// `navigation_dock.dart` 的 `FloatingNavigationBar` **没有**改成用这个组件：
// 它的拖动跟手、悬停视差、长度自适应标签缩放、尾部按钮的「物质化」转场是一整套
// 搬来的实现，改写它就等于把它与 FlClash 上游的对照价值弄没了（那份文件的价值
// 就在于还能对着上游读）。这里是**另立一份**：共用同一颗弹簧、同一份几何、同一个
// 档位表，于是两处手感一致，而各自的代码仍各自可读。
//
// # 为什么单独收一个组件而不是各处各写
//
// 三处已经迁进来的地方（书架顶栏 / 泳道面板页签条 / 侧栏指示条）形态差得很远：
// 等宽与不等宽、横排与竖排、可滚动与不可滚动、能不能拖动跟手。原先每一处都得
// 自己重算一遍落点，于是「lens 该落在哪一格」在三个文件里有三个口径。
//
// # `draggable` 为什么是参数
//
// 泳道面板页签条那一处**不能**给拖动跟手：那里 `LongPressDraggable`（220ms
// 延时）已经在用同一片手势区做拖排序与跨泳道搬运，两个手势物理互斥，抢起来
// 拖排序就废了。所以那一档只借「点一下 lens 弹过去」的丝滑。
//
// 反过来，任何**已经**有长按拖动的 tab 栏都该传 `draggable: false`。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/control_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

part 'spring_lens_painter.dart';
part 'spring_lens_slot.dart';

/// 一条 tab 栏的度量。收在一处，口径与 [SpringLensBar] 的画图读同一份数。
abstract final class SpringLensBarMetrics {
  /// 按下时 lens 的涨幅。
  static const double growth = LensMetrics.growth;

  /// 按下时底下内容的放大倍率。
  static const double magnify = LensMetrics.magnify;

  /// 悬停高亮的透明度。
  static const double hoverAlpha = LensMetrics.hoverAlpha;

  /// 悬停时被指着的那格追过去的比例。
  static const double hoverMagnet = LensMetrics.hoverMagnet;

  /// 内容视差（比 [hoverMagnet] 小，所以有层次）。
  static const double hoverParallax = LensMetrics.hoverParallax;

  /// 甩动投射的时长。
  static const Duration flingProjection = LensMetrics.flingProjection;
}

/// 一条 bar 上的一格。
@immutable
class SpringLensTab {
  const SpringLensTab({required this.child, this.semanticLabel, this.tooltip});

  /// 这一格画什么（图标 / 图标+文字 / 只有文字，由调用方定）。
  final Widget child;

  /// 无障碍读屏用的名字；不给就用 `child` 自己的语义。
  final String? semanticLabel;

  /// 鼠标悬停的提示。给了才包 `Tooltip`，不给就不包。
  final String? tooltip;
}

/// 一条带弹簧 lens 的 tab 栏。
///
/// 两种槽位给定法：
/// - **等宽**：`SpringLensBar` 自己按内容均分（对应 `LensSlots.uniform`）——
///   Dock 那一档、Dock 那份 `FloatingNavigationBar` 就是这么算的；
/// - **按内容取宽**：调用方给 [tabSizes]，lens 按真实跨度算落点
///   （对应 `LensSlots.sized`）—— 书架顶栏那排文字 tab 就是这一档。
///
/// 两种都只影响**落点换算**，画出来的 lens 一模一样。
class SpringLensBar extends StatefulWidget {
  const SpringLensBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.axis = Axis.horizontal,
    this.tabSizes,
    this.draggable = true,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.lensColor,
    this.lensCorner,
    this.lensShadow,
    this.tintColor,
    this.padding = EdgeInsets.zero,
    this.semanticContainer = true,
  });

  final List<SpringLensTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  final Axis axis;

  /// 每格沿主轴的跨度。**不给就是等宽**（按份数均分可用宽度）。
  ///
  /// 给了就必须与 [tabs] 等长。lens 的落点、宽度、以及「这一格有多宽」都读它，
  /// 所以量出来的数与画出来的形状是同一份账。
  final List<double>? tabSizes;

  /// 按住能不能拖着走。
  ///
  /// 传 `false` 的场合：**那一处已经有别的拖动手势**（例如泳道面板页签条的
  /// 长按拖排序），抢手势会让那个功能失效。那时只保留点击切换时的弹跳。
  final bool draggable;

  final CrossAxisAlignment crossAxisAlignment;

  /// lens 的底色。不给取 `secondaryContainer` 那一档 —— 与本仓
  /// `widgets/action_group.dart` 的 `selected` 口径一致（选中走tonal 底色，
  /// 不另起一套视觉语言）。
  final Color? lensColor;

  /// lens 的圆角：默认 12；文字和图标页签可按尺寸分别指定。
  /// 选中、悬停与内容染色共用此轮廓。
  final double? lensCorner;

  /// lens 的投影；不给就不画。
  ///
  /// 给「选中块读作一块**浮起的**卡片」那种设计用：书架那排 tab 改造前就是
  /// `surface` 底 + 一层很淡的投影（`black@5%`、`blurRadius: 4`、下移 1px），
  /// 换成 lens 之后要把这层观感带回来（2026-10-11 用户截图）。
  final Shadow? lensShadow;

  /// 选中那格的**内容**是否被强制染成这个色；不给就不动内容色。
  ///
  /// 走的是 `BlendMode.srcIn`，也就是**替换**掉内容原本的颜色。
  /// 默认关是有理由的：书架那排 tab 的内容是**文字**，改造前选中的字就是普通的
  /// `textColor`；早先这里写死 `primary`，于是选中的字被染成粉色，与「未选中
  /// 60% 透明」那套分档对不上（2026-10-11 用户截图报的就是这一处）。
  /// 内容自己带选中态配色的地方（面板页签条那颗图标）本就该关掉。
  final Color? tintColor;

  /// 内容与轨道之间的内边距（也是 lens 的副轴起点）。
  final EdgeInsets padding;

  /// 是否给每一格套一层 `Semantics(selected:)`。整条 bar 是一个选择组时开着。
  final bool semanticContainer;

  @override
  State<SpringLensBar> createState() => SpringLensBarState();
}

class SpringLensBarState extends State<SpringLensBar>
    with TickerProviderStateMixin {
  late final SpringLensValue _lens = SpringLensValue(
    this,
    widget.selectedIndex.toDouble(),
  );
  late final SpringLensValue _lift = SpringLensValue(this, 0);
  late final SpringLensValue _hover = SpringLensValue(this, 0);
  late final SpringLensValue _hoverShow = SpringLensValue(this, 0);
  late final SpringLensValue _stretch = SpringLensValue(this, 0);
  late final Listenable _motion = Listenable.merge([_lens, _lift]);
  late final Listenable _hoverMotion = Listenable.merge([_hover, _hoverShow]);

  int? _pointer;
  int? _pressedIndex;
  double _pressAlong = 0;
  bool _dragging = false;
  VelocityTracker? _tracker;
  Offset? _cursor;
  final ValueNotifier<double?> _hoverAt = ValueNotifier(null);

  int get _lastIndex => math.max(0, widget.tabs.length - 1);

  int get _selectedIndex => widget.selectedIndex.clamp(0, _lastIndex);

  @override
  void initState() {
    super.initState();
    if (_selectedIndex != widget.selectedIndex) {
      _lens.jumpTo(_selectedIndex.toDouble());
    }
  }

  @override
  void didUpdateWidget(covariant SpringLensBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 目的地数量变了（下标可能被夹到别处）时直接落位，不弹。
    if (oldWidget.tabs.length != widget.tabs.length) {
      _lens.jumpTo(_selectedIndex.toDouble());
      return;
    }
    final rest = _lensRest;
    if (_pressedIndex == null && _lens.target != rest) {
      _lens.springTo(rest, LensMetrics.settle);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _lift.dispose();
    _hover.dispose();
    _hoverShow.dispose();
    _stretch.dispose();
    _hoverAt.dispose();
    super.dispose();
  }

  // ── 几何 ───────────────────────────────────────────────────────────────

  /// 当前这一帧的槽位几何。
  ///
  /// 两条路：调用方给了 [SpringLensBar.tabSizes] 就走不等宽，否则按份数均分。
  ///
  /// **原点是内容的原点（0），不是内边距之后的那个点**：内边距由 `build`
  /// 加在 `Stack` **外面**（见那里的注释），所以槽位坐标与 `Stack` 的坐标
  /// 天然重合，不需要再补一段前导偏移。
  ///
  /// **副轴留 0**：那一维只有绘制期才知道（由 `LensSlots.resolvedTo` 按实到的
  /// `size` 补）。这里猜过一版「约束有界就用约束」，在 AppBar 里把 lens 画成了
  /// 48 高而内容只有 32 —— 比胶囊还高出一截。
  LensSlots _slotsFor(BuildContext context, double availableAlong) {
    final sizes = widget.tabSizes;
    if (sizes != null && sizes.length == widget.tabs.length) {
      return LensSlots.sized(sizes: sizes, axis: widget.axis);
    }
    // 均分档**必须有界**：它要拿可用长度除以份数。无界（外层是横向
    // `SingleChildScrollView` / 未加约束的 `Row`）时除法得到 `infinity`，
    // 于是每一格是无限宽 —— 框架在布局期直接抛
    // 「BoxConstraints forces an infinite width」（实测踩到过）。
    //
    // 这一档没有「正确的猜测」：均分的前提就是「知道整条多长」。真要在无边界的
    // 地方用，就该由调用方量出每格宽度走 `tabSizes`（那一条与长度无关）。
    // 所以这里 debug 下**明确断言**，release 下退回屏幕那一维兜住不崩。
    final horizontal = widget.axis == Axis.horizontal;
    assert(availableAlong.isFinite, '均分档需要一个有界的主轴约束；无界时请传 tabSizes（按内容取宽）');
    final along = availableAlong.isFinite
        ? availableAlong
        : (horizontal
              ? MediaQuery.sizeOf(context).width
              : MediaQuery.sizeOf(context).height);
    // 均分成 0 时兜一个 1，否则 lens 宽度为零会整颗消失（空 bar / 极端窄）。
    final span = math.max(1.0, along / math.max(1, widget.tabs.length));
    return LensSlots.uniform(
      count: widget.tabs.length,
      extent: span,
      axis: widget.axis,
    );
  }

  double _alongOf(Offset localPosition) =>
      widget.axis == Axis.horizontal ? localPosition.dx : localPosition.dy;

  /// 静止时lens 该在哪儿（被指针磁吸时会偏一点点）。
  double get _lensRest {
    final hoverAt = _hoverAt.value;
    if (hoverAt == null || hoverAt.round() != _selectedIndex) {
      return _selectedIndex.toDouble();
    }
    final index = hoverAt.round();
    return index + (hoverAt - index) * LensMetrics.hoverMagnet;
  }

  void _leanLens() {
    if (_pressedIndex != null || _lens.target.round() != _selectedIndex) {
      return;
    }
    final rest = _lensRest;
    if (_lens.target != rest) {
      _lens.springTo(rest, LensMetrics.hover);
    }
  }

  // ── 悬停（鼠标那一支） ───────────────────────────────────────────────────

  void _handleHover(PointerHoverEvent event) {
    // 引擎会在触摸落下前合成一次 hover，而那只触摸指针会一直留着 ——
    // 于是点一下之后高亮会赖着不走。触摸这一支整个不接。
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    final slots = _lastSlots;
    if (slots == null || slots.isEmpty) return;
    _cursor = event.localPosition;
    final position = slots.positionAt(
      _alongOf(event.localPosition),
      overdrag: LensMetrics.overdrag,
    );
    _hoverAt.value = position;
    if (_hoverShow.target == 0 && _hoverShow.value == 0) {
      _hover.jumpTo(position);
    } else {
      _hover.springTo(position, LensMetrics.hover);
    }
    _hoverShow.springTo(1, LensMetrics.fade);
    _leanLens();
  }

  void _handleExit(PointerExitEvent event) {
    _cursor = null;
    _hoverShow.springTo(0, LensMetrics.fade);
    _hoverAt.value = null;
    _leanLens();
  }

  // ── 按下 / 拖动 / 甩动 ──────────────────────────────────────────────────

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _hoverShow.springTo(0, LensMetrics.fade);
    _hoverAt.value = null;
    if (widget.draggable) {
      _lift.springTo(1, LensMetrics.press);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _tracker?.addPosition(event.timeStamp, event.position);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null && _dragging) {
      _fling(tracker.getVelocity());
    }
    _release(commit: event is PointerUpEvent && _dragging);
    _dragging = false;
    if (_cursor != null) {
      _cursor = event.localPosition;
      _handleHover(PointerHoverEvent(position: event.localPosition));
    }
  }

  /// 按下那一刻定住落点。**返回是否跨了格**（跨格要弹触感）。
  ///
  /// 收的是**已经算好的落点**而不是坐标：几何是布局给的、坐标是手势给的，
  /// 在 build 里把两者合成一个格位再传进来，于是「画的」与「判的」读的是
  /// 同一份数 —— 这正是记忆里那条「命中测试始终按静止位置算」的延续。
  bool _press(double position) {
    if (widget.tabs.isEmpty) return false;
    final index = _lastSlots == null
        ? _pressedIndex
        : _lastSlots!.indexAt(position);
    if (_pressedIndex == index) return false;
    _pressedIndex = index;
    _lens.springTo(index!.toDouble(), LensMetrics.settle);
    return true;
  }

  /// 按住之后每帧跟手。**返回是否跨了格**（跨格要弹触感）。
  ///
  /// 关键：每一帧都要把 `_lens` 的弹簧**目标**移到手指底下 ——
  /// 只更新 `_pressedIndex` 的话，lens 会停在按下那一格不动（拖动不跟手），
  /// 而 `_fling` 又是从 `_lens.target` 往后投射的，于是甩动会按一个**陈旧**
  /// 目标算落点，把手指已经拖到的那一格又拉回去（实测拖到第 4 格、甩一下
  /// 变成第 3 格）。
  bool _slide(double position, Offset localPosition, Size size) {
    if (_pressedIndex == null) return false;
    if (!_dragging) {
      if ((_alongOf(localPosition) - _pressAlong).abs() < kTouchSlop) {
        return false;
      }
      _dragging = true;
    }
    final along = _alongOf(localPosition);
    final main = _lastSlots!.length;
    // 越过两端时整条 bar 跟着拉伸一点（橡皮筋），静止时立刻收回。
    final overshoot = along - along.clamp(0.0, main);
    _stretch.springTo(
      rubberBand(overshoot, size.shortestSide * LensMetrics.pullLimit),
      LensMetrics.track,
    );
    // lens 跟手：用最短的那根弹簧，于是它是「贴着手指」而不是「追着手指」。
    _lens.springTo(position, LensMetrics.track);
    final slots = _lastSlots;
    if (slots == null) return false;
    final index = slots.indexAt(position);
    if (index == _pressedIndex) return false;
    _pressedIndex = index;
    return true;
  }

  /// 最近一次布局量到的槽位几何。手势回调里拿不到 `LayoutBuilder` 的
  /// constraints，于是每帧build 时把这一份存下来给它们读。
  LensSlots? _lastSlots;

  /// 甩动：把松手前的投射位移折成额外格数，最多比手指底下那一格多走一格。
  bool _fling(Velocity velocity) {
    final pressed = _pressedIndex;
    if (pressed == null || !_dragging) return false;
    final slotSpan = _lastSlots?.spanOf(pressed);
    if (slotSpan == null || slotSpan <= 0) return false;
    // 竖轨取 dy，横轨取 dx；两档都取「沿主轴」的那一份。
    final speed = widget.axis == Axis.horizontal
        ? velocity.pixelsPerSecond.dx
        : velocity.pixelsPerSecond.dy;
    final lead =
        speed /
        slotSpan *
        LensMetrics.flingProjection.inMicroseconds /
        Duration.microsecondsPerSecond;
    final index = (_lens.target + lead)
        .round()
        .clamp(pressed - 1, pressed + 1)
        .clamp(0, _lastIndex);
    if (index == pressed) return false;
    _pressedIndex = index;
    return true;
  }

  void _release({required bool commit}) {
    final index = _pressedIndex;
    if (index == null) return;
    _pressedIndex = null;
    _lift.springTo(0, LensMetrics.settle);
    _stretch.springTo(0, LensMetrics.settle);
    if (!commit) {
      _lens.springTo(_selectedIndex.toDouble(), LensMetrics.settle);
      return;
    }
    _lens.springTo(index.toDouble(), LensMetrics.settle);
    if (index != widget.selectedIndex) {
      widget.onSelected(index);
    }
  }

  void _handleTap(int index) {
    if (index == widget.selectedIndex) {
      // 已经在这一格：让 lens 轻轻弹一下，给一个「点到了」的确认。
      _lens.springTo(index.toDouble(), LensMetrics.settle);
      return;
    }
    _lens.springTo(index.toDouble(), LensMetrics.settle);
    widget.onSelected(index);
  }

  // ── 画 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lensColor = widget.lensColor ?? colorScheme.secondaryContainer;
    final horizontal = widget.axis == Axis.horizontal;

    // 内边距加在**最外层**，不在 Stack 里面。
    //
    // 于是 Stack 的尺寸 == 内容的尺寸，lens 的坐标系与内容完全重合 ——
    // 「副轴该多高」由画出来的那个 box 自己回答，不必去猜约束。
    // 猜的那版在 AppBar 里出过事：`constraints.maxHeight` 是 48（标题区给的
    // 可用高度），而内容只有 32 高，于是 lens 被画成 48 高、比胶囊还高出一截
    // （2026-10-11 用户截图）。
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableAlong = horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          // 副轴一律留 0 —— 由 painter 按**实到的 size** 补（`LensSlots.resolvedTo`）。
          final slots = _slotsFor(context, availableAlong);
          _lastSlots = slots;

          List<Widget> slotChildren(LensSlots forSlots) => [
            for (var index = 0; index < widget.tabs.length; index++)
              _Slot(
                index: index,
                tab: widget.tabs[index],
                axis: widget.axis,
                extent: forSlots.spanOf(index),
                crossAxisAlignment: widget.crossAxisAlignment,
                lens: _lens,
                hoverAt: _hoverAt,
                lift: _lift,
                selected: index == _selectedIndex,
                semanticContainer: widget.semanticContainer,
                tintColor: widget.tintColor,
                slots: forSlots,
                corner: widget.lensCorner,
                onTap: () => _handleTap(index),
              ),
          ];

          final content = horizontal
              ? Row(
                  // 按内容取宽的那一档必须 `MainAxisSize.min`：调用方量出来的
                  // 跨度加起来就是它要的宽度，`max` 会把它摊到约束上限，
                  // 于是 lens 的落点与实际排出来的位置对不上。
                  mainAxisSize: widget.tabSizes == null
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: widget.crossAxisAlignment,
                  children: slotChildren(slots),
                )
              : Column(
                  mainAxisSize: widget.tabSizes == null
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: widget.crossAxisAlignment,
                  children: slotChildren(slots),
                );

          final bar = Stack(
            clipBehavior: Clip.none,
            children: [
              // ① lens 在**最底**。
              //
              // 顺序不能反：lens 是不透明的选中底色，画在内容之上会把选中那一格
              // 的图标与文字整个盖住（2026-10-11 实测：书架顶栏选中那格的
              // 「收藏」两个字看不见，而没选中的「历史 / 下载」正常）。
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: SpringLensPainter.animated(
                        repaint: _motion,
                        lensValue: _lens,
                        liftValue: _lift,
                        slots: slots,
                        color: lensColor,
                        corner: widget.lensCorner,
                        shadow: widget.lensShadow,
                        axis: widget.axis,
                      ),
                    ),
                  ),
                ),
              ),
              // ② 悬停高亮也在内容之下 —— 它只是一层淡底，不该盖住图标。
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HoverPainter(
                        repaint: _hoverMotion,
                        slots: slots,
                        position: _hover,
                        opacity: _hoverShow,
                        color: colorScheme.onSurface,
                        axis: widget.axis,
                        corner: widget.lensCorner,
                      ),
                    ),
                  ),
                ),
              ),
              // ③ 内容 + 指针，**同一棵子树**。
              //
              // 悬停与拖动跟手必须挂在内容这一棵上。另做一层铺在 Stack 上时，
              // 命中测试会在**第一个终止者**那里停下，两种排法都不成立：
              // 铺最上 ⇒ 底下的 `_Slot` 收不到点击（点 tab 没反应）；
              // 铺底下 ⇒ 被上面的 `_Slot` 挡掉 `onPointerMove`（跟手与甩动全废）。
              //
              // `HitTestBehavior.translucent`：自己也命中（拖动跟手要的是
              // 「按下那一刻就知道手指落在哪一格」，不能等手势 arena 出结果），
              // 同时**不终止** —— 每一格自己的 `GestureDetector` 照样收点击与长按。
              MouseRegion(
                // 传**原始事件**给 `_handleHover`：它要读 `event.kind` 把触摸
                // 那一支整个放掉（触摸的指针在抬起后会一直留着，重造事件就再也
                // 认不出它是触摸还是鼠标了）。
                onHover: _handleHover,
                onExit: _handleExit,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    _handlePointerDown(event);
                    if (widget.draggable && event.pointer == _pointer) {
                      _pressAlong = _alongOf(event.localPosition);
                      if (_press(_positionAt(event.localPosition))) {
                        HapticFeedback.selectionClick();
                      }
                    }
                  },
                  onPointerMove: (event) {
                    if (event.pointer != _pointer) return;
                    _handlePointerMove(event);
                    if (widget.draggable &&
                        _slide(
                          _positionAt(event.localPosition),
                          event.localPosition,
                          context.size ?? Size.zero,
                        )) {
                      HapticFeedback.selectionClick();
                    }
                  },
                  onPointerUp: _handlePointerUp,
                  // 取消时不该提交落点，而 `_handlePointerUp` 里
                  // `event is PointerUpEvent` 那一判正好把它挡掉了。
                  onPointerCancel: _handlePointerUp,
                  child: _claimDrag(content),
                ),
              ),
            ],
          );
          return RepaintBoundary(
            child: AnimatedBuilder(
              animation: _stretch,
              builder: (_, child) => PressTransform(
                lift: 0,
                pull: horizontal
                    ? Offset(_stretch.value, 0)
                    : Offset(0, _stretch.value),
                child: child,
              ),
              child: bar,
            ),
          );
        },
      ),
    );
  }

  /// 只为了**赢下手势**而存在的拖动识别器（不做任何事）。
  ///
  /// # 它解决什么
  ///
  /// 拖动跟手本身走上面那个 `Listener`（**原始指针事件**）—— 那不能进手势
  /// arena，否则「按下那一刻就知道手指落在哪一格」要等 arena 出结果，已经晚了。
  ///
  /// 但正因为它不进 arena，**祖先的可滚动容器（泳道条带）也会收到同一次拖动**，
  /// 表现成「在面板页签条上拖动切面板，整条泳道跟着横移」
  /// （2026-10-11 用户报告）。而这恰恰是最容易误触发的那种 —— 用户想切面板，
  /// 结果把整条泳道拖走了。
  ///
  /// 所以这里额外挂一个**只为抢手感存在**的识别器：它没有任何回调，只在整个
  /// 拖动期间赢得 arena，把祖先的滚动识别器挤出去。
  ///
  /// # 为什么是「内层赢」
  ///
  /// 单指横拖时，两边的识别器会在**同一个事件**上越过各自的 slop（都是
  /// `kTouchSlop`）。arena 的裁决按「谁先声明接受」：事件分发的顺序是命中顺序
  /// （由深到浅），而这一层比祖先的滚动层**深**，于是它先 `accept`，祖先被拒。
  /// 也就是说「先到先得」在这里等价于「内层优先」—— 正是我们要的语义，
  /// 不需要自己写 arena 逻辑。
  ///
  /// # 为什么按轴向分两种识别器
  ///
  /// 只抢**这一条 bar 自己的方向**：横排的 bar 抢横拖、竖排的抢竖拖。
  /// 抢错方向会把「在页签条上竖着划一下翻页 / 滚列表」也一起挡掉。
  ///
  /// `draggable: false` 那一档（排序模式下的页签条、或该处已有长按拖动）
  /// **不抢** —— 那时拖动本来就该留给宿主。
  Widget _claimDrag(Widget child) {
    if (!widget.draggable) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        if (widget.axis == Axis.horizontal)
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(
                HorizontalDragGestureRecognizer.new,
                // 空回调是**有意的**：落点与跟手全在 `Listener` 那一路，
                // 这一层的唯一职责是把手势留在自己这里。
                (instance) {
                  instance.onUpdate = (_) {};
                  instance.onCancel = () {
                    _release(commit: false);
                    _dragging = false;
                  };
                },
              )
        else
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                VerticalDragGestureRecognizer
              >(VerticalDragGestureRecognizer.new, (instance) {
                instance.onUpdate = (_) {};
                instance.onCancel = () {
                  _release(commit: false);
                  _dragging = false;
                };
              }),
      },
      child: child,
    );
  }

  /// 指针落点 → 格位。
  ///
  /// 读的是**布局期存下来的**那一份 `slots`（`build` 里算、`_lastSlots` 存）——
  /// 「画的」与「判的」必须读同一份几何，否则形变期间两者会错开。
  ///
  /// 这里**不做**任何尺寸换算：`slots` 的原点已经是内容的原点（内边距加在
  /// `Stack` 外面），副轴与落点无关。早先那版要在这里按 `context.size` 补一段
  /// 「内容居中偏移」，是因为当时内边距在 `Stack` 里面、两套坐标系不重合 ——
  /// 那个补偿本身就是错的（实测偏 245px），现在从结构上消掉了。
  double _positionAt(Offset localPosition) {
    final slots = _lastSlots;
    if (slots == null || slots.isEmpty) return _selectedIndex.toDouble();
    return slots.positionAt(
      _alongOf(localPosition),
      overdrag: LensMetrics.overdrag,
    );
  }
}
