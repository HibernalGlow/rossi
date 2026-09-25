/// 翻译那一跳的**真 HTTP**验证：本地起一个 OpenAI-compatible 桩，走 `WindHttp` → Rust reqwest。
///
/// `parseTranslatedLines` 是纯函数、已经单独钉住了；这里要验的是它上面那层：
/// URL 怎么拼（设置里带尾斜杠就会双斜杠）、请求体长什么样（编号必须是 1 基且逐条在）、
/// 响应结构怎么认（OpenAI 的 `choices[0].message.content` 与 Ollama 原生 `message.content`
/// 是两种形状）、非 2xx 时用户看到的是状态码还是一坨栈。
///
/// 桩不是「假装有翻译」：它验的是**协议接线**，翻译质量仍然只有真端点 + 真机说得清
/// （`docs/ocr-completed-page-acceptance.md` 第 3、4、9 条）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

const _texts = ['トカゲじゃ', 'あの田舎とかにいる!?'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nativeReady = false;
  String nativeError = '';
  late HttpServer server;
  late String baseUrl;
  final seen = <_Request>[];
  String Function(List<String> texts) reply = (t) =>
      List.generate(t.length, (i) => '${i + 1}\t〔${i + 1}〕').join('\n');
  int status = 200;
  Map<String, dynamic> Function(String content) envelope = _openAiShape;

  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}/v1/';
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add(
        _Request(
          method: req.method,
          path: req.uri.path,
          auth: req.headers.value('authorization') ?? '',
          contentType: req.headers.value('content-type') ?? '',
          body: body,
        ),
      );
      final payload = envelope(reply(_texts));
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  OcrTranslationConfig config() => const OcrTranslationConfig(
    baseUrl: 'http://127.0.0.1:1', // 每个用例里换成真端口
    model: 'stub',
  );

  Future<List<String>> translate({String? key, String glossary = ''}) =>
      OcrTranslator.instance.translateBlocks(
        texts: _texts,
        config: config().copyWith(
          baseUrl: baseUrl,
          apiKey: key ?? '',
          glossary: glossary,
        ),
      );

  setUp(() {
    seen.clear();
    status = 200;
    envelope = _openAiShape;
    reply = (t) =>
        List.generate(t.length, (i) => '${i + 1}\t〔${i + 1}〕').join('\n');
  });

  test('打到 /chat/completions，编号从 1 起且逐条原文都在', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    final out = await translate();
    expect(out, ['〔1〕', '〔2〕']);

    expect(seen, hasLength(1));
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.path, '/v1/chat/completions', reason: '设置里带尾斜杠也不许拼出双斜杠');
    expect(r.contentType, contains('application/json'));
    final sent = jsonDecode(r.body) as Map<String, dynamic>;
    final prompt =
        ((sent['messages'] as List).last as Map)['content'] as String;
    for (final t in _texts) {
      expect(prompt, contains(t), reason: '原文没进提示词 = 翻的是别的东西');
    }
    expect(
      RegExp(r'^1\t', multiLine: true).hasMatch(prompt),
      isTrue,
      reason: '编号必须是 1 基',
    );
    expect(RegExp(r'^0\t', multiLine: true).hasMatch(prompt), isFalse);
  });

  test('有 key 才带 Authorization，空 key 不发空头', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    await translate(key: 'sk-abc');
    expect(seen.single.auth, 'Bearer sk-abc');
    seen.clear();
    await translate();
    expect(seen.single.auth, isEmpty);
  });

  test('术语表真的进请求（不进就等于设置白填）', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    await translate(glossary: 'トカゲ=石龙子');
    final prompt =
        ((jsonDecode(seen.single.body)['messages'] as List).last
                as Map)['content']
            as String;
    expect(prompt, contains('トカゲ=石龙子'));
  });

  test('Ollama 原生形状也认得', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    envelope = (c) => {
      'message': {'content': c},
    };
    expect(await translate(), ['〔1〕', '〔2〕']);
  });

  test('非 2xx：报状态码，不抛一坨栈', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    status = 500;
    await expectLater(
      translate(),
      throwsA(
        isA<OcrTranslationException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('模型漏一条：抛「条数对不上」，不许少画一个气泡', () async {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了：$nativeError');
      return;
    }
    reply = (t) => '1\t〔1〕';
    await expectLater(
      translate(),
      throwsA(
        isA<OcrTranslationException>().having(
          (e) => e.message,
          'message',
          contains('期望 2'),
        ),
      ),
    );
  });
}

Map<String, dynamic> _openAiShape(String content) => {
  'choices': [
    {
      'message': {'content': content},
    },
  ],
};

class _Request {
  _Request({
    required this.method,
    required this.path,
    required this.auth,
    required this.contentType,
    required this.body,
  });

  final String method;
  final String path;
  final String auth;
  final String contentType;
  final String body;
}
