import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/panel_switcher_tabs.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';

/// 将泳道的业务操作传给公共切换条；不另实现选中态或动画。
class WorkspacePanelTabs extends StatelessWidget {
  const WorkspacePanelTabs({
    super.key,
    required this.panels,
    required this.activeId,
    required this.onSelected,
    required this.onHide,
    this.vertical = false,
    this.canRightClickHide = true,
  });

  final List<WorkspacePanelDefinition> panels;
  final String? activeId;
  final ValueChanged<WorkspacePanelDefinition> onSelected;
  final ValueChanged<WorkspacePanelDefinition> onHide;
  final bool vertical;

  /// 「右键图标 = 收起这块面板」要不要生效（见
  /// `WorkspaceInteractionSettings.panelTabRightClickHide`，设置页那颗开关）。
  ///
  /// 关掉时**手势不挂**、tooltip 也不提「右键收起」：留着一句做不到的承诺，
  /// 比不写更难解释 —— 用户会以为是自己点歪了。
  final bool canRightClickHide;

  @override
  Widget build(BuildContext context) {
    if (panels.isEmpty) return const SizedBox.shrink();
    final selected = panels.indexWhere((panel) => panel.id == activeId);
    return PanelSwitcherTabs(
      appearance: PanelSwitcherAppearance.icons,
      axis: vertical ? Axis.vertical : Axis.horizontal,
      selectedIndex: selected < 0 ? 0 : selected,
      onSelected: (index) => onSelected(panels[index]),
      items: [
        for (final panel in panels)
          PanelSwitcherItem(
            label: panel.title,
            tooltip:
                '${panel.title}'
                '${panel.canMove ? '（编辑布局后长按排序 / 换泳道）' : ''}'
                '${panel.canHide && canRightClickHide ? '　右键收起' : ''}',
            onSecondaryTap: panel.canHide && canRightClickHide
                ? () => onHide(panel)
                : null,
            child: SizedBox(
              width: PanelSwitcherTabs.iconSize,
              height: PanelSwitcherTabs.iconSize,
              child: GlyphIcon(
                panel.icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
