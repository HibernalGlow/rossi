import 'package:flutter/widgets.dart';

/// 供泳道阅读器感知并控制「铺满窗口全屏」的 Scope。
///
/// 当阅读器在工作台泳道中运行时，点击全屏按钮或按 F11 快捷键不触发 App 的操作系统全屏，
/// 而是通过本 Scope 通知工作台让阅读器自身铺满窗口（在 Solo 聚焦基础上去掉顶栏）。
class ReaderFullscreenScope extends InheritedWidget {
  const ReaderFullscreenScope({
    super.key,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required super.child,
  });

  /// 当前是否处于铺满窗口全屏状态。
  final bool isFullscreen;

  /// 切换铺满窗口全屏的回调。
  final VoidCallback onToggleFullscreen;

  static ReaderFullscreenScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ReaderFullscreenScope>();
  }

  @override
  bool updateShouldNotify(ReaderFullscreenScope oldWidget) {
    return isFullscreen != oldWidget.isFullscreen ||
        onToggleFullscreen != oldWidget.onToggleFullscreen;
  }
}
