import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/cards/auxiliary_card_placeholder.dart';
import 'package:zephyr/workspace/widgets/cards/bookshelf_card_placeholder.dart';
import 'package:zephyr/workspace/widgets/cards/workspace_reader_lane.dart';
import 'package:zephyr/workspace/widgets/edges/edge_drawer_panel.dart';

/// 四边栏沉浸容器组件（全屏画板 + 四边悬浮滑出抽屉）
class ControlledEdgeShell extends StatelessWidget {
  const ControlledEdgeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final cubit = context.read<WorkspaceCubit>();
        final layout = state.layout;
        final theme = Theme.of(context);

        const drawerWidth = 350.0;

        return Stack(
          children: [
            // 1. 中央满屏内容画板 (Reader Canvas)
            Positioned.fill(
              child: WorkspaceReaderLane(
                mode: WorkspaceMode.edges,
                onToggleMode: () => cubit.toggleMode(),
              ),
            ),

            // 2. 左侧边缘把手 (当未打开时显示)
            if (!layout.edgeLeftOpen)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildEdgeTriggerButton(
                    context,
                    icon: Icons.chevron_right_rounded,
                    tooltip: '展开书架与收藏 (左侧栏)',
                    onTap: () => cubit.toggleEdgeDrawer('left'),
                  ),
                ),
              ),

            // 3. 右侧边缘把手 (当未打开时显示)
            if (!layout.edgeRightOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildEdgeTriggerButton(
                    context,
                    icon: Icons.chevron_left_rounded,
                    tooltip: '展开工具与目录 (右侧栏)',
                    onTap: () => cubit.toggleEdgeDrawer('right'),
                  ),
                ),
              ),

            // 4. 左侧滑出抽屉 (复用书架卡片)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: layout.edgeLeftOpen ? 0 : -drawerWidth - 20,
              top: 0,
              bottom: 0,
              width: drawerWidth,
              child: EdgeDrawerPanel(
                title: '书架抽屉',
                icon: Icons.auto_stories_rounded,
                onClose: () => cubit.toggleEdgeDrawer('left'),
                children: [
                  FavoriteCardPlaceholder(
                    isExpanded: state.cardExpanded['favorite'] ?? true,
                    onToggle: () => cubit.toggleCardExpanded('favorite'),
                  ),
                  HistoryCardPlaceholder(
                    isExpanded: state.cardExpanded['history'] ?? true,
                    onToggle: () => cubit.toggleCardExpanded('history'),
                  ),
                  DownloadCardPlaceholder(
                    isExpanded: state.cardExpanded['download'] ?? true,
                    onToggle: () => cubit.toggleCardExpanded('download'),
                  ),
                ],
              ),
            ),

            // 5. 右侧滑出抽屉 (复用辅助工具卡片)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              right: layout.edgeRightOpen ? 0 : -drawerWidth - 20,
              top: 0,
              bottom: 0,
              width: drawerWidth,
              child: EdgeDrawerPanel(
                title: '辅助与目录',
                icon: Icons.tune_rounded,
                onClose: () => cubit.toggleEdgeDrawer('right'),
                children: [
                  LocalTreeCardPlaceholder(
                    isExpanded: state.cardExpanded['local_tree'] ?? true,
                    onToggle: () => cubit.toggleCardExpanded('local_tree'),
                  ),
                  SystemMonitorCardPlaceholder(
                    isExpanded: state.cardExpanded['system_status'] ?? true,
                    onToggle: () => cubit.toggleCardExpanded('system_status'),
                  ),
                ],
              ),
            ),

            // 6. 顶部边缘浮动条
            Positioned(
              top: 12,
              left: 80,
              right: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fullscreen_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('沉浸阅读中 · 边缘模式 (Edges)', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => cubit.toggleMode(),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text('切回泳道 ➔', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEdgeTriggerButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 24,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 6,
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}
