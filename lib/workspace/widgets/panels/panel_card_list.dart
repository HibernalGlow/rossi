import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_grid_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/grid/grid_widgets.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 一个面板的**卡片网格列表**。
///
/// 遵循 MD3 响应式设计规范与 FlClash 的模块网格体系（SuperGrid + GridItem）：
/// - 支持卡片自由展开与折叠（折叠态紧凑收起，网格自动重新紧凑排列）；
/// - 支持编辑模式下的拖拽重排与尺寸自由拉伸；
/// - 提供 1x1, 2x1, 2x2, 全宽等尺寸快捷预设；
/// - 支持无标题栏小组件（`headerless`）与展示区「全宽自适应撑满剩余可视高度」（`fillRemainingHeight`）。
class PanelCardList extends StatelessWidget {
  const PanelCardList({
    super.key,
    required this.panelId,
    required this.board,
    required this.isEditing,
    required this.onSetExpanded,
    required this.onMoveCard,
    required this.onHideCard,
    this.onToggleEditing,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
  });

  final String panelId;
  final WorkspaceBoardLayout board;
  final bool isEditing;
  final VoidCallback? onToggleEditing;

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

  /// 计算非自适应撑满卡片在当前面板中的像素高度（用于给 `fillRemainingHeight` 卡片留出剩余高度）。
  double _fixedCardPixelHeight(
    WorkspaceCardDefinition card,
    CardLayout layout, {
    required bool hasCustomHeight,
    required double mainAxisSpacing,
  }) {
    if (!layout.expanded) {
      if (card.headerless) {
        return isEditing ? 38.0 : 40.0;
      }
      return workspaceCollapsedHeight;
    }
    if (card.compactMainAxisExtent != null && !hasCustomHeight) {
      return card.compactMainAxisExtent! +
          (isEditing && card.headerless ? 36.0 : 0.0);
    }
    final span = (layout.heightSpan ?? card.defaultHeightSpan).clamp(1, 8);
    return (workspaceDefaultUnitHeight + mainAxisSpacing) * span -
        mainAxisSpacing;
  }

