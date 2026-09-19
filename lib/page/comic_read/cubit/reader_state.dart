import 'package:freezed_annotation/freezed_annotation.dart';

part 'reader_state.freezed.dart';

@freezed
abstract class ReaderState with _$ReaderState {
  const ReaderState._();

  const factory ReaderState({
    @Default(0) int currentSlot, // 当前全局槽位
    @Default(0) int totalSlots, // 总页数/槽位数
    @Default(true) bool isMenuVisible, // 菜单显隐
    @Default(0.0) double sliderValue, // 滑块进度
    @Default(false) bool isSliderRolling, // 是否正在拖动滑块
    @Default(false) bool isComicRolling, // 漫画本身是否在滚动
    @Default(false) bool isTopHovered, // 顶栏是否悬停唤出
    @Default(false) bool isBottomHovered, // 底栏是否悬停唤出
  }) = _ReaderState;

  /// 顶栏要不要画出来。`pinned`（用户按了钉住）排在最前：钉住之后，点中间收起
  /// 菜单、指针离开边缘都收不走它 —— 口径照 neo 的 `readerEdgeInteraction`
  /// （`locked-open || pinned ⇒ fixed-open`，且 `requestOpen` 对钉住的边是 no-op）。
  bool showTopAppBar({required bool pinned}) =>
      pinned || isMenuVisible || isTopHovered;

  bool showBottomBar({required bool pinned}) =>
      pinned || isMenuVisible || isBottomHovered;
}
