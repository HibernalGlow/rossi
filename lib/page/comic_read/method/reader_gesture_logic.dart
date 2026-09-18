import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';

/// 一次点击落在阅读区的哪一档。
enum ReaderTapZone { previousPage, nextPage, toggleMenu }

class ReaderGestureLogic {
  /// 把「按在阅读区里的哪一点」翻译成动作。
  ///
  /// **[localPosition] 与 [viewportSize] 必须是同一个坐标系里的两个量**：
  /// `localPosition` 取 `TapDownDetails.localPosition`（相对**接收手势的那个盒子**），
  /// `viewportSize` 取那个盒子自己量出来的尺寸（`LayoutBuilder` 的 `constraints.biggest`）。
  ///
  /// **不能**用 `details.globalPosition` 配 `MediaQuery.size`。两个理由：
  ///
  /// 1. 工作台把阅读器整页嵌进**泳道**时会改写 `MediaQuery.size` 成泳道尺寸
  ///    （见 `WorkspaceReaderHost`：阅读器的版式全按 `MediaQuery.size` 算，
  ///    必须给它一个「窗口就是泳道」的视口），而 `globalPosition` 仍然是**窗口**
  ///    坐标。于是分区整体平移了「泳道左边缘」那么多：阅读器泳道左边还压着一条
  ///    380 的泳道 ⇒ 窗口坐标里几乎每个点都落在「右半」「后两栏」，
  ///    表现为**点哪儿都翻下一页、中间那一档唤不出上下栏、左边点不出上一页**。
  /// 2. 即使不在泳道里（独立的全屏阅读器），`MediaQuery.size` 描述的是**窗口**
  ///    而不是「手指底下这块区域」（键盘弹起、`SafeArea` 内缩时两者并不相等）。
  ///    分区该按用户真正按着的那块面算。
  static ReaderTapZone resolveTapZone({
    required Offset localPosition,
    required Size viewportSize,
    required bool isWebtoon,
    required bool tapPageTurnInWebtoon,
    required ReaderTapPageTurnMode mode,
  }) {
    // 竖向（条漫）模式下默认「点一下只是唤出上下栏」：条漫是连续滚动的，
    // 点击翻页会让读者丢掉阅读位置，所以它得单独打开。
    if (isWebtoon && !tapPageTurnInWebtoon) return ReaderTapZone.toggleMenu;

    final thirdWidth = viewportSize.width / 3;
    final thirdHeight = viewportSize.height / 3;
    final inCenterControlArea =
        localPosition.dx >= thirdWidth &&
        localPosition.dx < thirdWidth * 2 &&
        localPosition.dy >= thirdHeight &&
        localPosition.dy < thirdHeight * 2;

    if (inCenterControlArea) return ReaderTapZone.toggleMenu;

    final shouldNext = isWebtoon
        ? _shouldNextForWebtoonTap(
            mode: mode,
            tapY: localPosition.dy,
            screenHeight: viewportSize.height,
          )
        : switch (mode) {
            ReaderTapPageTurnMode.fullScreen => true,
            ReaderTapPageTurnMode.leftHand =>
              localPosition.dx < (viewportSize.width / 2),
            ReaderTapPageTurnMode.rightHand =>
              localPosition.dx >= (viewportSize.width / 2),
          };

    return shouldNext ? ReaderTapZone.nextPage : ReaderTapZone.previousPage;
  }

  static void handleTap({
    required ReaderActionController actionController,
    required BuildContext context,
    required Offset localPosition,
    required Size viewportSize,
    required VoidCallback onToggleMenu,
    VoidCallback? onBeforePageTurn,
  }) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final zone = resolveTapZone(
      localPosition: localPosition,
      viewportSize: viewportSize,
      isWebtoon: readSetting.readMode == 0,
      tapPageTurnInWebtoon: readSetting.tapPageTurnInWebtoon,
      mode: readSetting.tapPageTurnMode,
    );

    switch (zone) {
      case ReaderTapZone.toggleMenu:
        onToggleMenu();
      case ReaderTapZone.nextPage:
        // 翻页前统一归位缩放（唤出上下栏不动视口）。
        onBeforePageTurn?.call();
        actionController.onPageActionNext();
      case ReaderTapZone.previousPage:
        onBeforePageTurn?.call();
        actionController.onPageActionPrev();
    }
  }

  static bool _shouldNextForWebtoonTap({
    required ReaderTapPageTurnMode mode,
    required double tapY,
    required double screenHeight,
  }) {
    return switch (mode) {
      ReaderTapPageTurnMode.fullScreen => true,
      ReaderTapPageTurnMode.leftHand => tapY < (screenHeight / 2),
      ReaderTapPageTurnMode.rightHand => tapY >= (screenHeight / 2),
    };
  }
}
