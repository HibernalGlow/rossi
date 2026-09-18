import 'package:material_ui/material_ui.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/page/bookshelf/service/favorite_folder_service.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/workspace/method/open_comic_item.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';

/// 真实收藏卡片（读取本地 ObjectBox 数据库，支持分类与直达阅读）
class FavoriteShelfCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const FavoriteShelfCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  State<FavoriteShelfCard> createState() => _FavoriteShelfCardState();
}

class _FavoriteShelfCardState extends State<FavoriteShelfCard> {
  String _selectedFolderKey = kFavoriteFolderAllKey;
  List<FavoriteFolderView> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  void _loadFolders() {
    setState(() {
      _folders = FavoriteFolderService.listFolders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 监听 ObjectBox 变化流
    final queryBuilder = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.deleted.equals(false))
        .order(UnifiedComicFavorite_.updatedAt, flags: Order.descending);

    return StreamBuilder<List<UnifiedComicFavorite>>(
      stream: queryBuilder.watch(triggerImmediately: true).map((q) => q.find()),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? [];
        final totalCount = allItems.length;

        // 根据文件夹过滤
        final filteredItems = _filterByFolder(allItems, _selectedFolderKey);

        return CollapsibleCard(
          cardId: 'favorite',
          title: '我的收藏 (Favorites)',
          icon: Icons.bookmark_added_rounded,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalCount 本',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 收藏分类选择轨
              if (_folders.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _folders.map((folder) {
                      final selected = folder.key == _selectedFolderKey;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(folder.name),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedFolderKey = folder.key);
                          },
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 列表视图
              if (filteredItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      '暂无收藏漫画',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredItems.length > 20 ? 20 : filteredItems.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 46),
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return _buildFavoriteTile(context, item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<UnifiedComicFavorite> _filterByFolder(
    List<UnifiedComicFavorite> items,
    String folderKey,
  ) {
    if (folderKey == kFavoriteFolderAllKey) return items;
    final memberKeys = FavoriteFolderService.membersOf(folderKey);
    return items.where((i) => memberKeys.contains(i.uniqueKey)).toList();
  }

  Widget _buildFavoriteTile(BuildContext context, UnifiedComicFavorite item) {
    final theme = Theme.of(context);

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
            // 漫画信息
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.source.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.creator.isEmpty ? '未知作者' : item.creator,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
              color: theme.colorScheme.outline,
              onPressed: () => _open(context, item),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开收藏条目。本地来源与插件来源的分岔在 [openComicItem] 里统一处理 ——
  /// 这里曾经无条件推详情页，本地漫画会被当成「插件 id = local」而加载失败。
  void _open(BuildContext context, UnifiedComicFavorite item) {
    openComicItem(context, comicId: item.comicId, from: item.source);
  }
}
