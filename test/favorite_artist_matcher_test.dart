import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';

void main() {
  group('FavoriteArtistMatcher tests', () {
    test('normalizeArtist handles brackets and cases', () {
      expect(FavoriteArtistMatcher.normalizeArtist('  [Artist]  '), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('(Artist)'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('【Artist】'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('（Artist）'), 'artist');
      expect(
        FavoriteArtistMatcher.normalizeArtist('[[Artist]]'),
        'artist',
      );
      expect(FavoriteArtistMatcher.normalizeArtist('武田弘光'), '武田弘光');
      expect(FavoriteArtistMatcher.normalizeArtist(null), '');
      expect(FavoriteArtistMatcher.normalizeArtist(''), '');
    });

    test('extractArtistCandidates extracts circle and artist', () {
      final candidates1 = FavoriteArtistMatcher.extractArtistCandidates(
        '[Alice (Bob)] Comic Title',
      );
      expect(candidates1, contains('Bob'));
      expect(candidates1, contains('Alice'));
      expect(candidates1, contains('[Alice (Bob)]'));

      final candidates2 = FavoriteArtistMatcher.extractArtistCandidates(
        '(C100) [社团名 (画师名)] 漫画标题',
      );
      expect(candidates2, contains('画师名'));
      expect(candidates2, contains('社团名'));
      expect(candidates2, contains('C100'));

      final candidates3 = FavoriteArtistMatcher.extractArtistCandidates(
        '【武田弘光】 纯爱故事',
      );
      expect(candidates3, contains('武田弘光'));
    });

    test('match succeeds with title bracket candidates', () {
      final result1 = FavoriteArtistMatcher.match(
        title: '(C99) [CircleA (ArtistX)] My Awesome Comic',
        favoriteArtists: ['ArtistX'],
      );
      expect(result1.isMatched, isTrue);
      expect(result1.matchedArtist, 'ArtistX');

      final result2 = FavoriteArtistMatcher.match(
        title: '[CircleA (ArtistX)] My Awesome Comic',
        favoriteArtists: ['CircleA'],
      );
      expect(result2.isMatched, isTrue);
      expect(result2.matchedArtist, 'CircleA');
    });

    test('match succeeds with tags', () {
      final result = FavoriteArtistMatcher.match(
        title: 'Original Title Without Artist Name',
        tags: ['artist:武田弘光', '纯爱', '萝莉'],
        favoriteArtists: ['武田弘光'],
      );
      expect(result.isMatched, isTrue);
      expect(result.matchedArtist, '武田弘光');
    });

    test('match succeeds with title substring', () {
      final result = FavoriteArtistMatcher.match(
        title: '水龙敬乐园特别篇',
        favoriteArtists: ['水龙敬'],
      );
      expect(result.isMatched, isTrue);
      expect(result.matchedArtist, '水龙敬');
    });

    test('match returns notMatched when no favorite artist matches', () {
      final result = FavoriteArtistMatcher.match(
        title: '[OtherCircle (OtherArtist)] Title',
        tags: ['tag1', 'tag2'],
        favoriteArtists: ['FavoriteArtist'],
      );
      expect(result.isMatched, isFalse);
      expect(result.matchedArtist, isNull);
    });

    test('match returns notMatched when favoriteArtists is empty', () {
      final result = FavoriteArtistMatcher.match(
        title: '[Circle (Artist)] Title',
        tags: ['Artist'],
        favoriteArtists: [],
      );
      expect(result.isMatched, isFalse);
    });
  });
}
