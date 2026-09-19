import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/widgets/panels/panel_card_list.dart';

/// **叠加在阅读器视口右缘的信息面板**（mimage 的全屏信息面板同款形态）。
///
/// 与泳道面板的区别是**叠加**：不占条带的任何宽度 —— 玻璃浮层直接压在
/// 漫画画面上（[LiquidGlassThickness.thick] 那档的注释写得很清楚，
/// 它就是为「压在内容上的阅读器浮层」准备的）。卡片内容走的仍是
/// **同一套卡片注册表记账**（`WorkspacePanelId.info`），
/// 展开 / 排序 / 隐藏与泳道里的卡片共享同一份布局。
///
/// 显示规则照抄 mimage 的 `FullscreenInfoPanelState::visible()`：
/// `visible = 钉住 || 悬停揭示`。
/// - **右缘感应带**：指针进阅读器泳道右缘 18px 即临时揭示，离开后延时收起
///   （两段式防抖与阅读器的 `ReaderHoverRevealOverlay` 同一套路）；
/// - **钉住**（mimage 的 🔒 / Neo 的 📌）：常开，收起只有关闭按钮 / `Esc`；
/// - 感应带**让位**给泳道的边缘揭示：Reader 独占或全屏时右缘归「揭示相邻
///   泳道」用，这里不抢（抢了会出现「想滚出右栏，信息面板先弹出来」）。
class InfoPanelOverlay extends StatefulWidget {
  const InfoPanelOverlay({super.key, required this.child});

  /// 被叠加的内容（阅读器的局部导航器）。
  final Widget child;

  @override
  State<InfoPanelOverlay> createState() => _InfoPanelOverlayState();
}

class _InfoPanelOverlayState extends State<InfoPanelOverlay> {
  /// 面板宽度上限（mimage 的 `METADATA_PANEL_WIDTH = 380.0`）。
  static const double _maxWidth = 380;

  /// 右缘感应带宽（mimage/Neo 用 28~32px；这里收窄到 18，
  /// 再宽就会在翻页摆臂时误触）。
  static const double _triggerStripWidth = 18;

  /// 离开后延时收起（Neo 边缘壳的默认 hideDelayMs = 500）。
  static const Duration _hideDelay = Duration(milliseconds: 500);

  static const Duration _slideDuration = Duration(milliseconds: 180);

  bool _hoverShown = false;
  bool _stripHovered = false;
  bool _panelHovered = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onStripEnter() {
    _stripHovered = true;
    _hideTimer?.cancel();
    if (!mounted) return;
    if (!context.read<WorkspaceCubit>().state.infoPanelPinned) {
      setState(() => _hoverShown = true);
    }
  }

  void _onStripExit() {
    _stripHovered = false;
    _scheduleHide();
  }

  void _onPanelEnter() {
    _panelHovered = true;
    _hideTimer?.cancel();
  }

  void _onPanelExit() {
    _panelHovered = false;
    _scheduleHide();
  }

  void _scheduleHide() {
    if (!mounted) return;
    if (context.read<WorkspaceCubit>().state.infoPanelPinned) return;
    if (_stripHovered || _panelHovered) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted) return;
      if (!_stripHovered && !_panelHovered) {
        setState(() => _hoverShown = false);
      }
    });
  }

  void _close() {
    final cubit = context.read<WorkspaceCubit>();
    _hideTimer?.cancel();
    cubit.setInfoPanelPinned(false);
    if (_hoverShown) setState(() => _hoverShown = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkspaceCubit>().state;
    final pinned = state.infoPanelPinned;
    // Reader 独占 / 全屏时右缘归泳道边缘揭示，这条叠加层的感应带让位。
    final hoverEnabled =
        !state.isReaderFullscreen &&
        state.effectiveSoloLaneId != LaneId.reader;
    final shown = pinned || (hoverEnabled && _hoverShown);

    return LayoutBuilder(
      builder: (context, constraints) {
        final laneWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _maxWidth;
        final panelWidth = math.min(
          _maxWidth,
          math.max(240.0, laneWidth * 0.5),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,

            // 右缘感应带：只跟踪指针，不拦截点击（translucent）。
            if (hoverEnabled)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _triggerStripWidth,
                child: MouseRegion(
                  hitTestBehavior: HitTestBehavior.translucent,
                  onEnter: (_) => _onStripEnter(),
                  onExit: (_) => _onStripExit(),
                  child: const SizedBox.expand(),
                ),
              ),

            AnimatedPositioned(
              duration: _slideDuration,
              curve: Curves.easeOutCubic,
              right: shown ? 0 : -(panelWidth + 16),
              top: 0,
              bottom: 0,
              width: panelWidth,
              child: _InfoPanelBody(
                shown: shown,
                pinned: pinned,
                onPin: () => context.read<WorkspaceCubit>().setInfoPanelPinned(
                  !pinned,
                ),
                onClose: _close,
                onPointerEnter: _onPanelEnter,
                onPointerExit: _onPanelExit,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 面板本体：玻璃底 + 36px 标题栏 + 卡片列表。
class _InfoPanelBody extends StatelessWidget {
  const _InfoPanelBody({
    required this.shown,
    required this.pinned,
    required this.onPin,
    required this.onClose,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  final bool shown;
  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onClose;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<WorkspaceCubit>();
    final board = context.select<WorkspaceCubit, WorkspaceBoardLayout>(
      (c) => c.state.board,
    );
    final hidden = WorkspaceCardRegistry.I.hiddenCardsForPanel(
      WorkspacePanelId.info,
      board,
    );

    // 贴着右缘，所以只圆左边的角（mimage 的面板是直角贴边，
    // 这里跟着本项目的玻璃材质走，圆角也只代表材质边界）。
    final shape = BorderRadius.only(
      topLeft: Radius.circular(14),
      bottomLeft: Radius.circular(14),
    );

    // 收着的时候不吃任何命中 —— 否则滑过右缘的指针会被一块看不见的板挡住。
    return IgnorePointer(
      ignoring: !shown,
      child: MouseRegion(
        onEnter: (_) => onPointerEnter(),
        onExit: (_) => onPointerExit(),
        child: LiquidGlassSurface(
          thickness: LiquidGlassThickness.thick,
          borderRadius: shape,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_rounded,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '信息',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hidden.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: '恢复被收起的卡片',
                          onSelected: (cardId) =>
                              cubit.setCardVisible(cardId, true),
                          itemBuilder: (context) => [
                            for (final card in hidden)
                              PopupMenuItem<String>(
                                value: card.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      card.icon,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      card.title,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.visibility_off_rounded,
                              size: 15,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      IconButton(
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        tooltip: pinned ? '取消钉住（离开后收起）' : '钉住（常开）',
                        color: pinned ? theme.colorScheme.primary : null,
                        icon: Icon(
                          pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                        ),
                        onPressed: onPin,
                      ),
                      IconButton(
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        tooltip: '关闭信息面板',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Expanded(
                child: PanelCardList(
                  panelId: WorkspacePanelId.info,
                  board: board,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 2,
                  ),
                  onSetExpanded: (cardId, expanded) =>
                      cubit.setCardExpanded(cardId, expanded),
                  onMoveCard: (cardId, direction) =>
                      cubit.moveCardInPanel(
                        WorkspacePanelId.info,
                        cardId,
                        direction,
                      ),
                  onHideCard: (cardId) => cubit.setCardVisible(cardId, false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
