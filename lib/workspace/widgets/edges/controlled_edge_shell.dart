import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/widgets/edges/edge_drawer_panel.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';
import 'package:zephyr/workspace/widgets/panels/panel_tab_strip.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_host.dart';

/// 四边栏沉浸容器：**中央还是 Reader**，四边是悬浮滑出的抽屉。
///
/// 与泳道模式共用同一份 `WorkspaceState` ——
/// 所以切模式不会重开当前这一本、不会换页，两个呈现只是同一件事的两种摆法。
/// 抽屉里的卡片是**真实数据卡片**（ObjectBox / 插件注册表 / 本地目录），
/// 不是占位图。
class ControlledEdgeShell extends StatelessWidget {
  const ControlledEdgeShell({super.key});

  static const double _drawerWidth = 350.0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final cubit = context.read<WorkspaceCubit>();
        final layout = state.layout;
        final theme = Theme.of(context);
        final target = state.readerTarget;

        return Stack(
          children: [
            // 1. 中央满屏阅读器画布
            Positioned.fill(child: WorkspaceReaderHost(target: target)),

            // 2. 左侧边缘把手
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

            // 3. 右侧边缘把手
            if (!layout.edgeRightOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildEdgeTriggerButton(
                    context,
                    icon: Icons.chevron_left_rounded,
                    tooltip: '展开图源与本地 (右侧栏)',
                    onTap: () => cubit.toggleEdgeDrawer('right'),
                  ),
                ),
              ),

            // 4. 左侧滑出抽屉：**同一套面板宿主**（图标轨 + 卡片）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: layout.edgeLeftOpen ? 0 : -_drawerWidth - 20,
              top: 0,
              bottom: 0,
              width: _drawerWidth,
              child: EdgeDrawerPanel(
                title: '左侧面板（书架）',
                icon: Icons.auto_stories_rounded,
                onClose: () => cubit.toggleEdgeDrawer('left'),
                panelTabs: const PanelTabStrip(side: WorkspacePanelSide.left),
                child: const LanePanelHost(side: WorkspacePanelSide.left),
              ),
            ),

            // 5. 右侧滑出抽屉：同一套面板宿主
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              right: layout.edgeRightOpen ? 0 : -_drawerWidth - 20,
              top: 0,
              bottom: 0,
              width: _drawerWidth,
              child: EdgeDrawerPanel(
                title: '右侧面板（发现与图源）',
                icon: Icons.tune_rounded,
                onClose: () => cubit.toggleEdgeDrawer('right'),
                panelTabs: const PanelTabStrip(side: WorkspacePanelSide.right),
                child: const LanePanelHost(side: WorkspacePanelSide.right),
              ),
            ),

            // 6. 顶部边缘浮动条（四边栏模式下模式切换的落点）
            Positioned(
              top: 12,
              left: 80,
              right: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fullscreen_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        target == null
                            ? '沉浸阅读中 · 边缘模式 (Edges)'
                            : '正在阅读 · ${target.displayTitle}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (target != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: '关闭当前漫画 (回到空态)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => cubit.closeReader(),
                        ),
                      ],
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => cubit.toggleMode(),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            '切回泳道 ➔',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.8,
            ),
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
