import 'package:material_ui/material_ui.dart';

/// 详情页「阅读」入口的落点。
///
/// 用户 2026-09-19 报：「开始阅读按钮放在右下角，对桌面端不友好。」
enum ComicInfoReadEntryPlacement {
  /// 叠在页面右下角的悬浮按钮。
  ///
  /// 触摸端的唯一合理落点：拇指半径够得到，不占正文的行。
  floatingButton,

  /// 贴在操作行里、和「下载」并排的一张卡片。
  ///
  /// 桌面端默认。桌面没有拇指半径，右下角那颗悬浮按钮对鼠标来说反而又远又浮，
  /// 还会盖住正文最后一段；并排的卡片和旁边几个操作是同一套视觉，一眼就能找到。
  inlineCard,
}

/// 这个平台**有没有鼠标指针**。
///
/// 口径与 `WorkspaceTopChromeMode.forTargetPlatform` 一致：判据是「有没有指针」，
/// 不是「名字里带不带 desk」（带触摸屏的 Windows 笔记本仍然有指针）。
/// 用 `defaultTargetPlatform` 而不是 `dart:io` 的 `Platform`：测试里能用
/// `debugDefaultTargetPlatformOverride` 把两种平台都跑一遍，`Platform` 改不动。
bool comicInfoPlatformHasPointer(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => false,
};

/// 详情页的「阅读」入口落在哪儿。
///
/// 不变式：**任何时刻只有一个入口**。桌面上页内卡片顶掉悬浮按钮 —— 两个入口
/// 同时在场时，用户会以为它们是两件不同的事（一句「开始阅读」、一句「继续阅读」）。
ComicInfoReadEntryPlacement resolveComicInfoReadEntryPlacement({
  required TargetPlatform platform,
  required bool inlineReadEntryEnabled,
}) {
  if (!inlineReadEntryEnabled) {
    return ComicInfoReadEntryPlacement.floatingButton;
  }
  return comicInfoPlatformHasPointer(platform)
      ? ComicInfoReadEntryPlacement.inlineCard
      : ComicInfoReadEntryPlacement.floatingButton;
}
