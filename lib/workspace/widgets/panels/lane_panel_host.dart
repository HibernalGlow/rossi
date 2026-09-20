import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_upstream_page.dart';
import 'package:zephyr/workspace/widgets/panels/panel_card_list.dart';

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
    final state = context.watch<WorkspaceCubit>().state;
    final board = state.board;
    final registry = WorkspacePanelRegistry.I;

    final panels = registry.panelsForSide(widget.side, board);
    if (panels.isEmpty) {
      return _buildNoPanel(context);
    }

    final requested = state.activePanel[widget.side.laneId];
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
  const PanelHeaderBar({super.key, required this.panelId, required this.board});

  final String panelId;
  final WorkspaceBoardLayout board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<WorkspaceCubit>();
    final panel = WorkspacePanelRegistry.I.find(panelId);
    final hidden = WorkspaceCardRegistry.I.hiddenCardsForPanel(panelId, board);
    if (panel == null) return const SizedBox.shrink();

    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(panel.icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              panel.title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hidden.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: '恢复被收起的卡片',
              onSelected: (cardId) => cubit.setCardVisible(cardId, true),
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
                        Text(card.title, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${hidden.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
