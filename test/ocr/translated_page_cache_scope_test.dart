/// 成品页缓存里那一项**源身份**的判据。
///
/// 这个测试守的是两件互相拉扯的事：
/// 1. 给了 scope 就必须进指纹 —— 否则不同书的同号页查同一张 `p5.png`，
///    端出来的是另一本书的画面，而芯片说它是译文页；
/// 2. 没给 scope 时指纹必须与加这个字段之前**逐字节相同** —— 否则光是让代码
///    走到这一行，就把用户盘上所有成品页判死（重跑一页十几秒）。
/// 第 2 条用「按改造前那条规则手算一遍哈希」来验，而不是只断言两个相等：
/// 只断言相等的话，两项一起错也照样绿。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';

const _modelTag = 'models-tag-for-test';

OcrTranslationConfig _config({String? cacheScope}) => OcrTranslationConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'some-model',
  targetLanguage: 'zh-Hans',
  engine: OcrTranslateEngine.endpoint,
  cacheScope: cacheScope,
);

/// 加 `scope` 之前那份指纹规则，按当时的字段顺序手算。
///
/// 抄的是 `describe` 里那八项的**顺序与取值**：顺序也进哈希，所以这里的顺序
/// 写错就是测试自己红，不会把一个真的改动放过去。
String _fingerprintAsBeforeChange({required OcrTranslationConfig config}) {
  String h(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 8);
  final entries = <String, String>{
    'engine': config.engine.id,
    'targetLanguage': config.targetLanguage,
    'endpointHost': Uri.parse(config.baseUrl).host,
    'model': config.model,
    'glossarySha1': h(config.glossary),
    'models': _modelTag,
    'font': TranslatedPageCache.fontVersion,
    'layout': '${TranslatedPageCache.layoutVersion}',
  };
  return entries.entries.map((e) => '${e.key}=${e.value}').join('|');
}

String _hashOf(String fingerprint) =>
    sha1.convert(utf8.encode(fingerprint)).toString().substring(0, 8);

void main() {
  test('没给源身份时，指纹与改造前逐字节一致', () async {
    // 手算那份只覆盖了「需要端点、且术语表生效」这一档；前提哪天变了，
    // 要在这里红成一句能读懂的话，而不是在断言里表现成一次莫名的不等。
    expect(OcrTranslateEngine.endpoint.requiresEndpoint, isTrue);
    expect(OcrTranslateEngine.endpoint.glossaryApplies, isTrue);
    final config = _config();
    final before = _fingerprintAsBeforeChange(config: config);
    final now = await TranslatedPageCache.describe(
      config: config,
      modelTag: _modelTag,
    );

    expect(now.fingerprint, before);
    expect(
      now.label,
      'zh-Hans_some-model_${_hashOf(before)}',
      reason: '目录名里那段哈希变了 = 用户盘上的成品页集体作废',
    );
    expect(now.fingerprint.contains('scope'), isFalse);
  });

  test('给了源身份才多这一项，而且它进的是哈希', () async {
    final withScope = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'p1|c1|ch1'),
      modelTag: _modelTag,
    );
    expect(withScope.fingerprint.contains('scope=p1|c1|ch1'), isTrue);
    expect(
      withScope.fingerprint,
      '${_fingerprintAsBeforeChange(config: _config())}|scope=p1|c1|ch1',
    );
  });

  test('两本书的同一页查的不是同一个键', () async {
    final a = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'pluginA|comicA|ch1'),
      modelTag: _modelTag,
    );
    final b = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'pluginB|comicB|ch1'),
      modelTag: _modelTag,
    );
    expect(a.label, isNot(b.label));
  });

  test('同一本书换一章，也是不同的键', () async {
    final ch1 = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'pluginA|comicA|ch1'),
      modelTag: _modelTag,
    );
    final ch2 = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'pluginA|comicA|ch2'),
      modelTag: _modelTag,
    );
    expect(ch1.label, isNot(ch2.label));
  });

  test('空串当没给，别凭空造出一个新档位', () async {
    final empty = await TranslatedPageCache.describe(
      config: _config(cacheScope: ''),
      modelTag: _modelTag,
    );
    final none = await TranslatedPageCache.describe(
      config: _config(),
      modelTag: _modelTag,
    );
    expect(empty.fingerprint, none.fingerprint);
  });

  test('目标语言与源身份各管各的，改其一不影响另一项的取值', () async {
    final zh = await TranslatedPageCache.describe(
      config: _config(cacheScope: 'p|c|ch'),
      modelTag: _modelTag,
    );
    // 只换语言：语言既是 label 的可读段、又进指纹。
    final en = await TranslatedPageCache.describe(
      config: OcrTranslationConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'some-model',
        targetLanguage: 'en',
        engine: OcrTranslateEngine.endpoint,
        cacheScope: 'p|c|ch',
      ),
      modelTag: _modelTag,
    );
    expect(en.fingerprint, isNot(zh.fingerprint));
    expect(en.label.startsWith('en_some-model_'), isTrue);
  });
}
