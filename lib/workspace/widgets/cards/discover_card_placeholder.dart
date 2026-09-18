import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 发现/插件入口卡片占位
class DiscoverPluginsCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const DiscoverPluginsCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'discover_plugins',
      title: '图源与扩展插件 (Plugins)',
      icon: Icons.extension_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      trailing: TextButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.storefront_rounded, size: 16),
        label: const Text('插件市场'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Column(
        children: [
          _buildPluginRow(context, 'Bika 哔咔漫画', 'v1.4.2 · 已就绪', Icons.filter_vintage_rounded, Colors.pink),
          _buildPluginRow(context, 'JM 18Comic', 'v2.0.1 · 已就绪', Icons.auto_stories_rounded, Colors.orange),
          _buildPluginRow(context, 'Local 本地漫画库', '内置引擎 · 0 拷贝', Icons.folder_special_rounded, Colors.teal),
          _buildPluginRow(context, 'Copymanga 拷贝漫画', 'v1.1.0 · 运行中', Icons.menu_book_rounded, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildPluginRow(
    BuildContext context,
    String name,
    String status,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(status, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

/// 发现推荐与热门标签占位
class DiscoverExploreCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const DiscoverExploreCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'discover_tags',
      title: '分类榜单与推荐 (Explore)',
      icon: Icons.explore_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildChip(context, '🔥 热门推荐'),
          _buildChip(context, '✨ 最新收录'),
          _buildChip(context, '🏆 日排行榜'),
          _buildChip(context, '📅 连载更新'),
          _buildChip(context, '🏷️ 奇幻/冒险'),
          _buildChip(context, '🏷️ 恋爱/日常'),
          _buildChip(context, '🏷️ 科幻/悬疑'),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String text) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(text, style: theme.textTheme.labelSmall),
      onPressed: () {},
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
