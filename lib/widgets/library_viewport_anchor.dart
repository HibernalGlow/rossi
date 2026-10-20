import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 只登记实际挂载的卡片；Sliver 回收时同步移除，不随历史页数增长。
class LibraryViewportRegistry {
  /// 登记键不能直接用条目 key：同一本漫画在相邻两页重复出现时 key 会撞车，
  /// 后挂载的那张会把前一张的几何顶掉。有下标时用下标当登记键，key 只作为
  /// 对外的身份（保存/恢复用）。
  final _contexts = <String, _RegisteredAnchor>{};

  String _slot(String key, int? index) => index == null ? key : 'i:$index';

  ({String key, int? index, double offset})? firstVisible() {
    ({String key, int? index, double offset})? first;
    for (final entry in _contexts.entries) {
      final anchor = entry.value;
      final geometry = _geometry(anchor.context);
      if (geometry == null ||
          geometry.bottom <= 0 ||
          geometry.top >= geometry.height) {
        continue;
      }
      final index = anchor.index;
      final earlierByIndex =
          index != null && (first?.index == null || index < first!.index!);
      final earlierByOffset =
          index == null &&
          first?.index == null &&
          (first == null || geometry.top < first.offset);
      if (first == null || earlierByIndex || earlierByOffset) {
        first = (key: anchor.entryKey, index: index, offset: geometry.top);
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
    final context = _contexts.values
        .where((anchor) => anchor.entryKey == key)
        .map((anchor) => anchor.context)
        .firstOrNull;
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
    this.entryIndex,
    required this.child,
  });
  final LibraryViewportRegistry registry;
  final String entryKey;

  /// 条目在宿主列表里的下标。给了下标时，[LibraryViewportRegistry.firstVisible]
  /// 按它取「最靠前的一张」，不靠像素位置推断 —— 同一本漫画在相邻两页重复出现
  /// 时 key 会撞车，按 key 反查页码就会一直读到后一页。
  final int? entryIndex;
  final Widget child;

  @override
  State<LibraryViewportAnchor> createState() => _LibraryViewportAnchorState();
}

class _LibraryViewportAnchorState extends State<LibraryViewportAnchor> {
  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(LibraryViewportAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry ||
        oldWidget.entryKey != widget.entryKey ||
        oldWidget.entryIndex != widget.entryIndex) {
      _remove(oldWidget);
      _register();
    }
  }

  void _register() {
    widget.registry._contexts[widget.registry._slot(
      widget.entryKey,
      widget.entryIndex,
    )] = _RegisteredAnchor(
      context: context,
      entryKey: widget.entryKey,
      index: widget.entryIndex,
    );
  }

  void _remove(LibraryViewportAnchor value) {
    final slot = value.registry._slot(value.entryKey, value.entryIndex);
    final registered = value.registry._contexts[slot];
    if (registered != null && identical(registered.context, context)) {
      value.registry._contexts.remove(slot);
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

class _RegisteredAnchor {
  const _RegisteredAnchor({
    required this.context,
    required this.entryKey,
    required this.index,
  });

  final BuildContext context;
  final String entryKey;
  final int? index;
}
