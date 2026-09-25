/// OCR 设置存取的验证。
///
/// 这里守的是两类后果：一是「没配好却照样发请求」（表现为一个用户看不懂的 HTTP 错误），
/// 二是「key 跟着配置导出走了」。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('没配齐就是没配齐：读回 null，不给一个必然失败的配置', () async {
    expect(await OcrSettings.loadConfig(), isNull);

    SharedPreferences.setMockInitialValues({'ocr_base_url': 'http://127.0.0.1:11434/v1'});
    expect(await OcrSettings.loadConfig(), isNull, reason: '只有端点、没有模型名，照样发不出去');
  });
  test('保存后读回，尾斜杠被削掉（拼 /chat/completions 才不会双斜杠）', () async {
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(
        baseUrl: 'https://api.deepseek.com/v1/',
        model: 'deepseek-chat',
        apiKey: 'sk-test',
        targetLanguage: 'en',
        glossary: 'トカゲ=石龙子',
      ),
    );
    final loaded = await OcrSettings.loadConfig();
    expect(loaded, isNotNull);
    expect(loaded!.baseUrl, 'https://api.deepseek.com/v1');
    expect(loaded.model, 'deepseek-chat');
    expect(loaded.apiKey, 'sk-test', reason: 'key 要能读回，否则每次重启都得重填');
    expect(loaded.targetLanguage, 'en');
    expect(loaded.glossary, 'トカゲ=石龙子');
  });

  test('apiKey 绝不进 toJson（导出/日志走的是它）', () async {
    const config = OcrTranslationConfig(
      baseUrl: 'https://x.example/v1',
      model: 'm',
      apiKey: 'sk-secret',
    );
    expect(config.toJson().containsKey('apiKey'), isFalse);
    expect(config.toJson().toString(), isNot(contains('sk-secret')));
  });

  test('改目标语言会通知监听者（阅读器上的提示条要跟着失效）', () async {
    final seen = <ChangeNotifier>[];
    OcrSettings.changes.addListener(() => seen.add(OcrSettings.changes));
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(baseUrl: 'https://x/v1', model: 'm'),
    );
    expect(seen, hasLength(1));
  });

  test('EP 存了个不认识的值，落回默认而不是拿去建会话', () async {
    SharedPreferences.setMockInitialValues({'ocr_ep': 'cuda'});
    expect(await OcrSettings.loadEp(), OcrSettings.defaultEp);
    await OcrSettings.saveEp('coreml');
    expect(await OcrSettings.loadEp(), 'coreml');
  });
}
