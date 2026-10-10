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
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

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
  const SpringLensTab({
    required this.child,
    this.semanticLabel,
    this.tooltip,
  });

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

  /// lens 的圆角；不给是全圆。
  final double? lensCorner;

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
  /// 两条路的**副轴起点**都来自 [SpringLensBar.padding]，于是 lens 与内容之间
  /// 的那圈内边距是一致的。
  LensSlots _slotsFor(double crossSize, double availableAlong) {
    final horizontal = widget.axis == Axis.horizontal;
    final leading = horizontal ? widget.padding.left : widget.padding.top;
    final crossStart = horizontal ? widget.padding.top : widget.padding.left;
    final sizes = widget.tabSizes;
    if (sizes != null && sizes.length == widget.tabs.length) {
      return LensSlots.sized(
        sizes: sizes,
        leading: leading,
        crossStart: crossStart,
        crossSize: crossSize,
        axis: widget.axis,
      );
    }
    // 等宽：均分**扣掉前导内边距之后**的可用长度。均分成 0 时兜一个1，
    // 否则 lens 宽度为零会整颗消失（空 bar / 极端窄）。
    final span = math.max(
      1.0,
      (availableAlong - leading) / math.max(1, widget.tabs.length),
    );
    return LensSlots.uniform(
      count: widget.tabs.length,
      extent: span,
      leading: leading,
      crossStart: crossStart,
      crossSize: crossSize,
      axis: widget.axis,
    );
  }

  double _alongOf(Offset localPosition) => widget.axis == Axis.horizontal
      ? localPosition.dx
      : localPosition.dy;

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
      ..addPosition(event.timeStamp, event.localPosition);
    _hoverShow.springTo(0, LensMetrics.fade);
    _hoverAt.value = null;
    if (widget.draggable) {
      _lift.springTo(1, LensMetrics.settle);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _tracker?.addPosition(event.timeStamp, event.localPosition);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null && _dragging) {
      _fling(tracker.getVelocity());
    }
    if (_dragging) {
      _release(commit: event is PointerUpEvent);
    }
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
    final main = _mainSizeOf(size);
    // 越过两端时整条 bar 跟着拉伸一点（橡皮筋），静止时立刻收回。
    final overshoot = along - along.clamp(0.0, main);
    _stretch.springTo(
      rubberBand(overshoot, main * (7 / 32)),
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

  double _mainSizeOf(Size size) =>
      widget.axis == Axis.horizontal ? size.width : size.height;

  /// 甩动：把松手前的投射位移折成额外格数，最多比手指底下那一格多走一格。
  bool _fling(Velocity velocity) {
    final pressed = _pressedIndex;
    if (pressed == null || !_dragging) return false;
    final slotSpan = _lastSpan;
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

  /// 最近一次布局量到的「一格多宽」，甩动用。
  double? _lastSpan;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 槽位在这里一次算清：**painter 与手势读的是同一份已解析的 `slots`**。
        //
        // 之前是「构造时算一份（副轴填 0），painter 里再 `resolvedTo` 补」——
        // 于是 painter 身上那份的副轴恒为 0，lens 画出来高度也是 0，而判据
        // 从 painter 读到的也正是那份未解析的（实测 lensRect 高度 0）。
        //
        // 副轴在 `Column` 里常常无界（`maxHeight == infinity`），所以那一维
        // 用「约束有界就用约束、否则按内容估」——内容那档只影响 lens 铺多高，
        // 不影响它落在哪一格。
        final boundedCross = horizontal
            ? constraints.maxHeight
            : constraints.maxWidth;
        final crossSize = boundedCross.isFinite
            ? math.max(
                0.0,
                boundedCross -
                    (horizontal
                        ? widget.padding.vertical
                        : widget.padding.horizontal),
              )
            : widget.axis == Axis.horizontal
            ? _IntrinsicMeasure.of(context).height
            : _IntrinsicMeasure.of(context).width;
        final availableAlong = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final slots = _slotsFor(crossSize, availableAlong);
        _lastSlots = slots;
        _lastSpan = slots.isEmpty ? null : slots.spanOf(0);

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
          onTap: () => _handleTap(index),
        ),
    ];

    final Widget content = Padding(
      padding: widget.padding,
      child: horizontal
          ? Row(
              // 按内容取宽的那一档必须 `MainAxisSize.min`：调用方量出来的跨度
              // 加起来就是它要的宽度，`max` 会把它摊到约束上限，于是 lens 的
              // 落点与实际排出来的位置对不上。
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
            ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 命中与拖动跟手**包在内容外面**，而不是另做一层铺在 Stack 上。
        //
        // 为什么不能另铺一层（试过两种排法都不成立）：命中测试只认路径上
        // 第一个终止者，而 `HitTestBehavior.translucent` 会终止 ——
        // - 铺在**最上**：命中在它那里就停，底下的 `_Slot` 永远收不到点击
        //   （实测命中链最外是 RenderMouseRegion/RenderPointerListener，
        //   点第二格没有任何回调）；
        // - 铺在**底下**：上面那些 `_Slot` 的 `GestureDetector`（`opaque`）
        //   先终止，它收不到 `onPointerMove`，拖动跟手整个失效。
        //
        // 包住内容就同时成立：`Listener` 与 `_Slot` 在**同一条**路径上
        // （`Listener` 不终止，子节点照旧命中），于是原始指针事件与点击都收得到。
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _handlePointerDown(event);
            if (widget.draggable) {
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
          child: content,
        ),
        // lens 画在内容**底下**：于是它扫过去时是内容被染色，而不是盖住内容。
        //
        // 用 `CustomPaint` 而不是 `Positioned` + `DecoratedBox`：`Positioned`
        // 要在**布局期**就给出确定的宽高，而横轨嵌在 `Column` /
        // 无限高的 `ListView` 里时 `maxHeight` 是无穷，减完内边距还是无穷，
        // 于是 `RenderStack` 直接抛「height.isNaN」（实测就报在那个 Stack 上）。
        // `CustomPaint` 的 painter 拿到的是解完约束的 `size` —— 一定是有限值，
        // 副轴的答案来自内容本身。
        //
        // `SizedBox.expand` 是必需的：Stack 的非定位子节点按自身尺寸参与布局，
        // 给 `SizedBox.shrink()` 会让 lens 拿到 0×0，painter 直接什么都不画
        // （实测量到的 lens 中心 x = 0）。而`Positioned.fill` 那层命中层
        // 已经保证了约束是紧的（Stack 有紧约束时按 tight 尺寸给）。
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _motion,
              builder: (_, _) => CustomPaint(
                painter: SpringLensPainter(
                  slots: slots,
                  position: _lens.value,
                  velocity: _lens.velocity,
                  lift: _lift.value,
                  color: lensColor,
                  corner: widget.lensCorner,
                  axis: widget.axis,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _hoverMotion,
              builder: (_, _) => CustomPaint(
                painter: _HoverPainter(
                  slots: slots,
                  position: _hover.value,
                  opacity: _hoverShow.value,
                  color: colorScheme.onSurface,
                  axis: widget.axis,
                ),
              ),
            ),
          ),
        ),
        // 悬停层在最上，但 `IgnorePointer` 让它**完全不参与命中** ——
        // 于是它只管画高亮与收 `onHover`，不与点击/拖动那条路径抢任何东西。
        //
        // 传**原始事件**给 `_handleHover`：它要读 `event.kind` 把触摸那一支
        // 整个放掉（触摸的指针在抬起后会一直留着，重造事件就再也认不出
        // 它是触摸还是鼠标了）。
        Positioned.fill(
          child: IgnorePointer(
            child: MouseRegion(
              onHover: _handleHover,
              onExit: _handleExit,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
      },
    );
  }

  /// 指针落点 → 格位。读的是**最近一次布局存下来的** `slots` ——
  /// 「画的」与「判的」必须读同一份几何，否则形变期间两者会错开。
  double _positionAt(Offset localPosition) {
    final raw = _lastSlots;
    if (raw == null || raw.isEmpty) return _selectedIndex.toDouble();
    // 与 painter 里那次 `alignedTo` 是同一个调用 —— 画的与判的同源。
    final size = context.size;
    final slots = size == null ? raw : (raw.alignedTo(size) ?? raw);
    return slots.positionAt(
      _alongOf(localPosition),
      overdrag: LensMetrics.overdrag,
    );
  }
}

