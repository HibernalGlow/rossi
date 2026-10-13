// 来源：FlClash（https://github.com/chen08209/FlClash），GPL-3.0。
// 原文：`lib/widgets/popup.dart`（上游提交 841d6035「add a sidebar, floating
// dock, snap sheets and drag to go back」）。许可口径与退出条件见
// `docs/adr/0021-flclash-navigation-port-and-gpl-relicense.md`。
//
// 相对原文的偏离（其余逐字未动）：
// 1. import 换成本仓路径：`SpringCurve` 来自 `lib/widgets/navigation/spring_curve.dart`、
//    `AppShape` / `AppCorner` 来自 `lib/widgets/navigation/navigation_shape.dart`、
//    `context.colorScheme` / `context.textTheme` 来自
//    `lib/widgets/navigation/navigation_context.dart`、图标来自 `lib/icons/`；
// 2. 原文从 `fl_clash/common/color.dart` 拿 `Color.opacity30` / `opacity10`，
//    本仓没有那份扩展 —— 在文件尾补了**只含这两档**的私有扩展，语义与原文一致；
// 3. `CommonPopupMenuItem` 加了两个字段：`content`（整段替换中部的标签文本，
//    泳道菜单的「常规宽度」要在项内嵌输入框）与 `isDivider`（分节线 —— 原文
//    的菜单没有分节需求，本仓的菜单项集是分节的）。除这两处外，项模型与
//    渲染逐字保持原文。

import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/navigation/navigation_context.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/navigation/spring_curve.dart';

part 'navigation/popup_layout.dart';

typedef PopupAnchorResolver = Rect? Function();

/// 打开弹出物的入口，由 [`CommonPopupBox`] / [`CommonPopupAnchor`] 交给触发控件。
///
/// 返回值是这条路由此刻正在弹的那一层**被关掉时的结果**（`Navigator.pop`
/// 带出来的那个值）——「选完再落账」那一类（书架筛选）要先拿到它。
/// 不看结果的调用点（菜单项）直接把 `open` 挂在 `onPressed` 上即可：
/// 返回 `Future` 的函数可以当 `VoidCallback` 用。
typedef PopupOpen<T> = Future<T?> Function({Offset offset});

enum PopupPlacement { overAnchorEnd, belowPoint, center }

const _screenMargin = 16.0;

const _anchorOverlap = 8.0;

const _avoidGap = 8.0;

const _cardInset = 8.0;

const _itemRadius = AppCorner.md;

const _cardRadius = _itemRadius + _cardInset;

/// 全屏形态的终点圆角。
///
/// 铺满整屏的那一档不留圆角：`_cardRadius`（24）在整屏尺度上会让四个屏幕角
/// 各缺一块 —— 那是「一张被放大的卡片」，不是「一层全屏」。
const _fullscreenRadius = AppCorner.none;

const _itemIconSize = 20.0;
const _submenuArrowSize = 16.0;

const _itemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

const _itemArrowPadding = EdgeInsets.only(
  left: 12,
  top: 12,
  bottom: 12,
  right: 8,
);

const _dividerHeight = _cardInset * 2 + 1;

// Soft and wide like HyperOS menus rather than a Material elevation.
List<BoxShadow> _cardShadows(ColorScheme colorScheme, [double depth = 1]) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  final alpha = strength * depth;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.05 * alpha),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * alpha),
      blurRadius: 30,
      offset: const Offset(0, 4),
    ),
  ];
}

const _maxContentBlur = 8.0;

const _openDuration = Duration(milliseconds: 750);

const _closeDuration = Duration(milliseconds: 400);

const _unfoldDuration = Duration(milliseconds: 480);

const _frameSpan = 0.3;

double _secondsOf(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerSecond;

final _openSeconds = _secondsOf(_openDuration);

final _closeSeconds = _secondsOf(_closeDuration);

final _growSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 500),
    bounce: 0.3,
  ),
  seconds: _openSeconds,
);

final _moveYSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 340),
    bounce: 0.12,
  ),
  seconds: _openSeconds,
);

final _moveXSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 520),
    bounce: 0.2,
  ),
  seconds: _openSeconds,
);

final _shrinkSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 340),
  ),
  seconds: _closeSeconds,
).flipped;

final _returnXSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 300),
  ),
  seconds: _closeSeconds,
).flipped;

final _returnYSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 440),
  ),
  seconds: _closeSeconds,
).flipped;

