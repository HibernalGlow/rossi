import 'package:material_ui/material_ui.dart';

/// 面板泳道里的一个面板。
class PanelLaneEntry {
  final String id;
  final IconData icon;
  final String tooltip;
  final WidgetBuilder builder;

  const PanelLaneEntry({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.builder,
  });
}

/// **面板泳道**：左侧一条 44px 图标轨 + 右侧当前面板。
///
/// 对齐 neoview 的面板泳道契约：
/// - 面板**按需构建、构建后保活**（`IndexedStack` + 首次访问才建）——
///   切走再切回来不重跑上游页面的加载，也不丢它们的滚动位置；
/// - 每条泳道**各自记自己的激活面板**，两条泳道的选择互不影响；
/// - 泳道只负责宿主几何，面板本身是完整的上游页面 / 卡片。
class EmbeddedPanelLane extends StatefulWidget {
  const EmbeddedPanelLane({
    super.key,
    required this.panels,
    required this.activePanelId,
    required this.onSelect,
  });

  final List<PanelLaneEntry> panels;
  final String activePanelId;
  final ValueChanged<String> onSelect;

  @override
  State<EmbeddedPanelLane> createState() => _EmbeddedPanelLaneState();
}

class _EmbeddedPanelLaneState extends State<EmbeddedPanelLane> {
  /// 已经访问过的面板 —— 只有访问过的才真正被构建（其余留空占位）。
  final Set<String> _visited = <String>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.activePanelId);
  }

  @override
  void didUpdateWidget(covariant EmbeddedPanelLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.activePanelId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panels.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    var index = widget.panels.indexWhere((p) => p.id == widget.activePanelId);
    if (index < 0) index = 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 44,
          color: theme.colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (final panel in widget.panels)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: IconButton(
                    icon: Icon(
                      panel.icon,
                      size: 18,
                      color: panel.id == widget.activePanelId
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: panel.tooltip,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: panel.id == widget.activePanelId
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.35,
                            )
                          : null,
                    ),
                    onPressed: () => widget.onSelect(panel.id),
                  ),
                ),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(
          child: IndexedStack(
            index: index,
            sizing: StackFit.expand,
            children: [
              for (final panel in widget.panels)
                if (_visited.contains(panel.id))
                  panel.builder(context)
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
