import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_controller.dart';
import 'package:zephyr/page/comic_read/controller/reader_action_dispatcher.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';

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
    required bool rightToLeft,
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

    // **空间动作 × 阅读方向**（本仓 bug 的修复点，语义与 Rust 引擎
    // `operation_binding::resolve::resolve_page_turn` 同构）：
    //
    // 分区给出的「左/右半」先翻成**空间动作**（`reader.page-right` /
    // `reader.page-left`，绑哪侧由左右手模式决定），再由阅读方向解释成
    // 「下一页 / 上一页」。旧实现把「右半 = 下一页」写死，左开（readMode=2）
    // 下点右边仍翻下一页 —— 而左开的下一页在**左边**。
    //
    // - rightHand 预设：右半 = page-right、左半 = page-left；
    // - leftHand 预设：镜像（拇指在左的人前进热区也在左）；
    // - fullScreen 是**语义**动作（整屏 = 前进），不随方向翻。
    final tappedRightHalf = localPosition.dx >= (viewportSize.width / 2);
    final bool shouldNext;
    if (isWebtoon) {
      // 条漫是竖向连续滚动，没有「左右」可言：上下分档保持语义（上=回退）。
      shouldNext = _shouldNextForWebtoonTap(
        mode: mode,
        tapY: localPosition.dy,
        screenHeight: viewportSize.height,
      );
    } else {
      shouldNext = switch (mode) {
        ReaderTapPageTurnMode.fullScreen => true,
        ReaderTapPageTurnMode.rightHand => tappedRightHalf != rightToLeft,
        ReaderTapPageTurnMode.leftHand => tappedRightHalf == rightToLeft,
      };
    }

    return shouldNext ? ReaderTapZone.nextPage : ReaderTapZone.previousPage;
  }

  static void handleTap({
    required ReaderActionController actionController,
    required BuildContext context,
    required ReaderTapSample sample,
    required VoidCallback onToggleMenu,
    VoidCallback? onBeforePageTurn,
    ReaderActionDispatcher? dispatcher,
    String? bindingsArrayJson,
  }) {
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;

    // 绑定表在位（开关开 + 表能用）时，点击这一路只做「落在哪一格」的归一化，
    // **动作与方向都交给引擎**。表还没播种或被用户导坏时回落到下面那份改造前的硬编码
    // 分区 —— 回落到「什么都不做」等于把阅读器锁死，那不可接受。
    //
    // （判据宿主说明：这一句 `if` 也是 `flutter test` 里那组分区判据能继续跑的原因 ——
    // 测试用的设置没有播种过的空表，走旧路径；真机走新路径。两条路的几何同一个
    // `tapInputAreaFor` / `resolveTapZone`，判据覆盖的是几何而不是引擎。）
    if (dispatcher != null && bindingsArrayJson != null) {
      final area = tapInputAreaFor(
        sample: sample,
        isWebtoon: readSetting.readMode == 0,
        tapPageTurnInWebtoon: readSetting.tapPageTurnInWebtoon,
        mode: readSetting.tapPageTurnMode,
      );
      if (area == null) {
        // `fullScreen` 档：「整屏都是前进」在九宫格里没有对应的一格（最小的空间单位
        // 就是一格），所以它不查表，直接给**语义**动作；方向仍由引擎解释。
        dispatcher.dispatch(BindingAction.nextPage, fromKeyboard: false);
        return;
      }
      dispatcher.dispatchTapArea(area: area, bindingsArrayJson: bindingsArrayJson);
      return;
    }

    final zone = resolveTapZone(
      sample: sample,
      isWebtoon: readSetting.readMode == 0,
      tapPageTurnInWebtoon: readSetting.tapPageTurnInWebtoon,
      mode: readSetting.tapPageTurnMode,
      rightToLeft: readSetting.readMode == 2,
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

  /// 点击归一化成九宫格里的**哪一格**（绑定表在位时的那一份「分区」）。
  ///
  /// 与 [resolveTapZone] 的几何**完全一致**，只是把结论换成 descriptor：分区只回答
  /// 「这一下落在哪一格」，「那一格该干什么」由绑定表说，「往右翻是前进还是退回」
  /// 由引擎按阅读方向说。三者分开，才有「改绑定不重新编译即生效」。
  ///
  /// **纵向只使用中排三格**：改造前的分区就是「左半 / 正中 / 右半」三档（上下两排与
  /// 中排同动作），所以这里把落点按列归到 `middle-*`。九宫格其余六格是 schema 里的
  /// 合法值（导入的包能装下，见 `model.rs` 的往返判据），v0.1 的采集端不产出它们。
  ///
  /// 返回 `null` 只有一种情况：`fullScreen` 档下的非正中点击 —— 那一档说的是
  /// 「整屏都是前进」，而九宫格最小的空间单位就是一格，没有「整屏」这一档可绑。
  /// 调用方因此直接派发**语义**动作 `reader.next-page`（方向仍交给引擎解释）。
  static String? tapInputAreaFor({
    required ReaderTapSample sample,
    required bool isWebtoon,
    required bool tapPageTurnInWebtoon,
    required ReaderTapPageTurnMode mode,
  }) {
    final localPosition = sample.localPosition;
    final viewportSize = sample.viewportSize;

    // 以下三道早退与 `resolveTapZone` 逐条对应（条漫默认、退化视口、正中那一格），
    // 差别只是「返回哪一格」而不是「返回哪一档」。
    if (isWebtoon && !tapPageTurnInWebtoon) return TapArea.middleCenter;
    if (!viewportSize.isFinite || viewportSize.isEmpty) {
      return TapArea.middleCenter;
    }

    final thirdWidth = viewportSize.width / 3;
    final thirdHeight = viewportSize.height / 3;
    final inCenterControlArea =
        localPosition.dx >= thirdWidth &&
        localPosition.dx < thirdWidth * 2 &&
        localPosition.dy >= thirdHeight &&
        localPosition.dy < thirdHeight * 2;
    if (inCenterControlArea) return TapArea.middleCenter;

    if (mode == ReaderTapPageTurnMode.fullScreen) return null;

    if (isWebtoon) {
      // 条漫是竖向连续滚动，横向位置没有意义，所以取纵向两半。绑到哪一格不重要 ——
      // 重要的是左右手预设把 `page-right` 放在哪一格：右手档下半 → `middle-right`
      // 正好是前进，左手档上半 → `middle-left` 也是前进，与改造前逐格一致。
      return localPosition.dy < viewportSize.height / 2
          ? TapArea.middleLeft
          : TapArea.middleRight;
    }
    return localPosition.dx >= viewportSize.width / 2
        ? TapArea.middleRight
        : TapArea.middleLeft;
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

  /// 一条**空间翻页动作**在当前阅读方向下的语义（键盘与点击共用）。
  ///
  /// [isPageRight] 为真表示动作是 `reader.page-right`（画面往右翻）：
  /// 右开时它是「下一页」，左开时它是「上一页」。`reader.page-left` 恒相反。
  /// 与 Rust 引擎 `resolve_page_turn` 同构，判据两边都要打。
  static bool spatialPageTurnIsNext({
    required bool isPageRight,
    required bool rightToLeft,
  }) {
    return isPageRight != rightToLeft;
  }
}
