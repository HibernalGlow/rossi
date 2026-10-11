import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

/// pointerSignalResolver 只仲裁信号消费，InteractiveViewer 的直接变换也需撤回。
/// 记录跟随事件生命周期，不重发输入，也不替代绑定解析。
abstract final class BindingPointerSignalGuard {
  static final _rejected = Expando<List<VoidCallback>>();

  // 每层命中变换会产生不同事件实例，归属以平台原始事件为准。
  static PointerEvent _original(PointerEvent event) => event.original ?? event;

  static void reject(PointerSignalEvent event) =>
      _rejected[_original(event)] = [];
  static bool isRejected(PointerSignalEvent event) =>
      _rejected[_original(event)] != null;

  static void afterRejected(PointerSignalEvent event, VoidCallback restore) {
    _rejected[_original(event)]?.add(restore);
  }

  static void finishRejected(PointerSignalEvent event) {
    for (final restore in _rejected[_original(event)] ?? <VoidCallback>[]) {
      restore();
    }
    _rejected[_original(event)] = null;
  }
}
