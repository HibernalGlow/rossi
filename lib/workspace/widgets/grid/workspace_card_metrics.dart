import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_grid_layout.dart';

/// 向网格下方的卡片与子组件透传网格度量信息（单元高、断点栅格等）。
class WorkspaceCardMetrics extends InheritedWidget {
  final double unitHeight;
  final double collapsedHeight;
  final int crossAxisCount;
  final WorkspaceGridBand band;

  const WorkspaceCardMetrics({
    super.key,
    this.unitHeight = workspaceDefaultUnitHeight,
    this.collapsedHeight = workspaceCollapsedHeight,
    this.crossAxisCount = 4,
    this.band = WorkspaceGridBand.compact,
    required super.child,
  });

  static WorkspaceCardMetrics? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WorkspaceCardMetrics>();
  }

  static WorkspaceCardMetrics of(BuildContext context) {
    final metrics = maybeOf(context);
    assert(metrics != null, 'WorkspaceCardMetrics not found in context.');
    return metrics!;
  }

  /// 计算在当前网格下的目标卡片高度。
  ///
  /// 若 [isExpanded] 为 false，则固定返回紧凑折叠高度 [collapsedHeight]。
  /// 若展开，则根据跨度 [heightSpan] 与单元高 [unitHeight] 计算。
  static double heightOf(
    BuildContext context, {
    required int heightSpan,
    bool isExpanded = true,
  }) {
    final metrics = maybeOf(context);
    final collapsed = metrics?.collapsedHeight ?? workspaceCollapsedHeight;
    if (!isExpanded) {
      return collapsed;
    }
    final unit = metrics?.unitHeight ?? workspaceDefaultUnitHeight;
    final span = heightSpan.clamp(1, 4);
    return unit * span;
  }

  @override
  bool updateShouldNotify(WorkspaceCardMetrics oldWidget) {
    return unitHeight != oldWidget.unitHeight ||
        collapsedHeight != oldWidget.collapsedHeight ||
        crossAxisCount != oldWidget.crossAxisCount ||
        band != oldWidget.band;
  }
}
