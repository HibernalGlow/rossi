import 'dart:convert';

import 'package:zephyr/network/http/wind_http.dart';

/// 翻译配置。**不内置 NMT 模型**（ADR-0018 §决定 7）：只走 OpenAI-compatible 端点，
/// 云端（DeepSeek / OpenAI / Groq…）与本机 Ollama（`http://127.0.0.1:11434/v1`）是同一个协议。
class OcrTranslationConfig {
  const OcrTranslationConfig({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.targetLanguage = 'zh-Hans',
    this.glossary = '',
  });

  /// 形如 `https://api.deepseek.com/v1` / `http://127.0.0.1:11434/v1`（**不带**尾斜杠）。
  final String baseUrl;
  final String model;
  final String apiKey;

  /// 目标语言，进缓存指纹（换目标语言必须重译）。
  final String targetLanguage;

  /// 术语表：每行 `原文=译文`。整体拼进提示词；它的**文本**进缓存指纹 ——
  /// 改一个词就该让成品页失效，而不是让人纳闷「为什么还是旧译名」。
  final String glossary;

  OcrTranslationConfig copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? targetLanguage,
    String? glossary,
  }) => OcrTranslationConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    glossary: glossary ?? this.glossary,
  );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'targetLanguage': targetLanguage,
    'glossary': glossary,
    // apiKey 刻意不落盘。
  };
}

class OcrTranslationException implements Exception {
  OcrTranslationException(this.message);

  final String message;
  @override
  String toString() => 'OcrTranslationException: $message';
}

/// 整页一次请求：漫画的台词短、且**上下文比单句重要**（人称、语气、前后呼应），
/// 逐块发请求既贵又会把上下文切碎。
class OcrTranslator {
  OcrTranslator._();

  static final OcrTranslator instance = OcrTranslator._();

  /// 把整页的原文翻成译文，**顺序与长度与输入严格一致**。任一条对不上就抛 ——
  /// 宁可不画，也不能把 A 的台词填到 B 的气泡里。
  Future<List<String>> translateBlocks({
    required List<String> texts,
    required OcrTranslationConfig config,
    String? chapterContext,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (texts.isEmpty) return const [];
    final payload = _buildRequest(texts, config, chapterContext);
    final url = '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';

    final response = await WindHttp().fetch(
      url,
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        if (config.apiKey.isNotEmpty) 'authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode(payload),
      timeout: timeout,
    );
    if (!response.ok) {
      throw OcrTranslationException(
        '翻译端点返回 ${response.status}: ${response.text.substring(0, response.text.length.clamp(0, 200))}',
      );
    }
    final body = response.json;
    final content = _extractContent(body);
    final lines = parseTranslatedLines(content, expected: texts.length);
    return lines;
  }

  Map<String, dynamic> _buildRequest(
    List<String> texts,
    OcrTranslationConfig config,
    String? chapterContext,
  ) {
    final numbered = <String>[];
    for (var i = 0; i < texts.length; i++) {
      numbered.add('${i + 1}\t${texts[i]}');
    }
    final buffer = StringBuffer()
      ..writeln('把下面这页漫画的台词逐条翻译成${config.targetLanguage}。')
      ..writeln('要求：')
      ..writeln('1. 只输出译文，不要解释、不要注音；')
      ..writeln('2. **保持条数与顺序**：每行一条，行首保留原来的编号与制表符；')
      ..writeln('3. 台词短、口语重，按角色说话的语气译，不要书面化；')
      ..writeln('4. 拟声词、专有名词若在术语表里，按术语表译。');
    if (config.glossary.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('术语表（原文=译文）：')
        ..writeln(config.glossary.trim());
    }
    if (chapterContext != null && chapterContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('本章上下文（仅供理解，不要翻译）：')
        ..writeln(chapterContext.trim());
    }
    buffer
      ..writeln()
      ..writeln('台词：')
      ..write(numbered.join('\n'));

    return {
      'model': config.model,
      'temperature': 0.2,
      'messages': [
        {
          'role': 'system',
          'content': '你是漫画翻译。输出必须与输入的条数、顺序、编号一一对应。',
        },
        {'role': 'user', 'content': buffer.toString()},
      ],
    };
  }

  String _extractContent(dynamic body) {
    if (body is! Map) throw OcrTranslationException('响应不是 JSON 对象：$body');
    // OpenAI-compatible：choices[0].message.content；Ollama 的原生接口是 message.content。
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
        if (first['text'] is String) return first['text'] as String;
      }
    }
    final message = body['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    throw OcrTranslationException('认不出响应结构：${body.keys.toList()}');
  }
}

/// 解析模型输出，抽出 `编号<TAB>译文` 的正文。**纯函数**，所以能单测。
///
/// 容错：模型经常会漏掉制表符、加粗编号、或在前面写一句「好的」。
/// 但**条数必须对得上** —— 少一条就抛，因为「漏译一条」在成品页上表现为某个气泡空白，
/// 而空白比错译更难被发现。
List<String> parseTranslatedLines(String content, {required int expected}) {
  final out = <String?>[];
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    // 编号与正文之间可能是制表符、句点、冒号，模型还常给编号加粗（形如 **2**）。
    // 注意别用 `\s*` 去接分隔符：它会把制表符先吃掉，导致「1<TAB>译文」整行匹配不上。
    final m = RegExp(r'^\s*\**\s*(\d+)\s*\**\s*(?:[.、:：]\s*)?(.*)$').firstMatch(line);
    if (m == null) continue;
    // 编号是**1 基**（提示词里就是这么给的）：别直接拿来当下标，否则最后一条永远落不进去、
    // 表现为「条数对不上」——这个错位正是被单测咬出来的。
    final lineNo = int.tryParse(m.group(1)!);
    if (lineNo == null || lineNo < 1) continue;
    final index = lineNo - 1;
    if (index >= expected) continue;
    while (out.length <= index) {
      out.add(null);
    }
    final text = m.group(2)!.replaceAll(RegExp(r'\*+$'), '').trim();
    if (text.isNotEmpty) out[index] = text;
  }
  if (out.length != expected || out.any((v) => v == null)) {
    throw OcrTranslationException(
      '译文条数对不上：期望 $expected，拿到 ${out.where((v) => v != null).length}；原文=$content',
    );
  }
  return out.cast<String>();
}