  @override
  Widget build(BuildContext context) {
    final registry = WorkspaceCardRegistry.I;
    final cards = registry.cardsForPanel(panelId, board);

    if (cards.isEmpty) {
      return _buildEmpty(context);
    }

    final panelDef = WorkspacePanelRegistry.I.find(panelId);
    // 只有非 headerless 的单卡独占面板（如书签、历史、下载、文件管理）才走直铺 standalone；
    // 无标题栏小组件面板（如页面导航）即使只剩 1 张可见卡也走 SuperGrid，保留右键菜单与恢复能力。
    if (panelDef?.exclusive == true &&
        cards.length == 1 &&
        !cards.first.headerless) {
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
    final hiddenDefs = registry.hiddenCardsForPanel(panelId, board);
    final hiddenEntries = <HiddenCardEntry>[
      for (final hidden in hiddenDefs)
        (id: hidden.id, title: hidden.title, icon: hidden.icon),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final gridWidth = (constraints.maxWidth - resolvedPadding.horizontal)
            .clamp(0.0, double.infinity);
        final band = WorkspaceGridBand.of(gridWidth);
        final columns = band.columns;
        const mainAxisSpacing = 8.0;
        const crossAxisSpacing = 8.0;

        // 先识别哪些卡片处于「自动撑满剩余可视高度」状态（默认全宽且用户未手动指定固定 heightSpan）。
        final isLegacyPreSplitSnapshot =
            board.cardLayout(WorkspaceCardRegistry.pageListSearch) == null &&
            board.cardLayout(WorkspaceCardRegistry.pageListJump) == null;
        final fillingCardIds = <String>{};
        for (final card in cards) {
          final rawLayout = board.cardLayout(card.id);
          final layout = registry.effectiveLayout(card, board);
          final legacyDefaultHeight =
              isLegacyPreSplitSnapshot &&
              card.id == WorkspaceCardRegistry.pageList &&
              rawLayout?.heightSpan == 2;
          if (card.fillRemainingHeight &&
              layout.expanded &&
              (rawLayout?.heightSpan == null || legacyDefaultHeight)) {
            fillingCardIds.add(card.id);
          }
        }

        // 若存在自动撑满卡片且面板有明确视口高度，则用 packGridSlots 量出其余卡片占用的高度，
        // 剩余可视高度平分给 fillingCardIds（通常就 1 张「页面展示栏」）。
        double? autoFillPixelHeight;
        if (fillingCardIds.isNotEmpty && constraints.hasBoundedHeight) {
          final otherColCounts = <int>[];
          final otherExtents = <double>[];
          for (final card in cards) {
            if (fillingCardIds.contains(card.id)) continue;
            final rawLayout = board.cardLayout(card.id);
            final layout = registry.effectiveLayout(card, board);
            final rawWidthSpan = layout.widthSpan ?? card.defaultWidthSpan;
            final cellCount = resolveCrossAxisCellCount(
              widthSpan: rawWidthSpan,
              band: band,
              availableWidth: gridWidth,
              minimumWidth: card.minimumWidth,
            );
            otherColCounts.add(cellCount);
            otherExtents.add(
              _fixedCardPixelHeight(
                card,
                layout,
                hasCustomHeight: rawLayout?.heightSpan != null,
                mainAxisSpacing: mainAxisSpacing,
              ),
            );
          }
          final otherGeometry = packGridSlots(
            crossAxisCellCounts: otherColCounts,
            mainAxisExtents: otherExtents,
            crossAxisCount: columns,
            crossAxisExtent: gridWidth,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );
          final otherTotalHeight = otherColCounts.isEmpty
              ? 0.0
              : otherGeometry.mainAxisExtent + mainAxisSpacing;
          final availableViewportHeight =
              constraints.maxHeight - resolvedPadding.vertical;
          final rawRemaining =
              (availableViewportHeight - otherTotalHeight) /
              fillingCardIds.length;
          autoFillPixelHeight = math.max(220.0, rawRemaining);
        }

        final gridItems = <GridItem>[];

        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          final rawLayout = board.cardLayout(card.id);
          final layout = registry.effectiveLayout(card, board);
          final hasCustomHeight = rawLayout?.heightSpan != null;
          final rawWidthSpan = layout.widthSpan ?? card.defaultWidthSpan;
          final rawHeightSpan = layout.heightSpan ?? card.defaultHeightSpan;

          final crossAxisCellCount = resolveCrossAxisCellCount(
            widthSpan: rawWidthSpan,
            band: band,
            availableWidth: gridWidth,
            minimumWidth: card.minimumWidth,
          );

          num? mainAxisCellCount;
          if (!layout.expanded) {
            mainAxisCellCount = null;
          } else if (fillingCardIds.contains(card.id) &&
              autoFillPixelHeight != null) {
            mainAxisCellCount =
                (autoFillPixelHeight + mainAxisSpacing) /
                (workspaceDefaultUnitHeight + mainAxisSpacing);
          } else if (card.compactMainAxisExtent != null && !hasCustomHeight) {
            final compactHeight =
                card.compactMainAxisExtent! +
                (isEditing && card.headerless ? 36.0 : 0.0);
            mainAxisCellCount =
                (compactHeight + mainAxisSpacing) /
                (workspaceDefaultUnitHeight + mainAxisSpacing);
          } else {
            mainAxisCellCount = rawHeightSpan;
          }

          // 独占面板（无 PanelHeaderBar）至少保留 1 张可见卡片，防止全部收起后面板失去恢复入口。
          final canHideThisCard =
              card.canHide && (panelDef?.exclusive != true || cards.length > 1);

          final chrome = WorkspaceCardChrome(
            expanded: layout.expanded,
            onToggle: () => onSetExpanded(card.id, !layout.expanded),
            index: i,
            count: cards.length,
            onMoveUp: i > 0 ? () => onMoveCard(card.id, -1) : null,
            onMoveDown: i < cards.length - 1
                ? () => onMoveCard(card.id, 1)
                : null,
            onHide: canHideThisCard ? () => onHideCard(card.id) : null,
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
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisSpacing: mainAxisSpacing,
                  onToggleEditing: onToggleEditing,
                  hiddenCards: hiddenEntries,
                  onRestoreCard: (cardId) => cubit.setCardVisible(cardId, true),
                  isFillingRemainingHeight: (key) =>
                      fillingCardIds.contains(_extractCardId(key)),
                  onFillRemainingHeight: (key) {
                    final cardId = _extractCardId(key);
                    final def = registry.find(cardId);
                    if (def != null &&
                        (def.fillRemainingHeight ||
                            def.compactMainAxisExtent != null)) {
                      cubit.resetCardAutoHeight(cardId);
                    }
                  },
                  onResizeCard: (key, w, h) {
                    final cardId = _extractCardId(key);
                    cubit.resizeCardInPanel(cardId, w, h);
                  },
                  minimumCardWidth: (key) =>
                      registry.find(_extractCardId(key))?.minimumWidth ?? 240,
                  minimumCardHeight: (key) =>
                      registry
                          .find(_extractCardId(key))
                          ?.compactMainAxisExtent ??
                      workspaceDefaultUnitHeight,
                  maxHeightSpan: (key) {
                    final def = registry.find(_extractCardId(key));
                    return (def?.fillRemainingHeight ?? false) ? 8 : 4;
                  },
                  canRemoveCard: (key) {
                    final def = registry.find(_extractCardId(key));
                    if (def == null || !def.canHide) return false;
                    if (panelDef?.exclusive == true && cards.length <= 1) {
                      return false;
                    }
                    return true;
                  },
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
              t.workspace.allCardsCollapsed,
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
