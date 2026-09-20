import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/comic/favorite_artist_matcher.dart';

void main() {
  group('归一化与命名空间', () {
    test('normalizeArtist 剥括号并转小写', () {
      expect(FavoriteArtistMatcher.normalizeArtist('  [Artist]  '), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('(Artist)'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('【Artist】'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('（Artist）'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('[[Artist]]'), 'artist');
      expect(FavoriteArtistMatcher.normalizeArtist('武田弘光'), '武田弘光');
      expect(FavoriteArtistMatcher.normalizeArtist(null), '');
      expect(FavoriteArtistMatcher.normalizeArtist(''), '');
    });

    test('画师与社团命名空间分桶，其余整组丢弃', () {
      final buckets = FavoriteArtistBuckets()
        ..addGroup(type: 'tag:artist', name: '作者', values: ['武田弘光'])
        ..addGroup(type: 'artist', name: 'Artist', values: ['Hakusei'])
        ..addGroup(type: 'tag:group', name: '社团', values: ['Fancy Face'])
        ..addGroup(type: 'uploader', name: 'Uploader', values: ['武田弘光'])
        ..addGroup(type: 'category', name: 'Category', values: ['[English]'])
        ..addGroup(type: 'tag:parody', name: '原作', values: ['东方'])
        ..addGroup(type: 'language', name: '语言', values: ['chinese'])
        ..addGroup(type: 'works', name: '作品', values: ['某作品']);
      expect(buckets.artistTags, ['武田弘光', 'Hakusei']);
      expect(buckets.circleTags, ['Fancy Face']);
    });

    test('原作（parody）不算画师位，角色与 cosplayer 也不算', () {
      expect(
        FavoriteArtistMatcher.classifyNamespace('tag:artist', '作者'),
        FavoriteArtistRelevance.artist,
      );
      expect(
        FavoriteArtistMatcher.classifyNamespace('author', '作者'),
        FavoriteArtistRelevance.artist,
      );
      expect(
        FavoriteArtistMatcher.classifyNamespace('tag:parody', '原作'),
        FavoriteArtistRelevance.irrelevant,
      );
      expect(
        FavoriteArtistMatcher.classifyNamespace('tag:group', '社团'),
        FavoriteArtistRelevance.circle,
      );
      expect(
        FavoriteArtistMatcher.classifyNamespace('tag:character', '人物'),
        FavoriteArtistRelevance.irrelevant,
      );
      expect(
        FavoriteArtistMatcher.classifyNamespace('uploader', '上传者'),
        FavoriteArtistRelevance.irrelevant,
      );
    });
  });

  group('标题画师块', () {
    test('画师位命中，事件括号与后缀标记不当画师', () {
      final result = FavoriteArtistMatcher.match(
        title: '(C99) [CircleA (ArtistX)] My Awesome Comic [Digital]',
        favoriteArtists: ['ArtistX'],
      );
      expect(result.isMatched, isTrue);
      expect(result.matchedArtist, 'ArtistX');
      expect(result.evidence, FavoriteArtistEvidence.titleArtist);
    });

    test('汉化组括号排在前面时跳过它', () {
      final result = FavoriteArtistMatcher.match(
        title: '[肉包子汉化] [CircleA (ArtistX)] Title',
        favoriteArtists: ['ArtistX'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.titleArtist);
    });

    test('只有一块时社团与画师不分，按画师认', () {
      final result = FavoriteArtistMatcher.match(
        title: '【武田弘光】 纯爱故事',
        favoriteArtists: ['武田弘光'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.titleAuthorBlock);
    });

    test('事件码本身不当画师', () {
      expect(
        FavoriteArtistMatcher.match(
          title: '[C100] Some Book',
          favoriteArtists: ['C100'],
        ).isMatched,
        isFalse,
      );
      expect(
        FavoriteArtistMatcher.match(
          title: '[Sample] Circle (Artist) Book',
          favoriteArtists: ['Sample'],
        ).isMatched,
        isFalse,
      );
    });
  });

  group('标签证据', () {
    test('画师命名空间标签命中', () {
      final result = FavoriteArtistMatcher.match(
        title: 'Original Title Without Artist Name',
        artistTags: ['artist:武田弘光'],
        favoriteArtists: ['武田弘光'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.artistTag);
    });

    test('带前缀但不是画师的标签一律不认', () {
      for (final tag in [
        'uploader:武田弘光',
        '上传者：武田弘光',
        'category:武田弘光',
        'tag:parody:武田弘光',
        'language:武田弘光',
      ]) {
        expect(
          FavoriteArtistMatcher.match(
            title: 'A Book',
            artistTags: [tag],
            favoriteArtists: ['武田弘光'],
          ).isMatched,
          isFalse,
          reason: '$tag 不该算画师证据',
        );
      }
    });

    test('社团桶里的 artist 前缀不算社团证据', () {
      expect(
        FavoriteArtistMatcher.match(
          title: 'A Book',
          circleTags: ['artist:武田弘光'],
          favoriteArtists: ['武田弘光'],
        ).isMatched,
        isFalse,
      );
    });

    test('详情作者字段命中', () {
      final result = FavoriteArtistMatcher.match(
        title: '标题里没有画师',
        creator: '武田弘光',
        favoriteArtists: ['武田弘光'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.creator);
    });
  });

  group('社团名三档', () {
    test('fallbackOnly：有画师证据时社团名不算命中', () {
      final result = FavoriteArtistMatcher.match(
        title: '(C99) [CircleA (ArtistX)] Title',
        favoriteArtists: ['CircleA'],
      );
      expect(result.isMatched, isFalse);
    });

    test('independent：社团名独立命中，但仍排在画师之后', () {
      final result = FavoriteArtistMatcher.match(
        title: '(C99) [CircleA (ArtistX)] Title',
        favoriteArtists: ['CircleA'],
        circleMode: FavoriteArtistCircleMode.independent,
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.titleCircle);
    });

    test('没有画师证据时 fallbackOnly 认社团', () {
      final result = FavoriteArtistMatcher.match(
        title: '标题里没有画师块',
        circleTags: ['group:Fancy Face'],
        favoriteArtists: ['Fancy Face'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.circleTag);
    });

    test('off：社团名完全不参与', () {
      expect(
        FavoriteArtistMatcher.match(
          title: '标题里没有画师块',
          circleTags: ['group:Fancy Face'],
          favoriteArtists: ['Fancy Face'],
          circleMode: FavoriteArtistCircleMode.off,
        ).isMatched,
        isFalse,
      );
    });

    test('存成 [社团 (画师)] 的喜欢项：两位都能认', () {
      final artistHit = FavoriteArtistMatcher.match(
        title: '(C99) [别的社团 (ArtistX)] Title',
        favoriteArtists: ['[CircleA (ArtistX)]'],
      );
      expect(artistHit.isMatched, isTrue);
      expect(artistHit.matchedArtist, '[CircleA (ArtistX)]');
      expect(artistHit.matchedName, 'ArtistX');

      final pairHit = FavoriteArtistMatcher.match(
        title: '(C99) [CircleA (ArtistX)] Title',
        favoriteArtists: ['CircleA (ArtistX)'],
      );
      expect(pairHit.isMatched, isTrue);
      expect(pairHit.evidence, FavoriteArtistEvidence.titleArtist);
    });
  });

  group('兜底：标题正文里的独立词', () {
    test('拉丁画师名作为独立词出现时命中', () {
      final result = FavoriteArtistMatcher.match(
        title: 'The Art of Hakusei 2024',
        favoriteArtists: ['Hakusei'],
      );
      expect(result.isMatched, isTrue);
      expect(result.evidence, FavoriteArtistEvidence.titleToken);
      expect(result.matchedName, 'Hakusei');
    });

    test('汉字连写不算独立词（旧版就在这里乱匹）', () {
      expect(
        FavoriteArtistMatcher.match(
          title: '水龙敬乐园特别篇',
          favoriteArtists: ['水龙敬'],
        ).isMatched,
        isFalse,
      );
      expect(
        FavoriteArtistMatcher.match(
          title: 'HakuseiStyle Book',
          favoriteArtists: ['Hakusei'],
        ).isMatched,
        isFalse,
      );
    });

    test('噪声括号内部不参与兜底', () {
      expect(
        FavoriteArtistMatcher.match(
          title: '[Circle (Artist)] 某本 [Sample Big One]',
          favoriteArtists: ['Big'],
        ).isMatched,
        isFalse,
      );
    });

    test('两个字的喜欢项不走兜底，但走画师块', () {
      expect(
        FavoriteArtistMatcher.match(
          title: 'A Book About Abcd Stuff',
          favoriteArtists: ['Ab'],
        ).isMatched,
        isFalse,
      );
      expect(
        FavoriteArtistMatcher.match(
          title: '[Ab] A Book',
          favoriteArtists: ['Ab'],
        ).isMatched,
        isTrue,
      );
    });
  });

  group('chip 点亮', () {
    test('喜欢项带括号时画师 chip 也亮', () {
      expect(
        FavoriteArtistMatcher.chipIsFavorite(
          label: 'ArtistX',
          namespaceType: 'tag:artist',
          namespaceName: '作者',
          favoriteArtists: ['[CircleA (ArtistX)]'],
        ),
        isTrue,
      );
      expect(
        FavoriteArtistMatcher.chipIsFavorite(
          label: 'CircleA',
          namespaceType: 'tag:group',
          namespaceName: '社团',
          favoriteArtists: ['[CircleA (ArtistX)]'],
        ),
        isTrue,
      );
      expect(
        FavoriteArtistMatcher.chipIsFavorite(
          label: 'CircleA',
          namespaceType: 'tag:group',
          namespaceName: '社团',
          favoriteArtists: ['[CircleA (ArtistX)]'],
          circleMode: FavoriteArtistCircleMode.off,
        ),
        isFalse,
      );
    });

    test('无关命名空间的 chip 退回整条等值，保证添加后自己会亮', () {
      expect(
        FavoriteArtistMatcher.chipIsFavorite(
          label: 'MyScanlation',
          namespaceType: 'tag:misc',
          namespaceName: '信息',
          favoriteArtists: ['MyScanlation'],
        ),
        isTrue,
      );
      expect(
        FavoriteArtistMatcher.chipIsFavorite(
          label: '别的名字',
          namespaceType: 'tag:misc',
          namespaceName: '信息',
          favoriteArtists: ['[CircleA (ArtistX)]'],
        ),
        isFalse,
      );
    });
  });

  group('不匹配的情形', () {
    test('喜欢列表为空直接不命中', () {
      expect(
        FavoriteArtistMatcher.match(
          title: '[Circle (Artist)] Title',
          artistTags: ['Artist'],
          favoriteArtists: [],
        ).isMatched,
        isFalse,
      );
    });

    test('没有任何重叠时不命中', () {
      final result = FavoriteArtistMatcher.match(
        title: '[OtherCircle (OtherArtist)] Title',
        artistTags: ['tag:cosplayer:OtherArtist'],
        favoriteArtists: ['FavoriteArtist'],
      );
      expect(result.isMatched, isFalse);
      expect(result.matchedArtist, isNull);
      expect(result.evidence, isNull);
    });
  });
}
