import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/motion/retained_panel_switcher.dart';

/// 书架内容与泳道共用同一套过渡，访问过的列表保留状态。
class BookshelfPanels extends StatefulWidget {
  const BookshelfPanels({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.children,
  }) : assert(selectedIndex >= 0 && selectedIndex < children.length);

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<Widget> children;

  @override
  State<BookshelfPanels> createState() => _BookshelfPanelsState();
}

class _BookshelfPanelsState extends State<BookshelfPanels> {
  final Set<int> _visited = {};
  double _dragDistance = 0;

  void _finishSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDistance.abs() < 48 && velocity.abs() < 400) return;
    final movement = velocity.abs() >= 400 ? velocity : _dragDistance;
    final forward = Directionality.of(context) == TextDirection.ltr
        ? movement < 0
        : movement > 0;
    final index = (widget.selectedIndex + (forward ? 1 : -1)).clamp(
      0,
      widget.children.length - 1,
    );
    if (index != widget.selectedIndex) widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.selectedIndex);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) =>
          _dragDistance += details.primaryDelta ?? 0,
      onHorizontalDragEnd: _finishSwipe,
      child: RetainedPanelSwitcher(
        selectedId: '${widget.selectedIndex}',
        children: {
          for (var i = 0; i < widget.children.length; i++)
            if (_visited.contains(i)) '$i': widget.children[i],
        },
      ),
    );
  }
}
