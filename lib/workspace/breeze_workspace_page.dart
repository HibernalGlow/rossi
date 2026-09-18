import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/widgets/edges/controlled_edge_shell.dart';
import 'package:zephyr/workspace/widgets/swimlane/swimlane_workspace.dart';

@RoutePage()
class BreezeWorkspacePage extends StatelessWidget {
  const BreezeWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WorkspaceCubit(),
      child: const _BreezeWorkspaceView(),
    );
  }
}

class _BreezeWorkspaceView extends StatelessWidget {
  const _BreezeWorkspaceView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final cubit = context.read<WorkspaceCubit>();
        final isSwimlane = state.mode == WorkspaceMode.swimlane;

        return Scaffold(
          appBar: isSwimlane
              ? AppBar(
                  titleSpacing: 16,
                  title: Row(
                    children: [
                      Icon(Icons.dashboard_customize_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        '工作台原型 (NeoView Workspace)',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 24),
                      // 模式互斥切换分段按钮
                      SegmentedButton<WorkspaceMode>(
                        segments: const [
                          ButtonSegment<WorkspaceMode>(
                            value: WorkspaceMode.swimlane,
                            icon: Icon(Icons.view_column_rounded),
                            label: Text('多列泳道'),
                          ),
                          ButtonSegment<WorkspaceMode>(
                            value: WorkspaceMode.edges,
                            icon: Icon(Icons.fullscreen_rounded),
                            label: Text('沉浸四边栏'),
                          ),
                        ],
                        selected: {state.mode},
                        onSelectionChanged: (selected) {
                          cubit.setMode(selected.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: '重置布局 (Reset)',
                      icon: const Icon(Icons.restore_rounded),
                      onPressed: () => cubit.resetLayout(),
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : null,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isSwimlane
                ? const SwimlaneWorkspace(key: ValueKey('swimlane'))
                : const ControlledEdgeShell(key: ValueKey('edges')),
          ),
        );
      },
    );
  }
}
