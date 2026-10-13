import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';
import 'package:flutter/widgets.dart';

/// 顶栏、底栏共享可重定向的空间弹簧，连续点击时从当前位置继续运动。
class ReaderChromeTransition extends StatefulWidget {
  const ReaderChromeTransition({
    super.key,
    required this.visible,
    required this.child,
    this.top = false,
    this.animate = true,
  });

  final bool visible;
  final bool top;
  final bool animate;
  final Widget child;

  @override
  State<ReaderChromeTransition> createState() => _ReaderChromeTransitionState();
}

class _ReaderChromeTransitionState extends State<ReaderChromeTransition>
    with SingleTickerProviderStateMixin {
  late final _motion = SpringLensValue(this, widget.visible ? 1 : 0);

  void _move() {
    final target = widget.visible ? 1.0 : 0.0;
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      _motion.jumpTo(target);
    } else {
      _motion.springTo(target, LensMetrics.settle);
    }
  }

  @override
  void didUpdateWidget(ReaderChromeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.animate != widget.animate) {
      _move();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) _move();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.visible,
    child: ExcludeFocus(
      excluding: !widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: AnimatedBuilder(
          animation: _motion,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  !widget.animate || MediaQuery.disableAnimationsOf(context),
            ),
            child: widget.child,
          ),
          builder: (context, child) => Opacity(
            opacity: _motion.value.clamp(0, 1),
            child: FractionalTranslation(
              translation: Offset(
                0,
                (1 - _motion.value) * (widget.top ? -1 : 1),
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
