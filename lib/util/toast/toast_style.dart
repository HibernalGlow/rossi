// 提示条（toast）的样式解析：用户设置 → 可直接渲染的样式规格。
//
// 这里刻意只做**纯逻辑**（位置映射 + 上下界钳制 + 常驻/关闭按钮的兜底语义），
// 不引用任何 widget，于是判据可以在 `flutter test` 里直接断言，
// 不需要把界面跑起来（本机 `flutter test` 还要先解沙箱代理，能省一次是一次）。

import 'package:flutter/widgets.dart';
import 'package:zephyr/config/global/global_setting.dart';

/// 各字段的合法区间。
///
/// 设置可能来自「云端同步覆盖」或旧版本写入，所以**读的时候一律再夹一次**，
/// 不能假定它一定落在滑块范围内。
abstract final class ToastStyleLimits {
  static const int minEdgePadding = 0;
  static const int maxEdgePadding = 64;
  static const int minDurationMs = 0; // 0 = 常驻
  static const int maxDurationMs = 20000;
  static const int minWidth = 220;
  static const int maxWidth = 720;
  static const int minOpacityPercent = 30;
  static const int maxOpacityPercent = 100;
  static const int minVisible = 1;
  static const int maxVisible = 8;
  static const int minAnimationMs = 0;
  static const int maxAnimationMs = 800;
}

/// 一条提示条的渲染规格。
@immutable
class ToastOverlaySpec {
  const ToastOverlaySpec({
    required this.alignment,
    required this.edgePadding,
    required this.duration,
    required this.maxWidth,
    required this.opacity,
    required this.maxVisible,
    required this.animationDuration,
    required this.liquidGlass,
    required this.showProgressBar,
    required this.showIcon,
    required this.showClose,
  });

  /// 停靠对齐（九宫格之一）。
  final Alignment alignment;

  /// 距屏幕边缘的安全留白。
  final double edgePadding;

  /// 自动关闭时长；`Duration.zero` 表示常驻。
  final Duration duration;

  /// 卡片最大宽度。
  final double maxWidth;

  /// 整卡不透明度（0~1）。
  final double opacity;

  /// 同屏最多堆叠条数。
  final int maxVisible;

  /// 进出场动画时长。
  final Duration animationDuration;

  /// 液态玻璃背景。
  final bool liquidGlass;

  final bool showProgressBar;
  final bool showIcon;

  /// 关闭按钮是否可见（常驻提示恒为 true，否则用户关不掉）。
  final bool showClose;

  /// 常驻：不自动关闭。
  bool get permanent => duration == Duration.zero;

  /// 是否画倒计时进度条（常驻没有倒计时可言）。
  bool get showsCountdown => showProgressBar && !permanent;

  /// 调用点显式指定时长时的覆盖（其它字段保持不变）。
  ///
  /// 覆盖成常驻时，关闭按钮必须补上，否则这条提示关不掉。
  ToastOverlaySpec withDuration(Duration value) {
    return ToastOverlaySpec(
      alignment: alignment,
      edgePadding: edgePadding,
      duration: value,
      maxWidth: maxWidth,
      opacity: opacity,
      maxVisible: maxVisible,
      animationDuration: animationDuration,
      liquidGlass: liquidGlass,
      showProgressBar: showProgressBar,
      showIcon: showIcon,
      showClose: showClose || value == Duration.zero,
    );
  }
}

/// 九宫格位置 → Flutter 对齐。
///
/// 注意 `Alignment` 的 y 轴向下为正，所以 `topLeft` 是 `(-1, -1)`。
Alignment toastAlignmentOf(ToastPosition position) {
  switch (position) {
    case ToastPosition.topLeft:
      return Alignment.topLeft;
    case ToastPosition.topCenter:
      return Alignment.topCenter;
    case ToastPosition.topRight:
      return Alignment.topRight;
    case ToastPosition.middleLeft:
      return Alignment.centerLeft;
    case ToastPosition.center:
      return Alignment.center;
    case ToastPosition.middleRight:
      return Alignment.centerRight;
    case ToastPosition.bottomLeft:
      return Alignment.bottomLeft;
    case ToastPosition.bottomCenter:
      return Alignment.bottomCenter;
    case ToastPosition.bottomRight:
      return Alignment.bottomRight;
  }
}

/// 把用户设置解析成渲染规格。
ToastOverlaySpec resolveToastOverlaySpec(ToastSettingState setting) {
  final durationMs = _clampInt(
    setting.durationMs,
    ToastStyleLimits.minDurationMs,
    ToastStyleLimits.maxDurationMs,
  );
  final permanent = durationMs == 0;

  return ToastOverlaySpec(
    alignment: toastAlignmentOf(setting.position),
    edgePadding: _clampInt(
      setting.edgePadding,
      ToastStyleLimits.minEdgePadding,
      ToastStyleLimits.maxEdgePadding,
    ).toDouble(),
    duration: Duration(milliseconds: durationMs),
    maxWidth: _clampInt(
      setting.maxWidth,
      ToastStyleLimits.minWidth,
      ToastStyleLimits.maxWidth,
    ).toDouble(),
    opacity:
        _clampInt(
          setting.opacityPercent,
          ToastStyleLimits.minOpacityPercent,
          ToastStyleLimits.maxOpacityPercent,
        ) /
        100,
    maxVisible: _clampInt(
      setting.maxVisible,
      ToastStyleLimits.minVisible,
      ToastStyleLimits.maxVisible,
    ),
    animationDuration: Duration(
      milliseconds: _clampInt(
        setting.animationDurationMs,
        ToastStyleLimits.minAnimationMs,
        ToastStyleLimits.maxAnimationMs,
      ),
    ),
    liquidGlass: setting.liquidGlass,
    showProgressBar: setting.showProgressBar,
    showIcon: setting.showIcon,
    // 常驻提示没有自动关闭，关闭按钮必须留一条出路。
    showClose: permanent || setting.showCloseButton,
  );
}

int _clampInt(int value, int minimum, int maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}
