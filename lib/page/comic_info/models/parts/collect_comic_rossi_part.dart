part of '../collect_comic.dart';
// rossi


/// 确保漫画已添加到本地收藏；若未收藏则将其添加，并根据全局配置联动自动追更。
/// 返回 true 表示新添加了收藏，false 表示此前已收藏。
Future<bool> ensureLocalComicCollected({
  required String from,
  required NormalComicAllInfo normalInfo,
  BuildContext? context,
  ComicFollowCubit? followCubit,
}) async {
  final comicInfo = normalInfo.comicInfo;
  final pluginId = (from).trim();
  final key = '$pluginId:${comicInfo.id}';
  final unified = objectbox.unifiedFavoriteBox
      .query(UnifiedComicFavorite_.uniqueKey.equals(key))
      .build()
      .findFirst();

  if (unified != null && unified.deleted == false) {
    return false;
  }

  final now = DateTime.now().toUtc();
  final createdAt = unified?.createdAt ?? now;
  final coverMap = _comicImageToMap(comicInfo.cover);

  objectbox.unifiedFavoriteBox.put(
    UnifiedComicFavorite(
      id: unified?.id ?? 0,
      uniqueKey: key,
      source: pluginId,
      comicId: comicInfo.id,
      title: comicInfo.title,
      description: comicInfo.description,
      cover: jsonEncode(coverMap),
      creator: jsonEncode(_creatorToMap(comicInfo.creator)),
      titleMeta: jsonEncode(comicInfo.titleMeta.map(_titleMetaToMap).toList()),
      metadata: jsonEncode(comicInfo.metadata.map(_metadataToMap).toList()),
      createdAt: createdAt,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    ),
  );

  ComicLinkService.addComic(key, null, ComicFolderType.favorite);

  // 联动自动追更
  try {
    final autoFollow =
        objectbox.userSettingBox.get(1)?.globalSetting.autoFollowOnCollect ??
        false;
    final cubit =
        followCubit ??
        (context != null && context.mounted
            ? () {
                try {
                  return context.read<ComicFollowCubit>();
                } catch (_) {
                  return null;
                }
              }()
            : null);
    if (autoFollow && cubit != null) {
      if (!cubit.isFollowing(pluginId, comicInfo.id)) {
        await cubit.addOrUpdateFollow(
          source: pluginId,
          comicId: comicInfo.id,
          info: normalInfo,
          lastChapterCount: normalInfo.eps.length,
        );
      }
    }
  } catch (e) {
    logger.w('联动自动追更失败: $e');
  }

  return true;
}


/// 当开启了“点击下载自动收藏”时，在下载时自动将漫画加入本地收藏。
Future<void> autoFavoriteComicOnDownloadIfEnabled({
  required String from,
  required String comicId,
  dynamic comicInfo,
  BuildContext? context,
  ComicFollowCubit? followCubit,
}) async {
  final enabled =
      objectbox.userSettingBox.get(1)?.globalSetting.autoFavoriteOnDownload ??
      false;
  if (!enabled) return;

  final cubit =
      followCubit ??
      (context != null && context.mounted
          ? () {
              try {
                return context.read<ComicFollowCubit>();
              } catch (_) {
                return null;
              }
            }()
          : null);

  NormalComicAllInfo? normalInfo;
  if (comicInfo is PluginComicDetailSource) {
    normalInfo = comicInfo.normalInfo;
  } else if (comicInfo is NormalComicAllInfo) {
    normalInfo = comicInfo;
  }

  if (normalInfo == null) {
    try {
      final detail = await getComicDetailByPlugin(
        comicId,
        from,
        pluginId: from,
      );
      normalInfo = detail.normalInfo;
    } catch (e) {
      logger.w('autoFavoriteComicOnDownloadIfEnabled 获取详情失败: $e');
      return;
    }
  }

  final added = await ensureLocalComicCollected(
    from: from,
    normalInfo: normalInfo,
    followCubit: cubit,
  );
  if (added) {
    showSuccessToast(t.reader.autoCollectedToast);
  }
}
