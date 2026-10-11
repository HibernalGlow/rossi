import 'package:material_ui/material_ui.dart';

/// 网格把排版交互交给卡片外壳，业务卡片不需要逐个接入拖拽参数。
class CardLayoutScope extends InheritedWidget {
  const CardLayoutScope({
    super.key,
    required this.editing,
    required this.resizing,
    this.previewSize,
    required this.dragging,
    required this.wrapHeader,
    required this.resizeHandle,
    required this.onResize,
    required this.widthSpan,
    required this.heightSpan,
    this.onHide,
    required super.child,
  });

  final bool editing;
  final bool resizing;
  final Size? previewSize;
  final bool dragging;
  final Widget Function(Widget header) wrapHeader;
  final Widget? resizeHandle;
  final void Function(int width, int height)? onResize;
  final VoidCallback? onHide;
  final int widthSpan;
  final int heightSpan;

  static CardLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardLayoutScope>();

  @override
  bool updateShouldNotify(CardLayoutScope oldWidget) =>
      editing != oldWidget.editing ||
      resizing != oldWidget.resizing ||
      previewSize != oldWidget.previewSize ||
      dragging != oldWidget.dragging ||
      widthSpan != oldWidget.widthSpan ||
      heightSpan != oldWidget.heightSpan ||
      resizeHandle != oldWidget.resizeHandle ||
      wrapHeader != oldWidget.wrapHeader ||
      onResize != oldWidget.onResize ||
      onHide != oldWidget.onHide;
}
