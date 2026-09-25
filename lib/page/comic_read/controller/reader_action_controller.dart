import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/service/reader/switch_toast_service.dart';

class ReaderActionController {
  static const int _webtoonTapScrollPercent = 70;

  final BuildContext context;
  final ScrollController scrollController;
  final PageController pageController;
  final bool Function(bool isNext)? onBeforeTurnPage;

  /// 用户是否正在触摸拖拽/惯性滚动列表（由列表侧的滚动通知维护）。
  final bool Function()? isUserScrolling;

  /// 横翻模式下「当前 loaded 范围到尽头后，是否还有下一话可以续」；
  /// 由宿主在构造时传入，用于在最后一页再次向前翻页时给出边界提示。
  /// 未提供时视为「可继续」，退化为改造前的静默行为。
  final bool Function()? canAdvanceNext;

  ReaderActionController({
    required this.context,
    required this.scrollController,
    required this.pageController,
    this.onBeforeTurnPage,
    this.isUserScrolling,
    this.canAdvanceNext,
  });

  ReadSettingState get _readSetting =>
      context.read<GlobalSettingCubit>().state.readSetting;

  int get _readMode => _readSetting.readMode;

  int get _currentSlot => context.read<ReaderCubit>().state.currentSlot;

  int get _totalSlots => context.read<ReaderCubit>().state.totalSlots;

  bool get _noAnimation => _readSetting.noAnimation;

  int get _autoScrollColumnDistancePercent =>
      _readSetting.autoScrollColumnDistancePercent;

  bool get _autoScrollSmooth => _readSetting.autoScrollSmooth;

  int get _autoScrollColumnIntervalMs =>
      _readSetting.autoScrollColumnIntervalMs;

  bool get _volumeKeyPageTurnEnabled => _readSetting.volumeKeyPageTurn;

  int get _volumeKeyPageTurnDistancePercent =>
      _readSetting.volumeKeyPageTurnDistancePercent;

  BuildContext get _activeContext => context;

  // ================= 1. 键盘专用逻辑 (桌面体验) =================
  // 特点：竖向模式下是“微调/平滑滚动”，模拟滚轮效果

  void onKeyScrollNext() {
    final mode = _readMode;
    if (mode == 0) {
      // 竖向：只滚 200px (平滑小步)
      _scrollVertical(offset: 200.0, durationMs: 100);
    } else {
      // 横向：翻下一页
      _turnPage(isNext: true);
    }
  }

  void onKeyScrollPrev() {
    final mode = _readMode;
    if (mode == 0) {
      // 竖向：回滚 200px
      _scrollVertical(offset: -200.0, durationMs: 100);
    } else {
      // 横向：翻上一页
      _turnPage(isNext: false);
    }
  }

  // ================= 1.5 空间翻页动作（左右键 / 九宫格点击共用） =================
  //
  // `reader.page-right` / `reader.page-left`：说的是「画面往哪边翻」，
  // 是不是前进由阅读方向决定（左开 readMode=2 时向右是退回）。
  // 语义与 Rust 引擎 `operation_binding::resolve::resolve_page_turn` 同构；
  // 条漫（readMode=0，竖向）没有左右，退化为语义动作（与改造前一致）。

  /// 画面往右翻（右开=下一页，左开=上一页，条漫=下一页）。
  void onSpatialPageRight() => _turnSpatial(isPageRight: true);

  /// 画面往左翻（右开=上一页，左开=下一页，条漫=上一页）。
  void onSpatialPageLeft() => _turnSpatial(isPageRight: false);

  void _turnSpatial({required bool isPageRight}) {
    final mode = _readMode;
    if (mode == 0) {
      isNextPageTurn(isPageRight: isPageRight, rightToLeft: false)
          ? onPageActionNext()
          : onPageActionPrev();
      return;
    }
    _turnPage(
      isNext: isNextPageTurn(isPageRight: isPageRight, rightToLeft: mode == 2),
    );
  }

  static bool isNextPageTurn({
    required bool isPageRight,
    required bool rightToLeft,
  }) {
    return isPageRight != rightToLeft;
  }

  // ================= 1.6 首尾页（绑定表里的 `reader.first-page` / `last-page`） =================

  void onGoToFirstPage() => _goToEnd(next: false);

  void onGoToLastPage() => _goToEnd(next: true);

  /// 条漫（竖向）与横翻的「第几页」根本不是同一个载体：前者是 `ScrollController`
  /// 的滚动极值，后者是 `PageController` 的槽位。所以两边各跳各的，不存在一份
  /// 「通用实现」能把两种版式都盖住。
  void _goToEnd({required bool next}) {
    if (_readMode == 0) {
      if (!scrollController.hasClients) return;
      final position = scrollController.position;
      scrollController.jumpTo(
        next ? position.maxScrollExtent : position.minScrollExtent,
      );
      return;
    }
    final totalSlots = _totalSlots;
    if (totalSlots <= 0 || !pageController.hasClients) return;
    pageController.jumpToPage(next ? totalSlots - 1 : 0);
  }

