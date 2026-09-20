import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/util/comic/comic_card_badge_policy.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';

class ComicEntryWidget extends StatelessWidget {
  const ComicEntryWidget({
    super.key,
    required this.comic,
    this.type = ComicEntryType.normal,
    this.refresh,
    this.pictureType,
  });

  final UnifiedComicListItem comic;
  final ComicEntryType type;
  final VoidCallback? refresh;
  final PictureType? pictureType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const coverWidth = 100.0;
    const coverHeight = 133.0;
    final statText = _buildStatText();
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final favoriteSetting = globalSetting.favoriteArtistSetting;
    final buckets = comic.favoriteArtistBuckets;
    final matchResult = favoriteSetting.highlightEnabled
        ? FavoriteArtistMatcher.match(
            title: comic.title,
            artistTags: buckets.artistTags,
            circleTags: buckets.circleTags,
            favoriteArtists: favoriteSetting.artists,
            circleMode: favoriteSetting.circleMode,
          )
        : null;
    final isFavoriteArtist = matchResult?.isMatched ?? false;
    // 与封面卡片共用同一对闸门（书架 → 卡片角标、内容 → 收藏 tag 高亮），
    // 判断本身交给 `ComicCardBadgePolicy`，免得行与卡片两处各写一份而漂移。
    final favoriteTagSetting = globalSetting.favoriteTagSetting;
    // 与卡片那边 `ComicSimplifyEntryInfo.tags` 同一份口径（压平的所有分桶值 +
    // 副标题），否则同一本在列表里高亮、在网格里不高亮。
    final tagCandidates = <String>[
      for (final group in comic.metadata)
        ...group.value.map((v) => v.toString()),
      if (comic.subtitle.trim().isNotEmpty) comic.subtitle.trim(),
    ];
    final tagMatchResult =
        ComicCardBadgePolicy(
          favoriteTagBadgeEnabled:
              globalSetting.comicCardSetting.favoriteTagBadgeEnabled,
        ).showFavoriteTagBadge(
          highlightEnabled: favoriteTagSetting.highlightEnabled,
        )
        ? FavoriteTagMatcher.match(
            tags: tagCandidates,
            title: comic.title,
            favoriteTags: favoriteTagSetting.tags,
          )
        : FavoriteTagMatchResult.notMatched;
    final isFavoriteTag = tagMatchResult.isMatched;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isLocalComicSource(comic.from, comic.id)) {
          context.pushRoute(
            ComicReadRoute(
              comicId: comic.id,
              order: 0,
              from: 'local',
              epsNumber: 1,
              type: type == ComicEntryType.normal
                  ? ComicEntryType.normal
                  : ComicEntryType.history,
              comicInfo: comic.id,
              stringSelectCubit: StringSelectCubit(),
            ),
          );
          return;
        }
        // 发现页的标签体系里：详情开成**一条标签**，而不是压住标签条的一页。
        // 书架、工作台别的泳道里 `maybeOf` 返回 null，行为逐字不变。
        final tabs = DiscoverTabScope.maybeOf(context);
        if (tabs != null) {
          tabs.openComicInfo(
            comicId: comic.id,
            from: comic.from,
            title: comic.title,
          );
          return;
        }
        context.pushRoute(
          ComicInfoRoute(comicId: comic.id, type: type, from: comic.from),
        );
      },
      onLongPress: type == ComicEntryType.normal
          ? null
          : () => _showDeleteDialog(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isFavoriteArtist || isFavoriteTag)
                ? const Color(0xFFF59E0B)
                : theme.colorScheme.outlineVariant,
            width: (isFavoriteArtist || isFavoriteTag) ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  CoverWidget(
                    fileServer: comic.cover.url,
                    path: comic.cover.cachePath,
                    id: comic.id,
                    pictureType: pictureType ?? PictureType.cover,
                    from: comic.from,
                    roundedCorner: false,
                    width: coverWidth,
                    height: coverHeight,
                  ),
                  if (isFavoriteArtist || isFavoriteTag)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFavoriteArtist)
                            FavoriteArtistBadge(
                              artistName: matchResult?.matchedName,
                            ),
                          if (isFavoriteTag) ...[
                            if (isFavoriteArtist) const SizedBox(height: 4),
                            FavoriteTagBadge(tagName: tagMatchResult.label),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: coverHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comic.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (comic.primaryText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              comic.primaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          if (comic.secondaryText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              comic.secondaryText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (comic.updatedAtText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              t.comicEntry.updatedAt(time: comic.updatedAtText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            comic.finished
                                ? t.comicEntry.finished
                                : t.comicEntry.ongoing,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: comic.finished
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (statText.isNotEmpty)
                            Text(
                              statText,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatText() {
    final stats = <String>[];
    if (comic.likesCount > 0) {
      stats.add(t.comicEntry.likes(count: comic.likesCount));
    }
    if (comic.viewsCount > 0) {
      stats.add(t.comicEntry.views(count: comic.viewsCount));
    }
    return stats.join('  ');
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final (title, content) = _dialogContent();
    if (title.isEmpty) {
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () async {
              dialogContext.pop();
              await _handleDelete();
            },
            child: Text(t.common.ok),
          ),
        ],
      ),
    );
  }

  (String, String) _dialogContent() {
    return switch (type) {
      ComicEntryType.favorite => (
        t.comicEntry.deleteFavorite,
        t.comicEntry.deleteFavoriteConfirm(title: comic.title),
      ),
      ComicEntryType.history => (
        t.comicEntry.deleteHistory,
        t.comicEntry.deleteHistoryConfirm(title: comic.title),
      ),
      ComicEntryType.download => (
        t.comicEntry.deleteDownload,
        t.comicEntry.deleteDownloadConfirm(title: comic.title),
      ),
      _ => ('', ''),
    };
  }

  Future<void> _handleDelete() async {
    try {
      if (type == ComicEntryType.favorite) {
        await _deleteFavorite();
      } else if (type == ComicEntryType.history) {
        await _deleteHistory();
      } else if (type == ComicEntryType.download) {
        await _deleteDownload();
      }
      refresh?.call();
    } catch (e, s) {
      logger.e('删除失败', error: e, stackTrace: s);
      showErrorToast(t.comicEntry.deleteFailed);
    }
  }

  Future<void> _deleteFavorite() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    final temp = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      temp.deleted = true;
      temp.updatedAt = DateTime.now().toUtc();
      objectbox.unifiedFavoriteBox.put(temp);
    }
  }

  Future<void> _deleteHistory() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    final temp = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      temp.deleted = true;
      temp.updatedAt = DateTime.now().toUtc();
      temp.lastReadAt = temp.updatedAt;
      objectbox.unifiedHistoryBox.put(temp);
    }
  }

  Future<void> _deleteDownload() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    final temp = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      objectbox.unifiedDownloadBox.remove(temp.id);
    }

    await _deleteDownloadDirectory();
  }

  Future<void> _deleteDownloadDirectory() async {
    await deleteComicDownloadDirectory(comic.from, comic.id);
  }
}
