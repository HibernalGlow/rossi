import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/bubble_fill.dart';
import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/hy_mt2_translator.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

/// 成品页构建的某一阶段。给 UI 显示「在做什么」用 —— 整页要十几秒，
/// 没有阶段提示的话用户只会觉得「点了没反应」。
enum TranslatedPageStage { cacheHit, analyzing, translating, typesetting }

/// 阶段的中文说法。**日志与界面共用这一份** —— 两边各写一遍迟早会说出两种话。
extension TranslatedPageStageLabel on TranslatedPageStage {
  String label() => switch (this) {
    TranslatedPageStage.cacheHit => '查缓存',
    TranslatedPageStage.analyzing => '检测 / 识别 / 擦字',
    TranslatedPageStage.translating => '翻译请求',
    TranslatedPageStage.typesetting => '回填排版',
  };
}

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
    this.stageEps,
    this.overlayNeedsBase = false,
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

  /// 分析那一跳三段各自**实际生效**的 EP（Rust 侧 resolve 之后的值，**不是**设置里的请求值）。
  ///
  /// 命中缓存时是 null：那一次什么都没跑，不该拿一个旧值顶替。
  /// 「选了 GPU 就不许偷偷用 CPU」这条纪律要核对的就是它。
  final OcrStageEps? stageEps;

  /// 叠层这一档：这一页的底**必须**是擦字底图（有框采不出平色）。
  ///
  /// 为什么要把它交回控制器：「叠层不占增强图轨」是这一档的全部理由，但那种必须擦的页
  /// 不占轨就等于把擦好的底丢在盘上没人换上屏 —— 用户看到的是超分后的原图压在中文下面
  /// （字压字率 0.085 那一格），正是这条链要避免的画面。
  /// true 时控制器替**这一页**占轨（超分为它让路），false 时照旧不占，超分照常。
  ///
  /// 默认 false：只有叠层那条分支会置真；烘焙与未识别到文字的返回都不该走到这个判断。
  final bool overlayNeedsBase;
}

/// 一档译文来源与它对应的缓存坐标。
///
/// 用 record 而不是自建类：与 `PageLayout` 同一个理由（`==` 免费成立，测试可直接断言）。
typedef TranslateAttempt = ({
  OcrTranslationConfig config,
  String fingerprint,
  String label,
  File target,
});

/// 整页链路：查缓存 → 分析（检测/识别/聚块/擦字）→ 翻译 → 回填 → 原子写缓存。
///
/// 单独一层的原因：`OcrService` 只管过桥、`OcrTranslator` 只管发请求、
/// `TranslatedPageRenderer` 只管画，**「谁先谁后、失败算谁的、什么时候能复用旧产物」**
/// 这三件事不属于它们任何一个。
class TranslatedPageBuilder {
  TranslatedPageBuilder({
    Future<OcrPageResult> Function(
      String imagePath,
      String? erasedPath,
      String ep,
    )?
    analyze,
    Future<OcrEraseResult> Function(
      String imagePath,
      List<Float32List> quads,
      String erasedOutput,
      String ep,
    )?
    erase,
    Future<List<String>> Function(
      List<String> texts,
      OcrTranslationConfig config,
    )?
    translate,
  }) : _analyze = analyze ?? _rustAnalyze,
       _erase = erase ?? _rustErase,
       _translate = translate ?? _dispatchTranslate;

  /// `erasedPath == null` = 这一趟**不要擦字**（叠层档先看框、采完色才决定擦不擦）。
  final Future<OcrPageResult> Function(String, String?, String) _analyze;

  /// 只擦字那一跳：不重跑检测与识别。见 [OcrService.erasePage] 的理由。
  final Future<OcrEraseResult> Function(String, List<Float32List>, String, String)
  _erase;
  final Future<List<String>> Function(List<String>, OcrTranslationConfig)
  _translate;

  static Future<OcrPageResult> _rustAnalyze(
    String imagePath,
    String? erasedPath,
    String ep,
  ) => OcrService.instance.analyzePage(
    imagePath: imagePath,
    inpaint: erasedPath != null,
    erasedOutput: erasedPath,
    ep: ep,
  );

