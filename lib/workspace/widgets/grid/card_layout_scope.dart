import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

/// 面板内已隐藏卡片的简要信息（供无顶栏面板在卡片菜单中直接恢复）。
typedef HiddenCardEntry = ({String id, String title, Glyph icon});

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
    this.onToggleEditing,
    this.hiddenCards = const <HiddenCardEntry>[],
    this.onRestoreCard,
    this.fillRemainingHeight = false,
    this.onFillRemainingHeight,
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

  /// 切换所属面板的「自定义布局 / 完成布局」编辑状态（供右键菜单或更多菜单调用）。
  final VoidCallback? onToggleEditing;

  /// 当前面板中被收起的卡片清单与恢复回调。
  final List<HiddenCardEntry> hiddenCards;
  final ValueChanged<String>? onRestoreCard;

  /// 当前卡片是否正处于「全宽并自动撑满面板剩余可视高度」状态。
  final bool fillRemainingHeight;

  /// 恢复为「全宽并自动撑满剩余可视高度」（或恢复紧凑默认高度）的回调。
  final VoidCallback? onFillRemainingHeight;

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
      onHide != oldWidget.onHide ||
      onToggleEditing != oldWidget.onToggleEditing ||
      hiddenCards != oldWidget.hiddenCards ||
      onRestoreCard != oldWidget.onRestoreCard ||
      fillRemainingHeight != oldWidget.fillRemainingHeight ||
      onFillRemainingHeight != oldWidget.onFillRemainingHeight;
}
