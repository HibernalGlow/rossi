import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/method/reader_gesture_logic.dart';

/// 触屏在阅读器顶部/底部有稳定的控制栏入口，复用现有感应带高度。
/// 不依赖鼠标悬停开关；仅在阅读器赢得单击后消费，不抢滑动、长按或视频按钮。
bool isReaderTouchControlsEdge(ReaderTapSample tap, ReadSettingState setting) {
  final size = tap.viewportSize;
  final point = tap.localPosition;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.isEmpty ||
      !point.dx.isFinite ||
      !point.dy.isFinite ||
      point.dx < 0 ||
      point.dx > size.width ||
      point.dy < 0 ||
      point.dy > size.height) {
    return false;
  }
  // 极矮泳道仍留出中央操作区，不能让感应带覆盖整块阅读面。
  final top = setting.hoverTriggerAreaTop
      .toDouble()
      .clamp(8.0, 150.0)
      .clamp(0.0, size.height / 3);
  final bottom = setting.hoverTriggerAreaBottom
      .toDouble()
      .clamp(8.0, 150.0)
      .clamp(0.0, size.height / 3);
  return point.dy <= top || point.dy >= size.height - bottom;
}
