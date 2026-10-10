import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_grid_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/grid/grid_widgets.dart';

/// 一个面板的**卡片网格列表**。
///
/// 遵循 MD3 响应式设计规范与 FlClash 的模块网格体系（SuperGrid + GridItem）：
/// - 支持卡片自由展开与折叠（折叠态紧凑收起，网格自动重新紧凑排列）；
/// - 支持编辑模式下的拖拽重排与尺寸自由拉伸；
/// - 提供 1x1, 2x1, 2x2, 全宽等尺寸快捷预设。
class PanelCardList extends StatelessWidget {
  const PanelCardList({
    super.key,
    required this.panelId,
    required this.board,
    required this.isEditing,
    required this.onSetExpanded,
    required this.onMoveCard,
    required this.onHideCard,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
  });

  final String panelId;
  final WorkspaceBoardLayout board;

  final void Function(String cardId, bool expanded) onSetExpanded;
  final void Function(String cardId, int direction) onMoveCard;
  final void Function(String cardId) onHideCard;

  final EdgeInsetsGeometry padding;

  String _extractCardId(Key key) {
    if (key is ValueKey<String>) {
      final val = key.value;
      final parts = val.split(':');
      if (parts.length >= 3) {
        return parts.sublist(2).join(':');
      }
      return val;
    }
    return key.toString();
  }

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
        supported: card.supportedHere?.call() ?? true,
        unsupportedHint: card.unsupportedHint,
        widthSpan: layout.widthSpan ?? card.defaultWidthSpan,
        heightSpan: layout.heightSpan ?? card.defaultHeightSpan,
        isEditing: false,
      );
      return KeyedSubtree(
        key: ValueKey<String>('card:$panelId:${card.id}'),
        child: card.builder(context, chrome),
      );
    }

    final cubit = context.read<WorkspaceCubit>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth =
            (constraints.maxWidth -
                    padding.resolve(Directionality.of(context)).horizontal)
                .clamp(0.0, double.infinity);
        final band = WorkspaceGridBand.of(gridWidth);
        final columns = band.columns;

        final gridItems = <GridItem>[];

        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          final layout = registry.effectiveLayout(card, board);
          final rawWidthSpan = layout.widthSpan ?? card.defaultWidthSpan;
          final rawHeightSpan = layout.heightSpan ?? card.defaultHeightSpan;

          final crossAxisCellCount = resolveCrossAxisCellCount(
            widthSpan: rawWidthSpan,
            band: band,
            availableWidth: gridWidth,
            minimumWidth: card.minimumWidth,
          );

          final num? mainAxisCellCount = layout.expanded ? rawHeightSpan : null;

          final chrome = WorkspaceCardChrome(
            expanded: layout.expanded,
            onToggle: () => onSetExpanded(card.id, !layout.expanded),
            index: i,
            count: cards.length,
            onMoveUp: i > 0 ? () => onMoveCard(card.id, -1) : null,
            onMoveDown: i < cards.length - 1
                ? () => onMoveCard(card.id, 1)
                : null,
            onHide: card.canHide ? () => onHideCard(card.id) : null,
            supported: card.supportedHere?.call() ?? true,
            unsupportedHint: card.unsupportedHint,
            widthSpan: rawWidthSpan,
            heightSpan: rawHeightSpan,
            isEditing: isEditing,
            onResize: (w, h) => cubit.resizeCardInPanel(card.id, w, h),
          );

          gridItems.add(
            GridItem(
              key: ValueKey<String>('card:$panelId:${card.id}'),
              crossAxisCellCount: crossAxisCellCount,
              mainAxisCellCount: mainAxisCellCount,
              logicalWidthSpan: rawWidthSpan,
              child: KeyedSubtree(
                key: ValueKey<String>('content:$panelId:${card.id}'),
                child: card.builder(context, chrome),
              ),
            ),
          );
        }

        return WorkspaceCardMetrics(
          unitHeight: workspaceDefaultUnitHeight,
          collapsedHeight: workspaceCollapsedHeight,
          crossAxisCount: columns,
          band: band,
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SuperGrid(
                  editing: isEditing,
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  onResizeCard: (key, w, h) {
                    final cardId = _extractCardId(key);
                    cubit.resizeCardInPanel(cardId, w, h);
                  },
                  minimumCardWidth: (key) =>
                      registry.find(_extractCardId(key))?.minimumWidth ?? 240,
                  canRemoveCard: (key) =>
                      registry.find(_extractCardId(key))?.canHide ?? false,
                  onRemoveCard: (key) {
                    final cardId = _extractCardId(key);
                    onHideCard(cardId);
                  },
                  onChanged: (reorderedItems) {
                    final orderedIds = reorderedItems
                        .map((item) => _extractCardId(item.key!))
                        .toList();
                    cubit.reorderCardsInPanel(panelId, orderedIds);
                  },
                  children: gridItems,
                ),
              ],
            ),
          ),
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
            GlyphIcon(
              AppGlyphs.gridPlus,
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
