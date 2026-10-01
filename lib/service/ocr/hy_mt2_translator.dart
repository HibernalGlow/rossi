import 'dart:async';
import 'dart:convert';

import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

/// 混元 Hy-MT2（本机 llama-server / Ollama 之类 OpenAI-compatible 服务）的调用。
///
/// **为什么不复用 [OcrTranslator] 那条批量路径**：Hy-MT2 的模型卡写明「一次只看一句」，
/// 而端点档发的是「整页 15 行带编号、要求按编号回一行一条」。把后者喂给前者是**出分布**的用法，
/// 测出来的错算不到模型头上。所以这一档自己发、自己收，一条一个请求。
///
/// 术语表走它**文档化的 Terminology 模式**（`X 翻译成 Y` 的前缀块），
/// 而不是像云端那样把术语表当附加说明塞进 prompt —— 这是这一档值得单列的原因：
/// 同一份术语表，两档的生效机制不同，产出也不同，缓存指纹因此必须分开。
class HyMt2Translator {
  HyMt2Translator._();

  static final instance = HyMt2Translator._();

  /// **实测之后定回 1**（我一开始顺手写了 4，那是没量的优化）。
  /// 本机 M4 + llama-server 1.8B Q4、带术语块的真实提示：串行 158 ms/条，
  /// 2 路并发 **184 ms/条（0.86×，更慢）**，4 路 **141 ms/条（1.12×，几乎没差）**。
  /// 这类模型解码吃的是显存带宽而不是请求数，并发换不到吞吐，
  /// 却要多背一个「服务端 `-np` 得够」的依赖和一类回填错序的风险 —— 不值。
  static const concurrency = 1;

  /// `zh-Hans` → 模型卡要求的**中文全称**。它明确写了「中文提示里用中文名」，
  /// 直接把 BCP-47 标签塞进提示词，模型会把它当成待译文本的一部分。
  static String languageName(String tag) => switch (tag) {
    'zh-Hans' || 'zh' || 'zh-CN' => '简体中文',
    'zh-Hant' || 'zh-TW' => '繁体中文',
    'en' || 'en-US' => '英语',
    'ja' => '日语',
    _ => tag,
  };

  /// 默认翻译提示（模型卡里的中文那一版，逐字照抄，不改措辞）。
  static String defaultPrompt(String text, String target) =>
      '将以下文本翻译为 `$target`，注意**只需要输出翻译后的结果，不要额外解释**：'
      '\n\n$text';

  /// Terminology 提示：先给若干条 `原文 翻译成 译文`，再套默认提示。
  static String terminologyPrompt(
    String text,
    String target,
    List<(String, String)> terms,
  ) {
    final refs = terms.map((t) => '${t.$1} 翻译成 ${t.$2}').join('\n');
    return '参考下面的翻译：\n$refs\n\n'
        '将以下文本翻译为 `$target`，注意**只需要输出翻译后的结果，不要额外解释**：'
        '\n\n$text';
  }

  /// 把设置里 `原文=译文` 的术语表解析成对。容忍全角等号与空行 ——
  /// 这是用户手打的字段，格式不会总是干净。
  static List<(String, String)> parseGlossary(String raw) {
    final out = <(String, String)>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf(RegExp('[=＝]'));
      if (i <= 0 || i == t.length - 1) continue;
      out.add((t.substring(0, i).trim(), t.substring(i + 1).trim()));
    }
    return out;
  }

  /// 返回顺序与 [texts] 严格一致。任何一条失败都抛 [OcrTranslationException]：
  /// 半页译文比整页降级更糟 —— 用户看不出哪几块是旧的。
  Future<List<String>> translateBlocks({
    required List<String> texts,
    required OcrTranslationConfig config,

    /// 注入点：单测里给假的，真机走 [_httpPost]。签名就是「提示词进、译文出」。
    Future<String> Function(String prompt, OcrTranslationConfig config)? post,
  }) async {
    if (texts.isEmpty) return const [];
    final send = post ?? _httpPost;
    final target = languageName(config.targetLanguage);
    final terms = parseGlossary(config.glossary);
    String promptFor(String text) => terms.isEmpty
        ? defaultPrompt(text, target)
        : terminologyPrompt(text, target, terms);

    final out = List<String?>.filled(texts.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= texts.length) return;
        out[i] = (await send(promptFor(texts[i]), config)).trim();
      }
    }

    await Future.wait([
      for (var k = 0; k < concurrency.clamp(1, texts.length); k++) worker(),
    ]);

    final done = out.whereType<String>().toList(growable: false);
    if (done.length != texts.length) {
      throw OcrTranslationException(
        '混元返回 ${done.length} 条，送出去 ${texts.length} 条 —— 按块回填会整体错位',
      );
    }
    for (var i = 0; i < texts.length; i++) {
      if (out[i]!.isEmpty) {
        throw OcrTranslationException('第 ${i + 1} 块翻出来是空的（原文「${texts[i]}」）');
      }
    }
    return done;
  }

  Future<String> _httpPost(String prompt, OcrTranslationConfig config) async {
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final response = await WindHttp().fetch(
      url,
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        if (config.apiKey.isNotEmpty)
          'authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.model,
        // 模型卡：更高的温度会「偶尔编造内容」。这里要的是稳定，不是文采。
        'temperature': 0.0,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
      timeout: const Duration(seconds: 120),
    );
    if (!response.ok) {
      final text = response.text;
      throw OcrTranslationException(
        '混元端点返回 ${response.status}：'
        '${text.substring(0, text.length.clamp(0, 200))}'
        '（本机 llama-server 起来了吗？）',
      );
    }
    final body = response.json;
    final choices = (body is Map && body['choices'] is List)
        ? body['choices'] as List
        : const [];
    if (choices.isEmpty) {
      throw OcrTranslationException(
        '混元端点没返回 choices：${body.toString().substring(0, 120)}',
      );
    }
    final msg = (choices.first as Map)['message'];
    final content = msg is Map ? msg['content'] : null;
    if (content is! String) {
      throw OcrTranslationException('混元返回的 content 不是字符串');
    }
    return content;
  }
}

/// 供测试与日志复用的编码出口（避免有人再去手拼一遍提示词）。
String hyMt2Prompt(
  String text,
  String targetTag,
  List<(String, String)> terms,
) => terms.isEmpty
    ? HyMt2Translator.defaultPrompt(
        text,
        HyMt2Translator.languageName(targetTag),
      )
    : HyMt2Translator.terminologyPrompt(
        text,
        HyMt2Translator.languageName(targetTag),
        terms,
      );
