import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:zephyr/service/ocr/ocr_translator.dart';

/// 译文从哪来。**这是用户能主动选的**：走端点要花钱/要网络，走端侧不要。
///
/// 为什么不是一个布尔「离线开关」：端侧这一档在三个平台上是三种完全不同的东西 ——
/// Apple 有系统翻译框架、Windows 有 Foundry Local（**它本身就是 OpenAI-compatible 端点**，
/// 属于 [OcrTranslateEngine.endpoint] 的一种配法，不是新引擎）、Android/iOS 一期整条功能都关着。
/// 所以枚举只列「真正不同的实现」，把「本机跑一个 OpenAI 兼容服务」留在端点那一档里，
/// 免得设置页出现两个其实走同一条码路的选项。
enum OcrTranslateEngine {
  /// OpenAI-compatible 端点：云端（DeepSeek / OpenAI…）或本机（Ollama / Foundry Local）。
  endpoint('endpoint'),

  /// Apple 系统翻译框架（`Translation`）：端侧离线、免费、不要 key。
  /// **没有术语表接口**，所以选它等于放弃 `glossary`。
  appleOnDevice('apple');

  const OcrTranslateEngine(this.id);

  /// 进缓存指纹的**稳定标识**：改名不能改它，否则所有人的旧成品页集体失效。
  final String id;

  static OcrTranslateEngine fromId(String? id) => OcrTranslateEngine.values
      .firstWhere((e) => e.id == id, orElse: () => OcrTranslateEngine.endpoint);

  /// 本平台**有没有**这条实现。与「装了语言包」是两件事，后者看 [AppleTranslateBackend.status]。
  bool get availableHere {
    if (kIsWeb) return false;
    // iOS 上系统翻译也在，但本功能的入口在移动端整条不画（ADR-0018 §决定 6：
    // `ocrSupportedHere` 排除 Android / iOS），所以这里也不放开。
    return this == OcrTranslateEngine.endpoint || Platform.isMacOS;
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