final _unfoldSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 420),
    bounce: 0.2,
  ),
  seconds: _secondsOf(_unfoldDuration),
);

final _frameSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 150),
  ),
  seconds: _secondsOf(_unfoldDuration) * _frameSpan,
);

/// 弹出物此刻该画成哪一形态 —— 由**推出它的那条路由**塞进子树。
///
/// 为什么不让内容自己读宽度猜：确认类弹层是「一律全屏」（宽屏上也一样），
/// 那条「一律」只有路由知道；内容侧若自己按 `width < 600` 猜，宽屏上就会
/// 画成卡片，而托盘长成的却是整屏 —— 两者一错位，交接那一帧就露馅。
class PopupFormScope extends InheritedWidget {
  const PopupFormScope({
    super.key,
    required this.fullscreen,
    required super.child,
  });

  final bool fullscreen;

  /// 不在弹出路由里的子树（面板被直接塞进某个页面）按卡片形态画。
  static bool fullscreenOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PopupFormScope>()?.fullscreen ??
      false;

  @override
  bool updateShouldNotify(PopupFormScope oldWidget) =>
      oldWidget.fullscreen != fullscreen;
}

class CommonPopupRoute<T> extends PopupRoute<T> {
  CommonPopupRoute({
    super.settings,
    required this.builder,
    required this.anchorOf,
    required this.barrierLabel,
    this.placement = PopupPlacement.overAnchorEnd,
    this.anchorShift = Offset.zero,
    this.sourceColor = Colors.transparent,
    this.sourceImage,
    this.modal = true,
    this.avoid,
    this.fullscreen = false,
    this.scrimColor,
  }) : super(requestFocus: modal ? null : false);

  final WidgetBuilder builder;

  /// Resolves the rect of the control the popup grows out of.
  final PopupAnchorResolver anchorOf;
  final PopupPlacement placement;

  /// Moves where the popup is placed without moving where it grows from.
  final Offset anchorShift;

  /// The background of the source control, which the platter starts from.
  final Color sourceColor;

  /// A snapshot of the source control, drawn inside the platter while the
  /// control itself is hidden; null while it is still being taken.
  final ValueListenable<ui.Image?>? sourceImage;

  /// Off, focus stays on the page and touches outside pass through to it.
  final bool modal;

  /// A rect the popup keeps clear of when there is room above or below it.
  final Rect? avoid;

  /// 铺满整屏（窄屏那一支，以及确认类弹层）。
  ///
  /// 与卡片形态**共用同一段动画**：托盘照样从锚点长出来，只是长成的目标从
  /// 「卡片大小」换成「整屏」，终点圆角归零（[_fullscreenRadius]）。
  /// 所以「弹全屏」不是另一套动画，而是同一段弹簧的另一个终点 —— 这正是
  /// 「哪怕铺满整屏，进出场也要连贯」这条要求的落点。
  ///
  /// 内容侧要知道自己该画成哪一形态（卡片还是全屏外壳），读
  /// [PopupFormScope.fullscreenOf] —— 由这条路由此处塞进子树，
  /// 面板不必自己去猜宽度。
  final bool fullscreen;

  @override
  final String? barrierLabel;

  final Color? scrimColor;

  @override
  Color? get barrierColor => scrimColor;

  @override
  bool get barrierDismissible => true;

  bool get _reduceMotion =>
      eInkInstantRoutes ||
      (navigator != null &&
          (MediaQuery.maybeDisableAnimationsOf(navigator!.context) ?? false));

  @override
  Duration get transitionDuration =>
      !_reduceMotion ? _openDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      !_reduceMotion ? _closeDuration : Duration.zero;

  late final CurvedAnimation _grow = CurvedAnimation(
    parent: animation!,
    curve: _growSpring,
    reverseCurve: _shrinkSpring,
  );

  late final CurvedAnimation _moveX = CurvedAnimation(
    parent: animation!,
    curve: _moveXSpring,
    reverseCurve: _returnXSpring,
  );

  late final CurvedAnimation _moveY = CurvedAnimation(
    parent: animation!,
    curve: _moveYSpring,
    reverseCurve: _returnYSpring,
  );

  late final CurvedAnimation _content = CurvedAnimation(
    parent: animation!,
    curve: const Interval(0.04, 0.45, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.5, 1, curve: Curves.easeIn),
  );

