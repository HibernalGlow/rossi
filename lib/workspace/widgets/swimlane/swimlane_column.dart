import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';

/// 单个泳道容器：栏头（折叠 / 独占 / 宽度）+ 内容。
///
/// **栏头归泳道自己**（neoview 契约）：edge 模式那套「钉边 / 拖动 / 改尺寸」的控件
/// 在这里一律不出现；[headerActions] 是泳道往自己栏头里塞控件的口子 ——
/// 阅读器泳道就用它把模式切换放进自己的 chrome，于是 Reader 的动作永远跟着 Reader 走。
class SwimlaneColumn extends StatelessWidget {
  final String laneId;
  final LaneConfig config;

  /// 本泳道当前的实际宽度（阅读器泳道由视口比例算出，不等于 [LaneConfig.width]）。
  final double resolvedWidth;

  final bool isSolo;
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final VoidCallback? onResetWidth;

  /// 覆盖栏头标题（例如阅读器泳道显示当前书名）。
  final String? titleOverride;

  /// 栏头右侧的附加控件。**必须窄**（图标按钮级别），否则窄栏会挤压标题。
  final List<Widget> headerActions;

  final Widget? child;
  final List<Widget>? cards;

  const SwimlaneColumn({
    super.key,
    required this.laneId,
    required this.config,
    required this.resolvedWidth,
    required this.isSolo,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.titleOverride,
    this.headerActions = const <Widget>[],
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
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
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
                  laneIcon(laneId),
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),

                // 泳道标题（双击重置宽度）
                Expanded(
                  child: Tooltip(
                    message: '双击重置该栏宽度',
                    child: InkWell(
                      onDoubleTap: onResetWidth,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              titleOverride ?? config.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${resolvedWidth.toInt()}px',
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

                ...headerActions,

                // Solo 独占按钮
                IconButton(
                  icon: Icon(
                    isSolo
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                    color: isSolo
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
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
          // 泳道内容 Body
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
            icon: Icon(
              laneIcon(laneId),
              size: 18,
              color: theme.colorScheme.primary,
            ),
            tooltip: '${config.title} (点击展开泳道)',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              titleOverride ?? config.title,
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

  static IconData laneIcon(String id) {
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