  /// 只擦字那一跳的默认实现。见 [OcrService.erasePage]：叠层档采不到平色时才走这里，
  /// 目的是不把这页的检测+识别（实测约 4 s）再付一遍。
  static Future<OcrEraseResult> _rustErase(
    String imagePath,
    List<Float32List> quads,
    String erasedOutput,
    String ep,
  ) => OcrService.instance.erasePage(
    imagePath: imagePath,
    quads: quads,
    erasedOutput: erasedOutput,
    ep: ep,
  );

  /// 按**用户选的引擎**分流。放在这一层而不是塞进 `OcrTranslator`：
  /// 端侧那条路不发 HTTP、也不该被 prompt 模板那套东西碰着。
  static Future<List<String>> _dispatchTranslate(
    List<String> texts,
    OcrTranslationConfig config,
  ) => switch (config.engine) {
    OcrTranslateEngine.appleOnDevice => AppleTranslateBackend.translateBlocks(
      texts: texts,
      config: config,
    ),
    OcrTranslateEngine.hyMt2Local => HyMt2Translator.instance.translateBlocks(
      texts: texts,
      config: config,
    ),
    OcrTranslateEngine.endpoint => OcrTranslator.instance.translateBlocks(
      texts: texts,
      config: config,
    ),
  };

  /// 这一页按**哪几档顺序**去问译文：用户选的那一档在前，端点档填全了就跟在后面当回落。
  ///
  /// Apple 与混元那两档都靠用户机器上的别的部件（系统语言包、`llama-server`），
  /// 「这一会儿没有」是常态而不是错误；端点档通常本来就是配好的，所以拿它兜一层。
  ///
  /// 为什么不直接用 `OcrSettings.loadConfig()` 的结果：选 Apple 时它按设计把
  /// `baseUrl` / `model` 写成空串（那条路本来就不要端点），回落要的恰恰是那几个字段，
  /// 只能从原样快照 [OcrSettings.loadDraft] 里另读。而 `targetLanguage` / `glossary`
  /// 跟着传进来的 [config] 走 —— 回落只是**换个来源**，不能顺手把这页的目标语言换掉。
  static Future<List<OcrTranslationConfig>> _candidateConfigs(
    OcrTranslationConfig config,
  ) async {
    if (config.engine == OcrTranslateEngine.endpoint) return [config];
    final draft = await OcrSettings.loadDraft();
    final baseUrl = draft.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final model = draft.model.trim();
    if (baseUrl.isEmpty || model.isEmpty) return [config];
    return [
      config,
      draft.copyWith(
        baseUrl: baseUrl,
        model: model,
        targetLanguage: config.targetLanguage,
        glossary: config.glossary,
        engine: OcrTranslateEngine.endpoint,
      ),
    ];
  }

  /// Apple 端侧档的**前置检查**：只在**这台机器上根本没有这条路**时拦，并且说清去哪装。
  ///
  /// 为什么不替用户下：整个 `Translation.swiftinterface` 里 `download` 只出现一次，
  /// 是 `TranslationSession.canRequestDownloads` 这个**只读**布尔 —— 没有下载 API，
  /// 而唯一的公开构造器 `init(installedSource:target:)` 名字就要求已装。
  /// 「装不装」只能是用户在系统设置里点的那一下。
  ///
  /// 为什么还留着这一道：`unsupported` / `unavailable` 是确定翻不动的，而检测+识别+擦字
  /// 实测 14 s、那一跳只要 400 ms —— 明知不可为还让人等十几秒才报错，就是白等。
  /// 有端点可回落时不拦（只记一行）：端点本来就是配好的那条路。
  static Future<void> _bailIfAppleNotInstalled(
    OcrTranslationConfig config,
    List<TranslateAttempt> attempts,
  ) async {
    if (config.engine != OcrTranslateEngine.appleOnDevice) return;
    final status = await AppleTranslateBackend.status(
      target: config.targetLanguage,
    );
    if (status == 'installed') return;
    final pair =
        '${AppleTranslateBackend.defaultSource}→${config.targetLanguage}';
    // `supported` **不等于「用不了」**：本机那份翻译日志（2026-10-03 18:37）里状态报
    // supported、这一页被判给端点档，可二十秒后 apple 那一档自己翻出了 7/7 ——
    // macOS 在第一次真调用时才把语言对补上。拿 supported 当硬闸，等于挡掉一页
    // 本来能翻的；没配端点的人还会收到一句假的「先去系统设置装」。
    // 真翻不动有逐档那一圈兜（那一跳实测 400 ms），不必在这里预判。
    if (status == 'supported') {
      OcrLog.add('Apple 语言对状态=supported（系统会在第一次用时补装），先按端侧试 $pair');
      return;
    }
    if (attempts.length > 1) {
      OcrLog.add('Apple 这一档在这台机器上没有（$pair：$status），这一页交给端点档');
      return;
    }
    throw OcrTranslationException(
      '这台机器上用不了 Apple 系统翻译（$pair：$status），请在设置里改用端点翻译。',
    );
  }

