import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';

void main() {
  test('标签与封面共享名单缓存，原地修改会同步更新两个入口', () {
    final favorites = ['[CircleOne (ArtistOne)]'];
    bool chip(
      String label, {
      String type = 'tag:artist',
      FavoriteArtistCircleMode mode = FavoriteArtistCircleMode.fallbackOnly,
    }) => FavoriteArtistMatcher.chipIsFavorite(
      label: label,
      namespaceType: type,
      namespaceName: '',
      favoriteArtists: favorites,
      circleMode: mode,
    );
    FavoriteArtistMatchResult match() => FavoriteArtistMatcher.match(
      title: 'Book',
      artistTags: ['ArtistOne', 'ArtistTwo'],
      favoriteArtists: favorites,
    );
    expect(chip('ArtistOne'), isTrue);
    expect(chip('CircleOne', type: 'tag:group'), isTrue);
    expect(
      chip('CircleOne', type: 'tag:group', mode: FavoriteArtistCircleMode.off),
      isFalse,
    );
    expect(match().matchedArtist, favorites.single);
    favorites[0] = '[CircleTwo (ArtistTwo)]';
    expect(chip('ArtistOne'), isFalse);
    expect(chip('ArtistTwo'), isTrue);
    expect(chip('CircleOne', type: 'tag:group'), isFalse);
    expect(match().matchedArtist, favorites.single);
    favorites.clear();
    expect(chip('ArtistTwo'), isFalse);
    expect(match().isMatched, isFalse);
  });
  test('相同名单原地增删与改顺序后，命中和优先级立即更新', () {
    final favorites = ['ArtistOne', 'ArtistTwo'];
    FavoriteArtistMatchResult match() => FavoriteArtistMatcher.match(
      title: 'Book',
      artistTags: ['ArtistOne', 'ArtistTwo'],
      favoriteArtists: favorites,
    );
    expect(match().matchedArtist, 'ArtistOne');
    favorites.removeAt(0);
    expect(match().matchedArtist, 'ArtistTwo');
    favorites.insert(0, 'ArtistOne');
    expect(match().matchedArtist, 'ArtistOne');
    favorites.clear();
    expect(match().isMatched, isFalse);
  });
  test('相同标题的标签、作者字段与社团模式独立匹配', () {
    FavoriteArtistMatchResult match({
      List<String> artists = const [],
      String? creator,
      FavoriteArtistCircleMode mode = FavoriteArtistCircleMode.off,
    }) => FavoriteArtistMatcher.match(
      title: '[CircleName (OtherArtist)] Book',
      favoriteArtists: ['CircleName', 'KnownArtist'],
      artistTags: artists,
      creator: creator,
      circleMode: mode,
    );
    expect(match().isMatched, isFalse);
    expect(
      match(artists: ['KnownArtist']).evidence,
      FavoriteArtistEvidence.artistTag,
    );
    expect(
      match(creator: 'KnownArtist').evidence,
      FavoriteArtistEvidence.creator,
    );
    expect(
      match(mode: FavoriteArtistCircleMode.independent).matchedArtist,
      'CircleName',
    );
    expect(match().isMatched, isFalse);
  });
  test('超过文字缓存容量后仍保留独立词和噪声边界规则', () {
    for (var i = 0; i < 600; i++) {
      expect(
        FavoriteArtistMatcher.match(
          title: 'Book $i [ArtistLong汉化组]',
          favoriteArtists: ['ArtistLong'],
        ).isMatched,
        isFalse,
      );
    }
    expect(
      FavoriteArtistMatcher.match(
        title: 'Book by ArtistLong',
        favoriteArtists: ['ArtistLong'],
      ).evidence,
      FavoriteArtistEvidence.titleToken,
    );
  });
}
