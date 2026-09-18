import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/widgets/cards/discover_plugins_card.dart';
import 'package:zephyr/workspace/widgets/cards/local_folder_card.dart';

/// 面板泳道的「图源与本地」面板：两个**真实**卡片，不是整页复用。
///
/// 与另外两块面板的分工：`DiscoverPage` 负责浏览与热搜，
/// `MorePage` 负责设置；这里负责「图源装了什么 / 本地这份在哪」这类
/// 一看一动的操作。三者都用上游既有组件，本层不含业务实现。
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    final expanded = context.select(
      (WorkspaceCubit c) => c.state.cardExpanded,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      children: [
        DiscoverPluginsCard(
          isExpanded: expanded['discover_plugins'] ?? true,
          onToggle: () => cubit.toggleCardExpanded('discover_plugins'),
        ),
        LocalFolderCard(
          isExpanded: expanded['local_folder'] ?? true,
          onToggle: () => cubit.toggleCardExpanded('local_folder'),
        ),
      ],
    );
  }
}
