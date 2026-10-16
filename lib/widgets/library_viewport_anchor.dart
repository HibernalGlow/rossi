import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 只登记实际挂载的卡片；Sliver 回收时同步移除，不随历史页数增长。
class LibraryViewportRegistry {
  final _contexts = <String, BuildContext>{};

  ({String key, double offset})? firstVisible() {
    ({String key, double offset})? first;
    for (final entry in _contexts.entries) {
      final geometry = _geometry(entry.value);
      if (geometry == null ||
          geometry.bottom <= 0 ||
          geometry.top >= geometry.height) {
        continue;
      }
      if (first == null || geometry.top < first.offset) {
        first = (key: entry.key, offset: geometry.top);
      }
    }
    return first;
  }

  ({double top, double bottom, double height})? _geometry(
    BuildContext context,
  ) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || viewport is! RenderBox) return null;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return null;
    final top = box.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    return (
      top: top,
      bottom: top + box.size.height,
      height: viewportBox.size.height,
    );
  }

  bool align(String key, double offset) {
    final context = _contexts[key];
    if (context == null) return false;
    final geometry = _geometry(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (geometry == null || position == null) return false;
    final target = (position.pixels + geometry.top - offset).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() > .5) position.jumpTo(target);
    return true;
  }
}

class LibraryViewportAnchor extends StatefulWidget {
  const LibraryViewportAnchor({
    super.key,
    required this.registry,
    required this.entryKey,
    required this.child,
  });
  final LibraryViewportRegistry registry;
  final String entryKey;
  final Widget child;

  @override
  State<LibraryViewportAnchor> createState() => _LibraryViewportAnchorState();
}

class _LibraryViewportAnchorState extends State<LibraryViewportAnchor> {
  @override
  void initState() {
    super.initState();
    widget.registry._contexts[widget.entryKey] = context;
  }

  @override
  void didUpdateWidget(LibraryViewportAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry ||
        oldWidget.entryKey != widget.entryKey) {
      _remove(oldWidget);
      widget.registry._contexts[widget.entryKey] = context;
    }
  }

  void _remove(LibraryViewportAnchor value) {
    if (identical(value.registry._contexts[value.entryKey], context)) {
      value.registry._contexts.remove(value.entryKey);
    }
  }

  @override
  void dispose() {
    _remove(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
