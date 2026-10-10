import 'package:flutter/widgets.dart';

import 'package:zephyr/service/notify/notify_gateway.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
// `export` 只把名字传给使用方，本文件自己的签名与默认值要用还得 import 一遍。
import 'package:zephyr/widgets/toast/toast_card.dart' show ToastType;

/// 类型从卡片模块导出，历史调用点（`ToastType.xxx`）无需改动。
export 'package:zephyr/widgets/toast/toast_card.dart' show ToastType;

/// 宿主控制器：给「手上已经有一条要按原样弹出来的提示」的调用点用
/// （以及测试里直接摸 Overlay 的用例）。
export 'package:zephyr/widgets/toast/toast_overlay.dart'
    show ToastOverlayController;

/// 应用内提示的统一入口。
///
/// 分成两层，别把它们混起来：
/// - **判定**在 `NotifyGateway`（能不能弹、同类压成一条，出口默认是提示条）——见
///   `lib/service/notify/notify_gateway.dart`；
/// - **外观**由「设置 → 提示样式」决定（`ToastSettingState` +
///   `resolveToastOverlaySpec`），位置、时长、宽度、透明度都在那儿。
///
/// 调用点只说「提示什么 / 什么类型 / 是哪一事项」。
///
/// 三百多处历史调用点走下面四个 `show*Toast`，它们登记为
/// [NotifyTopic.action]（操作反馈，永不被逐事项开关静音）。
/// **后台自己冒出来的**提示不要再用这四个函数，改用 [notifyAmbient] 并带上事项，
/// 否则它游离在个性化表外、用户关不掉。

void _submit({
  required NotifyTopic topic,
  required ToastType type,
  required String message,
  String? title,
  Duration? duration,
  BuildContext? context,
  bool userInitiated = false,
}) {
  NotifyGateway.instance.submit(
    NotifyEvent(
      topic: topic,
      type: type,
      title: title,
      message: message,
      duration: duration,
      context: context,
      userInitiated: userInitiated,
    ),
  );
}

/// 后台自动提示：必须登记事项，逐事项开关才管得到它。
///
/// [userInitiated] 留给「同一件事既可能由定时器触发、也可能由用户点按钮触发」
/// 的调用点（例如手动刷新追更）：置 `true` 时这一次不被总闸与逐事项开关静音
/// （同文本的合并窗口照旧要过 —— 连点两次不该出两条一样的提示）。
void notifyAmbient(
  NotifyTopic topic,
  String message, {
  ToastType type = ToastType.info,
  String? title,
  Duration? duration,
  BuildContext? context,
  bool userInitiated = false,
}) {
  _submit(
    topic: topic,
    type: type,
    title: title,
    message: message,
    duration: duration,
    context: context,
    userInitiated: userInitiated,
  );
}

void showInfoToast(
  String message, {
  String? title,
  Duration? duration,
  BuildContext? context,
}) {
  _submit(
    topic: NotifyTopic.action,
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
  _submit(
    topic: NotifyTopic.action,
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
  _submit(
    topic: NotifyTopic.action,
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
  _submit(
    topic: NotifyTopic.action,
    type: ToastType.error,
    title: title,
    message: message,
    duration: duration,
    context: context,
  );
}
