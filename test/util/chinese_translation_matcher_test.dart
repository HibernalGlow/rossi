import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';

/// `ChineseTranslationMatcher` 的判据。
///
/// 这个判定是**纯函数**（只吃标签与标题），所以判据也全在这里 ——
/// 卡片角标只是它的一个画法。
///
/// 为什么要这么细：各家插件的语言词汇不一样（Bika 用分类字段、同人本靠
/// 标题里的 `[XX漢化組]`），而且**误报比漏报更糟** —— 把日语原版标成
/// 「汉化」会让人白下一本读不了的书。所以既要验「该认的认出来」，
/// 也要成对验「不该认的别乱认」（ASCII 词边界、生肉不扫标题）。
void main() {
  ChineseTranslationMatch match(String title, List<String>? tags) =>
      ChineseTranslationMatcher.match(title: title, tags: tags);

  group('汉化：明确表示有人译成中文', () {
    test('标签是「汉化」/「汉化组」', () {
      final result = match('某作品', ['汉化']);
      expect(result.kind, ChineseTranslationKind.translated);
      // 命中来源要能报回去（提示条与词表排查都靠它）。
      expect(result.matchedText, '汉化');
      expect(result.matchedInTitle, isFalse);
    });

    test('繁体「漢化組」等价于「汉化组」', () {
      final result = match('某作品', ['漢化組']);
      expect(result.kind, ChineseTranslationKind.translated);
      // 报的是标签原文，不做繁简改写。
      expect(result.matchedText, '漢化組');
    });

    test('标签带前缀与包裹括号也能认出', () {
      for (final tag in ['标签：汉化', 'tag: 汉化', '【漢化】', '(汉化)']) {
        expect(
          match('某作品', [tag]).kind,
          ChineseTranslationKind.translated,
          reason: '标签 `$tag` 应判为汉化',
        );
      }
    });

    test('标题里的 [XX汉化组] 也算 —— 很多同人本没有语言标签', () {
      final result = match('[空气系汉化] 某作品', const []);
      expect(result.kind, ChineseTranslationKind.translated);
      expect(result.matchedInTitle, isTrue);
      expect(result.matchedText, '汉化');
    });

    test('自定义补充词与内置词同优先级', () {
      final result = ChineseTranslationMatcher.match(
        title: '某作品',
        tags: const ['烤肉组'],
        extraTranslatedKeywords: const ['烤肉'],
      );
      expect(result.kind, ChineseTranslationKind.translated);
      expect(result.matchedText, '烤肉组');
    });
  });

  group('中文：只说明语言是中文', () {
    test('「中文」/「简体」/「繁體」', () {
      expect(match('某作品', ['中文']).kind, ChineseTranslationKind.chinese);
      expect(match('某作品', ['简体']).kind, ChineseTranslationKind.chinese);
      expect(match('某作品', ['繁體']).kind, ChineseTranslationKind.chinese);
    });

    test('英文 chinese 不区分大小写', () {
      expect(match('某作品', ['Chinese']).kind, ChineseTranslationKind.chinese);
    });
  });

  group('生肉：日语原版', () {
    test('标签「日本語」/「日语」/「raw」', () {
      for (final tag in ['日本語', '日语', 'raw', 'Japanese']) {
        expect(
          match('某作品', [tag]).kind,
          ChineseTranslationKind.raw,
          reason: '标签 `$tag` 应判为生肉',
        );
      }
    });

    test('生肉**只**看标签，不扫标题', () {
      // 「原版封面」这类中文标题太常见，扫标题只有误报没有召回。
      final result = match('原版封面集', const []);
      expect(result.kind, ChineseTranslationKind.none);
    });
  });

  group('优先级', () {
    test('汉化 > 中文 > 生肉（多语言版本时给能读的那个）', () {
      expect(
        match('某作品', ['日本語', '漢化']).kind,
        ChineseTranslationKind.translated,
      );
      expect(match('某作品', ['日本語', '中文']).kind, ChineseTranslationKind.chinese);
    });

    test('跨类型时「类型」优先于「来源」：标题里的汉化胜过标签里的中文', () {
      final result = match('[某汉化组] 作品', ['中文']);
      expect(result.kind, ChineseTranslationKind.translated);
      expect(result.matchedInTitle, isTrue);
    });

    test('同类型内标签优先于标题', () {
      // 标题里也有「汉化」，但标签命中的应被报出来（更可信）。
      final result = match('[某汉化组] 作品', ['汉化组']);
      expect(result.kind, ChineseTranslationKind.translated);
      expect(result.matchedText, '汉化组');
      expect(result.matchedInTitle, isFalse);
    });
  });

  group('不该乱认的', () {
    test('没有语言线索就是 none（角标不显示）', () {
      expect(match('某作品', const []).kind, ChineseTranslationKind.none);
      expect(match('某作品', ['百合', '制服']).kind, ChineseTranslationKind.none);
      expect(match('某作品', null).kind, ChineseTranslationKind.none);
      expect(match('某作品', const []).hasBadge, isFalse);
    });

    test('ASCII 关键词要落在词边界上（raw 不该命中 draw / straw）', () {
      expect(match('某作品', ['draw']).kind, ChineseTranslationKind.none);
      expect(match('某作品', ['straw']).kind, ChineseTranslationKind.none);
      expect(match('某作品', ['drawing']).kind, ChineseTranslationKind.none);
      // 但真词要认。
      expect(match('某作品', ['raw']).kind, ChineseTranslationKind.raw);
    });

    test('chinese 不该命中 chineseteam 这类拼接串', () {
      expect(match('某作品', ['chineseteam']).kind, ChineseTranslationKind.none);
    });

    test('空白标签被忽略，不会把空串当命中', () {
      expect(match('某作品', ['   ', '']).kind, ChineseTranslationKind.none);
    });
  });
}
