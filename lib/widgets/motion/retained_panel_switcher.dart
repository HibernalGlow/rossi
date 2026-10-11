import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';

/// 保留各面板的导航栈和滚动位置，只在切换时对进出面板做过渡。
class RetainedPanelSwitcher extends StatefulWidget {
  const RetainedPanelSwitcher({
    super.key,
    required this.selectedId,
    required this.children,
  });

  final String selectedId;
  final Map<String, Widget> children;

  @override
  State<RetainedPanelSwitcher> createState() => _RetainedPanelSwitcherState();
}

class _RetainedPanelSwitcherState extends State<RetainedPanelSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  )..addStatusListener(_handleAnimationStatus);
  Map<String, ({double opacity, double offset})> _starts = {};
  double _direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = ExpressiveMotion.duration(
      context,
      ExpressiveMotion.spatialDuration,
    );
    if (_controller.duration == Duration.zero) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(RetainedPanelSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId == oldWidget.selectedId) return;
    final ids = widget.children.keys.toList();
    final direction =
        ids.indexOf(widget.selectedId) >= ids.indexOf(oldWidget.selectedId)
        ? 1.0
        : -1.0;
    // 途中过来的切换从当前画面接续，避免淡入尚未结束就突然重置透明度。
    final starts = <String, ({double opacity, double offset})>{};
    for (final id in ids) {
      final current = _values(id, oldWidget.selectedId);
      starts[id] = id == widget.selectedId && current.opacity == 0
          ? (opacity: 0, offset: .045 * direction)
          : current;
    }
    _starts = starts;
    _direction = direction;
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      // 仅在结束时把退出面板藏起来；动画帧直接更新渲染层。
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in widget.children.entries)
          _panel(entry.key, entry.value),
      ],
    ),
  );

  ({double opacity, double offset}) _values(String id, String selectedId) {
    final selected = id == selectedId;
    final start = _starts[id] ?? (opacity: selected ? 1.0 : 0.0, offset: 0.0);
    final fade = Curves.easeOut.transform(_controller.value);
    final spatial = ExpressiveMotion.spatialCurve.transform(_controller.value);
    final endOpacity = selected ? 1.0 : 0.0;
    final endOffset = selected ? 0.0 : -.025 * _direction;
    return (
      opacity: start.opacity + (endOpacity - start.opacity) * fade,
      offset: start.offset + (endOffset - start.offset) * spatial,
    );
  }

  Widget _panel(String id, Widget child) {
    final selected = id == widget.selectedId;
    final outgoing = (_starts[id]?.opacity ?? 0) > 0 && _controller.value < 1;
    final start = _starts[id] ?? (opacity: selected ? 1.0 : 0.0, offset: 0.0);
    final opacity = _controller.drive(
      Tween<double>(
        begin: start.opacity,
        end: selected ? 1 : 0,
      ).chain(CurveTween(curve: Curves.easeOut)),
    );
    final position = _controller.drive(
      Tween<Offset>(
        begin: Offset(start.offset, 0),
        end: Offset(selected ? 0 : -.025 * _direction, 0),
      ).chain(CurveTween(curve: ExpressiveMotion.spatialCurve)),
    );
    return Offstage(
      key: ValueKey(id),
      offstage: !selected && !outgoing,
      child: TickerMode(
        enabled: selected,
        child: IgnorePointer(
          ignoring: !selected,
          child: ExcludeSemantics(
            excluding: !selected,
            child: SlideTransition(
              position: position,
              child: FadeTransition(
                opacity: opacity,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
