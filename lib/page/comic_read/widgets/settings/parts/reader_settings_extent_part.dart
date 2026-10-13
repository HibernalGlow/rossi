part of '../reader_settings_sheet.dart';

/// 复用 M3E 的滚动交接，不使用会自带第二套标题/关闭按钮的 Frame。
/// 可见高度就是正文 viewport 高度；落位弹簧与项目 Dock / lens 共用。
class _ReaderSettingsExtent implements M3EBottomSheetDragTarget {
  _ReaderSettingsExtent(TickerProvider vsync)
    : motion = SpringLensValue(vsync, .72);

  final SpringLensValue motion;
  double maxHeight = 0;
  bool animate = true;
  Timer? _wheelSettle;
  static const detents = [.5, .72, .9, 1.0];

  double get fraction => motion.value.clamp(.5, 1.0);

  @override
  bool get isAtMax => fraction >= .999;

  @override
  bool get canDrag => maxHeight >= 480;

  @override
  void dragBy(double delta) {
    if (!canDrag) return;
    _wheelSettle?.cancel();
    motion.jumpTo((fraction - delta / maxHeight).clamp(.5, 1.0));
  }

  void scrollBy(double delta) {
    dragBy(-delta);
    _wheelSettle = Timer(const Duration(milliseconds: 120), () {
      // 小幅滚动也能向下一档落位，不会每个 wheel event 都被吸回原处。
      settle(delta.sign * maxHeight * .8);
    });
  }

  @override
  void settle(double velocity) {
    if (!canDrag) return;
    final projected = fraction + velocity / maxHeight * .1;
    var target = detents.first;
    for (final detent in detents) {
      if ((detent - projected).abs() < (target - projected).abs()) {
        target = detent;
      }
    }
    snapTo(target);
  }

  void snapTo(double fraction) {
    if (animate) {
      motion.springTo(fraction, LensMetrics.settle);
    } else {
      motion.jumpTo(fraction);
    }
  }

  void dispose() {
    _wheelSettle?.cancel();
    motion.dispose();
  }
}

class _ReaderSettingsExtentScope extends InheritedWidget {
  const _ReaderSettingsExtentScope({
    required this.extent,
    required super.child,
  });
  final _ReaderSettingsExtent extent;

  static _ReaderSettingsExtent of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ReaderSettingsExtentScope>()!
      .extent;

  @override
  bool updateShouldNotify(_ReaderSettingsExtentScope oldWidget) =>
      extent != oldWidget.extent;
}
