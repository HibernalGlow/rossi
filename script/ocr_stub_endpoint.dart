/// 一个**本机假翻译端点**：OpenAI-compatible 的 `/v1/chat/completions`，用来看这条链路
/// 通不通，不用来证明译文像人话。
///
/// 为什么要它：ADR-0018 §决定 7 不内置 NMT，验收清单里第 1、4、5、10、11b、12 条
/// 全都要一个「能应答的端点」。手边没有 key、也没有拉几十 GB 模型时，这几条就成了
/// 「实现完了但没人能验」。这个端点把**通路**那一半接过来：编号协议、条数、顺序、
/// 术语表是否随请求走、Authorization 有没有带上、降级档能不能触发 ——
/// **译文质量它判不了**，那一条仍然必须换成真端点。
///
/// 跑法（另开一个终端）。**用 `dart <文件>` 而不是 `dart run`**：后者在这个包里会先跑
/// native-assets 的构建钩子（实测打印就停在 `Running build hooks…` 去编 Rust），
/// 一个假端点不该顺手触发整条原生构建。
///
/// ```bash
/// dart script/ocr_stub_endpoint.dart                  # 监听 127.0.0.1:8787
/// dart script/ocr_stub_endpoint.dart --shape=ollama    # 按 Ollama 原生结构回
/// dart script/ocr_stub_endpoint.dart --drop-one         # 故意少回一条 → 降级档
/// dart script/ocr_stub_endpoint.dart --fail             # 直接 500 → 降级档（另一种成因）
/// dart script/ocr_stub_endpoint.dart --port=0 --delay-ms=8000  # 随机端口 + 慢应答
/// ```
///
/// 然后在设置里填：接口地址 `http://127.0.0.1:8787/v1`、模型名随便（会原样进日志）、
/// 目标语言与术语表按要验的那条填。
library;

import 'dart:convert';
import 'dart:io';

/// 用于占位的汉字：伪译文按**原文字数**生成，长度是真的，才能把回填的字号求解压到
/// 与真译文同一量级（喂固定短串会让越框变得不可能发生）。
const _filler = '这是一句用来占位的中文译文而已啦它并不真的翻译什么';

Future<void> main(List<String> args) async {
  final port = int.tryParse(_argValue(args, '--port') ?? '') ?? 8787;
  final shape = _argValue(args, '--shape') ?? 'openai';
  if (shape != 'openai' && shape != 'ollama') {
    stderr.writeln('--shape 只能是 openai 或 ollama，收到 $shape');
    exitCode = 64;
    return;
  }
  final dropOne = args.contains('--drop-one');
  final fail = args.contains('--fail');
  final latencyMs = int.tryParse(_argValue(args, '--delay-ms') ?? '') ?? 0;

  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
    shared: false,
  );
  stdout.writeln(
    '假端点已监听 http://127.0.0.1:${server.port}/v1/chat/completions'
    '（shape=$shape${dropOne ? '，故意少回一条' : ''}${fail ? '，直接 500' : ''}'
    '${latencyMs > 0 ? '，每请求延迟 $latencyMs ms' : ''}）',
  );
  stdout.writeln('设置里填：接口地址 http://127.0.0.1:${server.port}/v1，模型名任意。');

  await for (final request in server) {
    await _handle(
      request,
      shape: shape,
      dropOne: dropOne,
      fail: fail,
      latencyMs: latencyMs,
    );
  }
}

Future<void> _handle(
  HttpRequest request, {
  required String shape,
  required bool dropOne,
  required bool fail,
  required int latencyMs,
}) async {
  if (request.method == 'GET' && request.uri.path.endsWith('/models')) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'stub', 'object': 'model', 'owned_by': 'rossi-script'},
          ],
        }),
      );
    await request.response.close();
    return;
  }
  if (request.method != 'POST' ||
      !request.uri.path.endsWith('/chat/completions')) {
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'error': {'message': '这个端点只服务 /v1/chat/completions'},
        }),
      );
    await request.response.close();
    return;
  }

  final body = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(body);
  final sources = sourcesFromPrompt(decoded);
  final model = decoded is Map ? '${decoded['model']}' : '?';
  final glossarySeen = promptOf(decoded).contains('术语表');

  if (latencyMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: latencyMs));
  }
  if (fail) {
    request.response
      ..statusCode = HttpStatus.internalServerError
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'error': {'message': '假端点按 --fail 回的错误'},
        }),
      );
    await request.response.close();
    stdout.writeln('500（模拟端点挂了）：${sources.length} 条台词被拒');
    return;
  }

  var lines = [
    for (var i = 0; i < sources.length; i++)
      '${i + 1}\t${_pseudoFor(sources[i])}',
  ];
  if (dropOne && lines.isNotEmpty) {
    lines = lines.sublist(0, lines.length - 1);
  }
  final content = lines.join('\n');
  final payload = shape == 'ollama'
      ? {
          'model': model,
          'message': {'role': 'assistant', 'content': content},
        }
      : {
          'id': 'chatcmpl-stub',
          'object': 'chat.completion',
          'model': model,
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': content},
              'finish_reason': 'stop',
            },
          ],
        };
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(payload));
  await request.response.close();
  // 这几行是给验收的人看的：能证明「术语表进没进请求」「key 有没有带」，
  // 而界面上看不出这两件事。
  stdout.writeln(
    '应答 ${lines.length}/${sources.length} 条（model=$model，'
    'authorization=${request.headers.value('authorization') == null ? '无' : '有'}，'
    '术语表=${glossarySeen ? '进了请求' : '没进'}）',
  );
}

/// 从生产那一版提示词里抽出 `编号<TAB>原文` 的台词。
///
/// 客户端把编号写成 1 基（`ocr_translator.dart` 里 `${i + 1}\t…`），这里必须按同一口径读，
/// 否则假端点会回错条数 —— 而这个测试要防的就是这种双方各自解释编号的漂移。
List<String> sourcesFromPrompt(dynamic decoded) {
  final prompt = promptOf(decoded);
  final out = <String>[];
  for (final raw in prompt.split('\n')) {
    final m = RegExp(r'^(\d+)\t(.*)$').firstMatch(raw.trim());
    if (m != null) out.add(m.group(2)!);
  }
  return out;
}

String promptOf(dynamic decoded) {
  if (decoded is! Map) return '';
  final messages = decoded['messages'];
  if (messages is! List) return '';
  // 取最后一条 user：系统提示在前，台词在用户消息里。
  for (final m in messages.reversed) {
    if (m is Map && m['role'] == 'user' && m['content'] is String) {
      return m['content'] as String;
    }
  }
  return '';
}

final _fillerRunes = _filler.runes.toList(growable: false);

/// 按原文的非空白字符数造一条**同字数**的中文占位译文。
String _pseudoFor(String source) {
  final n = source.runes.where((r) => r > 0x20).length.clamp(1, 120);
  return String.fromCharCodes([
    for (var i = 0; i < n; i++) _fillerRunes[i % _fillerRunes.length],
  ]);
}

String? _argValue(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