/// 副轴无界时拿来估内容那一维的量尺。
///
/// 只用来回答「lens 该铺多高/多宽」—— 它**不参与**落点判定（落点只沿主轴）。
/// 所以取屏幕那一维是个安全的下界：lens 会铺满可用带，而不会算出一个 NaN
/// 或 0（`RenderStack` 对这两种值都直接抛断言）。
class _IntrinsicMeasure {
  const _IntrinsicMeasure(this.context);

  final BuildContext context;

  static _IntrinsicMeasure of(BuildContext context) =>
      _IntrinsicMeasure(context);

  double get height => MediaQuery.sizeOf(context).height;
  double get width => MediaQuery.sizeOf(context).width;
}

/// 画选中态那颗lens。只画不布局。
///
/// **公开**是为了让判据能读它身上的 [slots] / [position] 重算一遍落点：
/// painter 只在 `paint(canvas, size)` 里作画，从外面量不到那颗矩形
/// （见 `test/widgets/spring_lens_bar_test.dart` 的 `_lensRect`）。
class SpringLensPainter extends CustomPainter {
  const SpringLensPainter({
    required this.slots,
    required this.position,
    required this.velocity,
    required this.lift,
    required this.color,
    required this.corner,
    required this.axis,
  });

  final LensSlots slots;
  final double position;
  final double velocity;
  final double lift;
  final Color color;
  final double? corner;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty || size.isEmpty) return;
    final real = slots.alignedTo(size);
    if (real == null || real.isEmpty) return;
    final rect = lensRect(
      slots: real,
      position: position,
      velocity: velocity,
      lift: lift,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final paint = Paint()..color = color;
    final rrect = corner == null
        ? RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2))
        : RRect.fromRectAndRadius(rect, Radius.circular(corner!));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(SpringLensPainter old) =>
      old.position != position ||
      old.velocity != velocity ||
      old.lift != lift ||
      old.color != color ||
      old.corner != corner;
}

