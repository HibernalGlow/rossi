import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/comic/favorite_tag_matcher.dart';
import 'package:zephyr/util/text/tag_text.dart';

FavoriteTag tag(String name, [List<String> aliases = const []]) =>
    FavoriteTag(name: name, aliases: aliases);

void main() {
  group('归一化', () {
    test('大小写、包裹括号、全半角、下划线与空格都折成同一个键', () {
      expect(TagText.normalize('  [School Lolita]  '), 'school lolita');
      expect(TagText.normalize('school_lolita'), 'school lolita');
      expect(TagText.normalize('SCHOOL　LOLITA'), 'school lolita');
      expect(TagText.normalize('【school_lolita】'), 'school lolita');
      // 只有整串被括号包住才剥；夹在中间的括号是 tag 自身的一部分。
      expect(TagText.normalize('school（lolita）'), 'school(lolita)');
      expect(TagText.normalize('ａ：ｂ'), 'a:b');
      expect(TagText.normalize(null), '');
      expect(TagText.normalize(''), '');
    });

    test('命名空间前缀只削「紧跟冒号、冒号后不空格」的那一种', () {
      expect(TagText.stripNamespace(TagText.normalize('artist:foo')), 'foo');
      expect(
        TagText.stripNamespace(TagText.normalize('other:lolita')),
        'lolita',
      );
      // `artist: foo` 的冒号更像正文里的分隔，不当命名空间。
      expect(TagText.stripNamespace(TagText.normalize('artist: foo')), isNull);
      expect(
        TagText.stripNamespace(TagText.normalize('fate/grand order')),
        isNull,
      );
    });

    test('标题括号里的内容逐个归一化', () {
      expect(
        TagText.bracketCandidates('[Chinese] [Fancy Face] 本子名'),
        unorderedEquals(['chinese', 'fancy face']),
      );
      expect(TagText.bracketCandidates('没有括号'), isEmpty);
    });
  });

  group('命中判断', () {
    test('本名与别名都能命中，命中别名时标出来', () {
      final favorites = [
        tag('school_lolita', ['学校萝莉', 'School Lolita']),
      ];

      final byName = FavoriteTagMatcher.match(
        tags: const ['school lolita'],
        favoriteTags: favorites,
      );
      expect(byName.isMatched, isTrue);
      expect(byName.label, 'school_lolita');
      expect(byName.viaAlias, isFalse);

      final byAlias = FavoriteTagMatcher.match(
        tags: const ['学校萝莉'],
        favoriteTags: favorites,
      );
      expect(byAlias.isMatched, isTrue);
      expect(byAlias.viaAlias, isTrue);
      expect(byAlias.matchedText, '学校萝莉');
    });

    test('插件给的 tag 带命名空间前缀时照样命中', () {
      final result = FavoriteTagMatcher.match(
        tags: const ['artist:武田弘光'],
        favoriteTags: [tag('武田弘光')],
      );
      expect(result.isMatched, isTrue);
    });

    test('刻意不做子串兜底：lolita 不命中 school_lolita', () {
      final result = FavoriteTagMatcher.match(
        tags: const ['school_lolita'],
        favoriteTags: [tag('lolita')],
      );
      expect(result.isMatched, isFalse);
    });

    test('标签里没有时看标题括号，且标签优先于标题', () {
      final favorites = [tag('chinese'), tag('complete')];

      final fromTitle = FavoriteTagMatcher.match(
        tags: const ['magnet-link'],
        title: '[Complete] 某本子',
        favoriteTags: favorites,
      );
      expect(fromTitle.label, 'complete');

      final tagWins = FavoriteTagMatcher.match(
        tags: const ['chinese'],
        title: '[Complete] 某本子',
        favoriteTags: favorites,
      );
      expect(tagWins.label, 'chinese');
    });

    test('收藏为空、或写法全是空白时不命中', () {
      expect(
        FavoriteTagMatcher.match(
          tags: const ['chinese'],
          favoriteTags: const [],
        ).isMatched,
        isFalse,
      );
      expect(
        FavoriteTagMatcher.match(
          tags: const ['chinese'],
          favoriteTags: [tag('   ')],
        ).isMatched,
        isFalse,
      );
    });

    test('同一归一化键被两条收藏抢到时，先加入者赢', () {
      final index = FavoriteTagMatcher.buildAliasIndex([
        tag('School Lolita'),
        tag('school_lolita', ['学校萝莉']),
      ]);
      expect(index.length, 2);
      expect(index['school lolita']!.name, 'School Lolita');
      expect(index['学校萝莉']!.name, 'school_lolita');
    });

    test('hitInIndex 与 match 同口径（胶囊变色用的就是它）', () {
      final index = FavoriteTagMatcher.buildAliasIndex([tag('loli')]);
      expect(FavoriteTagMatcher.hitInIndex(index, 'LOLI'), isTrue);
      expect(FavoriteTagMatcher.hitInIndex(index, 'tag:loli'), isTrue);
      expect(FavoriteTagMatcher.hitInIndex(index, 'school_loli'), isFalse);
      expect(FavoriteTagMatcher.hitInIndex(const {}, 'loli'), isFalse);
    });
  });
}
