import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 收藏夹卡片占位
class FavoriteCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const FavoriteCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsibleCard(
      cardId: 'favorite',
      title: '我的收藏 (Favorite)',
      icon: Icons.bookmark_added_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '128 本',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类 Chip 占位
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTagChip(context, '全部', selected: true),
                _buildTagChip(context, '默认收藏夹'),
                _buildTagChip(context, '已完结'),
                _buildTagChip(context, '追更中'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 漫画卡片列表条目
          _buildItemTile(context, '葬送的芙莉莲', '山田钟人 / 阿部司', '更新至 138 话', Icons.auto_stories),
          _buildItemTile(context, '迷宫饭', '九井谅子', '全 14 卷完结', Icons.menu_book),
          _buildItemTile(context, '电锯人', '藤本树', '更新至 192 话', Icons.import_contacts),
        ],
      ),
    );
  }

  Widget _buildTagChip(BuildContext context, String label, {bool selected = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, String title, String subtitle, String status, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              status,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 阅读历史卡片占位
class HistoryCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const HistoryCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleCard(
      cardId: 'history',
      title: '阅读历史 (History)',
      icon: Icons.history_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: Column(
        children: [
          _buildHistoryRow(context, '间谍过家家', '第 98 话 (P.14)', '10 分钟前'),
          _buildHistoryRow(context, '别当欧尼酱了！', '第 85 话 (P.22)', '昨天 21:30'),
          _buildHistoryRow(context, '孤独摇滚！', '第 4 卷 (P.45)', '3 天前'),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(BuildContext context, String title, String progress, String time) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(progress, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
          Text(time, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

/// 下载队列卡片占位
class DownloadCardPlaceholder extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const DownloadCardPlaceholder({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsibleCard(
      cardId: 'download',
      title: '离线下载 (Downloads)',
      icon: Icons.download_done_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('正在下载: 迷宫饭 第 12 卷', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('76%', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.76,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已完成 14 部 / 存储已用 3.8 GB',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
