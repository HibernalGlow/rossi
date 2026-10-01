import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';

/// 本平台是否做 OCR 翻译。
///
/// **Android / iOS 是排除项，不是待办**（ADR-0018 §决定 6）：本仓 `ort` 的 linux/android
/// 那两段没注册任何加速器 EP，等于纯 CPU；识别模型是 fp32 的 ViT+BERT（~441 MB），
/// 移动端要可用得先做 int8 重导出。所以入口在移动端整条不画，而不是点了报错。
bool get ocrSupportedHere =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// OCR 翻译的设置存储。
///
/// 存在 SharedPreferences 而**不进** ObjectBox 的 `GlobalSettingState`：与 RealSR 同一口径
/// （`real_sr_settings.dart:107` 的理由一样）—— 这是「功能自己的配置」，
/// 不该把全局设置状态撑成一锅粥，也不该跟着主题/阅读设置一起同步。
///
/// ⚠️ `apiKey` 是明文存的（与仓库里其他 token 同等待遇）。它**不进** [OcrTranslationConfig.toJson]，
/// 所以不会被写进任何导出文件或日志；但 SharedPreferences 本身不是安全存储，
/// 用户把配置目录同步到网盘时 key 会跟着走。
class OcrSettings {
  OcrSettings._();

  static const _keyBaseUrl = 'ocr_base_url';
  static const _keyModel = 'ocr_model';
  static const _keyApiKey = 'ocr_api_key';
  static const _keyTargetLang = 'ocr_target_lang';
  static const _keyGlossary = 'ocr_glossary';
  static const _keyEp = 'ocr_ep';
  static const _keyEngine = 'ocr_translate_engine';

  static const defaultTargetLanguage = 'zh-Hans';

  /// 译文引擎。**默认仍是端点**：端侧那一档没有术语表，且要用户自己在系统里装语言包，
  /// 把它设成默认等于悄悄拿走了「专名翻对」这件事（实测 Apple 把「危機契約」翻成「危机合同」、
  /// 「かえして」翻成「换一下」）。所以它是一档**可主动选择的省钱/离线**路。
  static const defaultEngine = OcrTranslateEngine.endpoint;
  static const engineChoices = <(OcrTranslateEngine, String)>[
    (OcrTranslateEngine.endpoint, 'API 端点（云端，或本机 Ollama / Foundry Local）'),
    (
      OcrTranslateEngine.hyMt2Local,
      '混元 Hy-MT2（本机 llama-server；一条一次，术语表走原生 Terminology）',
    ),
    (OcrTranslateEngine.appleOnDevice, 'Apple 系统翻译（端侧离线、免费；不支持术语表）'),
  ];

  /// 推理后端。默认 **auto = 按「平台 + 哪一段模型」选**，不是一个固定值。
  ///
  /// 为什么不是「Apple 就 CoreML、Windows 就 DirectML」：实测三段的胜负各不相同 ——
  /// Windows 上 DirectML 让识别快 4 倍（10.7 s → 2.6 s）、擦字快 8.7 倍（12.5 s → 1.4 s），
  /// 但检测反而慢（151 ms → 209 ms）；macOS 上 CoreML 对 det / encoder / LaMa 全都更慢。
  /// 数字与策略见 `REFERENCE_RESEARCH.md` §8.6.3 与 `rust/ocr_core` 的 `Ep::resolve`。
  /// 显式选的值一定照办（哪怕更慢），且不支持的 EP **报错**，不静默退回 CPU。
  static const defaultEp = 'auto';
  static const epChoices = <(String, String)>[
    ('auto', '自动（按平台与模型选，实测最快）'),
    ('cpu', 'CPU（强制）'),
    ('coreml', 'CoreML（Apple；这几个模型上实测更慢）'),
    ('directml', 'DirectML（Windows；识别与擦字明显更快）'),
  ];

  static final _changes = _OcrSettingsNotifier();
  static ChangeNotifier get changes => _changes;

  /// 读配置。**没配齐就返回 null**，而不是返回一个发出去必然失败的配置 ——
  /// 阅读器据此弹「先去设置里填端点」，比抛一个 HTTP 错误友好。
  ///
  /// 「配齐」的定义**随引擎变**：端侧那一档不要端点也不要 key，
  /// 拿端点的要求去问它，用户会被一句「请先填端点」挡在门外 —— 而那台机器上功能其实是通的。
  static Future<OcrTranslationConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final engine = _engineOf(prefs);
    final targetLanguage =
        (prefs.getString(_keyTargetLang) ?? defaultTargetLanguage).trim();
    final glossary = prefs.getString(_keyGlossary) ?? '';
    if (!engine.requiresEndpoint) {
      return OcrTranslationConfig(
        baseUrl: '',
        model: '',
        targetLanguage: targetLanguage,
        glossary: glossary,
        engine: engine,
      );
    }
    final baseUrl = (prefs.getString(_keyBaseUrl) ?? '').trim();
    final model = (prefs.getString(_keyModel) ?? '').trim();
    if (baseUrl.isEmpty || model.isEmpty) return null;
    return OcrTranslationConfig(
      baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
      model: model,
      apiKey: (prefs.getString(_keyApiKey) ?? '').trim(),
      targetLanguage: targetLanguage,
      glossary: glossary,
      engine: engine,
    );
  }

  /// 设置页用的**原样**快照：字段可能为空，但每一项都要能回填到输入框里，
  /// 否则用户改一个字段就得重填全部。校验过的版本看 [loadConfig]。
  static Future<OcrTranslationConfig> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return OcrTranslationConfig(
      baseUrl: (prefs.getString(_keyBaseUrl) ?? '').trim(),
      model: (prefs.getString(_keyModel) ?? '').trim(),
      apiKey: (prefs.getString(_keyApiKey) ?? '').trim(),
      targetLanguage: (prefs.getString(_keyTargetLang) ?? defaultTargetLanguage)
          .trim(),
      glossary: prefs.getString(_keyGlossary) ?? '',
      engine: _engineOf(prefs),
    );
  }

  static Future<void> saveConfig(OcrTranslationConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, config.baseUrl);
    await prefs.setString(_keyModel, config.model);
    await prefs.setString(_keyApiKey, config.apiKey);
    await prefs.setString(_keyTargetLang, config.targetLanguage);
    await prefs.setString(_keyGlossary, config.glossary);
    await prefs.setString(_keyEngine, config.engine.id);
    _changes.notify();
  }

  static OcrTranslateEngine _engineOf(SharedPreferences prefs) {
    final e = OcrTranslateEngine.fromId(prefs.getString(_keyEngine));
    // 存了个这台机器上没有的引擎（比如在 Windows 上从 Mac 同步过来的配置）→ 回落到端点，
    // 而不是让整条链路去调一个不存在的桥。
    return e.availableHere ? e : defaultEngine;
  }

  /// 单独读引擎：设置页要在还没拼出完整 config 时就能决定「端点那一栏画不画」。
  static Future<OcrTranslateEngine> loadEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return _engineOf(prefs);
  }

  static Future<String> loadEp() async {
    final prefs = await SharedPreferences.getInstance();
    final ep = (prefs.getString(_keyEp) ?? defaultEp).trim();
    return epChoices.any((c) => c.$1 == ep) ? ep : defaultEp;
  }

  static Future<void> saveEp(String ep) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEp, ep);
    _changes.notify();
  }
}

class _OcrSettingsNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
