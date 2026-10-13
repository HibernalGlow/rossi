import 'dart:async';
import 'dart:convert';

import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/service/ocr/hy_mt2_translator.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

/// B站 **Index-Translate**（Qwen3.5 底座，apache-2.0，150 语种）跑在本机 llama-server 上。
///
/// # 为什么要单列一档，而不是「endpoint 档换个 baseUrl」
///
/// 和这一档同形态的 `endpoint` 发的是「整页 15 行带编号、按编号回一行一条」，
/// 而这一族模型按**一句一次**的 instTrans 格式训练。把批量格式喂给它属于出分布用法
/// —— 与本仓 [HyMt2Translator] 当初单列的理由一字不差：测出来的错算不到模型头上，
/// 而且产出不同，缓存指纹必须能区分。
///
/// # 这一档**故意不读 config.glossary**
///
/// 2026-10-03 本机实测（`docs/mt-bench/`，同一批 33 条真页台词、`--temp 0 --seed 1`、
/// Q4_K_M、M4 + MTL0）：
///
/// | 挂不挂术语块 | ヤモリ（壁虎）三次 | 危機契約 两次 | 中位延迟/条 |
/// |---|---|---|---|
/// | 不挂（本档的做法） | 壁虎／壁虎／与蜥蜴区分开 | 危机契约／危机契约 ✓ | 380 ms |
/// | 挂（4 条术语的 instTrans 硬约束格式） | 两次被带成「**野良波**」 | 危机契约／危机契约 ✓ | 433 ms |
///
/// 也就是说：不加术语表时它**本来就翻对**的东西，加了术语表反而被别的条目串味带跑
/// （ノラボス→野良波 渗到 ヤモリ），延迟还多 14%。这和 Hy-MT2 那行「加术语块→母狗」
/// 是同一个形状。所以这里不是"省事不传"，是**传了会更差** ——
/// 因此 `OcrTranslateEngine.glossaryApplies` 必须对这一档为 `false`，
/// 否则用户改一个术语词就把一批「压根没用术语表」的成品页白白作废。
///
/// # 为什么请求里没有 `chat_template_kwargs`
///
/// 官方卡片写的是**服务端** flag（`--chat-template-kwargs '{"enable_thinking":false}'`）。
/// 实测这颗键从客户端请求体里带与不带，输出都不含思考块（同一条「危機契約を発動します」
/// 两次都直接回「将启动危机契约。」），所以这里不带，也就**不要求用户按某个 flag 起服务**。
/// 真要出现思考块，那是 `stripThinking` 那条安全网的事，不是这颗 flag 的事。
class IndexTranslator {
  IndexTranslator._();

  static final IndexTranslator instance = IndexTranslator._();

  /// 与混元同一口径：这类模型解码吃显存带宽，并发换不到吞吐，
  /// 却要多背一个「服务端 `-np` 得够」的依赖和一类回填错序的风险。
  static const concurrency = 1;

  /// 官方 `inference/llm/translate.py::trans_prompt` 的**无约束**那一支，逐字照抄：
  /// `请将以下{源}文本翻译为{目标}，直接输出翻译结果，不要进行任何解释。`
  /// 源语言写死「日语」与本链路的假设一致（检测件认的就是日文，见
  /// `AppleTranslateBackend.defaultSource`）。
  static String prompt(String text, String target) =>
      '请将以下日语文本翻译为$target，直接输出翻译结果，不要进行任何解释。\n\n'
      '$text';

  /// 官方 `strip_think` 的安全网，按它的语义逐句对齐：**第一个**闭合标签之后的内容
  /// 留下；没有闭合标签时，若以开标签起头就剥掉开标签；最后 trim。
  ///
  /// 两端标签写成相邻字面量（`'<' 'think>'`）：这一对标签在文档与工具链里容易被
  /// 当成标记语法吞掉，拼写法多一个引号，但复制粘贴不会把语义改没。
  static String stripThinking(String raw) {
    const open =
        '<'
        'think>';
    const close =
        '<'
        '/think>';
    var t = raw.trim();
    final at = t.indexOf(close);
    if (at >= 0) {
      t = t.substring(at + close.length);
    } else if (t.startsWith(open)) {
      t = t.substring(open.length);
    }
    return t.trim();
  }

  /// 返回顺序与 [texts] 严格一致。任何一条失败都抛 [OcrTranslationException] ——
  /// 半页译文比整页降级更糟，用户看不出哪几块是旧的。
  Future<List<String>> translateBlocks({
    required List<String> texts,
    required OcrTranslationConfig config,

    /// 注入点：单测里给假的，真机走 [_httpPost]。
    Future<String> Function(String prompt, OcrTranslationConfig config)? post,
  }) async {
    if (texts.isEmpty) return const [];
    final send = post ?? _httpPost;
    final target = HyMt2Translator.languageName(config.targetLanguage);

    final out = List<String?>.filled(texts.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= texts.length) return;
        out[i] = stripThinking(await send(prompt(texts[i], target), config));
      }
    }

    await Future.wait([
      for (var k = 0; k < concurrency.clamp(1, texts.length); k++) worker(),
    ]);

    // 一格没填上或翻成空串都当整页失败：按块回填会画出一个空白气泡，
    // 而用户看不出这一格其实没翻 —— 比整页退回原图更糟。
    for (var i = 0; i < texts.length; i++) {
      final t = out[i];
      if (t == null || t.isEmpty) {
        throw OcrTranslationException('第 ${i + 1} 块翻出来是空的（原文「${texts[i]}」）');
      }
    }
    return out.cast<String>();
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
        // 模型卡与台架都用贪心：这里要的是可复现，不是文采。
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
        'Index-Translate 端点返回 ${response.status}：'
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
        'Index-Translate 端点没返回 choices：${body.toString().substring(0, 120)}',
      );
    }
    final msg = (choices.first as Map)['message'];
    final content = msg is Map ? msg['content'] : null;
    if (content is! String) {
      throw OcrTranslationException('Index-Translate 返回的 content 不是字符串');
    }
    return content;
  }
}

/// 供测试与日志复用：这一档到底发出去的是什么提示词。
String indexPrompt(String text, String targetTag) =>
    IndexTranslator.prompt(text, HyMt2Translator.languageName(targetTag));
