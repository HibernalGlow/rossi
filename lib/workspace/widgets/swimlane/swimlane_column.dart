import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';

/// 增强版单个泳道容器组件（支持完整复用嵌入子页面、微调宽度、Solo、折叠紧凑轨）
class SwimlaneColumn extends StatelessWidget {
  final String laneId;
  final LaneConfig config;
  final bool isSolo;
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final ValueChanged<double>? onWidthChange;
  final VoidCallback? onResetWidth;
  final Widget? child;
  final List<Widget>? cards;

  const SwimlaneColumn({
    super.key,
    required this.laneId,
    required this.config,
    required this.isSolo,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onWidthChange,
    this.onResetWidth,
    this.child,
    this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 折叠状态（紧凑 44dp 轨）
    if (config.collapsed && !isSolo) {
      return _buildCollapsedRail(context, theme);
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 泳道 Header 工具栏
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSolo
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _laneIcon(laneId),
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                // 泳道标题（双击可重置宽度）
                Expanded(
                  child: Tooltip(
                    message: '双击重置该栏宽度',
                    child: InkWell(
                      onDoubleTap: onResetWidth,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              config.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${config.width.toInt()}px',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Solo 独占按钮
                IconButton(
                  icon: Icon(
                    isSolo ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    size: 20,
                    color: isSolo ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: isSolo ? '退出独占 (Exit Solo)' : '独占该栏 (Solo 聚焦)',
                  onPressed: onToggleSolo,
                  visualDensity: VisualDensity.compact,
                ),
                // 折叠泳道按钮
                IconButton(
                  icon: const Icon(Icons.vertical_align_center_rounded, size: 18),
                  tooltip: '折叠为紧凑条 (Collapse)',
                  onPressed: onToggleCollapse,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 泳道内容 Body (优先使用嵌入的原生页面，支持自虚拟化滚动)
          Expanded(
            child: child ??
                ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: cards ?? const [],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedRail(BuildContext context, ThemeData theme) {
    return Container(
      width: WorkspaceLayoutConfig.collapsedLaneWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          IconButton(
            icon: Icon(_laneIcon(laneId), size: 18, color: theme.colorScheme.primary),
            tooltip: '${config.title} (点击展开泳道)',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              config.title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.unfold_more_rounded, size: 16),
            tooltip: '展开泳道',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _laneIcon(String id) {
    switch (id) {
      case LaneId.left:
        return Icons.menu_book_rounded;
      case LaneId.reader:
        return Icons.auto_stories_rounded;
      case LaneId.right:
        return Icons.explore_rounded;
      default:
        return Icons.view_column_rounded;
    }
  }
}
