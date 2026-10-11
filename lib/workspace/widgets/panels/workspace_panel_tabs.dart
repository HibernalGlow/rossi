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
  });

  final List<WorkspacePanelDefinition> panels;
  final String? activeId;
  final ValueChanged<WorkspacePanelDefinition> onSelected;
  final ValueChanged<WorkspacePanelDefinition> onHide;
  final bool vertical;

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
                '${panel.canHide ? '　右键收起' : ''}',
            onSecondaryTap: panel.canHide ? () => onHide(panel) : null,
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
