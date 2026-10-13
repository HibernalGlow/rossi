import 'package:material_ui/material_ui.dart';

/// 由封面外层的悬浮操作给标题预留空间，不改变其他卡片的标题宽度。
class ComicCoverCaptionScope extends InheritedWidget {
  const ComicCoverCaptionScope({
    super.key,
    required this.trailingInset,
    required super.child,
  });
  final double trailingInset;

  static double trailingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComicCoverCaptionScope>()
          ?.trailingInset ??
      0;

  @override
  bool updateShouldNotify(ComicCoverCaptionScope oldWidget) =>
      trailingInset != oldWidget.trailingInset;
}
