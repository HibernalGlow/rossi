import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_cover_surface.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

/// 扩展标签种类只需提供一个稳定 id、默认权重和匹配信号，不改展墙算法。
const discoverWeightSignals = [
  LibraryWeightSignal('favoriteTag', '喜欢的 tag', 3),
  LibraryWeightSignal('favoriteArtist', '喜欢的画师', 2),
  LibraryWeightSignal('translated', '汉化', 1),
];

LibraryEntry discoverLibraryEntry(
  ComicSimplifyEntryInfo info,
  GlobalSettingState settings,
) {
  final tag = FavoriteTagMatcher.match(
    tags: info.tags,
    title: info.title,
    favoriteTags: settings.favoriteTagSetting.tags,
  );
  final artist = FavoriteArtistMatcher.match(
    title: info.title,
    artistTags: info.artistTags,
    circleTags: info.circleTags,
    favoriteArtists: settings.favoriteArtistSetting.artists,
    circleMode: settings.favoriteArtistSetting.circleMode,
  );
  final language = ChineseTranslationMatcher.match(
    title: info.title,
    tags: info.tags,
  );
  return LibraryEntry(
    key: '${info.source.isEmpty ? info.from : info.source}:${info.id}',
    title: settings.chineseConvertMode == ChineseConvertMode.off
        ? info.title
        : openccConvert(
            text: info.title,
            config: settings.chineseConvertMode.openccConfig,
          ),
    source: info,
    section: '作品',
    tags: info.tags,
    subtitle: [...info.artistTags, ...info.circleTags].take(2).join(' · '),
    metaText: info.from,
    weightSignals: {
      'favoriteTag': tag.isMatched ? 1 : 0,
      'favoriteArtist': artist.isMatched ? 1 : 0,
      'translated': language.kind == ChineseTranslationKind.translated ? 1 : 0,
    },
    media:
        (
          context, {
          required width,
          required height,
          required radius,
          required fit,
        }) => ComicCoverSurface(
          info: info,
          width: width,
          height: height,
          roundedCorner: false,
          showTitle: false,
        ),
  );
}
