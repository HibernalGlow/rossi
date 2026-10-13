part of '../common_popup.dart';

class _PopupAnchorTracker extends StatefulWidget {
  const _PopupAnchorTracker({
    required this.anchorOf,
    required this.builder,
    required this.child,
  });

  final PopupAnchorResolver anchorOf;
  final Widget Function(Rect anchor, EdgeInsets safeInsets, Widget child)
  builder;
  final Widget child;

  @override
  State<_PopupAnchorTracker> createState() => _PopupAnchorTrackerState();
}

class _PopupAnchorTrackerState extends State<_PopupAnchorTracker> {
  Rect? _anchor;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      final anchor = widget.anchorOf();
      if (anchor == null || anchor == _anchor) {
        return;
      }
      setState(() {
        _anchor = anchor;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final anchor = _anchor ??= widget.anchorOf() ?? Rect.zero;
    // padding already gives up the part of the bottom inset the keyboard
    // covers, so the sum keeps clear of the taller of the two.
    return widget.builder(
      anchor,
      mediaQuery.padding + mediaQuery.viewInsets,
      widget.child,
    );
  }
}

class _PopupLayoutDelegate extends SingleChildLayoutDelegate {
  const _PopupLayoutDelegate({
    required this.anchor,
    required this.safeInsets,
    required this.placement,
    this.avoid,
    this.fullscreen = false,
  });

  final Rect anchor;
  final EdgeInsets safeInsets;
  final PopupPlacement placement;
  final Rect? avoid;
  final bool fullscreen;

  /// 全屏形态不吃安全区：那一份留给内容自己（外壳里的 `SafeArea`），
  /// 因为安全区在整屏上是「内容的内边距」，不是「弹层的外边距」。
  EdgeInsets get _insets =>
      fullscreen
      ? EdgeInsets.zero
      : safeInsets + const EdgeInsets.all(_screenMargin);

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    if (fullscreen) {
      return BoxConstraints.tight(constraints.biggest);
    }
    final insets = _insets;
    return BoxConstraints.loose(
      Size(
        math.max(0.0, constraints.maxWidth - insets.horizontal),
        math.max(0.0, constraints.maxHeight - insets.vertical),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (fullscreen) {
      return Offset.zero;
    }
    final insets = _insets;
    final maxX = size.width - insets.right - childSize.width;
    final maxY = size.height - insets.bottom - childSize.height;
    final (x, y) = switch (placement) {
      PopupPlacement.overAnchorEnd => (
        anchor.right - childSize.width,
        anchor.top - _anchorOverlap,
      ),
      PopupPlacement.center => (
        insets.left + (size.width - insets.horizontal - childSize.width) / 2,
        insets.top + (size.height - insets.vertical - childSize.height) / 2,
      ),
      PopupPlacement.belowPoint => (
        anchor.left,
        _yBelowPoint(childSize.height, insets.top, maxY),
      ),
    };
    return Offset(
      x.clamp(insets.left, math.max(insets.left, maxX)),
      y.clamp(insets.top, math.max(insets.top, maxY)),
    );
  }

  double _yBelowPoint(double height, double minY, double maxY) {
    final avoid = this.avoid;
    if (avoid != null) {
      final above = avoid.top - _avoidGap - height;
      if (above >= minY) {
        return above;
      }
      final below = avoid.bottom + _avoidGap;
      if (below <= maxY) {
        return below;
      }
    }
    if (anchor.bottom > maxY && anchor.top - height >= minY) {
      return anchor.top - height;
    }
    return anchor.bottom;
  }

  @override
  bool shouldRelayout(_PopupLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.safeInsets != safeInsets ||
        oldDelegate.placement != placement ||
        oldDelegate.avoid != avoid ||
        oldDelegate.fullscreen != fullscreen;
  }
}
