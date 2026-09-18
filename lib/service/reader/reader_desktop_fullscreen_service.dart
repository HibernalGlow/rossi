import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口全屏状态的**唯一记账处**（阅读器与整应用外壳共用）。
///
/// 记账有两路输入，缺一不可：
/// - **应用自己请求的切换**：阅读器里的全屏按钮 → [setFullscreen]；
/// - **窗口自己报的全屏事件**：⌃⌘F、视图菜单里的「进入全屏」、绿灯
///   → [onWindowEnterFullScreen] / [onWindowLeaveFullScreen]。
///
/// 只记第一路是不够的：用户用 ⌃⌘F（或菜单）进全屏时应用毫不知情，
/// 状态就停在 `false` —— 表现是「已经全屏了，顶上还压着一条自制标题栏」。
/// 所以第二路是**权威**的：它不是「我们调过什么」，而是「窗口真的变了」。
///
/// 只有 [fullscreenNotifier] 一个出口：订阅者（应用外壳的标题栏、阅读器
/// AppBar 上的图标）不该各自去问窗口，那会造出第二本账。
class ReaderDesktopFullscreenService with WindowListener {
  static final ReaderDesktopFullscreenService instance =
      ReaderDesktopFullscreenService._();

  ReaderDesktopFullscreenService._() {
    // **构造即登记**：本实例在 App 第一次 build（main.dart 的 MaterialApp
    // builder）时就被取到，早于任何一次全屏切换，也早于阅读器被打开 ——
    // 于是「没开阅读器时按 ⌃⌘F」也能抓到。
    if (_isDesktopPlatform) windowManager.addListener(this);
  }

  final ValueNotifier<bool> fullscreenNotifier = ValueNotifier(false);

  /// 过渡结束后的对账延迟。进出全屏带几百毫秒动画，动画期间 `styleMask`
  /// 可能还没翻，查早了会读到旧值。
  static const _reconcileDelay = Duration(milliseconds: 600);

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 查询当前窗口是否处于全屏状态（**窗口说了算**）。
  Future<bool> isFullscreen() async {
    if (!_isDesktopPlatform) return false;
    return windowManager.isFullScreen();
  }

  /// 请求切换窗口全屏状态。
  ///
  /// 先**乐观**更新：动画要几百毫秒，等它回来才动 UI 会顿一下。
  /// 再在过渡结束后**与窗口对账** —— 万一窗口没真的全屏（切换失败、
  /// 被系统拒），这里会把它改回去，免得留下「应用说全屏、窗口没全屏」
  /// 的错账（这次的 bug 就是错账造成的）。
  Future<void> setFullscreen(bool value) async {
    if (!_isDesktopPlatform) return;
    _setFullscreen(value);
    await windowManager.setFullScreen(value);
    unawaited(_reconcile());
  }

  /// 仅同步全局通知状态，不调用窗口 API（用于初始化时与窗口实际状态对齐）。
  void syncFullscreen(bool value) => _setFullscreen(value);

  /// 窗口自己进入了全屏。**权威输入。**
  @override
  void onWindowEnterFullScreen() => _setFullscreen(true);

  /// 窗口自己退出了全屏。**权威输入。**
  @override
  void onWindowLeaveFullScreen() => _setFullscreen(false);

  Future<void> _reconcile() async {
    await Future<void>.delayed(_reconcileDelay);
    if (!_isDesktopPlatform) return;
    _setFullscreen(await windowManager.isFullScreen());
  }

  void _setFullscreen(bool value) {
    if (fullscreenNotifier.value == value) return;
    fullscreenNotifier.value = value;
  }
}
