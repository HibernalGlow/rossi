// 「黄黑溢出斜纹」（RIGHT/BOTTOM OVERFLOWED BY N PIXELS 那条）总开关的落点。
//
// 条纹不是我们画的，是 Flutter 画的：`DebugOverflowIndicatorMixin.paintOverflowIndicator()`
// 被 `RenderFlex.paint` 在 **assert 块里**调用（`rendering/flex.dart`），
// 而框架**没有提供任何全局开关** —— 3.47.3 实测：`lib/src/rendering/` 下除了那个 mixin
// 自己，没有任何 overflowIndicator 相关的可读可写标志位。所以「随时关掉」这件事
// 只可能拦以下两处，各拦一半：
//
// 1. **我们自己造的 Flex**（见 `quiet_flex.dart`）：覆写 `paintOverflowIndicator`，
//    关掉时直接 return —— 条纹与 `_reportOverflow` 的溢出上报一起省掉；
// 2. **错误上报本身**（这一条是**全局**的，Flutter 自带控件也拦得住）：
//    `FlutterError.onError` 的入口用 [shouldReportFlutterError] 把溢出类错误整条丢掉，
//    控制台 / 日志不再刷屏。但 Flutter 自己那些 Row（ListTile、AppBar…）的**条纹**
//    仍然会画 —— 那一半没有 Dart 侧的抓手。
//
// 想让任何控件都不画条纹，只剩编译期一条路：跑 profile / release（assert 关闭 ⇒
// 那段绘制根本不执行）。

import 'package:flutter/foundation.dart';

/// 是否绘制「黄黑溢出斜纹」。默认 true ＝ 与 Flutter 原生行为一致
/// （改造前的行为，关掉才是主动选择）。
///
/// 与 `blockRustHttpRequests` 同款：唯一入口是设置页，改设置时**同时**写这里与落盘，
/// 免得绘制路径为了一个 bool 去查数据库。
bool layoutOverflowStripesEnabled = true;

/// 与设置项同一入口的写方法。
void setLayoutOverflowStripesEnabled({required bool enabled}) {
  layoutOverflowStripesEnabled = enabled;
}

/// 这条错误是不是「布局溢出」。
///
/// 认的是框架自己那句话：`A RenderFlex overflowed by 12 pixels on the right.`
/// （见 `DebugOverflowIndicatorMixin._reportOverflow`）。`RenderConstraintsTransformBox`
/// 走同一个 mixin，文案同形，所以一起命中。
///
/// 刻意收得这么窄：只看 `overflowed` 一个词的话，我们自己手写的、带这个词的
/// FlutterError 也会被静音 —— 那是「关掉一个提示」，不是「关掉错误上报」。
bool isLayoutOverflowReport(FlutterErrorDetails details) {
  final exception = details.exception;
  if (exception is! FlutterError) {
    return false;
  }
  final message = exception.message;
  return message.contains('overflowed by') && message.contains('pixels');
}

/// `FlutterError.onError` 的入口滤网：开关关掉时把**溢出类**错误整条丢掉。
///
/// 其余错误一律原样放行 —— 这个开关只管条纹，不是「关闭错误上报」。
bool shouldReportFlutterError(FlutterErrorDetails details) {
  if (layoutOverflowStripesEnabled) {
    return true;
  }
  return !isLayoutOverflowReport(details);
}