/// 画鼠标悬停那层高亮（跟着指针磁吸）。
class _HoverPainter extends CustomPainter {
  const _HoverPainter({
    required this.slots,
    required this.position,
    required this.opacity,
    required this.color,
    required this.axis,
  });

  final LensSlots slots;
  final double position;
  final double opacity;
  final Color color;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = LensMetrics.hoverAlpha * opacity.clamp(0.0, 1.0);
    if (alpha == 0 || slots.isEmpty || size.isEmpty) return;
    final real = slots.alignedTo(size);
    if (real == null || real.isEmpty) return;
    final index = real.indexAt(position);
    final rect = lensRect(
      slots: real,
      position: position,
      velocity: 0,
      lift: 0,
    );
    final band = axis == Axis.horizontal
        ? Rect.fromLTWH(
            rect.left,
            real.crossStart,
            real.spanOf(index),
            real.crossSize,
          )
        : Rect.fromLTWH(
            real.crossStart,
            rect.top,
            real.crossSize,
            real.spanOf(index),
          );
    if (band.width <= 0 || band.height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        band,
        Radius.circular(band.shortestSide / 2),
      ),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_HoverPainter old) =>
      old.position != position ||
      old.opacity != opacity ||
      old.color != color;
}

class _Slot extends StatefulWidget {
  const _Slot({
    required this.index,
    required this.tab,
    required this.axis,
    required this.extent,
    required this.crossAxisAlignment,
    required this.lens,
    required this.hoverAt,
    required this.lift,
    required this.selected,
    required this.semanticContainer,
    required this.onTap,
  });

  /// 本格在宿主列表里的下标。染色判据读它。
  final int index;