  // ================= 2. 音量键/点击专用逻辑 (手机体验) =================
  // 特点：竖向模式下按固定比例滚动，避免依赖漫画项分页定位。

  void onPageActionNext() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(percent: _webtoonTapScrollPercent, next: true);
    } else {
      _turnPage(isNext: true);
    }
  }

  void onPageActionPrev() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(percent: _webtoonTapScrollPercent, next: false);
    } else {
      _turnPage(isNext: false);
    }
  }

  void onVolumeActionNext() {
    if (!_volumeKeyPageTurnEnabled) return;
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(
        percent: _volumeKeyPageTurnDistancePercent,
        next: true,
      );
    } else {
      _turnPage(isNext: true);
    }
  }

  void onVolumeActionPrev() {
    if (!_volumeKeyPageTurnEnabled) return;
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(
        percent: _volumeKeyPageTurnDistancePercent,
        next: false,
      );
    } else {
      _turnPage(isNext: false);
    }
  }

  void onAutoReadTick({double? deltaMs}) {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalAuto(deltaMs: deltaMs);
    } else {
      _turnPage(isNext: true);
    }
  }

  // ================= 内部实现 =================

  void _scrollVertical({double offset = 0, int durationMs = 0}) {
    if (!scrollController.hasClients) return;

    final double currentOffset = scrollController.offset;
    final double targetOffset = currentOffset + offset;
    final clampedOffset = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );

    if (_noAnimation) {
      scrollController.jumpTo(clampedOffset);
    } else {
      scrollController.animateTo(
        clampedOffset,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeOutQuad,
      );
    }
  }

  void _scrollVerticalAuto({double? deltaMs}) {
    if (!scrollController.hasClients) return;

    // 用户触摸拖拽/惯性滚动期间让位，避免自动滚动与手势打架。
    if (isUserScrolling?.call() ?? false) return;

    final viewportHeight = MediaQuery.of(_activeContext).size.height;
    final distancePercent = _autoScrollColumnDistancePercent.clamp(10, 100);
    final stepDistance = viewportHeight * (distancePercent / 100);

    // 平滑模式：速度 = 步距/间隔，按真实帧间隔位移（与 vsync 对齐）。
    if (_autoScrollSmooth && deltaMs != null && deltaMs > 0) {
      final intervalMs = _autoScrollColumnIntervalMs.clamp(300, 5000);
      final delta = stepDistance * (deltaMs / intervalMs);
      final position = scrollController.position;
      final clamped = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (clamped == position.pixels) return;
      position.jumpTo(clamped);
      return;
    }

    final targetOffset = scrollController.offset + stepDistance;
    final clamped = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );

    if (_noAnimation) {
      scrollController.jumpTo(clamped);
    } else {
      scrollController.animateTo(
        clamped,
        duration: kReaderSmoothScrollDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollVerticalByPercent({required int percent, required bool next}) {
    if (!scrollController.hasClients) return;

    // 使用当前应用窗口的高度，不取屏幕尺寸或宽高中的较大值。
    final windowHeight = MediaQuery.sizeOf(_activeContext).height;
    final distancePercent = percent.clamp(10, 100);
    final direction = next ? 1.0 : -1.0;
    final targetOffset =
        scrollController.offset +
        windowHeight * (distancePercent / 100) * direction;
    final clamped = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );

    if (_noAnimation) {
      scrollController.jumpTo(clamped);
    } else {
      scrollController.animateTo(
        clamped,
        duration: kReaderSmoothScrollDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _turnPage({required bool isNext}) {
    if (onBeforeTurnPage?.call(isNext) ?? false) return;
    if (!pageController.hasClients) return;

    // 已在最后一页、也没有下一话可续时，不再静默吞掉前进：
    // 受 enableBoundaryToast 控制的「已是最后一页」提示走 SwitchToastService。
    if (isNext) {
      final total = _totalSlots;
      final current = _currentSlot;
      if (total > 0 &&
          current >= total - 1 &&
          !(canAdvanceNext?.call() ?? true)) {
        SwitchToastService.instance.notifyLastPage();
        return;
      }
    }

    final shouldGoForward = isNext;
    final noAnimation = _noAnimation;

    if (noAnimation) {
      final totalSlots = _totalSlots;
      if (totalSlots <= 0) return;

      final currentSlot = _currentSlot;
      final targetSlot = (currentSlot + (shouldGoForward ? 1 : -1)).clamp(
        0,
        totalSlots - 1,
      );
      pageController.jumpToPage(targetSlot);
      return;
    }

    if (shouldGoForward) {
      pageController.nextPage(
        duration: kReaderAnimationDuration,
        curve: Curves.easeInOut,
      );
    } else {
      pageController.previousPage(
        duration: kReaderAnimationDuration,
        curve: Curves.easeInOut,
      );
    }
  }
}
