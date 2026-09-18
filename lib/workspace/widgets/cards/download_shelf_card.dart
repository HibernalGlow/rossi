import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 真实下载卡片（监听 ObjectBox 下载任务库与已下载离线统计）
class DownloadShelfCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const DownloadShelfCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 查询已下载总数
    final downloadedCount = objectbox.unifiedDownloadBox.count();

    // 监听正在下载/排队中的任务
    final queryBuilder = objectbox.downloadTaskBox
        .query()
        .order(DownloadTask_.id, flags: Order.descending);

    return CollapsibleCard(
      cardId: 'download',
      title: '下载与离线 (Downloads)',
      icon: Icons.download_done_rounded,
      isExpanded: isExpanded,
      onToggle: onToggle,
      trailing: TextButton.icon(
        onPressed: () => context.pushRoute(const DownloadTaskRoute()),
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: const Text('管理'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
      ),
      child: StreamBuilder<List<DownloadTask>>(
        stream: queryBuilder.watch(triggerImmediately: true).map((q) => q.find()),
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? [];
          final activeTasks = tasks.where((t) => t.isDownloading).toList();
          final pendingTasks = tasks.where((t) => !t.isCompleted && !t.isDownloading).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 概览统计条
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(context, '已离线漫画', '$downloadedCount 本', Icons.inventory_2_outlined),
                    Container(height: 24, width: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    _buildStatItem(context, '进行中任务', '${activeTasks.length + pendingTasks.length} 个', Icons.downloading_rounded),
                  ],
                ),
              ),

              if (activeTasks.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '正在下载',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...activeTasks.take(3).map((task) => _buildActiveTaskItem(context, task)),
              ] else if (tasks.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: Text(
                      '暂无下载任务',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, fontSize: 10)),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveTaskItem(BuildContext context, DownloadTask task) {
    final theme = Theme.of(context);
    final isDownloading = task.isDownloading;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task.comicName,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  task.status.isNotEmpty ? task.status : (isDownloading ? '下载中' : '等待中'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
