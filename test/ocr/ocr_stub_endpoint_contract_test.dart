/// 假端点与**真解析器**之间的契约测试。
///
/// 存在的理由只有一个：`script/ocr_stub_endpoint.dart` 与 `OcrTranslator` 是两边各自
/// 解释「`编号<TAB>正文`」这套格式的。哪天客户端把编号写成 0 基、或者假端点漏了制表符，
/// 错的样子是「验收时每条都判不成、却没人知道自己对不上」——所以这里让假端点真的起来跑一次，
/// 拿**生产那个 `parseTranslatedLines`** 去读它的应答。
///
/// 不用 `dart run`：那个形式在本包里会先跑 native-assets 构建钩子（去编 Rust），
/// 起一个假端点不该顺带触发整条原生构建。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';

/// 生产提示词里那一段台词的形状（`ocr_translator.dart` 写的是 `${i + 1}\t原文`）。
const _prompt = '''
把下面这页漫画的台词逐条翻译成zh-Hans。
要求：
1. 只输出译文，不要解释、不要注音；

术语表（原文=译文）：
トカゲ=石龙子

台词：
1\tトカゲじゃ
2\tあの田舎とかにいる!?
3\tだんだんだん
''';

void main() {
  test('假端点的应答能被生产的 parseTranslatedLines 原样读回（openai 形状）', () async {
    final stub = await _startStub(const []);
    try {
      final content = await _complete(stub.port, _prompt);
      final lines = parseTranslatedLines(content, expected: 3);
      expect(lines, hasLength(3));
      expect(lines.every((l) => l.trim().isNotEmpty), isTrue);
    } finally {
      await stub.dispose();
    }
  });

  test('ollama 原生形状走的是同一个抽取分支', () async {
    final stub = await _startStub(['--shape=ollama']);
    try {
      final content = await _complete(stub.port, _prompt);
      expect(parseTranslatedLines(content, expected: 3), hasLength(3));
    } finally {
      await stub.dispose();
    }
  });

  test('--drop-one 少回一条：生产的条数守卫必须抛（这就是降级档的触发口）', () async {
    final stub = await _startStub(['--drop-one']);
    try {
      final content = await _complete(stub.port, _prompt);
      expect(
        () => parseTranslatedLines(content, expected: 3),
        throwsA(isA<OcrTranslationException>()),
        reason: '假端点少回一条却没人报错 = 界面上多一个空气泡，而它比错译更难发现',
      );
    } finally {
      await stub.dispose();
    }
  });

  test('--fail 回 500：状态码要留在异常文本里（验收第 12 条靠它）', () async {
    final stub = await _startStub(['--fail']);
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${stub.port}/v1/chat/completions'),
      );
      request.headers.contentType = ContentType.json;
      request.write(_body(_prompt));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);
      expect(response.statusCode, 500);
      expect(body, contains('error'));
    } finally {
      await stub.dispose();
    }
  });
}

String _body(String prompt) => jsonEncode({
  'model': 'contract-test',
  'temperature': 0.2,
  'messages': [
    {'role': 'system', 'content': '…'},
    {'role': 'user', 'content': prompt},
  ],
});

Future<String> _complete(int port, String prompt) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
    );
    request.headers.contentType = ContentType.json;
    request.write(_body(prompt));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    // 两条形状都支持：OpenAI 的 choices[0].message.content 与 Ollama 的 message.content，
    // 与 `OcrTranslator._extractContent` 同一口径。
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      return choices.first['message']['content'] as String;
    }
    return body['message']['content'] as String;
  } finally {
    client.close(force: true);
  }
}

class _Stub {
  _Stub(this.process, this.port);

  final Process process;
  final int port;

  Future<void> dispose() async {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }
}

/// `flutter test` 里的 `resolvedExecutable` 可能指向内嵌的 tester 而不是能跑脚本的 dart，
/// 所以认不出来就退回 PATH 上的 `dart`。
String get _dartBinary {
  final self = Platform.resolvedExecutable;
  return self.endsWith('${Platform.pathSeparator}dart') ? self : 'dart';
}

Future<_Stub> _startStub(List<String> extraArgs) async {
  final process = await Process.start(_dartBinary, [
    'script/ocr_stub_endpoint.dart',
    '--port=0',
    ...extraArgs,
  ]);
  final completer = Completer<int>();
  final portPattern = RegExp(r'127\.0\.0\.1:(\d+)');
  process.stdout.transform(utf8.decoder).listen((chunk) {
    final m = portPattern.firstMatch(chunk);
    if (m != null && !completer.isCompleted) {
      completer.complete(int.parse(m.group(1)!));
    }
  });
  process.stderr.transform(utf8.decoder).listen((chunk) {
    if (!completer.isCompleted) completer.completeError('端点启动失败：$chunk');
  });
  final port = await completer.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw StateError(
      '假端点 20 s 内没报出监听端口（dart 可执行文件是 ${Platform.resolvedExecutable}）',
    ),
  );
  return _Stub(process, port);
}
