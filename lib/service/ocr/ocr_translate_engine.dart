import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';

/// 译文从哪来。**这是用户能主动选的**：走端点要花钱/要网络，走本机与端侧不要。
///
/// 分档的标准是**「同一份输入，产出会不会不同」**，不是「用的是不是同一个协议」：
/// - [endpoint] 与 [hyMt2Local] 都是 OpenAI-compatible HTTP，但一个发「整页编号批量」、
///   一个发「一条一次 + 原生 Terminology 术语块」，产出不同 → 必须分两档，指纹也要能区分；
/// - Windows 的 Foundry Local **不单独列**，因为它就是 [endpoint] 换个 baseUrl，
///   请求形状与术语注入方式都没变 —— 那才叫「同一条码路」。
/// - Apple 有系统翻译框架、Android/iOS 一期整条功能都关着（ADR-0018 §决定 6）。
enum OcrTranslateEngine {
  /// OpenAI-compatible 端点：云端（DeepSeek / OpenAI…）或本机（Ollama / Foundry Local）。
  endpoint('endpoint'),

  /// 混元 Hy-MT2 跑在本机（llama-server 等）。见上面分档的理由。
  hyMt2Local('hunyuan'),

  /// Apple 系统翻译框架（`Translation`）：端侧离线、免费、不要 key。
  /// **没有术语表接口**，所以选它等于放弃 `glossary`（术语类错要靠输出端替换兜）。
  appleOnDevice('apple');

  const OcrTranslateEngine(this.id);

  /// 进缓存指纹的**稳定标识**：改名不能改它，否则所有人的旧成品页集体失效。
  final String id;

  static OcrTranslateEngine fromId(String? id) => OcrTranslateEngine.values
      .firstWhere((e) => e.id == id, orElse: () => OcrTranslateEngine.endpoint);

  /// 术语表在这一档**是否生效**。只有生效的档才该把 `glossarySha1` 编进指纹 ——
  /// 否则改一个术语就把一份「本来就没用术语表」的产物白白作废。
  bool get glossaryApplies => this != OcrTranslateEngine.appleOnDevice;

  /// 这一档**要不要用户填 baseUrl / model**。与 [glossaryApplies] 是两回事，
  /// 只是眼下恰好同真同假 —— 分开写，加下一档时才不会拿错条件（比如「Apple + 输出端替换」
  /// 就是不要端点、但术语表照样生效）。
  bool get requiresEndpoint => this != OcrTranslateEngine.appleOnDevice;

  /// 本平台**有没有**这条实现。与「装了语言包」是两件事，后者看 [AppleTranslateBackend.status]。
  bool get availableHere {
    if (kIsWeb) return false;
    // iOS 上系统翻译也在，但本功能的入口在移动端整条不画（ADR-0018 §决定 6：
    // `ocrSupportedHere` 排除 Android / iOS），所以这里也不放开。
    if (this == OcrTranslateEngine.appleOnDevice) return Platform.isMacOS;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }
}

/// Apple `Translation` 框架的 Dart 侧。桥在 `macos/Runner/TranslationBridgeMac.swift`。
///
/// 为什么走 MethodChannel 而不是 FRB：这个框架只有 Swift / ObjC 绑定，
/// 从 Rust 调它要么自己包一层 ObjC 桥、要么引 `objc2` 依赖 —— 而本仓在 Apple 侧
/// 已经有同形态的先例（`com.breeze.macos/activity`、`GpuPresentBridgeMac`）。
class AppleTranslateBackend {
  AppleTranslateBackend._();

  static const channel = MethodChannel('rossi/apple_translation');

  /// 语言对状态：`installed` / `supported` / `unsupported` / `unavailable`。
  ///
  /// `unavailable` 是**故意**留的一档：非 Apple 平台、或桥没编进去（比如 Windows 构建）时，
  /// 调用方要能看到「这条码路在这台机器上根本不存在」，而不是拿到一个空字符串以为「没装」。
  static Future<String> status({
    String source = defaultSource,
    String target = 'zh-Hans',
  }) async {
    if (!OcrTranslateEngine.appleOnDevice.availableHere) return 'unavailable';
    try {
      final r = await channel.invokeMethod<Map<Object?, Object?>>('status', {
        'source': source,
        'target': target,
      });
      return (r?['status'] as String?) ?? 'unavailable';
    } on PlatformException {
      return 'unavailable';
    } on MissingPluginException {
      return 'unavailable';
    }
  }

  /// 检测件认的是日文；目标语言由设置里的 `targetLanguage` 决定。
  static const defaultSource = 'ja';

  /// 与 `OcrTranslator.translateBlocks` **同形状**的入口：编排层要按引擎分流，
  /// 两边签名不一致就会逼出一堆 `if` 散在链路里。
  ///
  /// 关键差别在这里收口：这条路上任何失败（没装语言包、桥没编进来、条数不符）
  /// 一律转成 [OcrTranslationException] —— 编排层只认这一种异常来决定「降级成原文回填」，
  /// 漏出去就是一个红屏而不是「这页没翻成」。
  static Future<List<String>> translateBlocks({
    required List<String> texts,
    required OcrTranslationConfig config,
  }) async {
    try {
      return await translate(
        texts: texts,
        target: config.targetLanguage,
        source: defaultSource,
      );
    } on OcrTranslationException {
      rethrow;
    } catch (e) {
      throw OcrTranslationException('Apple 系统翻译不可用：$e');
    }
  }

  /// 整批翻。返回顺序与 [texts] 一一对应 —— 上层按块下标回填，错位就是**串行**，
  /// 比翻得差更糟，所以这里对长度做硬校验。
  static Future<List<String>> translate({
    required List<String> texts,
    required String target,
    String source = defaultSource,
  }) async {
    if (texts.isEmpty) return const [];
    final r = await channel.invokeMapMethod<Object?, Object?>('translate', {
      'source': source,
      'target': target,
      'texts': texts,
    });
    final out = (r?['texts'] as List<Object?>?)?.cast<String>();
    if (out == null) {
      throw PlatformException(
        code: 'shape',
        message: 'Apple 翻译返回里没有 texts 字段：${r?.keys.toList()}',
      );
    }
    if (out.length != texts.length) {
      throw PlatformException(
        code: 'count',
        message:
            'Apple 翻译返回 ${out.length} 条，送出去 ${texts.length} 条 —— '
            '按块回填会整体错位，这里直接当失败处理',
      );
    }
    return out;
  }
}
