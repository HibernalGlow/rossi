import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/network/http/plugin/qjs_download_runtime.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';
import 'package:zephyr/util/comic/comic_card_badge_policy.dart';
import 'package:zephyr/util/comic/comic_quick_read.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_download_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_caption_scope.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_read_button.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_translation_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_unread_indicator.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_artist_badge.dart';
import 'package:zephyr/widgets/comic_simplify_entry/favorite_tag_badge.dart';

const double kComicCardBorderRadius = 12;

/// 横向轨道与书架共用的封面。判定、阅读和下载沿用既有消费者。
class ComicCoverSurface extends StatelessWidget {
  const ComicCoverSurface({
    super.key,
    required this.info,
    required this.width,
    required this.height,
    this.coverKey,
    this.roundedCorner = true,
    this.showDownloadAction = true,
    this.showTranslationBadge = true,
    this.showReadAction = true,
    this.isSelected = false,
    this.selectionMode = false,
    this.unread = false,
    this.showTitle = true,
  });
  final ComicSimplifyEntryInfo info;
  final double width, height;
  final Key? coverKey;
  final bool roundedCorner, showDownloadAction, showTranslationBadge;
  final bool showReadAction, isSelected, selectionMode, unread;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<GlobalSettingCubit>().state;
    final scheme = Theme.of(context).colorScheme;
    final source = (info.source.trim().isEmpty ? info.from : info.source)
        .trim();
    final policy = ComicCardBadgePolicy(
      downloadBadgeEnabled: settings.comicCardSetting.downloadBadgeEnabled,
      translationBadgeEnabled:
          settings.comicCardSetting.translationBadgeEnabled,
      readButtonEnabled: settings.comicCardSetting.readButtonEnabled,
      favoriteTagBadgeEnabled:
          settings.comicCardSetting.favoriteTagBadgeEnabled,
      unreadIndicatorEnabled: settings.comicCardSetting.unreadIndicatorEnabled,
    );
    final download = policy.showDownloadBadge(
      pluginId: source,
      comicId: info.id,
      cardEnabled: showDownloadAction,
      selectionMode: selectionMode,
    );
    final read = policy.showReadButton(
      pluginId: source,
      comicId: info.id,
      cardEnabled: showReadAction,
      selectionMode: selectionMode,
    );
    final artistSettings = settings.favoriteArtistSetting;
    final artist = artistSettings.highlightEnabled
        ? FavoriteArtistMatcher.match(
            title: info.title,
            artistTags: info.artistTags,
            circleTags: info.circleTags,
            favoriteArtists: artistSettings.artists,
            circleMode: artistSettings.circleMode,
          )
        : null;
    final tagSettings = settings.favoriteTagSetting;
    final tag =
        policy.showFavoriteTagBadge(
          highlightEnabled: tagSettings.highlightEnabled,
        )
        ? FavoriteTagMatcher.match(
            tags: info.tags,
            title: info.title,
            favoriteTags: tagSettings.tags,
          )
        : FavoriteTagMatchResult.notMatched;
    final language =
        policy.showTranslationBadge(cardEnabled: showTranslationBadge)
        ? ChineseTranslationMatcher.match(title: info.title, tags: info.tags)
        : ChineseTranslationMatch.none;
    final radius = roundedCorner
        ? themeRadius(context, fallback: kComicCardBorderRadius)
        : 0.0;
    final attributes = <Widget>[
      if (artist?.isMatched ?? false)
        FavoriteArtistBadge(artistName: artist?.matchedName),
      if (tag.isMatched) FavoriteTagBadge(tagName: tag.label),
      if (language.hasBadge)
        ComicTranslationBadge(match: language, compact: width < 110),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        foregroundDecoration: selectionMode && isSelected
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 3),
                borderRadius: BorderRadius.circular(radius),
              )
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverWidget(
              key: coverKey,
              fileServer: info.fileServer,
              path: info.path,
              id: info.id,
              pictureType: info.pictureType,
              from: info.from,
              roundedCorner: false,
              width: width,
              height: height,
            ),
            if (showTitle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ComicCoverTitle(
                  title: convertChineseForDisplay(info.title),
                ),
              ),
            // 先铺阅读的悬停检测，再铺元信息与下载，避免吞掉右上角手势。
            if (read)
              Positioned.fill(
                child: ComicReadButton(
                  onTap: () => startComicQuickRead(
                    context,
                    comicId: info.id,
                    from: source,
                  ),
                  onHover: isLocalComicSource(source, info.id)
                      ? null
                      : () => prewarmQjsRuntime(source),
                  size: comicReadButtonSize(width),
                ),
              ),
            if (attributes.isNotEmpty)
              Positioned(
                top: (download || selectionMode) && width < 140 ? 52 : 6,
                left: 6,
                right: (download || selectionMode) && width >= 140 ? 54 : 6,
                child: ComicCoverMetadata(children: attributes),
              ),
            if (download)
              Positioned(
                top: 0,
                right: 0,
                child: ComicDownloadBadge(
                  from: source,
                  comicId: info.id,
                  title: info.title,
                  size: width < 110 ? 28 : 32,
                ),
              ),
            if (policy.showUnreadIndicator(
              unread: unread,
              selectionMode: selectionMode,
            ))
              Positioned(
                top: download ? 50 : 6,
                right: 6,
                child: ComicUnreadIndicator(
                  style: settings.comicCardSetting.unreadIndicatorStyle,
                  compact: width < 110,
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 4,
                right: 4,
                child: SizedBox.square(
                  dimension: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primary
                          : scheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: GlyphIcon(
                      isSelected ? AppGlyphs.check : AppGlyphs.ring,
                      color: isSelected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 信息允许自然换行；长名称受本行可用宽度约束。
class ComicCoverMetadata extends StatelessWidget {
  const ComicCoverMetadata({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final child in children)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: child,
          ),
      ],
    ),
  );
}

class ComicCoverTitle extends StatelessWidget {
  const ComicCoverTitle({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xA6000000), Color(0xE6000000)],
        stops: [0, .42, 1],
      ),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        24,
        8 + ComicCoverCaptionScope.trailingOf(context),
        8,
      ),
      child: Text(
        title,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    ),
  );
}
