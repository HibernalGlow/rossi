import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';

/// 一次点击落在阅读区的哪一档。
///
/// [toggleMenu] 只说明「落点落在唤出上下栏的那一档」；**能不能真的唤出**由
/// [ReaderGestureLogic.handleTap] 按设置里的 `centerTapToggleBars` 决定
/// （这个开关可以让上下栏只由悬停/双击唤出，单击彻底不碰它）。
enum ReaderTapZone { previousPage, nextPage, toggleMenu }

/// 一次点击的**成对样本**：落点，加上**接收它的那个盒子**自己量出来的尺寸。
///
/// 两个量只有在配对时才有意义 —— 「落在哪一档」= 落点在这块面宽的哪个三分之一里，
/// 只知道其中一个算不出任何东西。所以这里做成一个不可变值对象，而不是让调用方
/// 各传各的：**拿错坐标系的那一半在签名层面就写不出来**。
///
/// 构造它的地方也必须是**唯一**能同时拿到这两样东西的地方：
/// `ReaderInputController` 里那个紧贴 `GestureDetector` 的 `LayoutBuilder`
/// （落点取它外面的 `onTapDown`、尺寸取它自己的 `constraints.biggest`）。
class ReaderTapSample {
  const ReaderTapSample({
    required this.localPosition,
    required this.viewportSize,
  });

  /// 相对**接收手势的那个盒子**的落点（`TapDownDetails.localPosition`）。
  final Offset localPosition;

  /// 那个盒子自己的尺寸（`LayoutBuilder` 的 `constraints.biggest`）。
  final Size viewportSize;
}

class ReaderGestureLogic {
  /// 把「按在阅读区里的哪一点」翻译成动作。
  ///
  /// [sample] 里的两个量**必须是同一个坐标系里的两个量**：落点相对接收手势的
  /// 那个盒子，尺寸取那个盒子自己量出来的大小。
  ///
  /// **不能**拿 `details.globalPosition`（**窗口**坐标）配 `MediaQuery.size`。
  /// 两个理由：
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
  ///
  /// 分区是**唯一**决定「这一次点击翻页还是唤出上下栏」的东西，而翻页会把上下栏
  /// 收起（`RowModeWidget` / `ColumnModeWidget` 翻页即 `updateMenuVisible(false)`）
  /// ⇒ 一旦它判错，用户就再也点不回上下栏。所以这里的错法都是「整串交互看起来
  /// 完全坏掉」，不是小偏差。
  static ReaderTapZone resolveTapZone({
    required ReaderTapSample sample,
    required bool isWebtoon,
    required bool tapPageTurnInWebtoon,
    required ReaderTapPageTurnMode mode,
  }) {
    final localPosition = sample.localPosition;
    final viewportSize = sample.viewportSize;

    // 竖向（条漫）模式下默认「点一下只是唤出上下栏」：条漫是连续滚动的，
    // 点击翻页会让读者丢掉阅读位置，所以它得单独打开。
    if (isWebtoon && !tapPageTurnInWebtoon) return ReaderTapZone.toggleMenu;

    // **视口尺寸退化时不许落到翻页分支**（0 / NaN / 无穷）。
    //
    // 分区全靠它算：`viewportSize` 是 0 时三个「三分之一」全是 0，
    // `inCenterControlArea` 成了 `dx >= 0 && dx < 0` —— 恒假；而「右半」成了
    // `dx >= 0` —— 恒真。于是**每一次点击都被判成「下一页」**，连「上一页」
    // 那一档也一起没了，症状与坐标错配一模一样（点哪儿都翻下一页、
    // 上下栏再也唤不出来）。实测过一次：早期版本把尺寸记在一个每次 build
    // 都刷新的字段里，与落点分属两次时机，就可能配出 0。
    //
    // 拿不准时选**可逆**的那一档：唤出上下栏只是让 chrome 出来，再点一下就回去；
    // 翻页会改阅读进度，还会把上下栏收起。
    if (!viewportSize.isFinite || viewportSize.isEmpty) {
      return ReaderTapZone.toggleMenu;
    }

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
    required ReaderTapSample sample,
    required VoidCallback onToggleMenu,
    VoidCallback? onBeforePageTurn,
  }) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final zone = resolveTapZone(
      sample: sample,
      isWebtoon: readSetting.readMode == 0,
      tapPageTurnInWebtoon: readSetting.tapPageTurnInWebtoon,
      mode: readSetting.tapPageTurnMode,
    );

    switch (zone) {
      // 「点击中间唤出/收起上下栏」是做成了开关的（设置 → 手势）。关掉后单击落到
      // 这一档时什么都不做。
      //
      // 这里只管**单击**：双击那条路（`doubleTapOpenMenu`）不走 `handleTap`，
      // 桌面端也还有边缘悬停 —— 所以关掉它不会把用户锁在一个唤不出上下栏的
      // 阅读器里（顶栏上还有返回键）。
      case ReaderTapZone.toggleMenu:
        if (readSetting.centerTapToggleBars) onToggleMenu();
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
