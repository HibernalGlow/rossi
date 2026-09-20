import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 真实发现与插件图源卡片（读取 PluginRegistryService 已注册的图源插件）
class DiscoverPluginsCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 卡片在面板轨道上的位置动作，由宿主（面板 / 抽屉）传入。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const DiscoverPluginsCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pluginStates = context.watch<PluginRegistryCubit>().state;
    final enabledPlugins = pluginStates.values
        .where((p) => p.isEnabled)
        .toList();

    if (isStandalone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部信息操作栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.extension_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '图源与扩展',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, size: 18),
                    tooltip: '跨图源聚合搜索',
                    onPressed: () {
                      context.pushRoute(
                        SearchRoute(
                          searchState: SearchStates.initial(),
                          aggregateMode: true,
                        ),
                      );
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        context.pushRoute(const PluginStoreRoute()),
                    icon: const Icon(Icons.storefront_rounded, size: 14),
                    label: const Text('市场'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: enabledPlugins.isEmpty
                  ? Center(
                      child: Text(
                        '暂无启用的插件',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: enabledPlugins.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, indent: 44),
                      itemBuilder: (context, index) {
                        final plugin = enabledPlugins[index];
                        return _buildPluginItem(context, plugin);
                      },
                    ),
            ),
          ],
        ),
      );
    }

    return CollapsibleCard(
      cardId: 'discover_plugins',
      title: '图源与扩展 (Extensions)',
      icon: Icons.extension_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 18),
            tooltip: '跨图源聚合搜索',
            onPressed: () {
              context.pushRoute(
                SearchRoute(
                  searchState: SearchStates.initial(),
                  aggregateMode: true,
                ),
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          TextButton.icon(
            onPressed: () => context.pushRoute(const PluginStoreRoute()),
            icon: const Icon(Icons.storefront_rounded, size: 14),
            label: const Text('市场'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enabledPlugins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  '暂无启用的插件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: enabledPlugins.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 44),
              itemBuilder: (context, index) {
                final plugin = enabledPlugins[index];
                return _buildPluginItem(context, plugin);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPluginItem(BuildContext context, PluginRuntimeState plugin) {
    final theme = Theme.of(context);
    final info = PluginRegistryService.I.getCachedPluginInfo(plugin.uuid);
    final displayName = info?['name']?.toString() ?? plugin.uuid;
    final isReady = plugin.lastLoadSuccess;

    return InkWell(
      onTap: () {
        context.pushRoute(
          SearchRoute(
            searchState: SearchStates(from: plugin.uuid),
            aggregateMode: false,
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer.withValues(
                alpha: 0.6,
              ),
              child: Icon(
                _pluginIcon(plugin.uuid),
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${plugin.version.isEmpty ? "内置" : "v${plugin.version}"} · ${isReady ? "已就绪" : "正在加载"}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      // 「正在加载」用 tertiary 而不是硬编码橙色：
                      // 调色板里没有 #FF9800 这个值，深色模式下它几乎刺眼。
                      color: isReady
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () {
                context.pushRoute(
                  SearchRoute(
                    searchState: SearchStates(from: plugin.uuid),
                    aggregateMode: false,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _pluginIcon(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.contains('bika')) return Icons.filter_vintage_rounded;
    if (lower.contains('jm')) return Icons.auto_stories_rounded;
    if (lower.contains('local')) return Icons.folder_special_rounded;
    return Icons.extension_rounded;
  }
}
