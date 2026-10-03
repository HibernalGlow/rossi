/// Index-Translate 本机档的调用形状。
///
/// 主判据不是翻译质量（那是模型与语料的事，量在 `docs/mt-bench/` 那边），
/// 而是这一档**自己的两条决定**有没有被后来人改掉：
/// 1. 提示词必须是官方 `trans_prompt` 无约束那一支的原文 —— 改措辞等于换了个模型；
/// 2. **术语表绝不进提示词** —— 实测挂了术语块会把 ヤモリ（壁虎）带成「野良波」，
///    即不加本来就对的东西被带崩。这一条没有测试守着的话，
///    下一个人会「顺手把 glossary 接上」，而那在数据上是退步。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/hy_mt2_translator.dart';
import 'package:zephyr/service/ocr/index_translator.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

/// `engine` 这一项本档根本不读（分流在编排层按它选实现）。等枚举里加上
/// `indexTranslate` 那一档时，这里换成它；现在先不写一个不存在的值。
const _cfg = OcrTranslationConfig(
  baseUrl: 'http://127.0.0.1:8088/v1',
  model: 'Index-Translate-2B',
  targetLanguage: 'zh-Hans',
);

void main() {
  group('提示词形状（官方 trans_prompt 无约束那一支，逐字）', () {
    test('目标语言用中文全称，标签原样塞进去会被当成正文', () {
      final p = indexPrompt('危機契約を発動します', 'zh-Hans');
      expect(
        p,
        '请将以下日语文本翻译为简体中文，直接输出翻译结果，不要进行任何解释。\n\n'
        '危機契約を発動します',
      );
      expect(p, isNot(contains('zh-Hans')));
    });

    test('语言名映射与混元那一档共用同一份', () {
      expect(
        HyMt2Translator.languageName('zh-Hant'),
        '繁体中文',
        reason: '两档各自维护一份映射，迟早对不上',
      );
      expect(indexPrompt('おかえり', 'zh-Hant'), contains('繁体中文'));
    });

    test('术语表一个字都进不去 —— 挂上它实测会把壁虎带成人名', () async {
      final cfg = _cfg.copyWith(
        glossary: '危機契約=危机契约\nナナ=娜娜\nリーリィ=莉莉\nノラボス=野良波',
      );
      final sent = <String>[];
      await IndexTranslator.instance.translateBlocks(
        texts: const ['ヤモリの繁殖にみごと成功したのでした!', '出てきなさいナナ!'],
        config: cfg,
        post: (prompt, _) async {
          sent.add(prompt);
          return '好的';
        },
      );
      expect(sent.length, 2);
      for (final p in sent) {
        expect(p, isNot(contains('野良波')));
        expect(p, isNot(contains('术语')));
        expect(p, isNot(contains('约束')));
      }
      // 与不带术语表时**逐字相同** —— 这才叫「这一档不吃 glossary」，
      // 而不是「吃了但很少」。
      expect(sent.first, indexPrompt('ヤモリの繁殖にみごと成功したのでした!', 'zh-Hans'));
    });
  });

  group('返回形状：错位比翻得差更糟', () {
    test('某条翻成空的 → 报第几块与原文，不画一个空白气泡', () async {
      var threw = '';
      try {
        await IndexTranslator.instance.translateBlocks(
          texts: const ['第一句', '第二句', '第三句'],
          config: _cfg,
          post: (p, cfg) async => p.endsWith('第二句') ? '  ' : '译文',
        );
      } on OcrTranslationException catch (e) {
        threw = e.message;
      }
      expect(threw, contains('第 2 块'));
      expect(threw, contains('第二句'));
    });

    test('回填顺序与块序一致（并发度是 1，实测并发换不到吞吐）', () async {
      expect(
        IndexTranslator.concurrency,
        1,
        reason: '这台机器上 1.8B 实测 2 路 0.86×、4 路 1.12×；'
            '这一档没理由更便宜，偷偷调高要多背一个服务端 -np 的依赖',
      );
      final out = await IndexTranslator.instance.translateBlocks(
        texts: const ['一', '二', '三', '四'],
        config: _cfg,
        post: (p, cfg) async => 'X${p.substring(p.length - 1)}',
      );
      expect(out, ['X一', 'X二', 'X三', 'X四']);
    });
  });

  group('思考块安全网', () {
    const open = '<' 'think>';
    const close = '<' '/think>';

    test('模型自己吐出思考块时按第一个闭合标签切，正文保留', () {
      expect(
        IndexTranslator.stripThinking('$open先想想$close真正的译文'),
        '真正的译文',
      );
      expect(
        IndexTranslator.stripThinking('没有思考块$close也不吃后面的字'),
        '也不吃后面的字',
        reason: '这条是官方客户端的行为，照抄，不自创',
      );
      expect(
        IndexTranslator.stripThinking('$open只有开头标签$open也照剥'),
        '只有开头标签$open也照剥',
        reason: '官方 removeprefix 只剥最前面一次，正文里的开标签不该动',
      );
    });

    test('没有思考块时原样返回（不许动正文里的尖括号）', () {
      expect(
        IndexTranslator.stripThinking('他说<未知>然后走了'),
        '他说<未知>然后走了',
      );
    });
  });

  group('档位属性', () {
    test('本机 llama-server 这类档要端点，与 Apple 端侧那档不同', () {
      expect(OcrTranslateEngine.endpoint.requiresEndpoint, isTrue);
      expect(OcrTranslateEngine.appleOnDevice.requiresEndpoint, isFalse);
    });
  });
}