  final _unfolded = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _grow.dispose();
    _moveX.dispose();
    _moveY.dispose();
    _content.dispose();
    _unfolded.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (isCurrent) {
      navigator?.pop();
    }
  }

  @override
  Widget buildModalBarrier() {
    return modal ? super.buildModalBarrier() : const SizedBox.shrink();
  }

  Widget _buildDismissLayer() {
    if (modal) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: _handleDismiss,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handleDismiss(),
      onPointerPanZoomStart: (_) => _handleDismiss(),
      onPointerSignal: (_) => _handleDismiss(),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // 形态由**路由**说了算（确认类在宽屏上也是全屏，那个「一律」只有这里
    // 知道），内容侧读这一个作用域，别自己去猜宽度。
    return PopupFormScope(fullscreen: fullscreen, child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final colorScheme = context.colorScheme;
    final reduced =
        eInkInstantRoutes || MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(child: _buildDismissLayer()),
        _PopupAnchorTracker(
          anchorOf: anchorOf,
          builder: (anchor, safeInsets, child) => CustomSingleChildLayout(
            delegate: _PopupLayoutDelegate(
              anchor: anchor.shift(anchorShift),
              safeInsets: safeInsets,
              placement: placement,
              avoid: avoid,
              fullscreen: fullscreen,
            ),
            child: reduced
                ? child
                : _PopupMorph(
                    anchor: anchor,
                    animation: animation,
                    grow: _grow,
                    moveX: _moveX,
                    moveY: _moveY,
                    content: _content,
                    unfolded: _unfolded,
                    endRadius: fullscreen ? _fullscreenRadius : _cardRadius,
                    sourceColor: sourceColor,
                    sourceImage: sourceImage,
                    surfaceColor: colorScheme.surfaceContainer,
                    shadows: _cardShadows(colorScheme),
                    child: child,
                  ),
          ),
          child: NotificationListener<_PopupUnfoldNotification>(
            onNotification: (_) {
              _unfolded.value = true;
              return true;
            },
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PopupUnfoldNotification extends Notification {
  const _PopupUnfoldNotification();
}

class _PopupMorph extends SingleChildRenderObjectWidget {
  const _PopupMorph({
    required this.anchor,
    required this.animation,
    required this.grow,
    required this.moveX,
    required this.moveY,
    required this.content,
    required this.unfolded,
    required this.endRadius,
    required this.sourceColor,
    required this.sourceImage,
    required this.surfaceColor,
    required this.shadows,
    super.child,
  });

  final Rect anchor;
  final Animation<double> animation;
  final Animation<double> grow;
  final Animation<double> moveX;
  final Animation<double> moveY;
  final Animation<double> content;
  final ValueListenable<bool> unfolded;

  /// 长成之后那张脸的圆角：卡片形态是 `_cardRadius`，全屏形态是
  /// [_fullscreenRadius]。
  final double endRadius;

  final Color sourceColor;
  final ValueListenable<ui.Image?>? sourceImage;
  final Color surfaceColor;
  final List<BoxShadow> shadows;

  @override
  _RenderPopupMorph createRenderObject(BuildContext context) {
    return _RenderPopupMorph(
      anchor: anchor,
      animation: animation,
      grow: grow,
      moveX: moveX,
      moveY: moveY,
      content: content,
      unfolded: unfolded,
      endRadius: endRadius,
      sourceColor: sourceColor,
      sourceImage: sourceImage,
      surfaceColor: surfaceColor,
      shadows: shadows,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPopupMorph renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..animation = animation
      ..grow = grow
      ..moveX = moveX
      ..moveY = moveY
      ..content = content
      ..unfolded = unfolded
      ..endRadius = endRadius
      ..sourceColor = sourceColor
      ..sourceImage = sourceImage
      ..surfaceColor = surfaceColor
      ..shadows = shadows;
  }
}

/// Grows the popup out of its anchor the way iOS 26 menus leave their button:
/// a platter flies from the anchor's capsule to the card's center on an arc,
/// growing on its own spring, while the content rides inside it, scaling,
/// fading and sharpening in; closing shrinks it first and flies it back.
class _RenderPopupMorph extends RenderProxyBox {
  _RenderPopupMorph({
    required this._anchor,
    required Animation<double> animation,
    required this.grow,
    required this.moveX,
    required this.moveY,
    required this.content,
    required this._unfolded,
    required double endRadius,
    required this._sourceColor,
    required this._sourceImage,
    required this._surfaceColor,
    required this._shadows,
  }) : _animation = animation,
       _endRadius = endRadius;

  Animation<double> grow;
  Animation<double> moveX;
  Animation<double> moveY;
  Animation<double> content;

  Rect _anchor;

  /// 长成之后那张脸的圆角，见 `_PopupMorph.endRadius`。
  double _endRadius;

  set endRadius(double value) {
    if (value == _endRadius) {
      return;
    }
    _endRadius = value;
    markNeedsPaint();
  }

  set anchor(Rect value) {
    if (value == _anchor) {
      return;
    }
    _anchor = value;
    markNeedsPaint();
  }

  Animation<double> _animation;

  set animation(Animation<double> value) {
    if (value == _animation) {
      return;
    }
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  ValueListenable<bool> _unfolded;

  set unfolded(ValueListenable<bool> value) {
    if (value == _unfolded) {
      return;
    }
    if (attached) {
      _unfolded.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _unfolded = value;
    markNeedsPaint();
  }

  Color _sourceColor;

  set sourceColor(Color value) {
    if (value == _sourceColor) {
      return;
    }
    _sourceColor = value;
    markNeedsPaint();
  }

  ValueListenable<ui.Image?>? _sourceImage;

  set sourceImage(ValueListenable<ui.Image?>? value) {
    if (value == _sourceImage) {
      return;
    }
    if (attached) {
      _sourceImage?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _sourceImage = value;
    markNeedsPaint();
  }

  Color _surfaceColor;

  set surfaceColor(Color value) {
    if (value == _surfaceColor) {
      return;
    }
    _surfaceColor = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;

  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) {
      return;
    }
    _shadows = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
    _unfolded.addListener(markNeedsPaint);
    _sourceImage?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    _unfolded.removeListener(markNeedsPaint);
    _sourceImage?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  bool get _closing => _animation.status == AnimationStatus.reverse;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (_animation.isCompleted) {
      context.paintChild(child, offset);
      return;
    }
    // The anchor comes in the coordinates of the layout box that places this
    // one, so the placement offset turns it local.
    final placement = (parentData! as BoxParentData).offset;
    final from = _anchor.shift(-placement);
    final bounds = Offset.zero & size;
    final progress = grow.value;
    final extent = Size.lerp(from.size, bounds.size, progress)!;
    final rect = Rect.fromCenter(
      center: Offset(
        lerpDouble(from.center.dx, bounds.center.dx, moveX.value)!,
        lerpDouble(from.center.dy, bounds.center.dy, moveY.value)!,
      ),
      width: math.max(0.0, extent.width),
      height: math.max(0.0, extent.height),
    );
    final radius = lerpDouble(from.shortestSide / 2, _endRadius, progress)!;
    final clip = AppShape.all(math.max(0.0, radius)).getOuterPath(rect);
    final sourceImage = _sourceImage;
    final image = sourceImage?.value;
    // The source control stays visible until its snapshot exists, so the
    // platter would only cover it.
    if (sourceImage != null && image == null && !_closing) {
      return;
    }
    final reveal = content.value;
    // The card paints the same surface and shadow as the platter, so once it
    // is revealed, or a sub menu leaves the root's bounds, the platter steps
    // aside instead of clipping the levels until the spring settles.
    if ((reveal >= 1 || _unfolded.value) && !_closing && !size.isEmpty) {
      context.pushTransform(
        needsCompositing,
        offset,
        _contentTransform(rect),
        (context, offset) => context.paintChild(child, offset),
      );
      return;
    }
    final closing = _closing;
    // Closing levels keep their own shadows as they fade into the platter.
    final platter = closing ? 1 - reveal : 1.0;
    final settled = progress.clamp(0.0, 1.0);
    final path = clip.shift(offset);
    final canvas = context.canvas;
    final depth = settled * platter;
    final reach = _shadows.fold(
      0.0,
      (reach, shadow) =>
          math.max(reach, shadow.blurSigma * 3 + shadow.offset.distance),
    );
    // The blur shades under the platter too; keep that out of fading content.
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(path.getBounds().inflate(reach))
          ..addPath(path, Offset.zero),
      );
    for (final shadow in _shadows) {
      canvas.drawPath(
        path.shift(shadow.offset),
        shadow.toPaint()
          ..color = shadow.color.withValues(alpha: shadow.color.a * depth),
      );
    }
    canvas.restore();
    final fill = Color.lerp(_sourceColor, _surfaceColor, settled)!;
    canvas.drawPath(
      path,
      Paint()..color = fill.withValues(alpha: fill.a * platter),
    );
    final glyph = 1 - reveal;
    if (image != null && glyph > 0) {
      final source = from.shift(rect.center - from.center + offset);
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        source,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, glyph)
          ..filterQuality = FilterQuality.medium,
      );
    }
    if (reveal <= 0 || size.isEmpty) {
      return;
    }
    final transform = _contentTransform(rect, fit: closing);
    final sigma = _maxContentBlur * (1 - reveal);
    void paintContent(PaintingContext context, Offset offset) =>
        context.pushOpacity(
          offset,
          Color.getAlphaFromOpacity(reveal),
          (context, offset) => context.pushLayer(
            ImageFilterLayer(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            ),
            (context, offset) => context.pushTransform(
              needsCompositing,
              offset,
              transform,
              (context, offset) => context.paintChild(child, offset),
            ),
            offset,
          ),
        );
    if (closing) {
      paintContent(context, offset);
      return;
    }
    context.pushClipPath(needsCompositing, offset, bounds, clip, paintContent);
  }

  Matrix4 _contentTransform(Rect rect, {bool fit = false}) {
    final scale = (fit ? math.min : math.max)(
      rect.width / size.width,
      rect.height / size.height,
    );
    return Matrix4.translationValues(rect.center.dx, rect.center.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }
}

class CommonPopupBox<T> extends StatefulWidget {
  const CommonPopupBox({
    super.key,
    required this.targetBuilder,
    required this.popupBuilder,
    this.fullscreen = false,
  });

  /// 触发控件。拿到的 [PopupOpen] 挂在自己的 `onPressed` / `onTap` 上。
  final Widget Function(PopupOpen<T> open) targetBuilder;

  final WidgetBuilder popupBuilder;

  /// 弹出物铺满整屏。见 [`CommonPopupRoute.fullscreen`]。
  ///
  /// 窄屏那一支（`PopupForm.adaptive`）由调用方按宽度算好再传进来 ——
  /// 这一层不读设置、也不读宽度，只回答「这一次弹哪一形态」。
  final bool fullscreen;

  @override
  State<CommonPopupBox<T>> createState() => _CommonPopupBoxState<T>();
}

class _CommonPopupBoxState<T> extends State<CommonPopupBox<T>> {
  final _sourceKey = GlobalKey();
  final _sourceHidden = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _sourceHidden.dispose();
    super.dispose();
  }

  Rect? _sourceRect() {
    if (!mounted) {
      return null;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
      return null;
    }
    final navigatorBox =
        Navigator.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final origin = renderBox.localToGlobal(Offset.zero, ancestor: navigatorBox);
    return origin & renderBox.size;
  }

  Color _sourceColor() {
    Color? color;
    void visit(Element element) {
      if (color != null) {
        return;
      }
      if (element.widget case final Material material) {
        color = material.type == MaterialType.transparency
            ? Colors.transparent
            : material.color ?? Colors.transparent;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    final resolved = color;
    if (resolved == null || resolved.a == 0) {
      return context.colorScheme.surfaceContainer;
    }
    return resolved;
  }

  void _captureSource(
    CommonPopupRoute<T> route,
    ValueNotifier<ui.Image?> snapshot,
  ) {
    if (!mounted || !route.isActive) {
      return;
    }
    final boundary = _sourceKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      return;
    }
    snapshot.value = boundary.toImageSync(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    _sourceHidden.value = true;
  }

  Future<T?> _open({Offset offset = Offset.zero}) {
    final snapshot = ValueNotifier<ui.Image?>(null);
    final route = CommonPopupRoute<T>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => widget.popupBuilder(context),
      anchorOf: _sourceRect,
      anchorShift: offset,
      sourceColor: _sourceColor(),
      sourceImage: snapshot,
      fullscreen: widget.fullscreen,
    );
    // 这条 future 与 `route.completed` 是同一个 —— 关掉时 `Navigator.pop`
    // 带出来的值就是它。要「选完再落账」的调用点 await 这个，
    // 不看结果的调用点把 `open` 直接当 `onPressed` 用。
    final result = Navigator.of(context).push(route);
    void reveal() {
      if (mounted) {
        _sourceHidden.value = false;
      }
    }

    route.animation!.addStatusListener((status) {
      if (status.isDismissed) {
        reveal();
      }
    });
    route.completed.whenComplete(() {
      reveal();
      snapshot.value?.dispose();
      snapshot.dispose();
    });
    // The control repaints its ink as it is tapped, so it can only be
    // captured once that frame has been painted.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _captureSource(route, snapshot),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _sourceHidden,
      builder: (_, hidden, child) =>
          Opacity(opacity: hidden ? 0 : 1, child: child),
      child: RepaintBoundary(
        key: _sourceKey,
        child: widget.targetBuilder(_open),
      ),
    );
  }
}

class CommonPopupMenuItem {
  const CommonPopupMenuItem({
    // `content` 行没有整行标签（那一行的中部就是内容自己），所以不设 required。
    this.label = '',
    this.glyph,
    this.onPressed,
    this.danger = false,
    this.checked,
    this.subItems = const [],
    this.content,
    this.isDivider = false,
  });

  /// 分节线。不占一项的语义，只在两组动作之间画一条线（`_dividerHeight` 那条
  /// 与子菜单展开用的是同一条）。原文没有这个概念 —— 本仓的菜单项集是分节的。
  const CommonPopupMenuItem.divider()
    : label = '',
      glyph = null,
      onPressed = null,
      danger = false,
      checked = null,
      subItems = const [],
      content = null,
      isDivider = true;

  final String label;
  final Glyph? glyph;
  final VoidCallback? onPressed;
  final bool danger;
  final bool? checked;
  final List<CommonPopupMenuItem> subItems;

  /// 整段替换中部的**标签文本**：泳道菜单的「常规宽度」要在项里嵌一只输入框，
  /// 那一行的中部就是输入框自己（`glyph` 仍照常画在前面）。注意菜单的量宽
  /// 逻辑只读 `label` —— `content` 行贡献不了宽度，菜单宽退到 min/max 夹取。
  final Widget? content;

  final bool isDivider;
}

/// 弹出物**长成之后那张脸**：底色、圆角、阴影与 [`CommonPopupRoute`] 的托盘
/// 同源（`surfaceContainer` + `_cardRadius` + `_cardShadows`）。
///
/// 为什么必须抽成一份：托盘是**逐帧往这张脸收敛**的（`_RenderPopupMorph`
/// 把锚点矩形插值到子件矩形），交接那一帧两边的形状只要差一点就能看出来。
/// 菜单（[CommonPopupMenu] 的每一层）与面板（`PopupPanel` 的卡片形态）都铺
/// 这一层，「弹出物长什么样」于是只有一处能漂。
///
/// 内边距**不**在这里定：菜单的 8（`_cardInset`，圆角正是由它推出来的）与
/// 面板的 20（`PopupPanel` 自己那档）不是同一个数，几何口径留在各自那边。
class CommonPopupSurface extends StatelessWidget {
  const CommonPopupSurface({
    super.key,
    required this.child,
    this.depth = 1,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// 阴影深度档：1 是全量，越小越淡（菜单的子层往后退时按它降档）。
  final double depth;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final shape = AppShape.all(_cardRadius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: _cardShadows(colorScheme, depth),
      ),
      child: Material(
        type: MaterialType.card,
        // 自己的淡入由托盘负责；这里再补一层 Material 自带的动画会让
        // 两段过渡叠在一起。
        animationDuration: Duration.zero,
        color: colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class CommonPopupMenu extends StatefulWidget {
  const CommonPopupMenu({
    super.key,
    required this.items,
    this.minWidth = 160,
    this.maxWidth = 280,
  });

  final List<CommonPopupMenuItem> items;
  final double minWidth;
  final double maxWidth;

  @override
  State<CommonPopupMenu> createState() => _CommonPopupMenuState();
}

class _MenuStep {
  const _MenuStep({
    required this.index,
    required this.itemTop,
    required this.cardWidth,
  });

  final int index;
  final double itemTop;
  final double cardWidth;
}

class _MenuLevel {
  const _MenuLevel({
    required this.items,
    required this.top,
    required this.fromWidth,
    required this.minWidth,
    required this.maxWidth,
    this.owner,
  });

  final List<CommonPopupMenuItem> items;
  final CommonPopupMenuItem? owner;
  final double top;
  final double fromWidth;
  final double minWidth;
  final double maxWidth;
}

class _CommonPopupMenuState extends State<CommonPopupMenu>
    with SingleTickerProviderStateMixin {
  static const _levelWidthScale = 1.12;
  static const _levelScaleStep = 0.05;
  static const _levelFadeStep = 0.2;
  static const _levelShadowStep = 1 / 3;
  static const _minShadow = 1 / 6;
  static final _arrowTween = Tween(begin: 0.0, end: 0.25);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _unfoldDuration,
    reverseDuration: _closeDuration,
    value: 1,
  );

  late final CurvedAnimation _frame = CurvedAnimation(
    parent: _controller,
    curve: Interval(0, _frameSpan, curve: _frameSpring),
    reverseCurve: _returnXSpring,
  );
  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.5, 1, curve: Curves.easeIn),
  );
  late final CurvedAnimation _unfold = CurvedAnimation(
    parent: _controller,
    curve: _unfoldSpring,
    reverseCurve: _shrinkSpring,
  );

  final List<_MenuStep> _path = [];
  bool _folding = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleStatusChanged);
  }

  @override
  void dispose() {
    _frame.dispose();
    _reveal.dispose();
    _unfold.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !_folding || _path.isEmpty) {
      return;
    }
    _folding = false;
    setState(() {
      _path.removeLast();
      _controller.value = 1;
    });
  }

  List<_MenuLevel> _resolveLevels() {
    final rootWidth = math.min(widget.minWidth, widget.maxWidth);
    final levels = [
      _MenuLevel(
        items: widget.items,
        top: 0,
        fromWidth: rootWidth,
        minWidth: rootWidth,
        maxWidth: widget.maxWidth,
      ),
    ];
    for (final step in _path) {
      final parent = levels.last;
      if (step.index >= parent.items.length) {
        break;
      }
      final item = parent.items[step.index];
      if (item.subItems.isEmpty) {
        break;
      }
      final fromWidth = math.max(step.cardWidth, parent.minWidth);
      final minWidth = fromWidth * _levelWidthScale;
      levels.add(
        _MenuLevel(
          items: item.subItems,
          owner: item,
          top: math.max(0, step.itemTop - _cardInset),
          fromWidth: fromWidth,
          minWidth: minWidth,
          maxWidth: math.max(minWidth, widget.maxWidth),
        ),
      );
    }
    return levels;
  }

  void _push(BuildContext itemContext, int index) {
    final itemBox = itemContext.findRenderObject() as RenderBox?;
    final stackBox = context.findRenderObject() as RenderBox?;
    final placed =
        itemBox != null &&
        stackBox != null &&
        itemBox.hasSize &&
        stackBox.hasSize;
    _folding = false;
    const _PopupUnfoldNotification().dispatch(context);
    setState(() {
      _path.add(
        _MenuStep(
          index: index,
          itemTop: placed
              ? itemBox.localToGlobal(Offset.zero, ancestor: stackBox).dy
              : 0,
          cardWidth: placed
              ? itemBox.size.width + 2 * _cardInset
              : widget.minWidth,
        ),
      );
    });
    _controller.forward(from: 0);
  }

  void _pop() {
    if (_path.isEmpty || _folding) {
      return;
    }
    _folding = true;
    _controller.reverse();
  }

  void _select(VoidCallback onPressed) {
    Navigator.of(context).pop();
    onPressed();
  }

  Widget _buildRow(
    BuildContext context, {
    required CommonPopupMenuItem item,
    required VoidCallback? onTap,
    Animation<double>? arrowTurns,
  }) {
    final colorScheme = context.colorScheme;
    // `content` 行（输入框那类）没有 onTap 也要亮着画 —— 它不是禁用项，
    // 只是「这一行没有整行的点击语义」。
    final enabled = onTap != null || item.content != null;
    final color = item.danger ? colorScheme.error : colorScheme.onSurface;
    final foregroundColor = enabled ? color : color.opacity30;
    Widget? arrow;
    if (item.subItems.isNotEmpty) {
      arrow = GlyphIcon(
        AppGlyphs.chevronForward,
        size: _submenuArrowSize,
        color: foregroundColor,
      );
      if (arrowTurns != null) {
        arrow = RotationTransition(turns: arrowTurns, child: arrow);
      }
    } else if (item.checked == true) {
      arrow = GlyphIcon(
        AppGlyphs.check,
        size: _submenuArrowSize,
        color: foregroundColor,
      );
    }
    final content = item.content;
    final child = InkWell(
      customBorder: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(_itemRadius)),
      ),
      onTap: onTap,
      splashColor: Colors.transparent,
      hoverColor: item.danger ? colorScheme.error.opacity10 : null,
      child: Padding(
        padding: arrow != null ? _itemArrowPadding : _itemPadding,
        child: Row(
          children: [
            if (item.glyph case final glyph?) ...[
              GlyphIcon(glyph, size: _itemIconSize, color: foregroundColor),
              const SizedBox(width: 12),
            ],
            Expanded(
              child:
                  content ??
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: foregroundColor,
                    ),
                  ),
            ),
            if (arrow != null) ...[const SizedBox(width: 8), arrow],
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      checked: item.checked,
      child: child,
    );
  }

  Widget _buildItem(BuildContext context, CommonPopupMenuItem item, int index) {
    if (item.isDivider) {
      return const Divider(height: _dividerHeight, thickness: 1);
    }
    if (item.subItems.isNotEmpty) {
      return Builder(
        builder: (itemContext) => _buildRow(
          itemContext,
          item: item,
          onTap: () => _push(itemContext, index),
        ),
      );
    }
    final onPressed = item.onPressed;
    return _buildRow(
      context,
      item: item,
      onTap: onPressed == null ? null : () => _select(onPressed),
    );
  }

  Widget _buildContent(
    BuildContext context,
    _MenuLevel level, {
    required bool active,
  }) {
    final items = [
      for (var index = 0; index < level.items.length; index++)
        _buildItem(context, level.items[index], index),
    ];
    final owner = level.owner;
    if (owner == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
    }
    final unfold = active ? _unfold : kAlwaysCompleteAnimation;
    final reveal = active ? _reveal : kAlwaysCompleteAnimation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(
          context,
          item: owner,
          onTap: _pop,
          arrowTurns: unfold.drive(_arrowTween),
        ),
        SizeTransition(
          sizeFactor: unfold,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: reveal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: _dividerHeight, thickness: 1),
                ...items,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLevel(
    BuildContext context,
    _MenuLevel level, {
    required int depth,
    required double pivot,
  }) {
    final receding = depth > 0;
    final colorScheme = context.colorScheme;
    final shape = AppShape.all(_cardRadius);
    return IgnorePointer(
      ignoring: receding,
      child: ExcludeSemantics(
        excluding: receding,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _frame,
            builder: (context, child) {
              final frame = receding ? 1.0 : _frame.value;
              final distance = receding ? depth - 1 + _frame.value : 0.0;
              final scale = math.max(0.0, 1 - _levelScaleStep * distance);
              final shadow = receding
                  ? math.max(_minShadow, 1 - distance * _levelShadowStep)
                  : frame;
              return Transform(
                transform: Matrix4.diagonal3Values(scale, scale, 1),
                alignment: Alignment.topRight,
                origin: Offset(0, pivot),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: ShapeDecoration(
                    color: colorScheme.surface.withValues(
                      alpha: math.min(0.4, _levelFadeStep * distance),
                    ),
                    shape: shape,
                  ),
                  child: CommonPopupSurface(
                    depth: shadow,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: lerpDouble(
                          level.fromWidth,
                          level.minWidth,
                          frame,
                        )!,
                        maxWidth: lerpDouble(
                          level.fromWidth,
                          level.maxWidth,
                          frame,
                        )!,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(_cardInset),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: IntrinsicWidth(
                  child: _buildContent(context, level, active: !receding),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final levels = _resolveLevels();
    final topIndex = levels.length - 1;
    return PopScope(
      canPop: topIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _pop();
        }
      },
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          for (var index = 0; index <= topIndex; index++)
            Padding(
              key: ValueKey(index),
              padding: EdgeInsets.only(top: levels[index].top),
              child: _buildLevel(
                context,
                levels[index],
                depth: topIndex - index,
                pivot: index < topIndex
                    ? _path[index].itemTop - levels[index].top
                    : 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// 原文从 `fl_clash/common/color.dart` 拿的两档透明度；本仓没有那份扩展，
/// 只把这份文件用到的两档搬进来，语义与原文逐字一致。
extension _PopupColorOpacity on Color {
  Color get opacity30 => withValues(alpha: 0.3);

  Color get opacity10 => withValues(alpha: 0.1);
}
