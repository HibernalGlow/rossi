import 'package:flutter/services.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';

/// 全局按键处理函数
/// 返回 true 表示：事件已处理，不要再发给 ListView 了（彻底屏蔽默认行为）
/// 返回 false 表示：我不关心这个键，继续往下传
///
/// **这是绑定表不可用时的回退路径**（开关关着 / 出厂表还没播种 / 用户导坏了）。
/// 表在位时按键判断全在 Rust 引擎（`rossi_local_core::operation_binding`），
/// 这里的一份名单不参与 —— 否则「删掉一条绑定它还在生效」（见
/// `ReaderInputController.handleKeyEvent`）。留着它的理由是：阅读器不能因为
/// 一张坏表而失灵，而改造前的这套判断已被验证过。
///
/// 左右方向键绑的是**空间动作**（`reader.page-right` / `reader.page-left`）：
/// 「右 = 下一页」不再写死 —— 左开（readMode=2）下按右键是**往右翻 = 上一页**，
/// 与九宫格点击分区共用同一条方向解析
/// （`ReaderActionController.onSpatialPageRight/Left`）。上下键与 WASD 的
/// 竖向键保持**语义动作**（任何方向下「下 = 前进」）。
bool handleGlobalKeyEvent(
  KeyEvent event,
  ReaderActionController actionController,
) {
  // 只响应按下瞬间 (KeyDown) 和 长按重复 (KeyRepeat)
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

  final key = event.logicalKey;

  // 1. 「向下/下一步」—— 语义动作：不论方向，就是前进。
  final isNext =
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.numpad2 || // 小键盘 2
      key == LogicalKeyboardKey.keyS;

  // 2. 「向上/上一步」—— 语义动作。
  final isPrev =
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.numpad8 || // 小键盘 8
      key == LogicalKeyboardKey.keyW;

  // 3. 左右方向键 —— 空间动作：方向在 ReaderActionController 里解析。
  final isSpatialRight =
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.numpad6 || // 小键盘 6
      key == LogicalKeyboardKey.keyD;
  final isSpatialLeft =
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.numpad4 || // 小键盘 4
      key == LogicalKeyboardKey.keyA;

  if (isNext) {
    actionController.onKeyScrollNext();
    return true; // 拦截！ListView 也就是这一刻收不到事件了，也就不会跳页了
  }

  if (isPrev) {
    actionController.onKeyScrollPrev();
    return true; // 拦截！
  }

  if (isSpatialRight) {
    actionController.onSpatialPageRight();
    return true;
  }

  if (isSpatialLeft) {
    actionController.onSpatialPageLeft();
    return true;
  }

  return false; // 其他键（比如音量键）放行
}
