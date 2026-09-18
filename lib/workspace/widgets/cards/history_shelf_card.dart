import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 真实阅读历史卡片（读取本地 ObjectBox 数据库，支持一键继续阅读）
class HistoryShelfCard extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 卡片在面板轨道上的位置动作，由宿主（面板 / 抽屉）传入。
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;

  const HistoryShelfCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 监听 ObjectBox 变化流
    final queryBuilder = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.deleted.equals(false))
        .order(UnifiedComicHistory_.lastReadAt, flags: Order.descending);

    return StreamBuilder<List<UnifiedComicHistory>>(
      stream: queryBuilder.watch(triggerImmediately: true).map((q) => q.find()),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];

        return CollapsibleCard(
          cardId: 'history',
          title: '阅读历史 (History)',
          icon: Icons.history_rounded,
          isExpanded: isExpanded,
          onToggle: onToggle,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onHide: onHide,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${items.length} 条',
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      '暂无阅读历史',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length > 15 ? 15 : items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 46),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildHistoryTile(context, item);
                  },
                ),
        );
      },
    );
  }

  Widget _buildHistoryTile(BuildContext context, UnifiedComicHistory item) {
    final theme = Theme.of(context);

    final progressText = item.chapterTitle.isNotEmpty
        ? '${item.chapterTitle} · P.${item.pageIndex + 1}'
        : '第 ${item.pageIndex + 1} 页';

    final timeAgo = _formatTimeAgo(item.lastReadAt);

    return InkWell(
      onTap: () => _open(context, item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            // 封面缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 38,
                height: 50,
                child: CoverWidget(
                  fileServer: '',
                  path: item.cover,
                  id: item.comicId,
                  pictureType: PictureType.cover,
                  from: item.source,
                  width: 38,
                  height: 50,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 历史进度
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.bookmark_outline_rounded, size: 12, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          progressText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeAgo,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
              color: theme.colorScheme.primary,
              tooltip: '继续阅读',
              onPressed: () => _open(context, item),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开历史条目。本地来源与插件来源的分岔在 [openComicItem] 里统一处理 ——
  /// 这里曾经无条件推详情页，本地漫画会被当成「插件 id = local」而加载失败。
  void _open(BuildContext context, UnifiedComicHistory item) {
    openComicItem(context, comicId: item.comicId, from: item.source);
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}月${time.day}日';
  }
}
