import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

/// 成品页构建的某一阶段。给 UI 显示「在做什么」用 —— 整页要十几秒，
/// 没有阶段提示的话用户只会觉得「点了没反应」。
enum TranslatedPageStage { cacheHit, analyzing, translating, typesetting }

/// 中途放弃（翻页翻走了、用户关了开关）。只在**阶段之间**生效：
/// 检测/识别/擦字是一次过桥的整段调用，Rust 侧没有协作式取消点。
class TranslatedPageCancelled implements Exception {
  @override
  String toString() => '成品页构建已取消';
}

class TranslatedPage {
  TranslatedPage({
    required this.path,
    required this.fromCache,
    required this.hasText,
    required this.blockCount,
    required this.truncatedCount,
    this.elapsed = Duration.zero,
  });

  /// 成品页 PNG 的路径。**没有文字的页直接返回原图路径** —— 那种页擦不擦都一样，
  /// 没必要为此占一份缓存，也没必要让用户看到一张「处理过」的图。
  final String path;
  final bool fromCache;
  final bool hasText;
  final int blockCount;

  /// 识别被上限截断的块数：这些块的原文不完整，译文自然也可疑，UI 要标出来。
  final int truncatedCount;

  /// 本次构建花了多久（命中缓存时是查表时间）。
  /// 冒烟页与以后的状态条都要显示它 —— 一页十几秒这件事得让用户看得见，
  /// 不然只会以为点了没反应。
  final Duration elapsed;
}

/// 整页链路：查缓存 → 分析（检测/识别/聚块/擦字）→ 翻译 → 回填 → 原子写缓存。
///
/// 单独一层的原因：`OcrService` 只管过桥、`OcrTranslator` 只管发请求、
/// `TranslatedPageRenderer` 只管画，**「谁先谁后、失败算谁的、什么时候能复用旧产物」**
/// 这三件事不属于它们任何一个。
class TranslatedPageBuilder {
  TranslatedPageBuilder({
    Future<OcrPageResult> Function(
      String imagePath,
      String erasedPath,
      String ep,
    )?
    analyze,
    Future<List<String>> Function(
      List<String> texts,
      OcrTranslationConfig config,
    )?
    translate,
  }) : _analyze = analyze ?? _rustAnalyze,
       _translate = translate ?? _httpTranslate;

  final Future<OcrPageResult> Function(String, String, String) _analyze;
  final Future<List<String>> Function(List<String>, OcrTranslationConfig)
  _translate;

  static Future<OcrPageResult> _rustAnalyze(
    String imagePath,
    String erasedPath,
    String ep,
  ) => OcrService.instance.analyzePage(
    imagePath: imagePath,
    inpaint: true,
    erasedOutput: erasedPath,
    ep: ep,
  );

  static Future<List<String>> _httpTranslate(
    List<String> texts,
    OcrTranslationConfig config,
  ) => OcrTranslator.instance.translateBlocks(texts: texts, config: config);

  Future<TranslatedPage> build({
    required String imagePath,
    required int pageIndex,
    required OcrTranslationConfig config,
    void Function(TranslatedPageStage stage)? onStage,
    bool Function()? shouldCancel,
    bool force = false,
  }) async {
    final clock = Stopwatch()..start();
    final (:fingerprint, :label) = await TranslatedPageCache.describe(
      config: config,
    );
    final target = await TranslatedPageCache.pageFile(
      label: label,
      pageIndex: pageIndex,
    );
    if (!force && await target.exists()) {
      onStage?.call(TranslatedPageStage.cacheHit);
      return TranslatedPage(
        path: target.path,
        fromCache: true,
        hasText: true,
        blockCount: 0,
        truncatedCount: 0,
        elapsed: clock.elapsed,
      );
    }

    _check(shouldCancel);
    onStage?.call(TranslatedPageStage.analyzing);
    // 后端从设置里读，不能在这里写死 cpu：设置页那颗选择器会变成一个骗人的控件。
    final ep = await OcrSettings.loadEp();
    final Uint8List png;
    final int blocks;
    final int truncated;
    // 擦干净的底图只是中间产物，落在系统临时目录、出函数就删；
    // 缓存目录里只留成品，免得用户看到两类分不清的 PNG。
    final scratch = await Directory.systemTemp.createTemp('rossi_ocr_erase_');
    try {
      final erasedPath = p.join(scratch.path, 'erased_p$pageIndex.png');
      final result = await _analyze(imagePath, erasedPath, ep);
      if (result.blocks.isEmpty) {
        return TranslatedPage(
          path: imagePath,
          fromCache: false,
          hasText: false,
          blockCount: 0,
          truncatedCount: 0,
          elapsed: clock.elapsed,
        );
      }

      _check(shouldCancel);
      onStage?.call(TranslatedPageStage.translating);
      final translations = await _translate(
        result.blocks.map((b) => b.text).toList(growable: false),
        config,
      );
      if (translations.length != result.blocks.length) {
        // 渲染那边只有 `assert`，release 下会被跳过 —— 那时它会按下标越界崩掉，
        // 用户看到的是一句没头没尾的 RangeError。条数在这条缝上就必须钉住。
        throw OcrTranslationException(
          '翻译返回的条数与块数不符：块 ${result.blocks.length}，'
          '译文 ${translations.length}',
        );
      }

      _check(shouldCancel);
      onStage?.call(TranslatedPageStage.typesetting);
      png = await TranslatedPageRenderer.render(
        erasedPng: await File(erasedPath).readAsBytes(),
        blocks: result.blocks,
        translations: translations,
      );
      blocks = result.blocks.length;
      truncated = result.blocks.where((b) => b.truncated).length;
    } finally {
      await scratch.delete(recursive: true);
    }

    await TranslatedPageCache.write(
      label: label,
      pageIndex: pageIndex,
      pngBytes: png,
      fingerprint: fingerprint,
    );
    return TranslatedPage(
      path: target.path,
      fromCache: false,
      hasText: true,
      blockCount: blocks,
      truncatedCount: truncated,
      elapsed: clock.elapsed,
    );
  }

  static void _check(bool Function()? shouldCancel) {
    if (shouldCancel?.call() ?? false) throw TranslatedPageCancelled();
  }
}
