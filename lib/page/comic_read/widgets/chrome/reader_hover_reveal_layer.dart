import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';

/// 悬停唤出控制器（参考 NeoView 风格）。
///
/// 采用「边缘触发带 + 悬浮控制栏本体」两段式防抖交互：
/// 1. 鼠标移入顶部/底部感应带，立即激活对应控制栏唤出；
/// 2. 控制栏滑出后，鼠标在控制栏本体上操作时保持常驻，不会被定时器收回；
/// 3. 鼠标离开感应带与控制栏本体后，等待设定的延时（默认 500ms）平滑收起；
/// 4. 处于手动呼出菜单（`isMenuVisible == true`）或滑块拖拽中（`isSliderRolling == true`）时锁定显示。
class ReaderHoverController {
  final BuildContext context;

  bool _isTopTriggerHovered = false;
  bool _isTopBarHovered = false;
  bool _isBottomTriggerHovered = false;
  bool _isBottomBarHovered = false;

  Timer? _topHideTimer;
  Timer? _bottomHideTimer;
  bool _isDisposed = false;

  ReaderHoverController(this.context);

  ReadSettingState get _readSetting =>
      context.read<GlobalSettingCubit>().state.readSetting;

  ReaderCubit get _readerCubit => context.read<ReaderCubit>();

  bool get _isLockedOpen =>
      _readerCubit.state.isMenuVisible || _readerCubit.state.isSliderRolling;

  // ──────────────────────── 顶部控制 ────────────────────────

  void onEnterTopTrigger() {
    if (_isDisposed) return;
    if (!_readSetting.hoverRevealEnabled || !_readSetting.hoverRevealTop) {
      return;
    }
    _isTopTriggerHovered = true;
    _topHideTimer?.cancel();
    _readerCubit.setTopHovered(true);
  }

  void onExitTopTrigger() {
    if (_isDisposed) return;
    _isTopTriggerHovered = false;
    _checkScheduleHideTop();
  }

  void onEnterTopBar() {
    if (_isDisposed) return;
    if (!_readSetting.hoverRevealEnabled || !_readSetting.hoverRevealTop) {
      return;
    }
    _isTopBarHovered = true;
    _topHideTimer?.cancel();
    _readerCubit.setTopHovered(true);
  }

  void onExitTopBar() {
    if (_isDisposed) return;
    _isTopBarHovered = false;
    _checkScheduleHideTop();
  }

  void _checkScheduleHideTop() {
    if (_isDisposed || _isLockedOpen) return;
    if (_isTopTriggerHovered || _isTopBarHovered) return;

    final delay = _readSetting.hoverHideDelayMs.clamp(100, 3000);
    _topHideTimer?.cancel();
    _topHideTimer = Timer(Duration(milliseconds: delay), () {
      if (_isDisposed || _isLockedOpen) return;
      if (!_isTopTriggerHovered && !_isTopBarHovered) {
        _readerCubit.setTopHovered(false);
      }
    });
  }

  // ──────────────────────── 底部控制 ────────────────────────

  void onEnterBottomTrigger() {
    if (_isDisposed) return;
    if (!_readSetting.hoverRevealEnabled || !_readSetting.hoverRevealBottom) {
      return;
    }
    _isBottomTriggerHovered = true;
    _bottomHideTimer?.cancel();
    _readerCubit.setBottomHovered(true);
  }

  void onExitBottomTrigger() {
    if (_isDisposed) return;
    _isBottomTriggerHovered = false;
    _checkScheduleHideBottom();
  }

  void onEnterBottomBar() {
    if (_isDisposed) return;
    if (!_readSetting.hoverRevealEnabled || !_readSetting.hoverRevealBottom) {
      return;
    }
    _isBottomBarHovered = true;
    _bottomHideTimer?.cancel();
    _readerCubit.setBottomHovered(true);
  }

  void onExitBottomBar() {
    if (_isDisposed) return;
    _isBottomBarHovered = false;
    _checkScheduleHideBottom();
  }

  void _checkScheduleHideBottom() {
    if (_isDisposed || _isLockedOpen) return;
    if (_isBottomTriggerHovered || _isBottomBarHovered) return;

    final delay = _readSetting.hoverHideDelayMs.clamp(100, 3000);
    _bottomHideTimer?.cancel();
    _bottomHideTimer = Timer(Duration(milliseconds: delay), () {
      if (_isDisposed || _isLockedOpen) return;
      if (!_isBottomTriggerHovered && !_isBottomBarHovered) {
        _readerCubit.setBottomHovered(false);
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _topHideTimer?.cancel();
    _bottomHideTimer?.cancel();
  }
}

/// 悬停控制器共享作用域。
class ReaderHoverScope extends InheritedWidget {
  final ReaderHoverController controller;

  const ReaderHoverScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static ReaderHoverController? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ReaderHoverScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(covariant ReaderHoverScope oldWidget) =>
      controller != oldWidget.controller;
}

/// 边缘悬停唤出感应层组件。
///
/// 放置在主 Stack 中漫画图层之上、控制栏图层之下，使用 [HitTestBehavior.translucent]
/// 保证所有触控与滚动手势完全穿透，仅捕获鼠标指针的 Hover 进入与离开。
class ReaderHoverRevealOverlay extends StatelessWidget {
  final ReaderHoverController controller;

  const ReaderHoverRevealOverlay({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final readSetting = context.select(
      (GlobalSettingCubit c) => c.state.readSetting,
    );

    if (!readSetting.hoverRevealEnabled) {
      return const SizedBox.shrink();
    }

    final showTopAppBar = context.select(
      (ReaderCubit c) => c.state.showTopAppBar,
    );
    final showBottomBar = context.select(
      (ReaderCubit c) => c.state.showBottomBar,
    );

    final double topAreaHeight = readSetting.hoverTriggerAreaTop
        .toDouble()
        .clamp(8.0, 150.0);
    final double bottomAreaHeight = readSetting.hoverTriggerAreaBottom
        .toDouble()
        .clamp(8.0, 150.0);

    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // 顶部唤出感应带
        if (readSetting.hoverRevealTop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topAreaHeight,
            child: MouseRegion(
              hitTestBehavior: HitTestBehavior.translucent,
              onEnter: (_) => controller.onEnterTopTrigger(),
              onExit: (_) => controller.onExitTopTrigger(),
              child: (readSetting.hoverShowVisualIndicator && !showTopAppBar)
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),

        // 底部唤出感应带
        if (readSetting.hoverRevealBottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomAreaHeight,
            child: MouseRegion(
              hitTestBehavior: HitTestBehavior.translucent,
              onEnter: (_) => controller.onEnterBottomTrigger(),
              onExit: (_) => controller.onExitBottomTrigger(),
              child: (readSetting.hoverShowVisualIndicator && !showBottomBar)
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}
