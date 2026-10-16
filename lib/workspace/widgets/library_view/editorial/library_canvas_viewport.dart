part of 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';

/// 展墙与插件页的恢复入口，共用已有的条目偏移和虚拟列表。
extension LibraryCanvasViewport on LibraryEditorialCanvasState {
  bool jumpToEntry(String key) {
    if (!_presentation.editorial || !_scroll.hasClients) return false;
    final offset = _entryOffsets[key];
    if (offset == null) return false;
    _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    return true;
  }

  /// 变高展墙的阅读跟随：先定位远处页，再按实际渲染框居中。
  void revealEntry(String key) {
    var remaining = 5;
    void position(Duration _) {
      if (!mounted || !_scroll.hasClients || remaining-- <= 0) return;
      final anchor = _anchors['tile:$key']?.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          alignment: .5,
          duration: ExpressiveMotion.duration(
            context,
            const Duration(milliseconds: 260),
          ),
        );
        return;
      }
      final top = _entryOffsets[key];
      if (top == null) return;
      final offset =
          top +
          (_entryHeights[key] ?? 200) / 2 -
          _scroll.position.viewportDimension / 2;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback(position);
      WidgetsBinding.instance.scheduleFrame();
    }

    WidgetsBinding.instance.addPostFrameCallback(position);
    WidgetsBinding.instance.scheduleFrame();
  }
}
