import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/cards/plugin_status_card.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/icons/icons.dart';

/// 图源快捷入口卡 —— 一格一个插件，点开直接进那个图源的搜索。
///
/// 与「发现」整页的分工：整页要自己翻标签找图源，这张卡把**已启用**的插件
/// 摊平成一眼可选的格子。只列 `isEnabled && !isDeleted` 的那些 ——
/// 未启用的插件点了必然报错，画出来是骗人。
///
/// 三颗常驻入口（聚合搜索 / 插件市场 / 图源扩展面板）不依赖有没有插件，
/// 所以空态下也照样能点。
class PluginShortcutsCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const PluginShortcutsCard({
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
    final plugins =
        context
            .watch<PluginRegistryCubit>()
            .state
            .values
            .where((p) => p.isActive)
            .toList()
          ..sort((a, b) {
            final order = (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0);
            return order != 0 ? order : _nameOf(a).compareTo(_nameOf(b));
          });

    return CollapsibleCard(
      cardId: 'plugin_shortcuts',
      title: '图源快捷入口',
      icon: AppGlyphs.apps,
      expressive: true,
      isExpanded: isExpanded,
      onToggle: onToggle,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onHide: onHide,
      trailing: ExpressiveStatusPill(
        text: '${plugins.length} 个图源',
        dot: false,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpressiveTileGrid(
            minTileWidth: 108,
            children: [
              _ShortcutTile(
                label: '聚合搜索',
                caption: '全部图源',
                icon: AppGlyphs.search,
                tone: ExpressiveTone.primary,
                onTap: () => context.pushRoute(
                  SearchRoute(
                    searchState: SearchStates.initial(),
                    aggregateMode: true,
                  ),
                ),
              ),
              _ShortcutTile(
                label: '插件市场',
                caption: '装新图源',
                icon: AppGlyphs.storefront,
                tone: ExpressiveTone.secondary,
                onTap: () => context.pushRoute(const PluginStoreRoute()),
              ),
              for (final plugin in plugins)
                _ShortcutTile(
                  label: _nameOf(plugin),
                  caption: _subtitle(plugin),
                  icon: pluginIcon(plugin.uuid),
                  onTap: () => context.pushRoute(
                    SearchRoute(
                      searchState: SearchStates(from: plugin.uuid),
                      aggregateMode: false,
                    ),
                  ),
                ),
            ],
          ),
          if (plugins.isEmpty) ...[
            const SizedBox(height: 12),
            const ExpressiveEmptyState(
              icon: AppGlyphs.apps,
              text: '没有已启用的图源',
              hint: '上面三颗入口仍然可用：装一个图源后这里会一格一个列出来',
            ),
          ],
        ],
      ),
    );
  }

  static String _nameOf(PluginRuntimeState plugin) {
    final info = PluginRegistryService.I.getCachedPluginInfo(plugin.uuid);
    return info?['name']?.toString().trim() ?? plugin.uuid;
  }

  static String _subtitle(PluginRuntimeState plugin) {
    if (plugin.debug) return '调试源';
    return plugin.version.isEmpty ? '内置' : 'v${plugin.version}';
  }
}

/// 一格快捷入口：cookie 图标座 + 名字 + 一句副标题，整格可点。
class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.caption,
    this.tone = ExpressiveTone.neutral,
  });

  final String label;
  final Glyph icon;
  final VoidCallback onTap;
  final String? caption;
  final ExpressiveTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 常驻入口带一档 container 色，插件格子走中性底 —— 一眼分得清哪三颗是系统给的。
    final tones = expressiveToneColors(scheme, tone);
    final tinted = tone != ExpressiveTone.neutral;
    final foreground = tinted ? tones.onContainer : scheme.onSurface;
    final captionColor = tinted ? tones.onContainer : scheme.onSurfaceVariant;

    return ExpressiveTile(
      onTap: onTap,
      color: tones.container,
      radius: expressiveCornerMd,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      semanticLabel: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpressiveIconBadge(
            icon: icon,
            size: 30,
            color: scheme.primary.withValues(alpha: tinted ? .2 : .12),
            foreground: tinted ? foreground : scheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: captionColor.withValues(alpha: .8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
