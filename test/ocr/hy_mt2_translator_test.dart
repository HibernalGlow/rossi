/// 混元 Hy-MT2 那一档的调用形状。
///
/// 它最容易错的不是翻译质量（那是模型的事），而是**并发取回后的顺序**：
/// 一条一个请求 + 4 个 worker 抢任务，回填是按块下标走的 ——
/// 错一位就是 A 气泡画 B 台词，而且**看上去完全正常**。所以顺序与条数是这里的主判据。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/hy_mt2_translator.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

const _cfg = OcrTranslationConfig(
  baseUrl: 'http://127.0.0.1:8080/v1',
  model: 'hy-mt2-7b',
  targetLanguage: 'zh-Hans',
  engine: OcrTranslateEngine.hyMt2Local,
);

void main() {
  group('提示词形状（照模型卡，不自己发挥）', () {
    test('无术语表 → 默认翻译提示，目标语言用中文全称', () {
      final p = HyMt2Translator.defaultPrompt('かえして〜', '简体中文');
      expect(p, contains('将以下文本翻译为 `简体中文`'));
      expect(p, endsWith('かえして〜'));
      // 语言标签不能原样塞进去：模型会把它当成待译文本的一部分。
      expect(p, isNot(contains('zh-Hans')));
    });

    test('languageName 覆盖我们实际会用的标签', () {
      expect(HyMt2Translator.languageName('zh-Hans'), '简体中文');
      expect(HyMt2Translator.languageName('zh-Hant'), '繁体中文');
      expect(HyMt2Translator.languageName('en'), '英语');
      expect(
        HyMt2Translator.languageName('klingon'),
        'klingon',
        reason: '认不出就原样带过，别编',
      );
    });

    test('有术语表 → Terminology 块在前，待译句在最后', () {
      final p = HyMt2Translator.terminologyPrompt('危機契約を発動します', '简体中文', [
        ('危機契約', '危机契约'),
      ]);
      expect(p, contains('参考下面的翻译：'));
      expect(p, contains('危機契約 翻译成 危机契约'));
      expect(
        p.indexOf('危機契約 翻译成 危机契约'),
        lessThan(p.indexOf('危機契約を発動します')),
        reason: '术语块必须在待译句之前，否则它是在给已经翻完的东西补充说明',
      );
    });

    test('术语表解析容忍全角等号、空行与没有值的行', () {
      final terms = HyMt2Translator.parseGlossary(
        '危機契約=危机契约\n\n沢田＝泽田\n没有等号的一行\n=开头没原文\n',
      );
      expect(terms, [('危機契約', '危机契约'), ('沢田', '泽田')]);
    });
  });

  group('取回', () {
    test('并发下顺序必须与输入严格一致（每条延迟故意不同）', () async {
      final texts = List.generate(11, (i) => '第${i + 1}句');
      final out = await HyMt2Translator.instance.translateBlocks(
        texts: texts,
        config: _cfg,
        post: (prompt, _) async {
          // 让后面的句子先返回：如果实现按完成顺序收，结果就会被打乱。
          final n = int.parse(RegExp(r'第(\d+)句').firstMatch(prompt)!.group(1)!);
          await Future<void>.delayed(Duration(milliseconds: (12 - n) * 5));
          return '译$n';
        },
      );
      expect(out, List.generate(11, (i) => '译${i + 1}'));
    });

    test('并发度就是配置值，不许偷偷变（实测并发不划算，所以它是 1）', () async {
      var live = 0, peak = 0;
      await HyMt2Translator.instance.translateBlocks(
        texts: List.generate(8, (i) => '句$i'),
        config: _cfg,
        post: (p, _) async {
          live++;
          peak = peak > live ? peak : live;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          live--;
          return 'ok';
        },
      );
      expect(peak, HyMt2Translator.concurrency);
      expect(
        HyMt2Translator.concurrency,
        1,
        reason:
            'M4 实测 4 路并发只有 1.12×、2 路反而 0.86×：解码吃显存带宽，'
            '并发换不到吞吐，却要多背一个服务端 -np 的依赖。要改回去请先重测。',
      );
    });

    test('少返回一条必须抛，不能默默少画一块', () async {
      await expectLater(
        HyMt2Translator.instance.translateBlocks(
          texts: const ['a', 'b', 'c'],
          config: _cfg,
          post: (p, _) async => p.contains('c') ? '' : '有',
        ),
        throwsA(isA<OcrTranslationException>()),
      );
    });

    test('空白的块不算失败？算 —— 宁可不画也不留半页', () async {
      await expectLater(
        HyMt2Translator.instance.translateBlocks(
          texts: const ['a', 'b'],
          config: _cfg,
          post: (p, _) async => '  ',
        ),
        throwsA(
          isA<OcrTranslationException>().having(
            (e) => e.message,
            'message',
            contains('空的'),
          ),
        ),
      );
    });

    test('空输入直接返回空，不发请求', () async {
      var called = 0;
      final out = await HyMt2Translator.instance.translateBlocks(
        texts: const [],
        config: _cfg,
        post: (p, _) async {
          called++;
          return 'x';
        },
      );
      expect(out, isEmpty);
      expect(called, 0);
    });
  });

  group('分档本身', () {
    test('混元要端点配置、且术语表生效；Apple 反过来', () {
      expect(OcrTranslateEngine.hyMt2Local.requiresEndpoint, isTrue);
      expect(OcrTranslateEngine.hyMt2Local.glossaryApplies, isTrue);
      expect(OcrTranslateEngine.appleOnDevice.requiresEndpoint, isFalse);
      expect(OcrTranslateEngine.appleOnDevice.glossaryApplies, isFalse);
    });

    test('三档的 id 互不相同（指纹靠它区分）', () {
      final ids = OcrTranslateEngine.values.map((e) => e.id).toSet();
      expect(ids.length, OcrTranslateEngine.values.length);
      expect(ids, containsAll(<String>{'endpoint', 'hunyuan', 'apple'}));
    });
  });
}