  Future<TranslatedPage> build({
    required String imagePath,
    required int pageIndex,
    required OcrTranslationConfig config,
    void Function(TranslatedPageStage stage)? onStage,
    bool Function()? shouldCancel,
    bool force = false,
  }) async {
    final clock = Stopwatch()..start();
    final page = OcrLog.page(pageIndex);
    // 取消也要留一行：否则「按了没反应」在日志里同样是一片空白，
    // 而这正是这份日志要治的那个病。
    void check(TranslatedPageStage next) {
      if (shouldCancel?.call() ?? false) {
        OcrLog.add('$page 已取消（停在「${next.label()}」之前）');
        throw TranslatedPageCancelled();
      }
    }

    // 候选档：用户选的那一档排在前面，端点档配好了就跟在后头当回落。
    // 每档各算一份指纹 —— 译文出自哪一档，产物就得记在哪一档名下。把端点翻出来的那张
    // 写进 Apple 档的目录里就是谎报引擎：等语言包装好、Apple 通了，这一页会永远命中
    // 一张端点翻的旧图（ADR-0018 §决定 7 一路在防的静默陈旧，同一个形状）。
    final attempts = <TranslateAttempt>[];
    for (final cfg in await _candidateConfigs(config)) {
      final (:fingerprint, :label) = await TranslatedPageCache.describe(
        config: cfg,
      );
      attempts.add((
        config: cfg,
        fingerprint: fingerprint,
        label: label,
        target: await TranslatedPageCache.pageFile(
          label: label,
          pageIndex: pageIndex,
        ),
      ));
    }
    for (final a in attempts) {
      if (force) continue;
      // 叠层档命中看的是图层与底，不是那张烤好的 PNG —— 这一档不写 PNG，
      // 按 PNG 判就永远 miss，每次上屏都要重跑那十几秒（等于把这一档的收益清零）。
      final hit = retainErasedBase
          ? await TranslatedPageCache.overlayDisplayable(
              label: a.label,
              pageIndex: pageIndex,
            )
          : await TranslatedPageCache.isUsable(
              label: a.label,
              pageIndex: pageIndex,
            );
      if (!hit) continue;
      onStage?.call(TranslatedPageStage.cacheHit);
      // 叠层档命中时交回的是**底图**（有擦字底就用它，否则原图）：这一档不烤 PNG，
      // 按 PNG 路径交回去等于交回一个不存在的文件。
      final base = await TranslatedPageCache.baseFile(
        label: a.label,
        pageIndex: pageIndex,
      );
      final hitPath = retainErasedBase
          ? (base.existsSync() ? base.path : imagePath)
          : a.target.path;
      OcrLog.add(
        '$page 命中缓存（${clock.elapsedMilliseconds} ms 档=${a.config.engine.id}'
        '${retainErasedBase ? " 叠层" : ""}）：${retainErasedBase ? hitPath : a.target.path}',
      );
      return TranslatedPage(
        path: hitPath,
        fromCache: true,
        hasText: true,
        blockCount: 0,
        truncatedCount: 0,
        elapsed: clock.elapsed,
      );
    }

    // Apple 那一档的语言包由系统自己管：没装就**现在就报**，别等十几秒 OCR 跑完才揭晓
    // （这一轮那个「翻出来还是日文」的现场就是它）。有端点可回落时不拦 —— 回落会接手。
    await _bailIfAppleNotInstalled(config, attempts);

    check(TranslatedPageStage.analyzing);
    onStage?.call(TranslatedPageStage.analyzing);
    // 后端从设置里读，不能在这里写死 cpu：设置页那颗选择器会变成一个骗人的控件。
    final ep = await OcrSettings.loadEp();
    OcrLog.add(
      '$page 开始构建：引擎=${config.engine.id}'
      '${config.engine == OcrTranslateEngine.endpoint ? ' 端点=${_hostOf(config.baseUrl)}/${config.model}' : ''} '
      '目标=${config.targetLanguage} 请求后端=$ep'
      '${attempts.length > 1 ? ' 回落档=${attempts[1].config.engine.id}(${_hostOf(attempts[1].config.baseUrl)}/${attempts[1].config.model})' : ''}'
      '${force ? '（force 重算）' : ''}',
    );
    final Uint8List png;
    final int blocks;
    final int truncated;
    late final OcrStageEps stageEps;
    // 图层在 try 里组装、烘焙档在 try **之后**才写盘（要和 PNG 同一批）。
    // 声明放在外面，是为了让「编译期就要求两条分支都赋过值」这条检查还在。
    late final TranslatedPageLayer layer;
    // 实际出译文的那一档（可能就是选的那一档，也可能是回落档），产物写它名下。
    late final TranslateAttempt used;
    // 擦干净的底图只是中间产物，落在系统临时目录、出函数就删；
    // 缓存目录里只留成品，免得用户看到两类分不清的 PNG。
    final scratch = await Directory.systemTemp.createTemp('rossi_ocr_erase_');
    try {
      final erasedPath = p.join(scratch.path, 'erased_p$pageIndex.png');
      // 叠层档先**不擦**：要看完框、采完色才知道需不需要那 4.2 s。
      final result = await _analyze(
        imagePath,
        retainErasedBase ? null : erasedPath,
        ep,
      );
      final eps = result.stageEps;
      OcrLog.add(
        '$page 分析：${result.blocks.length} 块，'
        '检测 ${result.detectMs} ms / 识别 ${result.recognizeMs} ms / '
        '擦字 ${result.inpaintMs} ms；'
        '实际生效 EP：检测=${eps.detect} 识别=${eps.recognize} '
        '擦字=${eps.inpaint ?? '未跑'}',
      );
      if (result.blocks.isEmpty) {
        OcrLog.add('$page 没识别到文字，直接用原图');
        return TranslatedPage(
          path: imagePath,
          fromCache: false,
          hasText: false,
          blockCount: 0,
          truncatedCount: 0,
          stageEps: result.stageEps,
          elapsed: clock.elapsed,
        );
      }

      check(TranslatedPageStage.translating);
      onStage?.call(TranslatedPageStage.translating);
      final sources = result.blocks.map((b) => b.text).toList(growable: false);
      final translateClock = Stopwatch()..start();
      List<String>? lines;
      for (var i = 0; i < attempts.length; i++) {
        final a = attempts[i];
        try {
          final t = await _translate(sources, a.config);
          if (t.length != sources.length) {
            // 渲染那边只有 `assert`，release 下会被跳过 —— 那时它会按下标越界崩掉，
            // 用户看到的是一句没头没尾的 RangeError。条数在这条缝上就必须钉住。
            throw OcrTranslationException(
              '翻译返回的条数与块数不符：块 ${sources.length}，译文 ${t.length}',
            );
          }
          lines = t;
          used = a;
          break;
        } on OcrTranslationException catch (e) {
          // 一档挂了不算这一页失败：还有下一档就问下一档。最后一档才把原因交出去，
          // 那时这一页**整体失败**、画面留原图 —— 不再拿原文回填冒充成品页：
          // 「擦掉日文又把日文画回去」是一张看着像成功的没翻译页，比失败更难被发现。
          final next = i + 1 < attempts.length ? attempts[i + 1].config : null;
          OcrLog.add(
            '$page ${a.config.engine.id} 那一跳失败：${e.message}'
            '${next == null ? ' —— 没有可回落的档，这一页按失败处理' : ' —— 回落 ${next.engine.id} ${_hostOf(next.baseUrl)}/${next.model}'}',
          );
          if (next == null) rethrow;
        }
      }
      // 循环没有第二条出路：没拿到译文就已经在最后一档 rethrow 了。
      final translations = lines!;
      OcrLog.add(
        '$page 翻译：${sources.length} 条 → ${translations.length} 条，'
        '用时 ${translateClock.elapsedMilliseconds} ms 档=${used.config.engine.id}',
      );

      // 填色采的是**原图**：要的是气泡自己的底色。LaMa 修出来的那片底虽然也能采，
      // 但叠层档现在根本不一定跑擦字了（见下面的分支），所以只能按原图采。
      final fills = retainErasedBase
          ? await _sampleFills(
              imagePath: imagePath,
              blocks: result.blocks,
              pageWidth: result.pageWidth,
              pageHeight: result.pageHeight,
              page: page,
            )
          : null;
      // 同一批数据在**画之前**的样子：框、原文、译文、可疑块。烧成 PNG 就再也问不回来，
      // 所以这份必须与那张 PNG 同源同档（ADR-0018 §决定 4 的图层那一半）。
      layer = TranslatedPageLayer(
        pageWidth: result.pageWidth,
        pageHeight: result.pageHeight,
        boxes: [
          for (var i = 0; i < result.blocks.length; i++)
            TranslatedBox(
              quad: result.blocks[i].quad.map((v) => v.toDouble()).toList(),
              source: result.blocks[i].text,
              text: translations[i],
              fill: fills?[i],
              truncated: result.blocks[i].truncated,
            ),
        ],
      );

      if (retainErasedBase) {
        // 叠层档：不烤 PNG、不占增强图轨，所以**底图越清晰越好**（超分照常生效）。
        // 每框都采到平色 → 填色就足够盖住原文，LaMa 那一跳（实测 4.2 s/页）整个跳过；
        // 有一框采不出 → 老老实实擦，底图落进同一档缓存里给叠层当底。
        final allFilled = layer.boxes.every((b) => b.fill != null);
        // 取消点放在**补擦之前**：这一档最贵的一跳还没发生，翻走了就不该再付 4.2 s。
        check(TranslatedPageStage.typesetting);
        onStage?.call(TranslatedPageStage.typesetting);
        final base = allFilled
            ? imagePath
            : (await TranslatedPageCache.baseFile(
                label: used.label,
                pageIndex: pageIndex,
              )).path;
        if (!allFilled) {
          final eraseClock = Stopwatch()..start();
          // 先擦进临时目录，再由缓存那层原子收进来（`writeBase`）。
          final erased = await _erase(
            imagePath,
            result.blocks.map((b) => b.quad).toList(growable: false),
            erasedPath,
            ep,
          );
          final written = erased.erasedPath;
          if (written == null) {
            // 掩膜为空 = Rust 侧一个字都没擦、也没写底图（框全是退化的那种）。
            // 这时能拿到的底只有原图，而叠在未擦字的原图上字压字率实测 0.085 ——
            // 与其画一张糊的冒充成品，不如如实失败，界面会说「译文失败」。
            throw OcrTranslationException('擦字没有写出底图（掩膜为空），这一页不能叠层');
          }
          await TranslatedPageCache.writeBase(
            label: used.label,
            pageIndex: pageIndex,
            erasedFile: File(written),
          );
          OcrLog.add(
            '$page 采不到全平色底，只擦字（不重跑检测/识别）：'
            '${eraseClock.elapsedMilliseconds} ms，实际生效 EP=${erased.ep ?? '未报'}',
          );
        }
        await TranslatedPageCache.writeLayer(
          label: used.label,
          pageIndex: pageIndex,
          json: layer.encode(),
          fingerprint: used.fingerprint,
        );
        OcrLog.add(
          '$page 叠层就绪：${layer.boxes.length} 框，'
          '${allFilled ? "全部填色（未跑擦字）" : "填色不足，已补擦底图"}，'
          '底图=${allFilled ? "原图" : "擦字底图"} 档=${used.config.engine.id}',
        );
        return TranslatedPage(
          path: base,
          fromCache: false,
          hasText: true,
          blockCount: layer.boxes.length,
          truncatedCount: layer.boxes.where((b) => b.truncated).length,
          label: used.label,
          stageEps: result.stageEps,
          overlayNeedsBase: !allFilled,
          elapsed: clock.elapsed,
        );
      }

      check(TranslatedPageStage.typesetting);
      onStage?.call(TranslatedPageStage.typesetting);
      final typesetClock = Stopwatch()..start();
      png = await TranslatedPageRenderer.render(
        erasedPng: await File(erasedPath).readAsBytes(),
        blocks: result.blocks,
        translations: translations,
      );
      blocks = result.blocks.length;
      truncated = result.blocks.where((b) => b.truncated).length;
      stageEps = result.stageEps;
      OcrLog.add(
        '$page 回填排版：${typesetClock.elapsedMilliseconds} ms，'
        '$blocks 块'
        '${truncated > 0 ? '，其中 $truncated 块被截断（可疑）' : ''}',
      );
    } finally {
      await scratch.delete(recursive: true);
    }

    await TranslatedPageCache.write(
      label: used.label,
      pageIndex: pageIndex,
      pngBytes: png,
      fingerprint: used.fingerprint,
    );
    // 图层与成品页**同一批写**：只写 PNG 就等于把 OCR 的全部产出烧死在一张图里，
    // 换超分档 / 换显示模式 / 手改译文都得重跑那十几秒（叠层模式没数据可用）。
    // 清单已由 `write` 记过，这里不再传 fingerprint。
    await TranslatedPageCache.writeLayer(
      label: used.label,
      pageIndex: pageIndex,
      json: layer.encode(),
    );
    OcrLog.add(
      '$page 成品已写入 ${used.target.path}（${png.length} 字节 档=${used.config.engine.id}）',
    );
    return TranslatedPage(
      path: used.target.path,
      fromCache: false,
      hasText: true,
      blockCount: blocks,
      truncatedCount: truncated,
      stageEps: stageEps,
      elapsed: clock.elapsed,
    );
  }

