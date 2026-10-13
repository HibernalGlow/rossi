import 'package:flutter/foundation.dart';

/// 「这台设备有没有悬停指针」—— 工作台里所有 **hover 专属触发**的总闸。
///
/// 判据用 [TargetPlatform] 而不是 `dart:io` 的 `Platform`：测试里可以用
/// `debugDefaultTargetPlatformOverride` 把两种设备各跑一遍（`Platform` 改不动），
/// 且 web 走的是同一套 —— `defaultTargetPlatform` 在浏览器里按宿主系统给答案。
///
/// 这条判据刻意**不是**「名字里带不带 desk」：带触摸屏的 Windows 笔记本仍然有
/// 指针，那边该走 hover 那一支；手机上没有，`MouseRegion.onEnter/onHover`
/// 与滚轮事件**永远不触发**，凡是只有那两个入口的能力在那边就等于不存在。
enum WorkspacePointerMode {
  /// 有指针 ⇒ 悬停驻留（边缘揭示、泳道聚焦）与右键菜单都成立。
  hover,

  /// 只有触摸 ⇒ 上面那些一条都走不到，必须有等价的触摸入口才算做完。
  touchOnly;

  static WorkspacePointerMode forTargetPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => WorkspacePointerMode.hover,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => WorkspacePointerMode.touchOnly,
    };
  }
}

/// 当前设备有没有悬停指针。
bool get hasHoverPointer =>
    WorkspacePointerMode.forTargetPlatform(defaultTargetPlatform) ==
    WorkspacePointerMode.hover;
