// 主题「形状」维度的载体：目前只有面板基准圆角。
//
// 为什么是**自建的 InheritedWidget**，而不是 Flutter 的 `ThemeExtension`：
// 本应用的主题栈是 `material_ui` 那套平行实现（它有自己的 `ThemeData` /
// `ColorScheme` / `ThemeExtension`），往任何一套上挂扩展都会在另一套里找不到，
// 桥接层（`MaterialUiCompatibilityBridge`）还得跟着改。`InheritedWidget` 与
// 两套主题实现都无关，且 `radiusOf` 会建立依赖 —— 换主题立刻重绘，
// 这正是全局常量给不了的。
//
// 消费方只有两类：**面板 / 卡片级的圆角**。组件自身的造型（44px 圆钮、贴边顶栏、
// 胶囊进度条）不该被主题拉走，那些调用点继续显式传 `radius:` / `borderRadius:`。

import 'package:flutter/widgets.dart';

/// 没有导入主题（或主题没给 `--radius`）时的面板基准圆角。
///
/// 这个值就是接主题圆角之前 `LiquidGlassSurface` 的默认值，保持既有观感不漂移。
const double kDefaultPanelRadius = 16;

/// 把主题的形状参数带进 widget 树，挂在 `MaterialApp.builder` 的最外层。
@immutable
class ThemeShapeScope extends InheritedWidget {
  const ThemeShapeScope({
    super.key,
    required this.radius,
    required super.child,
  });

  /// 面板基准圆角（px）。
  final double radius;

  static ThemeShapeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeShapeScope>();

  @override
  bool updateShouldNotify(covariant ThemeShapeScope oldWidget) =>
      oldWidget.radius != radius;
}

/// 当前主题的面板基准圆角。
///
/// 拿不到 scope（裸 widget 测试、或挂在 `MaterialApp.builder` 之外的浮层）时
/// 回落到 [fallback] —— 圆角这种事不该把调用方炸掉。
double themeRadius(
  BuildContext? context, {
  double fallback = kDefaultPanelRadius,
}) {
  if (context == null) return fallback;
  return ThemeShapeScope.maybeOf(context)?.radius ?? fallback;
}
