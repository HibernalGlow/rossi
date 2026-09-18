import 'package:material_ui/material_ui.dart';

/// 水平泳道拖拽分栏手柄
class LaneResizer extends StatefulWidget {
  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDoubleTapReset;

  const LaneResizer({
    super.key,
    required this.onDragDelta,
    this.onDoubleTapReset,
  });

  @override
  State<LaneResizer> createState() => _LaneResizerState();
}

class _LaneResizerState extends State<LaneResizer> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _isHovered || _isDragging;

    final barColor = active
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTapReset,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        onHorizontalDragUpdate: (details) {
          widget.onDragDelta(details.delta.dx);
        },
        child: SizedBox(
          width: 10,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 3.0 : 1.5,
              height: double.infinity,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
