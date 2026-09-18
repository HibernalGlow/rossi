import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_strip_metrics.dart';

/// 水平泳道拖拽分栏手柄
class LaneResizer extends StatefulWidget {
  /// 手柄的**占位宽度**。
  ///
  /// 泳道条带拼装时要把它算进总宽，**两处必须是同一个数** ——
  /// 否则「算出来的总宽」与「实际摆出来的总宽」差一个手柄的宽度，
  /// Row 就会溢出，Flutter 会直接糊一条黄黑斜纹到界面上（见 `swimlane_workspace` 的注释）。
  ///
  /// 取值引用 [WorkspaceStripMetrics.defaultResizerWidth]：宽度分配是纯函数
  /// （`WorkspaceStripMetrics.resolve`），判据脚本加载不了本 widget，
  /// 只有**同一个常量**才能保证「算的」与「画的」是同一件事。
  static const double width = WorkspaceStripMetrics.defaultResizerWidth;

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
          width: LaneResizer.width,
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
