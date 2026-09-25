import 'dart:io';

import 'package:flutter/foundation.dart';

/// macOS 原生全屏时，系统那条自动隐藏的「菜单栏 + 红绿灯」所占的高度。
///
/// 与 `widgets/desktop/custom_title_bar.dart` 里自制标题栏写死的 40 同源：两条栏
/// 占的是同一条物理边，用两个数迟早对不上。取 40 而不是菜单栏自己的 ~24/37，
/// 是因为红绿灯在满屏下落在 y≈6..28 —— 只让出菜单栏那一截的话，顶栏第一行
/// 仍会被它压住半截。
const double kMacOsFullscreenChromeHeight = 40;

/// 「跑代码这台机器真的是 macOS」。
///
/// 单独暴露出来，是为了让 `reader_hover_reveal_layer.dart` 的 `ReaderHoverScope`
/// 能把这个值**注入**：判据要能在任何主机上跑同一份真值表，直接读 `Platform`
/// 的话，Linux / Windows 的开发机上那条断言只是恰好成立。
bool get isMacOSHost => !kIsWeb && Platform.isMacOS;

/// 「平台 + 窗口全屏」→ 阅读器顶部该让出多少像素。
///
/// 只有 macOS 原生全屏需要让：那边的菜单栏与红绿灯是**推到屏幕顶边**唤出的，
/// 与阅读器顶栏的唤出带撞在同一条物理边上（一条边、两个主人）。
/// Windows / Linux 全屏没有自动隐藏的窗口控制条，移动端的顶部内缩由顶栏自己的
/// `SafeArea` 管 —— 两头都是 0，而 0 就是改造前的行为，新增这一档不波及它们。
double resolveReaderTopChromeReserve({
  required bool isMacOS,
  required bool isOsFullscreen,
}) {
  if (!isMacOS || !isOsFullscreen) return 0;
  return kMacOsFullscreenChromeHeight;
}
