part of '../common_popup.dart';

/// 不抢焦点的预览浮层复用弹层托盘的弧线、缩放、模糊和退出弹簧。
/// [anchor] 是浮层自身坐标中的来源控件矩形；尺寸固定保证连续更新不重启入场。
class CommonPopupOverlayMotion extends StatefulWidget {
  const CommonPopupOverlayMotion({
    super.key,
    required this.size,
    required this.anchor,
    required this.visible,
    required this.onDismissed,
    required this.child,
  });

  final Size size;
  final Rect anchor;
  final bool visible;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<CommonPopupOverlayMotion> createState() =>
      _CommonPopupOverlayMotionState();
}

class _CommonPopupOverlayMotionState extends State<CommonPopupOverlayMotion>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _openDuration,
    reverseDuration: _closeDuration,
  )..addStatusListener(_onStatus);
  late final _grow = CurvedAnimation(
    parent: _controller,
    curve: _growSpring,
    reverseCurve: _shrinkSpring,
  );
  late final _moveX = CurvedAnimation(
    parent: _controller,
    curve: _moveXSpring,
    reverseCurve: _returnXSpring,
  );
  late final _moveY = CurvedAnimation(
    parent: _controller,
    curve: _moveYSpring,
    reverseCurve: _returnYSpring,
  );
  late final _content = CurvedAnimation(
    parent: _controller,
    curve: const Interval(.04, .45, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(.5, 1, curve: Curves.easeIn),
  );
  final _unfolded = ValueNotifier(false);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = eInkInstantRoutes || MediaQuery.disableAnimationsOf(context);
    _syncVisibility();
  }

  @override
  void didUpdateWidget(CommonPopupOverlayMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _syncVisibility();
  }

  void _syncVisibility() {
    if (_reduced) {
      _controller.value = widget.visible ? 1 : 0;
      if (!widget.visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !widget.visible) widget.onDismissed();
        });
      }
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (!_reduced && status == AnimationStatus.dismissed && !widget.visible) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _moveX.dispose();
    _moveY.dispose();
    _content.dispose();
    _unfolded.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: widget.size,
    child: _reduced
        ? widget.child
        : CustomSingleChildLayout(
            delegate: const _PopupOverlayLayout(),
            child: _PopupMorph(
              anchor: widget.anchor,
              animation: _controller,
              grow: _grow,
              moveX: _moveX,
              moveY: _moveY,
              content: _content,
              unfolded: _unfolded,
              endRadius: _cardRadius,
              sourceColor: Colors.transparent,
              sourceImage: null,
              surfaceColor: context.colorScheme.surfaceContainerHigh,
              shadows: _cardShadows(context.colorScheme),
              child: widget.child,
            ),
          ),
  );
}

/// 与路由版相同的定位父节点，向 morph 提供 BoxParentData 和局部原点。
class _PopupOverlayLayout extends SingleChildLayoutDelegate {
  const _PopupOverlayLayout();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset.zero;

  @override
  bool shouldRelayout(_PopupOverlayLayout oldDelegate) => false;
}
