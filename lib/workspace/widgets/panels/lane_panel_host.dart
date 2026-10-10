import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_upstream_page.dart';
import 'package:zephyr/workspace/widgets/panels/panel_card_list.dart';
import 'package:zephyr/icons/icons.dart';

/// **一条面板泳道的内容宿主**：只画「当前面板是什么」。
///
/// 切换面板的**工具栏不在这里** —— 它停在泳道**顶栏**
/// （见 `PanelTabStrip`，由 `SwimlaneColumn` / 抽屉栏头挂上去），
/// 于是这条泳道的内容区从顶到底都是面板本身，不再被一条竖轨占掉 48px。
///
/// 面板的保活纪律来自 neoview 的 `mountedPanels`：
/// **访问过才构建、构建过就留着** —— 切走再切回来不重跑上游页面的加载，
/// 也不丢滚动位置；但绝不一次性把所有面板都建出来（那会在首帧上冻住）。
///
/// 「整页面板」再包一层 `EmbeddedUpstreamPage`：给它一条局部导航栈，
/// 于是从这块卡片里点开的东西开在卡片里，而不是盖住整个工作台。
class LanePanelHost extends StatefulWidget {
  const LanePanelHost({super.key, required this.side});

  final WorkspacePanelSide side;

  @override
  State<LanePanelHost> createState() => _LanePanelHostState();
}

class _LanePanelHostState extends State<LanePanelHost> {
  /// 已经访问过的面板 id（只有访问过的才真正被构建）。
  final Set<String> _visited = <String>{};

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    // **两项 select，不是整份 state 的 watch**：这条宿主住在泳道内容槽位里，
    // 而「谁被激活」对它没有意义 —— 原来那句 `context.watch` 会让每一次 emit
    // 都把 `IndexedStack` 里**每个访问过的面板**重 build 一遍，而每个整页面板
    // 都包着一条 `Navigator`（`EmbeddedUpstreamPage`），于是上游
    // `BookshelfPage` / `DiscoverPage` 也跟着整页重 build。
    // 读的两项就是这里真正用到的两项：面板集合的记账，与本泳道当前是哪个面板。
    final board = context.select<WorkspaceCubit, WorkspaceBoardLayout>(
      (c) => c.state.board,
    );
    final requested = context.select<WorkspaceCubit, String?>(
      (c) => c.state.activePanel[widget.side.laneId],
    );
    final registry = WorkspacePanelRegistry.I;

    final panels = registry.panelsForSide(widget.side, board);
    if (panels.isEmpty) {
      return _buildNoPanel(context);
    }

    var active = panels.indexWhere((p) => p.id == requested);
    if (active < 0) active = 0;
    final activePanel = panels[active];

    // 访问过就留着：首次可见时登记，之后不再从 IndexedStack 里摘掉。
    _visited.add(activePanel.id);