  final SpringLensTab tab;
  final Axis axis;
  final double extent;
  final CrossAxisAlignment crossAxisAlignment;
  final SpringLensValue lens;
  final ValueListenable<double?> hoverAt;
  final SpringLensValue lift;
  final bool selected;
  final bool semanticContainer;
  final VoidCallback onTap;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> with SingleTickerProviderStateMixin {
  late final SpringLensValue _parallax = SpringLensValue(this, 0);
  late final Listenable _motion = Listenable.merge([_parallax, widget.lift]);

  @override
  void initState() {
    super.initState();
    widget.hoverAt.addListener(_followPointer);
  }

  @override
  void didUpdateWidget(covariant _Slot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverAt != widget.hoverAt) {
      oldWidget.hoverAt.removeListener(_followPointer);
      widget.hoverAt.addListener(_followPointer);
    }
    _followPointer();
  }

  @override
  void dispose() {
    widget.hoverAt.removeListener(_followPointer);
    _parallax.dispose();
    super.dispose();
  }

  void _followPointer() {
    final hoverAt = widget.hoverAt.value;
    // 内容视差：指针在这一格附近时，底下内容追过去一点点（比lens 追得少）。
    final offset = hoverAt == null ? 0.0 : hoverAt - widget.lens.value.round();
    final target = offset.abs() > 0.5 ? 0.0 : offset * LensMetrics.hoverParallax;
    if (target != _parallax.target) {
      _parallax.springTo(target, LensMetrics.hover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final child = widget.tab.child;
    final content = AnimatedBuilder(
      animation: _motion,
      builder: (context, child) => _MotionTransform(
        lens: widget.lens,
        lift: widget.lift,
        parallax: _parallax,
        color: Theme.of(context).colorScheme.primary,
        horizontal: horizontal,
        index: widget.index,
        child: child,
      ),
      child: child,
    );

    Widget slot = horizontal
        ? SizedBox(width: widget.extent, child: content)
        : SizedBox(height: widget.extent, child: content);

    // 点击走**这一格自己的**识别器，而不是外层那个 `Listener`：外层要同时
    // 接拖动跟手与悬停。两者的分工靠「谁在命中路径上」：
    //
    // - 外层那个 `Listener` 在 Stack **最上**（`translucent`）——它必须收得到
    //   `onPointerMove`，否则拖动跟手整个失效；
    // - `translucent` 仍会**终止**命中，所以这一格不能是 `opaque`
    //   （`opaque` 自己也会终止），否则底下的点击到不了它。
    //
    // `translucent` 在这里已经够了：这一格的内容（Text/Icon）本身会命中，
    // `Listener` 仍然收得到指针。
    slot = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      child: slot,
    );

    // 有 tooltip 才包：给一个空 message 的 Tooltip 会挡住鼠标。
    if (widget.tab.tooltip != null) {
      slot = Tooltip(message: widget.tab.tooltip!, child: slot);
    }
    if (widget.semanticContainer) {
      slot = Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.tab.semanticLabel,
        excludeSemantics: widget.tab.semanticLabel != null,
        onTap: widget.onTap,
        child: slot,
      );
    }
    return slot;
  }
}

/// 内容在 lens 底下时染上选中色、并且按下时放大一点。
///
/// 与 `navigation_dock.dart` 里那个 `_LensTint` 同一套做法（clip 出 lens 的形状、
/// lens 内外的色分开画），只是这里把「lens 落在第几格」换成了弹簧的连续位置。
class _MotionTransform extends SingleChildRenderObjectWidget {
  const _MotionTransform({
    required this.lens,
    required this.lift,
    required this.parallax,
    required this.color,
    required this.horizontal,
    required this.index,
    super.child,
  });

  final SpringLensValue lens;
  final ValueListenable<double> lift;
  final ValueListenable<double> parallax;
  final Color color;
  final bool horizontal;

  /// 宿主里的下标：染色前用它判「lens 现在压不压着我」。
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMotionTransform(
      lens: lens,
      lift: lift,
      parallax: parallax,
      color: color,
      horizontal: horizontal,
      index: index,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderMotionTransform renderObject) {
    renderObject
      ..lens = lens
      ..lift = lift
      ..parallax = parallax
      ..color = color
      ..horizontal = horizontal
      ..index = index;
  }
}

class _RenderMotionTransform extends RenderProxyBox {
  _RenderMotionTransform({
    required this._lens,
    required ValueListenable<double> lift,
    required this._parallax,
    required this._color,
    required this._horizontal,
    required this._index,
  }) : _lift = lift;

