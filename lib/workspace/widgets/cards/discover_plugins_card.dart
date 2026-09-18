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

  const DiscoverPluginsCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pluginStates = context.watch<PluginRegistryCubit>().state;
    final enabledPlugins = pluginStates.values.where((p) => p.isEnabled).toList();

    return CollapsibleCard(
      cardId: 'discover_plugins',
      title: '图源与扩展 (Extensions)',
      icon: Icons.extension_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
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
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: enabledPlugins.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 44),
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
              backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
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
                      color: isReady ? theme.colorScheme.outline : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              color: theme.colorScheme.outline,
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