    return IndexedStack(
      index: active,
      sizing: StackFit.expand,
      children: [
        for (final panel in panels)
          if (_visited.contains(panel.id))
            _buildPanelContent(
              context,
              panel,
              board,
              cubit,
              // 只有**本泳道当前显示的那一个**面板才是推入的候选落点。
              isVisible: panel.id == activePanel.id,
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildPanelContent(
    BuildContext context,
    WorkspacePanelDefinition panel,
    WorkspaceBoardLayout board,
    WorkspaceCubit cubit, {
    required bool isVisible,
  }) {
    final page = panel.page;
    if (!panel.acceptsCards && page != null) {
      // 整页复用：面板不多画标题，上游页面自带 chrome。
      // 外面这层负责「从这里点开的东西开在这里」（局部导航栈）。
      return EmbeddedUpstreamPage(
        host: WorkspaceLaneHost(widget.side.laneId, panel.id),
        instanceKey: panel.id,
        isVisible: isVisible,
        builder: page,
      );
    }

    // 两块内容**都**要装局部导航栈：整页面板里的「设置」、卡片里的「历史 → 漫画详情」
    // 都属于「点开会铺满整个应用」的入口，只包一边等于漏一半。
    return KeyedSubtree(
      key: ValueKey<String>('panel-cards:${panel.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 非独占面板才画标题行（独占面板的内容自带 chrome）。
          // 标题行留在导航栈**外面**：它是这块面板自己的 chrome，
          // 不该被推进来的页面盖住（用户还得靠它换面板 / 恢复卡片）。
          if (!panel.exclusive) PanelHeaderBar(panelId: panel.id, board: board),
          Expanded(
            child: EmbeddedUpstreamPage(
              host: WorkspaceLaneHost(widget.side.laneId, panel.id),
              instanceKey: '${panel.id}:cards',
              isVisible: isVisible,
              builder: (context) => PanelCardList(
                panelId: panel.id,
                board: board,
                onSetExpanded: (cardId, expanded) =>
                    cubit.setCardExpanded(cardId, expanded),
                onMoveCard: (cardId, direction) =>
                    cubit.moveCardInPanel(panel.id, cardId, direction),
                onHideCard: (cardId) => cubit.setCardVisible(cardId, false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '这条泳道里的面板都被收起了 ——\n用顶栏页签条右侧的入口恢复一个。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 面板标题行（非独占面板用）：标题 + 被收起卡片的恢复入口。
///
/// 注意：这是**面板**的标题行，不是泳道的顶栏 —— 泳道顶栏在 `SwimlaneColumn`。
class PanelHeaderBar extends StatelessWidget {
  const PanelHeaderBar({
    super.key,
    required this.panelId,
    required this.board,
    required this.isEditing,
    required this.onToggleEditing,
  });

  final String panelId;
  final WorkspaceBoardLayout board;
  final bool isEditing;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<WorkspaceCubit>();
    final panel = WorkspacePanelRegistry.I.find(panelId);
    final hidden = WorkspaceCardRegistry.I.hiddenCardsForPanel(panelId, board);
    if (panel == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final iconOnly = width < 360;
        final showHiddenCount = width >= 420;

        final hiddenButton = FluentPopupMenuButton<String>(
          tooltip: '恢复被收起的卡片',
          onSelected: (cardId) => cubit.setCardVisible(cardId, true),
          itemBuilder: (context) => [
            for (final card in hidden)
              FluentPopupMenuItem<String>(
                value: card.id,
                leading: GlyphIcon(card.icon, size: 18, color: scheme.primary),
                title: Text(card.title, style: theme.textTheme.bodySmall),
              ),
          ],
          child: Container(
            width: showHiddenCount ? 52 : 40,
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: showHiddenCount ? 8 : 0),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                GlyphIcon(
                  AppGlyphs.eyeOff,
                  size: 19,
                  color: scheme.onSurfaceVariant,
                ),
                Positioned(
                  right: showHiddenCount ? -2 : -5,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${hidden.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        final editButton = iconOnly
            ? Tooltip(
                message: isEditing ? '完成布局' : '自定义布局',
                child: IconButton.filledTonal(
                  onPressed: onToggleEditing,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    reverseDuration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    child: GlyphIcon(
                      isEditing ? AppGlyphs.checkCircle : AppGlyphs.gridPlus,
                      key: ValueKey<bool>(isEditing),
                      size: 19,
                    ),
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(36),
                    fixedSize: const Size.square(36),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isEditing
                        ? scheme.primaryContainer
                        : scheme.secondaryContainer,
                    foregroundColor: isEditing
                        ? scheme.onPrimaryContainer
                        : scheme.onSecondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isEditing ? 16 : 14),
                    ),
                  ),
                ),
              )
            : FilledButton.tonalIcon(
                onPressed: onToggleEditing,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  child: GlyphIcon(
                    isEditing ? AppGlyphs.checkCircle : AppGlyphs.gridPlus,
                    key: ValueKey<bool>(isEditing),
                    size: 18,
                  ),
                ),
                label: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    isEditing ? '完成布局' : '自定义布局',
                    key: ValueKey<bool>(isEditing),
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: isEditing
                      ? scheme.primaryContainer
                      : scheme.secondaryContainer,
                  foregroundColor: isEditing
                      ? scheme.onPrimaryContainer
                      : scheme.onSecondaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isEditing ? 16 : 14),
                  ),
                ),
              );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isEditing
                ? scheme.primaryContainer.withValues(alpha: 0.28)
                : scheme.surfaceContainer,
            border: Border(
              bottom: BorderSide(
                color: isEditing
                    ? scheme.primary.withValues(alpha: 0.42)
                    : scheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isEditing ? scheme.primary : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(isEditing ? 14 : 11),
                ),
                child: GlyphIcon(
                  panel.icon,
                  size: 18,
                  color: isEditing
                      ? scheme.onPrimary
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  panel.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hidden.isNotEmpty) ...[
                hiddenButton,
                const SizedBox(width: 6),
              ],
              editButton,
            ],
          ),
        );
      },
    );
  }
}
