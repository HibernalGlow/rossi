import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';

/// 悬停唤出的「锁」（手动展开的菜单 `isMenuVisible` / 正在拖的进度条
/// `isSliderRolling`）是不是**刚刚**解除。
///
/// **只看「变没变」，不看当前值**：只有锁解除的那一瞬间才需要对账。若改成看当前值，
/// 那么锁一放开之后每一次状态变化都会重新对一次账 —— 包括「指针正悬停在底栏上」
/// 的那种时刻，会把用户手底下的栏收走。
///
/// 抽出顶层纯函数是为了能直接断言（判据见 `test/reader/reader_hover_reveal_test.dart`）；
/// 使用点只有一个：`ComicReadSuccessWidget` 里那个 `BlocListener.listenWhen`。
bool isHoverRevealLockReleased(ReaderState previous, ReaderState current) =>
    (previous.isMenuVisible && !current.isMenuVisible) ||
    (previous.isSliderRolling && !current.isSliderRolling);

/// 悬停唤出控制器（参考 NeoView 风格）。
///
/// 采用「边缘触发带 + 悬浮控制栏本体」两段式防抖交互：
/// 1. 鼠标移入顶部/底部感应带，立即激活对应控制栏唤出；
/// 2. 控制栏滑出后，鼠标在控制栏本体上操作时保持常驻，不会被定时器收回；
/// 3. 鼠标离开感应带与控制栏本体后，等待设定的延时（默认 500ms）平滑收起；
/// 4. 处于手动呼出菜单（`isMenuVisible == true`）或滑块拖拽中（`isSliderRolling == true`）时锁定显示。
class ReaderHoverController {
  BuildContext _context;

  bool _isTopTriggerHovered = false;
  bool _isTopBarHovered = false;
  bool _isBottomTriggerHovered = false;
  bool _isBottomBarHovered = false;

  Timer? _topHideTimer;
  Timer? _bottomHideTimer;
  bool _isDisposed = false;

  ReaderHoverController(this._context);

  BuildContext get context => _context;

  void updateContext(BuildContext newContext) {
    _context = newContext;
  }

  ReadSettingState get _readSetting =>
      _context.read<GlobalSettingCubit>().state.readSetting;

  ReaderCubit get _readerCubit => _context.read<ReaderCubit>();

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

  // ──────────────────── 锁解除时的对账（修「底栏收不起来」） ────────────────────

  /// 锁（菜单展开 / 拖拽滑块）解除后，用「指针此刻在不在唤出区/栏体上」把两侧的
  /// 悬停标记重新算一遍。
  ///
  /// **为什么必须有这一手**：`_checkScheduleHideTop` / `_checkScheduleHideBottom`
  /// 在锁定期是**故意**不排收起定时器的（锁着的时候本来就不该收），而
  /// `setTopHovered(false)` / `setBottomHovered(false)` **只有那条定时器会调**。
  /// 于是只要「指针离开唤出区」这一下正好发生在锁着的时候（比如鼠标从底栏滑走、
  /// 而菜单正因为刚才那次中间点击而展开着），这次离开就被彻底丢掉了：标记留在
  /// `true` 上，谁也不会再把它算回来。
  ///
  /// 后果不对称、看起来像「只有一半的 chrome 坏了」：可见性是
  /// `showTopAppBar = isMenuVisible || isTopHovered` /
  /// `showBottomBar = isMenuVisible || isBottomHovered`，被残留标记 OR 住的那一条
  /// **再也收不起来** —— 点中间收菜单时，没被标记过的那条正常滑走，另一条不动。
  ///
  /// 锁解除的时机由 `ComicReadSuccessWidget` 里的 `BlocListener` 送过来：那是唯一
  /// 同时握有「锁变没变」与控制器实例的地方。
  void syncHoveredWithPointer() {
    if (_isDisposed) return;
    _topHideTimer?.cancel();
    _bottomHideTimer?.cancel();

    final topPresent = _isTopTriggerHovered || _isTopBarHovered;
    final bottomPresent = _isBottomTriggerHovered || _isBottomBarHovered;

    // 指针两边都不在（绝大多数情况）：一次清掉两侧 —— 这正是被「锁着不排定时器」
    // 漏掉的那次清理。
    if (!topPresent && !bottomPresent) {
      _readerCubit.resetHoverState();
      return;
    }

    // 只有一侧指针还在（滑块拖到一半松手、鼠标停在底栏上）：那一侧保持唤出，
    // 另一侧才收走 —— 别把指针底下那一条栏从用户手底下抽掉。
    _readerCubit.setTopHovered(topPresent);
    _readerCubit.setBottomHovered(bottomPresent);
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

  const ReaderHoverRevealOverlay({super.key, required this.controller});

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
