import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 泳道与面板看板卡片：
/// - 调整泳道顺序（左泳道 / 阅读器泳道 / 右泳道，支持拖拽与左右移按钮）；
/// - 调整每条泳道上面板的顺序（支持拖拽与上下移按钮）及跨泳道移动；
/// - 调整每个面板的显示与彻底隐藏（隐藏后从面板栏彻底消失，不留隐藏图标）。
class WorkspaceSwimlanePanelKanbanCard extends StatefulWidget {
  const WorkspaceSwimlanePanelKanbanCard({
    super.key,
    required this.snapshot,
    required this.onChanged,
    this.showHeader = true,
  });

  final WorkspaceLayoutSnapshot snapshot;
  final ValueChanged<WorkspaceLayoutSnapshot> onChanged;
  final bool showHeader;

  @override
  State<WorkspaceSwimlanePanelKanbanCard> createState() =>
      _WorkspaceSwimlanePanelKanbanCardState();
}

class _PanelDragPayload {
  const _PanelDragPayload({
    required this.panelId,
    required this.fromSide,
    required this.canMoveAcrossLanes,
  });

  final String panelId;
  final WorkspacePanelSide fromSide;
  final bool canMoveAcrossLanes;
}

class _WorkspaceSwimlanePanelKanbanCardState
    extends State<WorkspaceSwimlanePanelKanbanCard> {
  String? _draggingLaneId;
  String? _draggingPanelId;

  WorkspaceLayoutConfig get _layout => widget.snapshot.layout;
  WorkspaceBoardLayout get _board => widget.snapshot.board;

  void _emitLayout(WorkspaceLayoutConfig nextLayout) {
    if (nextLayout == _layout) return;
    widget.onChanged(widget.snapshot.copyWith(layout: nextLayout));
  }

  void _emitBoard(
    WorkspaceBoardLayout nextBoard, {
    Map<String, String>? activePanel,
  }) {
    if (nextBoard == _board && activePanel == null) return;
    widget.onChanged(
      widget.snapshot.copyWith(board: nextBoard, activePanel: activePanel),
    );
  }

  void _handleResetAll() {
    widget.onChanged(
      widget.snapshot.copyWith(
        layout: _layout.copyWith(laneOrder: LaneId.defaultOrder),
        board: _board.resetPanels(),
        activePanel: const <String, String>{},
      ),
    );
  }

  void _moveLane(String laneId, int direction) {
    final next = _layout.moveLane(laneId, direction);
    if (next != null) {
      _emitLayout(next);
    }
  }

  void _reorderLane(String draggedLaneId, String targetLaneId) {
    _emitLayout(_layout.reorderLane(draggedLaneId, targetLaneId));
  }

  PanelLayout _fallbackPanelLayout(String panelId, WorkspacePanelSide side) {
    final def = WorkspacePanelRegistry.I.find(panelId);
    if (def == null) {
      return PanelLayout(visible: true, order: 0, side: side);
    }
    return WorkspacePanelRegistry.I.effectivePanelLayout(def, _board);
  }

  void _movePanel(WorkspacePanelSide side, String panelId, int direction) {
    final ordered = [
      for (final p in WorkspacePanelRegistry.I.allPanelsForSide(side, _board))
        p.id,
    ];
    final nextBoard = _board.movePanel(
      panelId,
      direction,
      ordered,
      fallbackFor: (id) => _fallbackPanelLayout(id, side),
    );
    if (nextBoard != null) {
      _emitBoard(nextBoard);
    }
  }

  void _arrangePanel({
    required String panelId,
    required WorkspacePanelSide targetSide,
    required int insertIndex,
    bool? visible,
  }) {
    final registry = WorkspacePanelRegistry.I;
    final def = registry.find(panelId);
    if (def == null) return;
    final current = registry.effectivePanelLayout(def, _board);
    if (!def.canMove && current.side != targetSide) return;

    final siblings = [
      for (final p in registry.allPanelsForSide(targetSide, _board))
        if (p.id != panelId) p.id,
    ];
    final nextBoard = _board.arrangePanel(
      panelId: panelId,
      side: targetSide,
      siblingIds: siblings,
      insertIndex: insertIndex,
      visible: visible,
      fallbackFor: (id) => _fallbackPanelLayout(id, targetSide),
    );
    _emitBoard(nextBoard);
  }

  void _togglePanelVisible(WorkspacePanelDefinition panel, bool visible) {
    final registry = WorkspacePanelRegistry.I;
    final current = registry.effectivePanelLayout(panel, _board);
    if (current.visible == visible) return;

    // 保持当前面板在所属泳道看板中的相对顺序，只切换 visible 状态。
    final ordered = [
      for (final p in registry.allPanelsForSide(current.side, _board)) p.id,
    ];
    final idx = ordered.indexOf(panel.id);
    final siblings = [
      for (final id in ordered)
        if (id != panel.id) id,
    ];
    final nextBoard = _board.arrangePanel(
      panelId: panel.id,
      side: current.side,
      siblingIds: siblings,
      insertIndex: idx < 0 ? siblings.length : idx,
      visible: visible,
      fallbackFor: (id) => _fallbackPanelLayout(id, current.side),
    );
    _emitBoard(nextBoard);
  }

  void _movePanelToOtherSide(WorkspacePanelDefinition panel) {
    if (!panel.canMove) return;
    final registry = WorkspacePanelRegistry.I;
    final current = registry.effectivePanelLayout(panel, _board);
    final targetSide = current.side == WorkspacePanelSide.left
        ? WorkspacePanelSide.right
        : WorkspacePanelSide.left;
    final targetPanels = registry.allPanelsForSide(targetSide, _board);
    _arrangePanel(
      panelId: panel.id,
      targetSide: targetSide,
      insertIndex: targetPanels.length,
    );
  }

  String _laneTitle(String laneId) {
    final configured = _layout.lanes[laneId]?.title;
    if (configured != null && configured.isNotEmpty) return configured;
    return switch (laneId) {
      LaneId.left => '左泳道',
      LaneId.reader => '阅读器',
      LaneId.right => '右泳道',
      _ => laneId,
    };
  }

  Glyph _laneIcon(String laneId) {
    return switch (laneId) {
      LaneId.left => AppGlyphs.book,
      LaneId.reader => AppGlyphs.columnsThree,
      LaneId.right => AppGlyphs.compass,
      _ => AppGlyphs.layoutTabs,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final registry = WorkspacePanelRegistry.I;
    final leftAll = registry.allPanelsForSide(WorkspacePanelSide.left, _board);
    final rightAll = registry.allPanelsForSide(
      WorkspacePanelSide.right,
      _board,
    );
    final totalCount = leftAll.length + rightAll.length;
    final visibleCount = [
      ...leftAll,
      ...rightAll,
    ].where((p) => registry.effectivePanelLayout(p, _board).visible).length;
    final hiddenCount = totalCount - visibleCount;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部概要与恢复默认按钮
          Row(
            children: [
              Expanded(
                child: Text(
                  '拖拽或点击按钮即可调整泳道顺序、各泳道内面板顺序及显示/隐藏状态。'
                  '隐藏后的面板将从面板栏彻底移除，不再显示隐藏图标。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                key: const ValueKey<String>('kanban-reset-button'),
                onPressed: _handleResetAll,
                icon: const GlyphIcon(AppGlyphs.reset, size: 16),
                label: Text(t.settings.kanbanRestoreDefault),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 状态统计胶囊行
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatPill(
                icon: AppGlyphs.columnsThree,
                label:
                    '泳道顺序：${_layout.laneOrder.map(_laneTitle).join(' → ')}',
                color: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
              _StatPill(
                icon: AppGlyphs.eye,
                label: '显示中 $visibleCount 个面板',
                color: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
              _StatPill(
                icon: AppGlyphs.eyeOff,
                label: '已彻底隐藏 $hiddenCount 个面板',
                color: scheme.surfaceContainerHighest,
                foreground: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 泳道顺序看板条
          _buildLaneOrderStrip(context),
          const SizedBox(height: 16),
          // 三栏看板列（响应式：宽屏三列并排，窄屏上下堆叠）
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final laneOrder = _layout.laneOrder;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < laneOrder.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _buildKanbanLaneColumn(
                          context,
                          laneId: laneOrder[i],
                          laneIndex: i,
                          laneCount: laneOrder.length,
                        ),
                      ),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < laneOrder.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _buildKanbanLaneColumn(
                      context,
                      laneId: laneOrder[i],
                      laneIndex: i,
                      laneCount: laneOrder.length,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );

    if (!widget.showHeader) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: body,
      );
    }

    return SettingSectionCard(
      title: t.settings.swimlanePanelKanban,
      icon: AppGlyphs.dashboard,
      children: [body],
    );
  }

  /// 顶部泳道顺序条：支持拖拽或左右按钮直接调整三8泳道顺序。
  Widget _buildLaneOrderStrip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final laneOrder = _layout.laneOrder;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphIcon(
                AppGlyphs.columnsThree,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '泳道顺序（可左右拖拽或点击箭头调整位置）',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (var i = 0; i < laneOrder.length; i++)
                _buildLaneOrderChip(
                  context,
                  laneId: laneOrder[i],
                  index: i,
                  total: laneOrder.length,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLaneOrderChip(
    BuildContext context, {
    required String laneId,
    required int index,
    required int total,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isReader = laneId == LaneId.reader;

    return DragTarget<String>(
      key: ValueKey<String>('lane-order-target:$laneId'),
      onWillAcceptWithDetails: (details) =>
          details.data != laneId && _layout.laneOrder.contains(details.data),
      onAcceptWithDetails: (details) => _reorderLane(details.data, laneId),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        final chipContent = AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: hovering
                ? scheme.primaryContainer
                : isReader
                ? scheme.secondaryContainer.withValues(alpha: 0.75)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovering
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: hovering ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlyphIcon(
                AppGlyphs.dragHandle,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GlyphIcon(_laneIcon(laneId), size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                _laneTitle(laneId),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: ValueKey<String>('lane-move-left:$laneId'),
                tooltip: t.settings.kanbanLaneMoveLeft,
                onPressed: index > 0 ? () => _moveLane(laneId, -1) : null,
                icon: const GlyphIcon(AppGlyphs.chevronBack, size: 15),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(26),
                  fixedSize: const Size.square(26),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                key: ValueKey<String>('lane-move-right:$laneId'),
                tooltip: t.settings.kanbanLaneMoveRight,
                onPressed: index < total - 1
                    ? () => _moveLane(laneId, 1)
                    : null,
                icon: const GlyphIcon(AppGlyphs.chevronForward, size: 15),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(26),
                  fixedSize: const Size.square(26),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );

        return Draggable<String>(
          data: laneId,
          onDragStarted: () => setState(() => _draggingLaneId = laneId),
          onDragEnd: (_) => setState(() => _draggingLaneId = null),
          feedback: Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: chipContent,
          ),
          childWhenDragging: Opacity(opacity: 0.45, child: chipContent),
          child: chipContent,
        );
      },
    );
  }

  /// 单列泳道看板容器。
  Widget _buildKanbanLaneColumn(
    BuildContext context, {
    required String laneId,
    required int laneIndex,
    required int laneCount,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final side = WorkspacePanelSide.fromLaneId(laneId);

    return DragTarget<String>(
      key: ValueKey<String>('kanban-lane-column:$laneId'),
      onWillAcceptWithDetails: (details) =>
          details.data != laneId && _layout.laneOrder.contains(details.data),
      onAcceptWithDetails: (details) => _reorderLane(details.data, laneId),
      builder: (context, laneCandidates, _) {
        final laneHover = laneCandidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: laneHover
                ? scheme.primaryContainer.withValues(alpha: 0.25)
                : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: laneHover
                  ? scheme.primary
                  : _draggingLaneId == laneId
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: laneHover ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 泳道列头
              Row(
                children: [
                  ExpressiveIconBadge(
                    icon: _laneIcon(laneId),
                    size: 32,
                    glyphSize: 17,
                    color: side == null
                        ? scheme.secondaryContainer
                        : scheme.primaryContainer,
                    foreground: side == null
                        ? scheme.onSecondaryContainer
                        : scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _laneTitle(laneId),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '第 ${laneIndex + 1} 栏',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          side == null
                              ? '阅读器主视图泳道'
                              : _panelLaneSummary(side),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.settings.kanbanLaneMoveLeft,
                    onPressed: laneIndex > 0
                        ? () => _moveLane(laneId, -1)
                        : null,
                    icon: const GlyphIcon(AppGlyphs.chevronBack, size: 16),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(28),
                      fixedSize: const Size.square(28),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    tooltip: t.settings.kanbanLaneMoveRight,
                    onPressed: laneIndex < laneCount - 1
                        ? () => _moveLane(laneId, 1)
                        : null,
                    icon: const GlyphIcon(AppGlyphs.chevronForward, size: 16),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(28),
                      fixedSize: const Size.square(28),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (side == null)
                _buildReaderLanePlaceholder(
                  context,
                  laneIndex: laneIndex,
                  laneCount: laneCount,
                )
              else
                _buildPanelColumnList(context, side),
            ],
          ),
        );
      },
    );
  }

  String _panelLaneSummary(WorkspacePanelSide side) {
    final registry = WorkspacePanelRegistry.I;
    final all = registry.allPanelsForSide(side, _board);
    final visible = all
        .where((p) => registry.effectivePanelLayout(p, _board).visible)
        .length;
    final hidden = all.length - visible;
    if (hidden == 0) {
      return '共 ${all.length} 个面板（全部显示）';
    }
    return '显示 $visible 个 · 隐藏 $hidden 个';
  }

  Widget _buildReaderLanePlaceholder(
    BuildContext context, {
    required int laneIndex,
    required int laneCount,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphIcon(AppGlyphs.book, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '漫画阅读器主画布',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '此泳道专用于承载正在阅读的漫画页面。可通过上方泳道顺序条或本列右上角箭头，'
            '将阅读器调整到左侧、居中或右侧位置。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: laneIndex > 0
                    ? () => _moveLane(LaneId.reader, -1)
                    : null,
                icon: const GlyphIcon(AppGlyphs.chevronBack, size: 15),
                label: Text(t.settings.kanbanLaneMoveLeft),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: laneIndex < laneCount - 1
                    ? () => _moveLane(LaneId.reader, 1)
                    : null,
                icon: const GlyphIcon(AppGlyphs.chevronForward, size: 15),
                label: Text(t.settings.kanbanLaneMoveRight),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanelColumnList(BuildContext context, WorkspacePanelSide side) {
    final registry = WorkspacePanelRegistry.I;
    final panels = registry.allPanelsForSide(side, _board);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildPanelKanbanTile(
            context,
            side: side,
            panel: panels[i],
            index: i,
            total: panels.length,
          ),
        ],
        const SizedBox(height: 8),
        _buildTrailingPanelDropZone(context, side, panels.length),
      ],
    );
  }

  Widget _buildPanelKanbanTile(
    BuildContext context, {
    required WorkspacePanelSide side,
    required WorkspacePanelDefinition panel,
    required int index,
    required int total,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effective = WorkspacePanelRegistry.I.effectivePanelLayout(
      panel,
      _board,
    );
    final isVisible = effective.visible;
    final payload = _PanelDragPayload(
      panelId: panel.id,
      fromSide: side,
      canMoveAcrossLanes: panel.canMove,
    );

    return DragTarget<_PanelDragPayload>(
      key: ValueKey<String>('kanban-panel-target:${side.name}:${panel.id}'),
      onWillAcceptWithDetails: (details) {
        final incoming = details.data;
        if (incoming.panelId == panel.id && incoming.fromSide == side) {
          return false;
        }
        if (incoming.fromSide != side && !incoming.canMoveAcrossLanes) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) {
        _arrangePanel(
          panelId: details.data.panelId,
          targetSide: side,
          insertIndex: index,
        );
      },
      builder: (context, candidates, _) {
        final isHovering = candidates.isNotEmpty;
        final cardWidget = AnimatedContainer(
          key: ValueKey<String>('kanban-panel-card:${panel.id}'),
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHovering
                ? scheme.primaryContainer.withValues(alpha: 0.45)
                : isVisible
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLowest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovering
                  ? scheme.primary
                  : isVisible
                  ? scheme.outlineVariant.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              width: isHovering ? 1.6 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlyphIcon(
                    AppGlyphs.dragHandle,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Opacity(
                    opacity: isVisible ? 1.0 : 0.48,
                    child: ExpressiveIconBadge(
                      icon: panel.icon,
                      size: 30,
                      glyphSize: 16,
                      color: isVisible
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      foreground: isVisible
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          panel.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isVisible
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            decoration: isVisible
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MiniStatusTag(
                              label: isVisible ? t.settings.kanbanVisible : t.settings.kanbanFullyHidden,
                              active: isVisible,
                            ),
                            if (!panel.canMove)
                              _MiniStatusTag(
                                label: t.settings.kanbanLanePinned,
                                active: false,
                              ),
                            if (!panel.defaultVisible)
                              _MiniStatusTag(
                                label: t.settings.kanbanLaneDefaultHidden,
                                active: false,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 显示 / 彻底隐藏切换开关
                  Tooltip(
                    message: isVisible
                        ? '从面板栏彻底隐藏（不留隐藏图标）'
                        : '在面板栏中显示此面板',
                    child: IconButton(
                      key: ValueKey<String>(
                        'kanban-panel-visibility:${panel.id}',
                      ),
                      onPressed: () => _togglePanelVisible(panel, !isVisible),
                      icon: GlyphIcon(
                        isVisible ? AppGlyphs.eye : AppGlyphs.eyeOff,
                        size: 17,
                        color: isVisible
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(30),
                        fixedSize: const Size.square(30),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: isVisible
                            ? scheme.primaryContainer.withValues(alpha: 0.55)
                            : scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 排序与跨泳道操作行
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '顺位 #${index + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (panel.canMove)
                    TextButton.icon(
                      key: ValueKey<String>(
                        'kanban-panel-move-side:${panel.id}',
                      ),
                      onPressed: () => _movePanelToOtherSide(panel),
                      icon: GlyphIcon(
                        side == WorkspacePanelSide.left
                            ? AppGlyphs.chevronForward
                            : AppGlyphs.chevronBack,
                        size: 14,
                      ),
                      label: Text(
                        side == WorkspacePanelSide.left ? '移至右泳道' : '移至左泳道',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  IconButton(
                    key: ValueKey<String>('kanban-panel-up:${panel.id}'),
                    tooltip: t.settings.kanbanPanelMoveUp,
                    onPressed: index > 0
                        ? () => _movePanel(side, panel.id, -1)
                        : null,
                    icon: const GlyphIcon(AppGlyphs.arrowUp, size: 15),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(26),
                      fixedSize: const Size.square(26),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('kanban-panel-down:${panel.id}'),
                    tooltip: t.settings.kanbanPanelMoveDown,
                    onPressed: index < total - 1
                        ? () => _movePanel(side, panel.id, 1)
                        : null,
                    icon: const GlyphIcon(AppGlyphs.arrowDown, size: 15),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(26),
                      fixedSize: const Size.square(26),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        return Draggable<_PanelDragPayload>(
          data: payload,
          onDragStarted: () => setState(() => _draggingPanelId = panel.id),
          onDragEnd: (_) => setState(() => _draggingPanelId = null),
          feedback: Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: cardWidget,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: _draggingPanelId == panel.id ? 0.4 : 1.0,
            child: cardWidget,
          ),
          child: cardWidget,
        );
      },
    );
  }

  Widget _buildTrailingPanelDropZone(
    BuildContext context,
    WorkspacePanelSide side,
    int insertIndex,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragTarget<_PanelDragPayload>(
      key: ValueKey<String>('kanban-panel-tail-target:${side.name}'),
      onWillAcceptWithDetails: (details) {
        final incoming = details.data;
        if (incoming.fromSide != side && !incoming.canMoveAcrossLanes) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) {
        _arrangePanel(
          panelId: details.data.panelId,
          targetSide: side,
          insertIndex: insertIndex,
        );
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: hovering ? 40 : 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering
                ? scheme.primaryContainer.withValues(alpha: 0.45)
                : scheme.surfaceContainerLowest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovering
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            hovering ? '松手放到此泳道末尾' : '拖拽面板到此追加至末尾',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hovering ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
  });

  final Glyph icon;
  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatusTag extends StatelessWidget {
  const _MiniStatusTag({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer.withValues(alpha: 0.7)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
