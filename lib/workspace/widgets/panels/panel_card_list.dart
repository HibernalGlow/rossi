import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

/// 一个面板的**卡片列表**。
///
/// 卡片从[卡片注册表]里取 —— 泳道面板与四边栏抽屉读的是**同一份**成员关系，
/// 所以「这张卡属于哪个面板」只有一处可改。
///
/// 每张卡的轨道操作（上移 / 下移 / 隐藏）由这里算好下标再交给卡片，
/// 卡片自己不关心自己在第几位。
class PanelCardList extends StatelessWidget {
  const PanelCardList({
    super.key,
    required this.panelId,
    required this.board,
    required this.onSetExpanded,
    required this.onMoveCard,
    required this.onHideCard,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
  });

  final String panelId;
  final WorkspaceBoardLayout board;

  final void Function(String cardId, bool expanded) onSetExpanded;
  final void Function(String cardId, int direction) onMoveCard;
  final void Function(String cardId) onHideCard;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final registry = WorkspaceCardRegistry.I;
    final cards = registry.cardsForPanel(panelId, board);

    if (cards.isEmpty) {
      return _buildEmpty(context);
    }

    final panelDef = WorkspacePanelRegistry.I.find(panelId);
    if (panelDef?.exclusive == true && cards.length == 1) {
      final card = cards.first;
      final layout = registry.effectiveLayout(card, board);
      final chrome = WorkspaceCardChrome(
        expanded: layout.expanded,
        onToggle: () => onSetExpanded(card.id, !layout.expanded),
        index: 0,
        count: 1,
        onHide: card.canHide ? () => onHideCard(card.id) : null,
        standalone: true,
      );
      return KeyedSubtree(
        key: ValueKey<String>('card:$panelId:${card.id}'),
        child: card.builder(context, chrome),
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        final layout = registry.effectiveLayout(card, board);
        final chrome = WorkspaceCardChrome(
          expanded: layout.expanded,
          onToggle: () => onSetExpanded(card.id, !layout.expanded),
          index: index,
          count: cards.length,
          onMoveUp: index > 0 ? () => onMoveCard(card.id, -1) : null,
          onMoveDown: index < cards.length - 1
              ? () => onMoveCard(card.id, 1)
              : null,
          onHide: card.canHide ? () => onHideCard(card.id) : null,
        );
        return KeyedSubtree(
          key: ValueKey<String>('card:$panelId:${card.id}'),
          child: card.builder(context, chrome),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 30,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            Text(
              '这个面板里的卡片都被收起来了',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