  final LayerHandle<ColorFilterLayer> _tint = LayerHandle<ColorFilterLayer>();
  final LayerHandle<TransformLayer> _motion = LayerHandle<TransformLayer>();

  SpringLensValue _lens;
  set lens(SpringLensValue value) {
    if (value == _lens) return;
    if (attached) {
      _lens.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lens = value;
    markNeedsPaint();
  }

  ValueListenable<double> _lift;
  set lift(ValueListenable<double> value) {
    if (value == _lift) return;
    if (attached) {
      _lift.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lift = value;
    markNeedsPaint();
  }

  ValueListenable<double> _parallax;
  set parallax(ValueListenable<double> value) {
    if (value == _parallax) return;
    if (attached) {
      _parallax.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _parallax = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  bool _horizontal;
  set horizontal(bool value) {
    if (value == _horizontal) return;
    _horizontal = value;
    markNeedsPaint();
  }

  /// 宿主里的下标 —— 染色前用它判「lens 现在压不压着我」。
  int _index;
  set index(int value) {
    if (value == _index) return;
    _index = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _lens.addListener(markNeedsPaint);
    _lift.addListener(markNeedsPaint);
    _parallax.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _lens.removeListener(markNeedsPaint);
    _lift.removeListener(markNeedsPaint);
    _parallax.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _tint.layer = null;
    _motion.layer = null;
    super.dispose();
  }

  /// 放大 + 视差平移，叠在一起是一个 Matrix4。静止时返回 null（不建层）。
  Matrix4? get _transform {
    final scale = 1 + LensMetrics.magnify * _lift.value.clamp(0.0, 1.0);
    final shift = _parallax.value * size.longestSide;
    if (scale == 1 && shift == 0) return null;
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx * (1 - scale) + (_horizontal ? shift : 0),
      center.dy * (1 - scale) + (_horizontal ? 0 : shift),
      0,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final motion = _transform;
    if (motion != null) transform.multiply(motion);
  }

  void _paintMoved(
    PaintingContext context,
    Offset offset,
    Matrix4? motion,
    LayerHandle<TransformLayer> handle,
  ) {
    if (motion == null) {
      handle.layer = null;
      super.paint(context, offset);
      return;
    }
    handle.layer = context.pushTransform(
      needsCompositing,
      offset,
      motion,
      super.paint,
      oldLayer: handle.layer,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final motion = _transform;
    _paintMoved(context, offset, motion, _motion);
    // 染色只在 lens 正压着这一格时才做：静止在别处就不用多开一层。
    if (_lens.value.round() == _index) {
      final filter = ColorFilter.mode(_color, BlendMode.srcIn);
      _tint.layer = context.pushColorFilter(
        offset,
        filter,
        (context, offset) => super.paint(context, offset),
        oldLayer: _tint.layer,
      );
    } else {
      _tint.layer = null;
    }
  }
}

/// 鼠标悬停时画的那层高亮：跟着指针走、也偏一点点（磁吸）。
class _HoverHighlight extends StatelessWidget {
  const _HoverHighlight({
    required this.slots,
    required this.position,
    required this.opacity,
    required this.color,
  });

  final LensSlots slots;
  final double position;
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final alpha = LensMetrics.hoverAlpha * opacity.clamp(0.0, 1.0);
    if (alpha == 0 || slots.isEmpty) return const SizedBox.shrink();
    final index = slots.indexAt(position);
    final rect = lensRect(
      slots: slots,
      position: position,
      velocity: 0,
      lift: 0,
    );
    final child = DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: alpha),
        // 悬停高亮跟着指针磁吸，所以形状与lens 一致（全圆），不然贴边那一档
        // 会露出方角。
        shape: AppShape.full,
      ),
    );
    if (slots.axis == Axis.horizontal) {
      return PositionedDirectional(
        start: rect.left,
        top: slots.crossStart,
        width: slots.spanOf(index),
        height: slots.crossSize,
        child: child,
      );
    }
    return Positioned(
      left: slots.crossStart,
      top: rect.top,
      width: slots.crossSize,
      height: slots.spanOf(index),
      child: child,
    );
  }
}