// 来源：FlClash（https://github.com/chen08209/FlClash），GPL-3.0。
// 原文：`lib/common/shape.dart`，**只搬导航组件用到的那一截**（角标 / 全圆两种形状
// 与 `all()` / `of()` 两个构造器）。原文件里的 `AppInputBorder` 与
// `vertical()` / `top()` 是表单与卡片在用的，本仓没有对应的调用点，不搬。
//
// 为什么不复用本仓已有的 `themeRadius(context)`（`config/global/theme_shape.dart`）：
// 那个是**面板圆角**（用户可调的一档），而侧栏条目与 Dock 胶囊的圆角是组件自己的
// 形状语言（10 / 全圆），跟着面板圆角走会让侧栏在「大圆角主题」下变成一排水滴。
//
// 形状用 `RoundedSuperellipseBorder`（连续曲率的超椭圆）而不是
// `RoundedRectangleBorder`：这是原文的取法，也是 Dock 那颗 lens 圆得「像 iOS」
// 的来源。`Path.getOuterPath` 与 `copyWith(side:)` 都被组件用到。

import 'package:material_ui/material_ui.dart';

abstract final class AppCorner {
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double full = 1000;
}

abstract final class AppRadius {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(
    Radius.circular(AppCorner.xs),
  );
  static const BorderRadius sm = BorderRadius.all(
    Radius.circular(AppCorner.sm),
  );
  static const BorderRadius md = BorderRadius.all(
    Radius.circular(AppCorner.md),
  );
  static const BorderRadius lg = BorderRadius.all(
    Radius.circular(AppCorner.lg),
  );
  static const BorderRadius xl = BorderRadius.all(
    Radius.circular(AppCorner.xl),
  );
  static const BorderRadius xxl = BorderRadius.all(
    Radius.circular(AppCorner.xxl),
  );
  static const BorderRadius full = BorderRadius.all(
    Radius.circular(AppCorner.full),
  );

  static BorderRadius all(double corner) => BorderRadius.circular(corner);
}

abstract final class AppShape {
  static const RoundedSuperellipseBorder none = RoundedSuperellipseBorder();
  static const RoundedSuperellipseBorder xs = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xs,
  );
  static const RoundedSuperellipseBorder sm = RoundedSuperellipseBorder(
    borderRadius: AppRadius.sm,
  );
  static const RoundedSuperellipseBorder md = RoundedSuperellipseBorder(
    borderRadius: AppRadius.md,
  );
  static const RoundedSuperellipseBorder lg = RoundedSuperellipseBorder(
    borderRadius: AppRadius.lg,
  );
  static const RoundedSuperellipseBorder xl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xl,
  );
  static const RoundedSuperellipseBorder xxl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xxl,
  );
  static const RoundedSuperellipseBorder full = RoundedSuperellipseBorder(
    borderRadius: AppRadius.full,
  );

  static RoundedSuperellipseBorder all(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.all(corner));

  static RoundedSuperellipseBorder of(BorderRadius borderRadius) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius);
}
