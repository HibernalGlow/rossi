import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/info_card_kit.dart';
import 'package:zephyr/workspace/widgets/cards/page_list_panel_controller.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 页面导航面板的「底部跳转栏」MD3 无标题栏小组件。
///
/// - **日常展开态**：紧凑展示阅读进度滑块、页码输入框与「跳转」按钮；
/// - **日常折叠态**：缩成精简导航胶囊条（显示当前页码进度 `21 / 33`）；
/// - **编辑模式态**：出现拖拽手柄与尺寸/布局控制，支持在面板内任意移动位置。
class PageListJumpCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;
  final PageListPanelController? controller;

  const PageListJumpCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final coordinator = ReaderSessionCoordinator.instance;
    final ctrl = controller ?? PageListPanelController.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([coordinator, ctrl]),
      builder: (context, _) {
        final hasSession = coordinator.hasActiveSession;
        final totalSlots = coordinator.totalSlots;
        final currentSlot = coordinator.currentSlot;

        final bar = PageListJumpToolbar(
          coordinator: coordinator,
          controller: ctrl,
          currentSlot: currentSlot,
          totalSlots: totalSlots,
          enabled: hasSession && totalSlots > 0,
        );

        if (isStandalone) {
          return bar;
        }

        return CollapsibleCard(
          cardId: WorkspaceCardRegistry.pageListJump,
          title: t.workspace.jumpBar,
          icon: AppGlyphs.linearScale,
          expressive: true,
          headerless: true,
          scrollContent: false,
          margin: EdgeInsets.zero,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: hasSession
              ? InfoCardCounter('${currentSlot + 1} / $totalSlots')
              : InfoCardCounter(t.workspace.idleState),
          child: Align(alignment: Alignment.centerLeft, child: bar),
        );
      },
    );
  }
}

/// 进度滑块 + 页码输入框 + 跳转按钮工具条（供小组件与 standalone 复用）。
class PageListJumpToolbar extends StatelessWidget {
  final ReaderSessionCoordinator coordinator;
  final PageListPanelController controller;
  final int currentSlot;
  final int totalSlots;
  final bool enabled;

  const PageListJumpToolbar({
    super.key,
    required this.coordinator,
    required this.controller,
    required this.currentSlot,
    required this.totalSlots,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final maxSlot = (totalSlots - 1).clamp(0, 999999).toDouble();
    final clampedValue = currentSlot.toDouble().clamp(0.0, maxSlot);

    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  value: clampedValue,
                  min: 0,
                  max: maxSlot,
                  onChanged: enabled
                      ? (value) {
                          coordinator.jumpTo(value.round());
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 52,
            height: 28,
            child: TextField(
              controller: controller.jumpPageController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: t.workspace.pageNumber,
                hintStyle: const TextStyle(fontSize: 10),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onSubmitted: (_) => controller.jumpToPageInput(context),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 28,
            child: FilledButton.tonal(
              onPressed: enabled
                  ? () => controller.jumpToPageInput(context)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('跳转', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
