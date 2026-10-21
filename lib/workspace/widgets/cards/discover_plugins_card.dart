import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/source_visibility.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

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
    final enabledPlugins = filterRestrictedPlugins(
      pluginStates.values.where((p) => p.isEnabled),
      showRestricted: context
          .watch<GlobalSettingCubit>()
          .state
          .showRestrictedSources,
    ).toList();

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
                  GlyphIcon(
                    AppGlyphs.puzzle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.workspace.imageSources,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const GlyphIcon(AppGlyphs.search, size: 18),
                    tooltip: t.workspace.aggregateSourceSearch,
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
                    icon: const GlyphIcon(AppGlyphs.storefront, size: 14),
                    label: Text(t.workspace.market),
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
                        t.workspace.noEnabledPlugins,
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
      expressive: true,
      title: t.workspace.imageSourcesEn,
      icon: AppGlyphs.puzzle,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const GlyphIcon(AppGlyphs.search, size: 18),
            tooltip: t.workspace.aggregateSourceSearch,
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
            icon: const GlyphIcon(AppGlyphs.storefront, size: 14),
            label: Text(t.workspace.market),
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
                  t.workspace.noEnabledPlugins,
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
              child: GlyphIcon(
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
                    '${plugin.version.isEmpty ? t.workspace.builtinWord : "v${plugin.version}"} · ${isReady ? t.workspace.gpuReadyState : t.workspace.loadingShort}',
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
              icon: const GlyphIcon(AppGlyphs.chevronForward, size: 14),
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

  Glyph _pluginIcon(String uuid) {
    final lower = uuid.toLowerCase();
    if (lower.contains('bika')) return AppGlyphs.sparkle;
    if (lower.contains('jm')) return AppGlyphs.openBook;
    if (lower.contains('local')) return AppGlyphs.folder;
    return AppGlyphs.puzzle;
  }
}
