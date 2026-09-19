import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/object_box/objectbox.g.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';
import 'package:zephyr/util/comic/comic_card_badge_policy.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_download_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_translation_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

const double kComicCardBorderRadius = 5.0;

class FavoriteArtistBadge extends StatelessWidget {
  final String? artistName;

  const FavoriteArtistBadge({super.key, this.artistName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24), // #fbbf24
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '♥',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            artistName?.isNotEmpty == true
                ? artistName!
                : t.settings.favoriteArtistBadge,
            style: const TextStyle(
              color: Color(0xFF451A03), // #451a03
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class ComicFixedSizeHorizontalList extends StatelessWidget {
  final List<ComicSimplifyEntryInfo> entries;
  final double spacing; // 卡片之间的横向间距
  final double itemWidth; // 卡片固定宽度
  final bool roundedCorner; // 是否有圆角
  final bool useRandomImageKey;

  /// 封面左上角是否显示语言 / 汉化角标。默认开。
  ///
  /// 这是**页面级**开关；用户的**总开关**在「设置 → 书架 → 卡片角标」，
  /// 两者是「与」的关系（见 [ComicCardBadgePolicy]）。
  final bool showTranslationBadge;

  /// 封面右上角是否显示下载角标。默认开。语义同 [showTranslationBadge]。
  final bool showDownloadAction;

  const ComicFixedSizeHorizontalList({
    super.key,
    required this.entries,
    this.spacing = 10.0, // 默认间距设为 10
    this.itemWidth = 200, // 固定宽度，不随窗口宽高比变化
    this.roundedCorner = true,
    this.useRandomImageKey = false,
    this.showTranslationBadge = true,
    this.showDownloadAction = true,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    // 使用固定的宽高，避免在 Windows 桌面端拖动窗口时因
    // MediaQuery.orientation 随宽高比切换而导致高度跳变
    final double itemHeight = itemWidth / 0.75;

    // 最外层需要限制高度，否则横向 ListView 会报错
    return SizedBox(
      height: itemHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final info = entries[index];

          // 过滤无数据的情况
          if (info.title == "无数据") {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: EdgeInsets.only(right: spacing),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _navigateToComicInfo(context, info),
              child: SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _buildCoverWithTitle(
                  context,
                  info,
                  itemWidth,
                  itemHeight,
                  useRandomImageKey
                      ? ValueKey('cover-${const Uuid().v4()}')
                      : ValueKey('cover-${info.from}:${info.id}:${info.path}'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCoverWithTitle(
    BuildContext context,
    ComicSimplifyEntryInfo info,
    double width,
    double height,
    Key coverKey,
  ) {
    final circular = roundedCorner
        ? themeRadius(context, fallback: kComicCardBorderRadius)
        : 0.0;
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    final badgePolicy = ComicCardBadgePolicy(
      downloadBadgeEnabled: globalSetting.comicCardSetting.downloadBadgeEnabled,
      translationBadgeEnabled:
          globalSetting.comicCardSetting.translationBadgeEnabled,
    );
    // 本地漫画本来就在盘上，不给下载角标。
    final showDownloadBadge = badgePolicy.showDownloadBadge(
      pluginId: pluginId,
      comicId: info.id,
      cardEnabled: showDownloadAction,
    );
    final favoriteSetting = globalSetting.favoriteArtistSetting;
    final matchResult = favoriteSetting.highlightEnabled
        ? FavoriteArtistMatcher.match(
            title: info.title,
            tags: info.tags,
            favoriteArtists: favoriteSetting.artists,
          )
        : null;
    final isFavoriteArtist = matchResult?.isMatched ?? false;
    final canShowTranslation = badgePolicy.showTranslationBadge(
      cardEnabled: showTranslationBadge,
    );
    final translationMatch = canShowTranslation
        ? ChineseTranslationMatcher.match(title: info.title, tags: info.tags)
        : ChineseTranslationMatch.none;

    return ClipRRect(
      borderRadius: BorderRadius.circular(circular),
      child: Container(
        foregroundDecoration: isFavoriteArtist
            ? BoxDecoration(
                border: Border.all(color: const Color(0xFFF59E0B), width: 2.5),
                borderRadius: BorderRadius.circular(circular),
              )
            : null,
        child: Stack(
          children: [
            // 1. 底层封面图
            CoverWidget(
              key: coverKey,
              fileServer: info.fileServer,
              path: info.path,
              id: info.id,
              pictureType: info.pictureType,
              from: info.from,
              roundedCorner: roundedCorner,
              width: width,
              height: height,
            ),
            if (showDownloadBadge)
              Positioned(
                top: 6,
                right: 6,
                child: ComicDownloadBadge(
                  from: pluginId,
                  comicId: info.id,
                  title: info.title,
                  size: width < 110 ? 24 : 28,
                ),
              ),
            if (canShowTranslation && translationMatch.hasBadge)
              Positioned(
                top: 6,
                left: 6,
                child: ComicTranslationBadge(
                  match: translationMatch,
                  compact: width < 110,
                ),
              ),

            // 2. 顶部阴影与标题
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.7],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(circular),
                    bottomRight: Radius.circular(circular),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(5.0, 20.0, 5.0, 5.0),
                child: Text(
                  info.title.let(convertChineseForDisplay),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 点击跳转逻辑 (需要把当前的 info 传进来)
  void _navigateToComicInfo(BuildContext context, ComicSimplifyEntryInfo info) {
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    if (pluginId.isEmpty) return;
    if (isLocalComicSource(pluginId, info.id)) {
      context.pushRoute(
        ComicReadRoute(
          comicId: info.id,
          order: 0,
          from: 'local',
          epsNumber: 1,
          type: ComicEntryType.history,
          comicInfo: info.id,
          stringSelectCubit: StringSelectCubit(),
        ),
      );
      return;
    }
    context.pushRoute(
      ComicInfoRoute(
        comicId: info.id,
        type: ComicEntryType.normal,
        from: pluginId,
      ),
    );
  }
}

class ComicSimplifyEntry extends StatelessWidget {
  final ComicSimplifyEntryInfo info;
  final ComicEntryType type;
  final VoidCallback? refresh;
  final ValueChanged<String>? onDeleteSuccess;
  final ValueChanged<ComicSimplifyEntryInfo>? onTapOverride;
  final void Function(
    ComicSimplifyEntryInfo info,
    LongPressStartDetails details,
  )?
  onLongPressOverride;
  final void Function(ComicSimplifyEntryInfo info, TapDownDetails details)?
  onSecondaryTapDown;
  final bool isSelected;
  final bool selectionMode;
  final bool topPadding;
  final bool roundedCorner;

  /// 封面右上角是否显示下载角标。默认开：看到喜欢的可以直接下载，
  /// 不用先点进详情页。本地漫画与多选模式会自动隐藏（见 `_buildCoverWithTitle`）。
  final bool showDownloadAction;

  /// 封面左上角是否显示语言 / 汉化角标。默认开。
  ///
  /// 判定只吃插件给的标签与标题（`ComicSimplifyEntryInfo.tags`），
  /// 所以插件没给语言线索时**本来就不会显示**（不是坏了）。
  final bool showTranslationBadge;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const ComicSimplifyEntry({
    super.key,
    required this.info,
    required this.type,
    this.refresh,
    this.onDeleteSuccess,
    this.onTapOverride,
    this.onLongPressOverride,
    this.onSecondaryTapDown,
    this.isSelected = false,
    this.selectionMode = false,
    this.topPadding = true,
    this.roundedCorner = true,
    this.showDownloadAction = true,
    this.showTranslationBadge = true,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  @override
  Widget build(BuildContext context) {
    if (info.title == "无数据") {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width / 0.75;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final onTapHandler = onTapOverride;
            if (onTapHandler != null) {
              onTapHandler(info);
              return;
            }
            _navigateToComicInfo(context);
          },
          onLongPressStart: (details) {
            final onLongPressHandler = onLongPressOverride;
            if (onLongPressHandler != null) {
              onLongPressHandler(info, details);
              return;
            }
            if (type != ComicEntryType.normal) {
              _showDeleteDialog(context);
            }
          },
          onSecondaryTapDown: (details) {
            onSecondaryTapDown?.call(info, details);
          },
          child: SizedBox(
            width: width,
            height: height,
            child: _buildCoverWithTitle(context, width, height),
          ),
        );
      },
    );
  }

  Widget _buildCoverWithTitle(
    BuildContext context,
    double width,
    double height,
  ) {
    final circular = roundedCorner
        ? themeRadius(context, fallback: kComicCardBorderRadius)
        : 0.0;
    final primary = Theme.of(context).colorScheme.primary;
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final badgePolicy = ComicCardBadgePolicy(
      downloadBadgeEnabled: globalSetting.comicCardSetting.downloadBadgeEnabled,
      translationBadgeEnabled:
          globalSetting.comicCardSetting.translationBadgeEnabled,
    );
    // 本地漫画本来就在盘上；多选模式下右上角让给勾选圈。
    final showDownloadBadge = badgePolicy.showDownloadBadge(
      pluginId: pluginId,
      comicId: info.id,
      cardEnabled: showDownloadAction,
      selectionMode: selectionMode,
    );
    final favoriteSetting = globalSetting.favoriteArtistSetting;
    final matchResult = favoriteSetting.highlightEnabled
        ? FavoriteArtistMatcher.match(
            title: info.title,
            tags: info.tags,
            favoriteArtists: favoriteSetting.artists,
          )
        : null;
    final isFavoriteArtist = matchResult?.isMatched ?? false;
    final canShowTranslation = badgePolicy.showTranslationBadge(
      cardEnabled: showTranslationBadge,
    );
    final translationMatch = canShowTranslation
        ? ChineseTranslationMatcher.match(title: info.title, tags: info.tags)
        : ChineseTranslationMatch.none;

    return ClipRRect(
      borderRadius: BorderRadius.circular(circular),
      child: Container(
        foregroundDecoration: isSelected && selectionMode
            ? BoxDecoration(
                border: Border.all(color: primary, width: 4),
                borderRadius: BorderRadius.circular(circular),
              )
            : (isFavoriteArtist
                  ? BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFF59E0B),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(circular),
                    )
                  : null),
        child: Stack(
          children: [
            CoverWidget(
              fileServer: info.fileServer,
              path: info.path,
              id: info.id,
              pictureType: info.pictureType,
              from: info.from,
              roundedCorner: roundedCorner,
              width: width,
              height: height,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.7],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(circular),
                    bottomRight: Radius.circular(circular),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(5.0, 20.0, 5.0, 5.0),
                child: Text(
                  info.title.let(convertChineseForDisplay),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  maxLines: 3, // 最多显示3行
                  overflow: TextOverflow.ellipsis, // 超出部分显示省略号
                  textAlign:
                      TextAlign.start, // 文字对齐方式，也可以用 TextAlign.center 居中显示
                ),
              ),
            ),
            if (showDownloadBadge)
              Positioned(
                top: 6,
                right: 6,
                child: ComicDownloadBadge(
                  from: pluginId,
                  comicId: info.id,
                  title: info.title,
                  size: width < 110 ? 24 : 28,
                ),
              ),
            // 左上角角标族：喜欢画师在上、语言/汉化在下，纵向排开。
            // 两个都画成独立的 Positioned 会互相盖住（同是 top:6,left:6）。
            if (isFavoriteArtist || translationMatch.hasBadge)
              Positioned(
                top: 6,
                left: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFavoriteArtist)
                      FavoriteArtistBadge(
                        artistName: matchResult?.matchedArtist,
                      ),
                    if (isFavoriteArtist && translationMatch.hasBadge)
                      const SizedBox(height: 4),
                    if (translationMatch.hasBadge)
                      ComicTranslationBadge(
                        match: translationMatch,
                        compact: width < 110,
                      ),
                  ],
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isSelected ? primary : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isSelected ? Icons.check : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.white : Colors.black54,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToComicInfo(BuildContext context) {
    final pluginId = (info.source.trim().isNotEmpty ? info.source : info.from)
        .trim();
    if (pluginId.isEmpty) return;

    // 本地来源必须绕开详情页 —— 与上方 [ComicFixedSizeHorizontalList] 的同名方法、
    // 以及 [ComicEntryWidget] 的分支保持一致。
    //
    // 本地漫画的 `source` 是 `local`、`id` 是文件路径，它**没有插件**。送进
    // [ComicInfoRoute] 会被详情页当成「插件 id = local」去问 qjs 运行时，
    // 得到 `plugin_not_found:local`；这在界面上只会显示成一句「加载失败，请重试。」
    // （历史上还会被错误处理改写成一句类型转换错误）。本地漫画直接进阅读器。
    if (isLocalComicSource(pluginId, info.id)) {
      context.pushRoute(
        ComicReadRoute(
          comicId: info.id,
          order: 0,
          from: 'local',
          epsNumber: 1,
          type: type == ComicEntryType.normal
              ? ComicEntryType.normal
              : ComicEntryType.history,
          comicInfo: info.id,
          stringSelectCubit: StringSelectCubit(),
        ),
      );
      return;
    }

    context.pushRoute(
      ComicInfoRoute(
        comicId: info.id,
        type: type,
        from: pluginId,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final (title, content) = _getDialogContent();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () {
              context.router.pop();
              _handleDeleteAction(context);
            },
            child: Text(t.common.confirm),
          ),
        ],
      ),
    );
  }

  (String, String) _getDialogContent() {
    logger.d(type);
    switch (type) {
      case ComicEntryType.favorite:
        return (
          t.comicEntry.deleteFavorite,
          t.comicEntry.deleteFavoriteConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      case ComicEntryType.history:
        return (
          t.comicEntry.deleteHistory,
          t.comicEntry.deleteHistoryConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      case ComicEntryType.download:
        return (
          t.comicEntry.deleteDownload,
          t.comicEntry.deleteDownloadConfirm(
            title: info.title.let(convertChineseForDisplay),
          ),
        );
      default:
        return ("", "");
    }
  }

  Future<void> _handleDeleteAction(BuildContext context) async {
    try {
      if (type == ComicEntryType.history) {
        await _deleteHistory();
      } else if (type == ComicEntryType.download) {
        await _deleteDownload();
      } else if (type == ComicEntryType.favorite) {
        await _deleteFavorite();
      }
      final deletedKey = '${info.from.trim()}:${info.id}';
      if (onDeleteSuccess != null) {
        onDeleteSuccess!(deletedKey);
      } else {
        refresh?.call();
      }
    } catch (e, s) {
      logger.e('删除失败', error: e, stackTrace: s);
      showErrorToast(t.comicEntry.deleteFailed);
    }
  }

  Future<void> _deleteHistory() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
    final temp = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      temp.deleted = true;
      temp.updatedAt = DateTime.now().toUtc();
      objectbox.unifiedHistoryBox.put(temp);
    }
  }

  Future<void> _deleteDownload() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
    final temp = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.uniqueKey.equals(uniqueKey))
        .build()
        .findFirst();

    if (temp != null) {
      objectbox.unifiedDownloadBox.remove(temp.id);
      await _deleteDownloadDirectory(info.id);
    }
  }

  Future<void> _deleteFavorite() async {
    final uniqueKey = '${info.from.trim()}:${info.id}';
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

  Future<void> _deleteDownloadDirectory(String id) async {
    try {
      await deleteComicDownloadDirectory(info.from, id);
      logger.d('目录已成功删除: $id');
    } catch (e) {
      logger.e('删除目录时发生错误: $e');
      throw Exception('删除目录失败');
    }
  }
}
