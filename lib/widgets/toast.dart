import 'package:flutter/widgets.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/widgets/toast/toast_card.dart';
import 'package:zephyr/widgets/toast/toast_overlay.dart';

/// 类型从卡片模块导出，历史调用点（`ToastType.xxx`）无需改动。
export 'package:zephyr/widgets/toast/toast_card.dart' show ToastType;

/// 宿主控制器：给「手上已经有一条 [ToastEvent]、要按事件里的类型原样弹出来」的
/// 调用点用（例如前台监听 `eventBus` 的那个页面）。
export 'package:zephyr/widgets/toast/toast_overlay.dart'
    show ToastOverlayController;

/// 应用内提示（toast）的统一入口。
///
/// 位置、时长、宽度、透明度等外观由「设置 → 提示样式」决定
/// （见 `ToastSettingState` 与 `resolveToastOverlaySpec`），
/// 调用点只说「提示什么 / 什么类型」即可。
///
/// 拿得到 `context` 就立刻弹；拿不到（后台任务、服务层）就发一条
/// [ToastEvent] 到 [eventBus]，由前台监听者补弹。
void _showToast({
  required ToastType type,
  required String message,
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  if (context != null && context.mounted) {
    ToastOverlayController.instance.show(
      context,
      type: type,
      message: message,
      title: title,
      duration: duration,
    );
    return;
  }

  eventBus.fire(
    ToastEvent(type: type, title: title, message: message, duration: duration),
  );
}

class ToastEvent {
  ToastType type;
  String? title;
  String message;

  /// `null` 表示「用设置里的时长」。
  Duration? duration;

  ToastEvent({
    required this.type,
    this.title,
    required this.message,
    this.duration,
  });
}

void showInfoToast(
  String message, {
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  _showToast(
    type: ToastType.info,
    title: title,
    message: message,
    duration: duration,
    context: context,
  );
}

void showSuccessToast(
  String message, {
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  _showToast(
    type: ToastType.success,
    title: title,
    message: message,
    duration: duration,
    context: context,
  );
}

void showWarningToast(
  String message, {
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  _showToast(
    type: ToastType.warning,
    title: title,
    message: message,
    duration: duration,
    context: context,
  );
}

void showErrorToast(
  String message, {
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  _showToast(
    type: ToastType.error,
    title: title,
    message: message,
    duration: duration,
    context: context,
  );
}
