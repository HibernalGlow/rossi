import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/navigation/spring_curve.dart';

/// 尺寸变化用收敛的弹簧，透明度用独立的有界曲线。
/// 不让弹簧过冲进入 Opacity / heightFactor，也尊重系统减少动画设置。
abstract final class ExpressiveMotion {
  static const spatialDuration = Duration(milliseconds: 320);
  static const exitDuration = Duration(milliseconds: 180);
  static const effectDuration = Duration(milliseconds: 140);
  static final spatialCurve = SpringCurve(
    const SpringDescription(mass: 1, stiffness: 400, damping: 40),
    seconds: .32,
  );

  static Duration duration(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// 搜索区域从触发工具栏下方展开，关闭时同时收回高度与透明度。
/// 只有一份可输入内容，退出中的内容立即停止命中与读屏。
class ExpressiveReveal extends StatelessWidget {
  const ExpressiveReveal({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: ExpressiveMotion.duration(
      context,
      ExpressiveMotion.spatialDuration,
    ),
    reverseDuration: ExpressiveMotion.duration(
      context,
      ExpressiveMotion.exitDuration,
    ),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => SizeTransition(
      sizeFactor: animation.drive(
        CurveTween(curve: ExpressiveMotion.spatialCurve),
      ),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation.drive(
          CurveTween(curve: const Interval(.12, 1, curve: Curves.easeOut)),
        ),
        child: SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, -.08),
              end: Offset.zero,
            ).chain(CurveTween(curve: ExpressiveMotion.spatialCurve)),
          ),
          child: child,
        ),
      ),
    ),
    child: visible
        ? KeyedSubtree(key: const ValueKey('revealed'), child: child)
        : const SizedBox.shrink(key: ValueKey('collapsed')),
  );
}
