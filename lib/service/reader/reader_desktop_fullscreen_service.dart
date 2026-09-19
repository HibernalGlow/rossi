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
/// 除了「现在是不是全屏」，这里还记**这次全屏是不是应用自己借的**
/// （[appRequestedFullscreen]）—— 因为「退出阅读器时要不要把窗口退出全屏」
/// 问的不是「窗口现在全屏吗」，而是「这次全屏是我借的吗」。两者混为一谈就是
/// 「点开始阅读把用户的软件全屏退掉」那个 bug。
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

  /// **应用自己借的那次全屏**（用户按 ⌃⌘F / 视图菜单进来的不算）。
  ///
  /// 这是 [releaseRequestedFullscreen] 的唯一判据，也是「阅读器退出时要不要
  /// 把窗口退出全屏」的答案 —— 借用才要还，白得的东西不能替用户还回去。
  ///
  /// 曾经的错账：阅读器拿「窗口现在是不是全屏」（`isFullScreen()`）当自己的账，
  /// 于是在**用户自己全屏**的窗口里开了阅读器、又换了一本（阅读器换实例）时，
  /// 旧实例的 `dispose` 会一本正经地 `setFullScreen(false)` —— 现象就是
  /// 「点了开始阅读，整个软件的全屏被退掉了」。
  bool get appRequestedFullscreen => _appRequestedFullscreen;
  bool _appRequestedFullscreen = false;

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
  ///
  /// 这是**应用主动借**全屏的唯一入口，所以只有它动 [appRequestedFullscreen]。
  Future<void> setFullscreen(bool value) async {
    if (!_isDesktopPlatform) return;
    _appRequestedFullscreen = value;
    _setFullscreen(value);
    await windowManager.setFullScreen(value);
    unawaited(_reconcile(value));
  }

  /// 退出阅读器时的收尾：**只还自己借的那次全屏**。
  ///
  /// 用户自己按 ⌃⌘F 进来的全屏不属于应用借的，这里一个字都不做 —— 连
  /// [fullscreenNotifier] 都别碰：窗口的全屏事件才是那本账的权威输入，
  /// 阅读器在 `dispose` 时把它按成 `false` 会造出「窗口还全屏着、外壳却把
  /// 自制标题栏挂回来」的第二本错账。
  Future<void> releaseRequestedFullscreen() async {
    if (!_appRequestedFullscreen) return;
    await setFullscreen(false);
  }

  /// 仅同步全局通知状态，不调用窗口 API（用于初始化时与窗口实际状态对齐）。
  ///
  /// **不代表认领全屏**：它只是「读窗口一眼，把通知状态对齐」，用户借的还是
  /// 用户借的（见 [appRequestedFullscreen]）。阅读器 bootstrap 时就是走它。
  void syncFullscreen(bool value) => _setFullscreen(value);

  /// 窗口自己进入了全屏。**权威输入。**
  ///
  /// 窗口自己报的事件一律算**用户/系统**的行为，所以顺手把「应用借的」清掉 ——
  /// 否则用户按 ⌃⌘F 进全屏之后，应用会以为这次全屏是自己借的，退出阅读器时
  /// 替他退掉。
  @override
  void onWindowEnterFullScreen() {
    _appRequestedFullscreen = false;
    _setFullscreen(true);
  }

  /// 窗口自己退出了全屏。**权威输入。**（同样不是应用借的。）
  @override
  void onWindowLeaveFullScreen() {
    _appRequestedFullscreen = false;
    _setFullscreen(false);
  }

  Future<void> _reconcile(bool requested) async {
    await Future<void>.delayed(_reconcileDelay);
    if (!_isDesktopPlatform) return;
    final actual = await windowManager.isFullScreen();
    _setFullscreen(actual);
    // 窗口没照办（没进 / 没退）⇒ 这次请求本来就没生效，没有「借出去的全屏」可还。
    _appRequestedFullscreen = requested && actual;
  }

  void _setFullscreen(bool value) {
    if (fullscreenNotifier.value == value) return;
    fullscreenNotifier.value = value;
  }
}