  /// 逐框采底色，**全页都能采到平色才交回颜色**。
  ///
  /// 为什么是全有或全无而不是「能采几框填几框」：同一页里一半是 LaMa 修出来的底、
  /// 一半是实心色块，两种底并排就是「翻译没弄干净」的样子 —— 而那正是这一档要避免的。
  /// 交回全 null 时上层仍然有擦字底图可叠，不会退化成原文露出来。
  static Future<List<ui.Color?>> _sampleFills({
    required String imagePath,
    required List<OcrBlock> blocks,
    required int pageWidth,
    required int pageHeight,
    required String page,
  }) async {
    final codec = await ui.instantiateImageCodec(
      await File(imagePath).readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (data == null || width <= 0 || height <= 0) {
      OcrLog.add('$page 原图解不出字节，这一页不采底色（继续用擦字底图叠）');
      return List<ui.Color?>.filled(blocks.length, null);
    }
    final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final fills = <ui.Color?>[];
    for (final b in blocks) {
      final sampled = sampleBoxFill(
        rgba: rgba,
        width: width,
        height: height,
        quad: b.quad.map((v) => v.toDouble()).toList(),
      );
      fills.add(sampled?.color);
    }
    final dirty = <int>[
      for (var i = 0; i < fills.length; i++)
        if (fills[i] == null) i + 1,
    ];
    if (dirty.isNotEmpty) {
      OcrLog.add(
        '$page ${dirty.length}/${fills.length} 框采不到平色底（第 ${dirty.join('、')} 框），'
        '这一页整页不填色 —— 半填半擦会露出两种底',
      );
      return List<ui.Color?>.filled(blocks.length, null);
    }
    OcrLog.add(
      '$page ${fills.length} 框全部采到平色底（填色可替代擦字，基准 ${pageWidth}x$pageHeight）',
    );
    return fills;
  }
}

/// 端点在日志里只记 **host**。
///
/// base URL 是用户自己填的，里面完全可能夹一段带 token 的路径或查询串
/// （某些网关把 key 写在 path 上）—— 而这份日志的用途就是被「复制」走。
String _hostOf(String url) {
  final host = Uri.tryParse(url)?.host;
  return (host == null || host.isEmpty) ? url : host;
}
